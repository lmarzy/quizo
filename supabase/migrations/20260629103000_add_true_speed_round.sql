update public.games
set game_mode = 'race_to_points'
where game_mode = 'speed_round';

alter table public.games
drop constraint if exists games_game_mode_check;

alter table public.games
add constraint games_game_mode_check
check (game_mode in ('classic', 'race_to_points', 'speed_round'));

create table if not exists public.speed_rounds (
  id uuid primary key default gen_random_uuid(),
  game_id uuid not null references public.games(id) on delete cascade,
  question_id uuid not null references public.questions(id) on delete restrict,
  round_number integer not null,
  timer_ends_at timestamptz not null,
  created_at timestamptz not null default now(),
  completed_at timestamptz,
  unique (game_id, round_number)
);

create table if not exists public.speed_round_answers (
  id uuid primary key default gen_random_uuid(),
  game_id uuid not null references public.games(id) on delete cascade,
  round_id uuid not null references public.speed_rounds(id) on delete cascade,
  member_id uuid not null references public.game_members(id) on delete cascade,
  question_id uuid not null references public.questions(id) on delete restrict,
  selected_option text not null check (selected_option in ('A', 'B', 'C', 'TIMEOUT')),
  is_correct boolean not null,
  points_delta integer not null default 0,
  answered_at timestamptz not null default now(),
  unique (round_id, member_id)
);

create index if not exists speed_rounds_game_created_idx on public.speed_rounds (game_id, created_at desc);
create index if not exists speed_round_answers_game_answered_idx on public.speed_round_answers (game_id, answered_at desc);

do $$
declare
  function_definition text;
begin
  function_definition := pg_get_functiondef('public.submit_game_answer(text, uuid, text, text)'::regprocedure);
  execute replace(function_definition, 'speed_round', 'race_to_points');

  function_definition := pg_get_functiondef('public.expire_current_turn(text)'::regprocedure);
  execute replace(function_definition, 'speed_round', 'race_to_points');
  execute replace(
    replace(function_definition, 'speed_round', 'race_to_points'),
    'public.expire_current_turn(',
    'public.expire_current_turn_turn_based('
  );
end;
$$;

grant execute on function public.expire_current_turn_turn_based(text) to anon, authenticated;

create or replace function public.start_game(p_game_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  game_record public.games;
  first_member public.game_members;
  first_question public.questions;
  joined_count integer;
  next_turn_number integer;
  next_round_number integer;
  first_timer_ends_at timestamptz;
begin
  select *
  into game_record
  from public.games
  where id = p_game_id
  for update;

  if game_record.id is null then
    raise exception 'Game not found';
  end if;

  if game_record.host_user_id <> auth.uid() then
    raise exception 'Only the host can start this game';
  end if;

  if game_record.status not in ('draft', 'lobby') then
    raise exception 'Game cannot be started from its current status';
  end if;

  select count(*)
  into joined_count
  from public.game_members
  where game_id = game_record.id
    and status = 'joined';

  if joined_count < 2 then
    raise exception 'At least two joined members are required to start';
  end if;

  select *
  into first_question
  from public.questions
  where pack_id = game_record.question_pack_id
  order by random()
  limit 1;

  if first_question.id is null then
    raise exception 'Selected question pack has no questions';
  end if;

  update public.game_members
  set status = 'active'
  where game_id = game_record.id
    and status = 'joined';

  first_timer_ends_at := now() + make_interval(secs => game_record.question_time_limit_seconds);

  if game_record.game_mode = 'speed_round' then
    select coalesce(max(round_number), 0) + 1
    into next_round_number
    from public.speed_rounds
    where game_id = game_record.id;

    insert into public.speed_rounds (game_id, question_id, round_number, timer_ends_at)
    values (game_record.id, first_question.id, next_round_number, first_timer_ends_at);

    update public.games
    set
      status = 'active',
      current_member_id = null,
      current_question_id = first_question.id,
      current_turn_attempt = 1,
      timer_ends_at = first_timer_ends_at,
      started_at = coalesce(started_at, now())
    where id = game_record.id
    returning * into game_record;

    insert into public.game_events (game_id, event_type, message, metadata)
    values (
      game_record.id,
      'game_started',
      'Speed round started. Everyone answers together.',
      jsonb_build_object('question_id', first_question.id, 'round_number', next_round_number, 'game_mode', game_record.game_mode)
    );

    return public.get_game_room(game_record.join_code);
  end if;

  select *
  into first_member
  from public.game_members
  where game_id = game_record.id
    and status = 'active'
  order by turn_order, created_at
  limit 1;

  select coalesce(max(turn_number), 0) + 1
  into next_turn_number
  from public.game_turns
  where game_id = game_record.id;

  insert into public.game_turns (
    game_id,
    member_id,
    question_id,
    turn_number,
    timer_ends_at
  )
  values (
    game_record.id,
    first_member.id,
    first_question.id,
    next_turn_number,
    first_timer_ends_at
  );

  update public.games
  set
    status = 'active',
    current_member_id = first_member.id,
    current_question_id = first_question.id,
    current_turn_attempt = 1,
    timer_ends_at = first_timer_ends_at,
    started_at = coalesce(started_at, now())
  where id = game_record.id
  returning * into game_record;

  insert into public.game_events (game_id, member_id, event_type, message, metadata)
  values (
    game_record.id,
    first_member.id,
    'game_started',
    'Game started. First turn: ' || first_member.display_name,
    jsonb_build_object(
      'member_id', first_member.id,
      'question_id', first_question.id,
      'attempt', 1,
      'game_mode', game_record.game_mode
    )
  );

  return public.get_game_room(game_record.join_code);
end;
$$;

create or replace function public.get_game_room(p_join_code text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  game_record public.games;
  question_record public.questions;
  active_member public.game_members;
  latest_answer_record public.game_answers;
  latest_speed_answer_record public.speed_round_answers;
  latest_answer_member public.game_members;
  latest_answer_question public.questions;
  latest_answer_attempt integer := 1;
  members jsonb;
  events jsonb;
  current_speed_round public.speed_rounds;
  speed_answers jsonb := '[]'::jsonb;
begin
  select *
  into game_record
  from public.games
  where join_code = upper(trim(p_join_code))
  limit 1;

  if game_record.id is null then
    raise exception 'Game not found';
  end if;

  if game_record.current_question_id is not null then
    select *
    into question_record
    from public.questions
    where id = game_record.current_question_id;
  end if;

  if game_record.current_member_id is not null then
    select *
    into active_member
    from public.game_members
    where id = game_record.current_member_id;
  end if;

  if game_record.game_mode = 'speed_round' then
    select *
    into current_speed_round
    from public.speed_rounds
    where game_id = game_record.id
      and question_id = game_record.current_question_id
      and completed_at is null
    order by round_number desc
    limit 1;

    if current_speed_round.id is null then
      select *
      into current_speed_round
      from public.speed_rounds
      where game_id = game_record.id
      order by round_number desc
      limit 1;
    end if;

    select *
    into latest_speed_answer_record
    from public.speed_round_answers
    where game_id = game_record.id
    order by answered_at desc
    limit 1;

    if latest_speed_answer_record.id is not null then
      select *
      into latest_answer_member
      from public.game_members
      where id = latest_speed_answer_record.member_id;

      select *
      into latest_answer_question
      from public.questions
      where id = latest_speed_answer_record.question_id;
    end if;

    if current_speed_round.id is not null then
      select coalesce(
        jsonb_agg(
          jsonb_build_object(
            'id', sra.id,
            'member_id', sra.member_id,
            'member_name', gm.display_name,
            'selected_option', sra.selected_option,
            'is_correct', sra.is_correct,
            'points_delta', sra.points_delta,
            'answered_at', sra.answered_at
          )
          order by sra.answered_at
        ),
        '[]'::jsonb
      )
      into speed_answers
      from public.speed_round_answers sra
      join public.game_members gm on gm.id = sra.member_id
      where sra.round_id = current_speed_round.id
        and sra.selected_option <> 'TIMEOUT';
    end if;
  else
    select *
    into latest_answer_record
    from public.game_answers
    where game_id = game_record.id
    order by answered_at desc
    limit 1;

    if latest_answer_record.id is not null then
      select *
      into latest_answer_member
      from public.game_members
      where id = latest_answer_record.member_id;

      select *
      into latest_answer_question
      from public.questions
      where id = latest_answer_record.question_id;

      select coalesce((ge.metadata->>'attempt')::integer, 1)
      into latest_answer_attempt
      from public.game_events ge
      where ge.game_id = latest_answer_record.game_id
        and ge.member_id = latest_answer_record.member_id
        and ge.event_type in ('answer_submitted', 'answer_correct', 'answer_wrong')
        and ge.created_at between latest_answer_record.answered_at - interval '2 seconds'
          and latest_answer_record.answered_at + interval '2 seconds'
      order by ge.created_at desc
      limit 1;
    end if;
  end if;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', gm.id,
        'display_name', gm.display_name,
        'points', gm.points,
        'status', gm.status,
        'turn_order', gm.turn_order
      )
      order by gm.points desc, gm.turn_order
    ),
    '[]'::jsonb
  )
  into members
  from public.game_members gm
  where gm.game_id = game_record.id;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', ge.id,
        'event_type', ge.event_type,
        'message', ge.message,
        'created_at', ge.created_at
      )
      order by ge.created_at desc
    ),
    '[]'::jsonb
  )
  into events
  from (
    select *
    from public.game_events
    where game_id = game_record.id
    order by created_at desc
    limit 8
  ) ge;

  return jsonb_build_object(
    'game',
    jsonb_build_object(
      'id', game_record.id,
      'name', game_record.name,
      'join_code', game_record.join_code,
      'status', game_record.status,
      'game_mode', game_record.game_mode,
      'target_points', game_record.target_points,
      'starting_points', game_record.starting_points,
      'timer_ends_at', game_record.timer_ends_at,
      'current_member_id', game_record.current_member_id,
      'current_question_id', game_record.current_question_id,
      'question_time_limit_seconds', game_record.question_time_limit_seconds,
      'current_turn_attempt', game_record.current_turn_attempt,
      'max_consecutive_questions', game_record.max_consecutive_questions
    ),
    'active_member',
    case
      when active_member.id is null then null
      else jsonb_build_object(
        'id', active_member.id,
        'display_name', active_member.display_name,
        'points', active_member.points
      )
    end,
    'question',
    case
      when question_record.id is null then null
      else jsonb_build_object(
        'id', question_record.id,
        'prompt', question_record.prompt,
        'option_a', question_record.option_a,
        'option_b', question_record.option_b,
        'option_c', question_record.option_c
      )
    end,
    'latest_answer',
    case
      when game_record.game_mode = 'speed_round' and latest_speed_answer_record.id is not null then jsonb_build_object(
        'id', latest_speed_answer_record.id,
        'member_name', latest_answer_member.display_name,
        'selected_option', latest_speed_answer_record.selected_option,
        'is_correct', latest_speed_answer_record.is_correct,
        'points_delta', latest_speed_answer_record.points_delta,
        'attempt', 1,
        'correct_option', latest_answer_question.correct_option,
        'correct_answer',
          case latest_answer_question.correct_option
            when 'A' then latest_answer_question.option_a
            when 'B' then latest_answer_question.option_b
            when 'C' then latest_answer_question.option_c
          end,
        'answered_at', latest_speed_answer_record.answered_at
      )
      when latest_answer_record.id is not null then jsonb_build_object(
        'id', latest_answer_record.id,
        'member_name', latest_answer_member.display_name,
        'selected_option', latest_answer_record.selected_option,
        'is_correct', latest_answer_record.is_correct,
        'points_delta', latest_answer_record.points_delta,
        'attempt', latest_answer_attempt,
        'correct_option', latest_answer_question.correct_option,
        'correct_answer',
          case latest_answer_question.correct_option
            when 'A' then latest_answer_question.option_a
            when 'B' then latest_answer_question.option_b
            when 'C' then latest_answer_question.option_c
          end,
        'answered_at', latest_answer_record.answered_at
      )
      else null
    end,
    'speed_round',
    case
      when current_speed_round.id is null then null
      else jsonb_build_object(
        'id', current_speed_round.id,
        'round_number', current_speed_round.round_number,
        'timer_ends_at', current_speed_round.timer_ends_at,
        'answered_member_ids', coalesce((select jsonb_agg(sra.member_id) from public.speed_round_answers sra where sra.round_id = current_speed_round.id), '[]'::jsonb),
        'answers', speed_answers
      )
    end,
    'members', members,
    'events', events
  );
end;
$$;

create or replace function public.submit_speed_round_answer(p_join_code text, p_member_id uuid, p_session_token text, p_selected_option text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  game_record public.games;
  round_record public.speed_rounds;
  question_record public.questions;
  member_record public.game_members;
  next_question public.questions;
  selected_option text;
  answer_correct boolean;
  points_delta integer;
  session_hash text;
  active_count integer;
  answered_count integer;
  next_round_number integer;
  next_timer_ends_at timestamptz;
  answer_reveal_delay_seconds integer := 5;
  winner_record public.game_members;
begin
  selected_option := upper(trim(p_selected_option));

  if selected_option not in ('A', 'B', 'C') then
    raise exception 'Invalid answer option';
  end if;

  select *
  into game_record
  from public.games
  where join_code = upper(trim(p_join_code))
  for update;

  if game_record.id is null or game_record.status <> 'active' or game_record.game_mode <> 'speed_round' then
    raise exception 'Speed round is not active';
  end if;

  select *
  into member_record
  from public.game_members
  where id = p_member_id
    and game_id = game_record.id
    and status = 'active'
  for update;

  if member_record.id is null then
    raise exception 'Player not found';
  end if;

  if member_record.user_id is not null and member_record.user_id = auth.uid() then
    null;
  else
    session_hash := encode(digest(coalesce(p_session_token, ''), 'sha256'), 'hex');

    if member_record.guest_session_token_hash is distinct from session_hash then
      raise exception 'Player session is invalid';
    end if;
  end if;

  select *
  into round_record
  from public.speed_rounds
  where game_id = game_record.id
    and question_id = game_record.current_question_id
    and completed_at is null
  order by round_number desc
  limit 1
  for update;

  if round_record.id is null then
    raise exception 'No active speed round found';
  end if;

  if now() > round_record.timer_ends_at then
    raise exception 'Round timer has expired';
  end if;

  select *
  into question_record
  from public.questions
  where id = round_record.question_id;

  answer_correct := question_record.correct_option = selected_option;
  points_delta := case when answer_correct then game_record.recovery_points else -game_record.wrong_answer_penalty end;

  insert into public.speed_round_answers (
    game_id,
    round_id,
    member_id,
    question_id,
    selected_option,
    is_correct,
    points_delta
  )
  values (
    game_record.id,
    round_record.id,
    member_record.id,
    question_record.id,
    selected_option,
    answer_correct,
    points_delta
  );

  update public.game_members
  set points = points + points_delta
  where id = member_record.id
  returning * into member_record;

  insert into public.game_events (game_id, member_id, event_type, message, metadata)
  values (
    game_record.id,
    member_record.id,
    case when answer_correct then 'answer_correct' else 'answer_wrong' end,
    member_record.display_name ||
      case
        when answer_correct then ' answered correctly and gained ' || points_delta || ' points'
        else ' answered incorrectly and lost ' || abs(points_delta) || ' points'
      end,
    jsonb_build_object('selected_option', selected_option, 'is_correct', answer_correct, 'points_delta', points_delta, 'game_mode', game_record.game_mode)
  );

  select *
  into winner_record
  from public.game_members
  where game_id = game_record.id
    and status = 'active'
    and points >= game_record.target_points
  order by points desc, updated_at asc
  limit 1;

  if winner_record.id is not null then
    update public.speed_rounds
    set completed_at = now()
    where id = round_record.id;

    update public.games
    set status = 'finished',
        current_member_id = null,
        current_question_id = null,
        timer_ends_at = null,
        finished_at = now()
    where id = game_record.id;

    insert into public.game_events (game_id, member_id, event_type, message)
    values (game_record.id, winner_record.id, 'game_finished', winner_record.display_name || ' reached ' || game_record.target_points || ' points');

    return public.get_game_room(game_record.join_code);
  end if;

  select count(*)
  into active_count
  from public.game_members
  where game_id = game_record.id
    and status = 'active';

  select count(*)
  into answered_count
  from public.speed_round_answers
  where round_id = round_record.id;

  if answered_count >= active_count then
    update public.speed_rounds
    set completed_at = now()
    where id = round_record.id;

    select *
    into next_question
    from public.questions
    where pack_id = game_record.question_pack_id
      and id <> question_record.id
    order by random()
    limit 1;

    if next_question.id is null then
      select *
      into next_question
      from public.questions
      where pack_id = game_record.question_pack_id
      order by random()
      limit 1;
    end if;

    select coalesce(max(round_number), 0) + 1
    into next_round_number
    from public.speed_rounds
    where game_id = game_record.id;

    next_timer_ends_at := now() + make_interval(secs => game_record.question_time_limit_seconds + answer_reveal_delay_seconds);

    insert into public.speed_rounds (game_id, question_id, round_number, timer_ends_at)
    values (game_record.id, next_question.id, next_round_number, next_timer_ends_at);

    update public.games
    set current_question_id = next_question.id,
        current_turn_attempt = next_round_number,
        timer_ends_at = next_timer_ends_at
    where id = game_record.id;

    insert into public.game_events (game_id, event_type, message, metadata)
    values (
      game_record.id,
      'speed_round_started',
      'Next speed round started',
      jsonb_build_object('question_id', next_question.id, 'round_number', next_round_number)
    );
  end if;

  return public.get_game_room(game_record.join_code);
end;
$$;

grant execute on function public.submit_speed_round_answer(text, uuid, text, text) to anon, authenticated;

create or replace function public.expire_current_turn(p_join_code text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  game_record public.games;
  round_record public.speed_rounds;
  member_record public.game_members;
  question_record public.questions;
  next_question public.questions;
  next_round_number integer;
  next_timer_ends_at timestamptz;
  answer_reveal_delay_seconds integer := 5;
begin
  select *
  into game_record
  from public.games
  where join_code = upper(trim(p_join_code))
  for update;

  if game_record.id is null or game_record.status <> 'active' then
    raise exception 'Game is not active';
  end if;

  if game_record.game_mode <> 'speed_round' then
    return public.expire_current_turn_turn_based(p_join_code);
  end if;

  if game_record.timer_ends_at is null or now() < game_record.timer_ends_at then
    raise exception 'Turn timer has not expired';
  end if;

  select *
  into round_record
  from public.speed_rounds
  where game_id = game_record.id
    and question_id = game_record.current_question_id
    and completed_at is null
  order by round_number desc
  limit 1
  for update;

  if round_record.id is null then
    return public.get_game_room(game_record.join_code);
  end if;

  select *
  into question_record
  from public.questions
  where id = round_record.question_id;

  for member_record in
    select *
    from public.game_members gm
    where gm.game_id = game_record.id
      and gm.status = 'active'
      and not exists (
        select 1
        from public.speed_round_answers sra
        where sra.round_id = round_record.id
          and sra.member_id = gm.id
      )
    for update
  loop
    insert into public.speed_round_answers (
      game_id,
      round_id,
      member_id,
      question_id,
      selected_option,
      is_correct,
      points_delta
    )
    values (
      game_record.id,
      round_record.id,
      member_record.id,
      question_record.id,
      'TIMEOUT',
      false,
      -game_record.wrong_answer_penalty
    );

    update public.game_members
    set points = points - game_record.wrong_answer_penalty
    where id = member_record.id;

    insert into public.game_events (game_id, member_id, event_type, message, metadata)
    values (
      game_record.id,
      member_record.id,
      'turn_timed_out',
      member_record.display_name || ' ran out of time and lost ' || game_record.wrong_answer_penalty || ' points',
      jsonb_build_object('points_delta', -game_record.wrong_answer_penalty, 'game_mode', game_record.game_mode)
    );
  end loop;

  update public.speed_rounds
  set completed_at = now()
  where id = round_record.id;

  select *
  into next_question
  from public.questions
  where pack_id = game_record.question_pack_id
    and id <> question_record.id
  order by random()
  limit 1;

  if next_question.id is null then
    select *
    into next_question
    from public.questions
    where pack_id = game_record.question_pack_id
    order by random()
    limit 1;
  end if;

  select coalesce(max(round_number), 0) + 1
  into next_round_number
  from public.speed_rounds
  where game_id = game_record.id;

  next_timer_ends_at := now() + make_interval(secs => game_record.question_time_limit_seconds + answer_reveal_delay_seconds);

  insert into public.speed_rounds (game_id, question_id, round_number, timer_ends_at)
  values (game_record.id, next_question.id, next_round_number, next_timer_ends_at);

  update public.games
  set current_question_id = next_question.id,
      current_turn_attempt = next_round_number,
      timer_ends_at = next_timer_ends_at
  where id = game_record.id;

  insert into public.game_events (game_id, event_type, message, metadata)
  values (
    game_record.id,
    'speed_round_started',
    'Next speed round started',
    jsonb_build_object('question_id', next_question.id, 'round_number', next_round_number)
  );

  return public.get_game_room(game_record.join_code);
end;
$$;

grant execute on function public.expire_current_turn(text) to anon, authenticated;
