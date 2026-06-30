alter table public.games
add column if not exists elimination_rounds integer not null default 3 check (elimination_rounds between 1 and 20),
add column if not exists questions_per_round integer not null default 3 check (questions_per_round between 1 and 50);

alter table public.games
drop constraint if exists games_game_mode_check;

alter table public.games
add constraint games_game_mode_check
check (game_mode in ('classic', 'race_to_points', 'speed_round', 'elimination_ladder'));

do $$
declare
  function_definition text;
begin
  function_definition := pg_get_functiondef('public.start_game(uuid)'::regprocedure);
  function_definition := replace(
    function_definition,
    'if game_record.game_mode = ''speed_round'' then',
    'if game_record.game_mode in (''speed_round'', ''elimination_ladder'') then'
  );
  execute function_definition;

  function_definition := pg_get_functiondef('public.get_game_room(text)'::regprocedure);
  function_definition := replace(
    function_definition,
    'if game_record.game_mode = ''speed_round'' then',
    'if game_record.game_mode in (''speed_round'', ''elimination_ladder'') then'
  );
  function_definition := replace(
    function_definition,
    'when game_record.game_mode = ''speed_round'' and latest_speed_answer_record.id is not null then',
    'when game_record.game_mode in (''speed_round'', ''elimination_ladder'') and latest_speed_answer_record.id is not null then'
  );
  function_definition := replace(
    function_definition,
    '''max_consecutive_questions'', game_record.max_consecutive_questions',
    '''max_consecutive_questions'', game_record.max_consecutive_questions,
      ''elimination_rounds'', game_record.elimination_rounds,
      ''questions_per_round'', game_record.questions_per_round'
  );
  execute function_definition;

  function_definition := pg_get_functiondef('public.expire_current_turn(text)'::regprocedure);
  execute replace(
    function_definition,
    'public.expire_current_turn(',
    'public.expire_current_turn_non_ladder('
  );
end;
$$;

grant execute on function public.expire_current_turn_non_ladder(text) to anon, authenticated;

create or replace function public.advance_elimination_ladder(p_game_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  game_record public.games;
  round_record public.speed_rounds;
  question_record public.questions;
  next_question public.questions;
  eliminated_member public.game_members;
  winner_record public.game_members;
  active_count integer;
  remaining_count integer;
  ladder_round integer;
  question_in_round integer;
  next_round_number integer;
  next_question_in_round integer;
  next_timer_ends_at timestamptz;
begin
  select *
  into game_record
  from public.games
  where id = p_game_id
  for update;

  if game_record.id is null or game_record.status <> 'active' or game_record.game_mode <> 'elimination_ladder' then
    raise exception 'Elimination ladder is not active';
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

  update public.speed_rounds
  set completed_at = now()
  where id = round_record.id;

  ladder_round := ceil(round_record.round_number::numeric / game_record.questions_per_round)::integer;
  question_in_round := ((round_record.round_number - 1) % game_record.questions_per_round) + 1;

  select count(*)
  into active_count
  from public.game_members
  where game_id = game_record.id
    and status = 'active';

  if question_in_round >= game_record.questions_per_round and active_count > 1 then
    select *
    into eliminated_member
    from public.game_members
    where game_id = game_record.id
      and status = 'active'
    order by points asc, turn_order desc, updated_at desc
    limit 1
    for update;

    update public.game_members
    set status = 'eliminated'
    where id = eliminated_member.id;

    insert into public.game_events (game_id, member_id, event_type, message, metadata)
    values (
      game_record.id,
      eliminated_member.id,
      'player_eliminated',
      eliminated_member.display_name || ' was eliminated with the lowest score',
      jsonb_build_object('ladder_round', ladder_round, 'points', eliminated_member.points)
    );
  end if;

  select count(*)
  into remaining_count
  from public.game_members
  where game_id = game_record.id
    and status = 'active';

  if remaining_count <= 1 or ladder_round >= game_record.elimination_rounds then
    select *
    into winner_record
    from public.game_members
    where game_id = game_record.id
      and status = 'active'
    order by points desc, turn_order
    limit 1;

    if winner_record.id is null then
      select *
      into winner_record
      from public.game_members
      where game_id = game_record.id
      order by points desc, turn_order
      limit 1;
    end if;

    update public.games
    set status = 'finished',
        current_member_id = null,
        current_question_id = null,
        timer_ends_at = null,
        finished_at = now()
    where id = game_record.id;

    insert into public.game_events (game_id, member_id, event_type, message)
    values (game_record.id, winner_record.id, 'game_finished', winner_record.display_name || ' wins the elimination ladder');

    return public.get_game_room(game_record.join_code);
  end if;

  select *
  into question_record
  from public.questions
  where id = round_record.question_id;

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

  if next_question.id is null then
    raise exception 'Selected question pack has no questions';
  end if;

  select coalesce(max(round_number), 0) + 1
  into next_round_number
  from public.speed_rounds
  where game_id = game_record.id;

  next_question_in_round := ((next_round_number - 1) % game_record.questions_per_round) + 1;
  next_timer_ends_at := now() + make_interval(secs => game_record.question_time_limit_seconds);

  insert into public.speed_rounds (game_id, question_id, round_number, timer_ends_at)
  values (game_record.id, next_question.id, next_round_number, next_timer_ends_at);

  update public.games
  set current_member_id = null,
      current_question_id = next_question.id,
      current_turn_attempt = next_question_in_round,
      timer_ends_at = next_timer_ends_at
  where id = game_record.id;

  insert into public.game_events (game_id, event_type, message, metadata)
  values (
    game_record.id,
    'elimination_question_started',
    'Next ladder question started',
    jsonb_build_object('question_id', next_question.id, 'round_number', next_round_number, 'question_in_round', next_question_in_round)
  );

  return public.get_game_room(game_record.join_code);
end;
$$;

grant execute on function public.advance_elimination_ladder(uuid) to anon, authenticated;

create or replace function public.submit_elimination_ladder_answer(p_join_code text, p_member_id uuid, p_session_token text, p_selected_option text)
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
  selected_option text;
  answer_correct boolean;
  points_delta integer;
  session_hash text;
  active_count integer;
  answered_count integer;
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

  if game_record.id is null or game_record.status <> 'active' or game_record.game_mode <> 'elimination_ladder' then
    raise exception 'Elimination ladder is not active';
  end if;

  select *
  into member_record
  from public.game_members
  where id = p_member_id
    and game_id = game_record.id
    and status = 'active'
  for update;

  if member_record.id is null then
    raise exception 'Player not found or already eliminated';
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
    raise exception 'No active ladder question found';
  end if;

  if now() > round_record.timer_ends_at then
    raise exception 'Question timer has expired';
  end if;

  if exists (
    select 1
    from public.speed_round_answers sra
    where sra.round_id = round_record.id
      and sra.member_id = member_record.id
  ) then
    raise exception 'You have already answered this question';
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
    points_delta,
    attempt
  )
  values (
    game_record.id,
    round_record.id,
    member_record.id,
    question_record.id,
    selected_option,
    answer_correct,
    points_delta,
    1
  );

  update public.game_members
  set points = points + points_delta
  where id = member_record.id;

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

  select count(*)
  into active_count
  from public.game_members
  where game_id = game_record.id
    and status = 'active';

  select count(distinct sra.member_id)
  into answered_count
  from public.speed_round_answers sra
  join public.game_members gm on gm.id = sra.member_id
  where sra.round_id = round_record.id
    and gm.status = 'active';

  if answered_count >= active_count then
    return public.advance_elimination_ladder(game_record.id);
  end if;

  return public.get_game_room(game_record.join_code);
end;
$$;

grant execute on function public.submit_elimination_ladder_answer(text, uuid, text, text) to anon, authenticated;

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
begin
  select *
  into game_record
  from public.games
  where join_code = upper(trim(p_join_code))
  for update;

  if game_record.id is null or game_record.status <> 'active' then
    raise exception 'Game is not active';
  end if;

  if game_record.game_mode <> 'elimination_ladder' then
    return public.expire_current_turn_non_ladder(p_join_code);
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
      points_delta,
      attempt
    )
    values (
      game_record.id,
      round_record.id,
      member_record.id,
      question_record.id,
      'TIMEOUT',
      false,
      -game_record.wrong_answer_penalty,
      1
    );

    update public.game_members
    set points = points - game_record.wrong_answer_penalty
    where id = member_record.id;

    insert into public.game_events (game_id, member_id, event_type, message, metadata)
    values (
      game_record.id,
      member_record.id,
      'elimination_question_timed_out',
      member_record.display_name || ' did not answer and lost ' || game_record.wrong_answer_penalty || ' points',
      jsonb_build_object('points_delta', -game_record.wrong_answer_penalty, 'game_mode', game_record.game_mode)
    );
  end loop;

  return public.advance_elimination_ladder(game_record.id);
end;
$$;

grant execute on function public.expire_current_turn(text) to anon, authenticated;

create or replace function public.get_joinable_game(p_join_code text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  game_record public.games;
  members jsonb;
begin
  select *
  into game_record
  from public.games
  where join_code = upper(trim(p_join_code))
    and status in ('draft', 'lobby', 'active', 'finished')
  limit 1;

  if game_record.id is null then
    raise exception 'Game not found';
  end if;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', gm.id,
        'display_name', gm.display_name,
        'points', gm.points,
        'status', gm.status,
        'turn_order', gm.turn_order,
        'joined_at', gm.joined_at
      )
      order by gm.turn_order, gm.created_at
    ),
    '[]'::jsonb
  )
  into members
  from public.game_members gm
  where gm.game_id = game_record.id;

  return jsonb_build_object(
    'game',
    jsonb_build_object(
      'id', game_record.id,
      'name', game_record.name,
      'join_code', game_record.join_code,
      'status', game_record.status,
      'game_mode', game_record.game_mode,
      'target_points', game_record.target_points,
      'elimination_rounds', game_record.elimination_rounds,
      'questions_per_round', game_record.questions_per_round,
      'starting_points', game_record.starting_points,
      'question_time_limit_seconds', game_record.question_time_limit_seconds
    ),
    'members',
    members
  );
end;
$$;

grant execute on function public.get_joinable_game(text) to anon, authenticated;
