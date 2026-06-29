alter table public.games
add column if not exists game_mode text not null default 'classic',
add column if not exists target_points integer not null default 100;

alter table public.games
drop constraint if exists games_game_mode_check;

alter table public.games
add constraint games_game_mode_check
check (game_mode in ('classic', 'speed_round'));

alter table public.games
drop constraint if exists games_target_points_check;

alter table public.games
add constraint games_target_points_check
check (target_points > 0);

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
  latest_answer_member public.game_members;
  latest_answer_question public.questions;
  latest_answer_attempt integer := 1;
  members jsonb;
  events jsonb;
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
      and ge.event_type = 'answer_submitted'
      and ge.created_at between latest_answer_record.answered_at - interval '2 seconds'
        and latest_answer_record.answered_at + interval '2 seconds'
    order by ge.created_at desc
    limit 1;
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
      when latest_answer_record.id is null then null
      else jsonb_build_object(
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
    end,
    'members', members,
    'events', events
  );
end;
$$;

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
  into first_member
  from public.game_members
  where game_id = game_record.id
    and status = 'joined'
  order by turn_order, created_at
  limit 1;

  select *
  into first_question
  from public.questions
  where pack_id = game_record.question_pack_id
  order by random()
  limit 1;

  if first_question.id is null then
    raise exception 'Selected question pack has no questions';
  end if;

  select coalesce(max(turn_number), 0) + 1
  into next_turn_number
  from public.game_turns
  where game_id = game_record.id;

  update public.game_members
  set status = 'active'
  where game_id = game_record.id
    and status = 'joined';

  first_timer_ends_at := now() + make_interval(secs => game_record.question_time_limit_seconds);

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

  return jsonb_build_object(
    'game',
    jsonb_build_object(
      'id', game_record.id,
      'status', game_record.status,
      'game_mode', game_record.game_mode,
      'target_points', game_record.target_points,
      'current_member_id', game_record.current_member_id,
      'current_question_id', game_record.current_question_id,
      'current_turn_attempt', game_record.current_turn_attempt,
      'timer_ends_at', game_record.timer_ends_at
    )
  );
end;
$$;

create or replace function public.submit_game_answer(p_join_code text, p_member_id uuid, p_session_token text, p_selected_option text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  game_record public.games;
  turn_record public.game_turns;
  question_record public.questions;
  member_record public.game_members;
  next_member public.game_members;
  next_question public.questions;
  active_count integer;
  next_turn_number integer;
  selected_option text;
  answer_correct boolean;
  new_points integer;
  points_delta integer;
  session_hash text;
  should_advance_player boolean;
  next_attempt integer;
  answer_reveal_delay_seconds integer := 5;
  next_timer_ends_at timestamptz;
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

  if game_record.id is null or game_record.status <> 'active' then
    raise exception 'Game is not active';
  end if;

  if game_record.current_member_id <> p_member_id then
    raise exception 'It is not this player''s turn';
  end if;

  select *
  into member_record
  from public.game_members
  where id = p_member_id
    and game_id = game_record.id
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
  into turn_record
  from public.game_turns
  where game_id = game_record.id
    and member_id = member_record.id
    and status = 'pending'
  order by turn_number desc
  limit 1
  for update;

  if turn_record.id is null then
    raise exception 'No pending turn found';
  end if;

  select *
  into question_record
  from public.questions
  where id = turn_record.question_id;

  answer_correct := question_record.correct_option = selected_option;

  if answer_correct then
    points_delta := game_record.recovery_points;
    new_points := member_record.points + points_delta;
  else
    points_delta := -game_record.wrong_answer_penalty;
    if game_record.game_mode = 'speed_round' then
      new_points := member_record.points + points_delta;
    else
      new_points := greatest(0, member_record.points + points_delta);
    end if;
  end if;

  insert into public.game_answers (
    game_id,
    turn_id,
    member_id,
    question_id,
    selected_option,
    is_correct,
    points_delta
  )
  values (
    game_record.id,
    turn_record.id,
    member_record.id,
    question_record.id,
    selected_option,
    answer_correct,
    points_delta
  );

  update public.game_turns
  set status = 'answered', completed_at = now()
  where id = turn_record.id;

  update public.game_members
  set
    points = new_points,
    status = case
      when game_record.game_mode = 'classic' and new_points <= 0 then 'eliminated'::public.member_status
      else status
    end
  where id = member_record.id
  returning * into member_record;

  insert into public.game_events (game_id, member_id, event_type, message, metadata)
  values (
    game_record.id,
    member_record.id,
    case when answer_correct then 'answer_correct' else 'answer_wrong' end,
    member_record.display_name ||
      case
        when answer_correct and points_delta > 0 then ' answered correctly and gained ' || points_delta || ' points'
        when answer_correct then ' answered correctly'
        else ' answered incorrectly and lost ' || abs(points_delta) || ' points'
      end,
    jsonb_build_object(
      'selected_option', selected_option,
      'is_correct', answer_correct,
      'points_delta', points_delta,
      'attempt', game_record.current_turn_attempt,
      'game_mode', game_record.game_mode
    )
  );

  if game_record.game_mode = 'speed_round' and member_record.points >= game_record.target_points then
    update public.games
    set
      status = 'finished',
      current_member_id = null,
      current_question_id = null,
      timer_ends_at = null,
      finished_at = now()
    where id = game_record.id;

    insert into public.game_events (game_id, member_id, event_type, message)
    values (game_record.id, member_record.id, 'game_finished', member_record.display_name || ' reached ' || game_record.target_points || ' points');

    return public.get_game_room(game_record.join_code);
  end if;

  if game_record.game_mode = 'classic' then
    select count(*)
    into active_count
    from public.game_members
    where game_id = game_record.id
      and status = 'active'
      and points > 0;

    if active_count <= 1 then
      update public.games
      set
        status = 'finished',
        current_member_id = null,
        current_question_id = null,
        timer_ends_at = null,
        finished_at = now()
      where id = game_record.id;

      insert into public.game_events (game_id, member_id, event_type, message)
      select game_record.id, gm.id, 'game_finished', gm.display_name || ' wins the game'
      from public.game_members gm
      where gm.game_id = game_record.id
        and gm.status = 'active'
        and gm.points > 0
      order by gm.points desc, gm.turn_order
      limit 1;

      return public.get_game_room(game_record.join_code);
    end if;
  end if;

  should_advance_player :=
    answer_correct
    or member_record.status = 'eliminated'
    or game_record.current_turn_attempt >= game_record.max_consecutive_questions;

  if should_advance_player then
    select *
    into next_member
    from public.game_members gm
    where gm.game_id = game_record.id
      and gm.status = 'active'
      and (game_record.game_mode = 'speed_round' or gm.points > 0)
      and gm.id <> member_record.id
      and gm.turn_order > member_record.turn_order
    order by gm.turn_order
    limit 1;

    if next_member.id is null then
      select *
      into next_member
      from public.game_members gm
      where gm.game_id = game_record.id
        and gm.status = 'active'
        and (game_record.game_mode = 'speed_round' or gm.points > 0)
        and gm.id <> member_record.id
      order by gm.turn_order
      limit 1;
    end if;

    next_attempt := 1;
  else
    next_member := member_record;
    next_attempt := game_record.current_turn_attempt + 1;
  end if;

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

  select coalesce(max(turn_number), 0) + 1
  into next_turn_number
  from public.game_turns
  where game_id = game_record.id;

  next_timer_ends_at := now() + make_interval(secs => game_record.question_time_limit_seconds + answer_reveal_delay_seconds);

  insert into public.game_turns (
    game_id,
    member_id,
    question_id,
    turn_number,
    timer_ends_at
  )
  values (
    game_record.id,
    next_member.id,
    next_question.id,
    next_turn_number,
    next_timer_ends_at
  );

  update public.games
  set
    current_member_id = next_member.id,
    current_question_id = next_question.id,
    current_turn_attempt = next_attempt,
    timer_ends_at = next_timer_ends_at
  where id = game_record.id;

  insert into public.game_events (game_id, member_id, event_type, message, metadata)
  values (
    game_record.id,
    next_member.id,
    'turn_started',
    case
      when next_attempt > 1 then 'Recovery question for ' || next_member.display_name
      else 'Next turn: ' || next_member.display_name
    end,
    jsonb_build_object('member_id', next_member.id, 'question_id', next_question.id, 'attempt', next_attempt)
  );

  return public.get_game_room(game_record.join_code);
end;
$$;

grant execute on function public.submit_game_answer(text, uuid, text, text) to anon, authenticated;

create or replace function public.expire_current_turn(p_join_code text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  game_record public.games;
  turn_record public.game_turns;
  member_record public.game_members;
  next_member public.game_members;
  next_question public.questions;
  active_count integer;
  next_turn_number integer;
  new_points integer;
  next_attempt integer;
  should_advance_player boolean;
  answer_reveal_delay_seconds integer := 5;
  next_timer_ends_at timestamptz;
begin
  select *
  into game_record
  from public.games
  where join_code = upper(trim(p_join_code))
  for update;

  if game_record.id is null or game_record.status <> 'active' then
    raise exception 'Game is not active';
  end if;

  if game_record.timer_ends_at is null or now() < game_record.timer_ends_at then
    raise exception 'Turn timer has not expired';
  end if;

  select *
  into turn_record
  from public.game_turns
  where game_id = game_record.id
    and member_id = game_record.current_member_id
    and status = 'pending'
  order by turn_number desc
  limit 1
  for update;

  if turn_record.id is null then
    return public.get_game_room(game_record.join_code);
  end if;

  select *
  into member_record
  from public.game_members
  where id = game_record.current_member_id
    and game_id = game_record.id
  for update;

  if member_record.id is null then
    raise exception 'Current player not found';
  end if;

  if game_record.game_mode = 'speed_round' then
    new_points := member_record.points - game_record.wrong_answer_penalty;
  else
    new_points := greatest(0, member_record.points - game_record.wrong_answer_penalty);
  end if;

  update public.game_turns
  set status = 'timed_out', completed_at = now()
  where id = turn_record.id;

  update public.game_members
  set
    points = new_points,
    status = case
      when game_record.game_mode = 'classic' and new_points <= 0 then 'eliminated'::public.member_status
      else status
    end
  where id = member_record.id
  returning * into member_record;

  insert into public.game_events (game_id, member_id, event_type, message, metadata)
  values (
    game_record.id,
    member_record.id,
    'turn_timed_out',
    member_record.display_name || ' ran out of time and lost ' || game_record.wrong_answer_penalty || ' points',
    jsonb_build_object('points_delta', -game_record.wrong_answer_penalty, 'attempt', game_record.current_turn_attempt, 'game_mode', game_record.game_mode)
  );

  if game_record.game_mode = 'classic' then
    select count(*)
    into active_count
    from public.game_members
    where game_id = game_record.id
      and status = 'active'
      and points > 0;

    if active_count <= 1 then
      update public.games
      set
        status = 'finished',
        current_member_id = null,
        current_question_id = null,
        timer_ends_at = null,
        finished_at = now()
      where id = game_record.id;

      insert into public.game_events (game_id, member_id, event_type, message)
      select game_record.id, gm.id, 'game_finished', gm.display_name || ' wins the game'
      from public.game_members gm
      where gm.game_id = game_record.id
        and gm.status = 'active'
        and gm.points > 0
      order by gm.points desc, gm.turn_order
      limit 1;

      return public.get_game_room(game_record.join_code);
    end if;
  end if;

  should_advance_player :=
    member_record.status = 'eliminated'
    or game_record.current_turn_attempt >= game_record.max_consecutive_questions;

  if should_advance_player then
    select *
    into next_member
    from public.game_members gm
    where gm.game_id = game_record.id
      and gm.status = 'active'
      and (game_record.game_mode = 'speed_round' or gm.points > 0)
      and gm.id <> member_record.id
      and gm.turn_order > member_record.turn_order
    order by gm.turn_order
    limit 1;

    if next_member.id is null then
      select *
      into next_member
      from public.game_members gm
      where gm.game_id = game_record.id
        and gm.status = 'active'
        and (game_record.game_mode = 'speed_round' or gm.points > 0)
        and gm.id <> member_record.id
      order by gm.turn_order
      limit 1;
    end if;

    next_attempt := 1;
  else
    next_member := member_record;
    next_attempt := game_record.current_turn_attempt + 1;
  end if;

  select *
  into next_question
  from public.questions
  where pack_id = game_record.question_pack_id
    and id <> turn_record.question_id
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

  select coalesce(max(turn_number), 0) + 1
  into next_turn_number
  from public.game_turns
  where game_id = game_record.id;

  next_timer_ends_at := now() + make_interval(secs => game_record.question_time_limit_seconds + answer_reveal_delay_seconds);

  insert into public.game_turns (
    game_id,
    member_id,
    question_id,
    turn_number,
    timer_ends_at
  )
  values (
    game_record.id,
    next_member.id,
    next_question.id,
    next_turn_number,
    next_timer_ends_at
  );

  update public.games
  set
    current_member_id = next_member.id,
    current_question_id = next_question.id,
    current_turn_attempt = next_attempt,
    timer_ends_at = next_timer_ends_at
  where id = game_record.id;

  insert into public.game_events (game_id, member_id, event_type, message, metadata)
  values (
    game_record.id,
    next_member.id,
    'turn_started',
    case
      when next_attempt > 1 then 'Recovery question for ' || next_member.display_name
      else 'Next turn: ' || next_member.display_name
    end,
    jsonb_build_object('member_id', next_member.id, 'question_id', next_question.id, 'attempt', next_attempt)
  );

  return public.get_game_room(game_record.join_code);
end;
$$;

grant execute on function public.expire_current_turn(text) to anon, authenticated;
