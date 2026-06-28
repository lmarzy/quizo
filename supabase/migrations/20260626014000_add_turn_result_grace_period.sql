create or replace function public.submit_game_answer(
  p_join_code text,
  p_member_id uuid,
  p_session_token text,
  p_selected_option text
)
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
  answer_reveal_delay_seconds integer := 3;
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
    new_points := greatest(0, member_record.points + points_delta);
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
    status = case when new_points <= 0 then 'eliminated'::public.member_status else status end
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
      'attempt', game_record.current_turn_attempt
    )
  );

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
      and gm.points > 0
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
        and gm.points > 0
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
  answer_reveal_delay_seconds integer := 3;
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

  new_points := greatest(0, member_record.points - game_record.wrong_answer_penalty);

  update public.game_turns
  set status = 'timed_out', completed_at = now()
  where id = turn_record.id;

  update public.game_members
  set
    points = new_points,
    status = case when new_points <= 0 then 'eliminated'::public.member_status else status end
  where id = member_record.id
  returning * into member_record;

  insert into public.game_events (game_id, member_id, event_type, message, metadata)
  values (
    game_record.id,
    member_record.id,
    'turn_timed_out',
    member_record.display_name || ' ran out of time and lost ' || game_record.wrong_answer_penalty || ' points',
    jsonb_build_object('points_delta', -game_record.wrong_answer_penalty, 'attempt', game_record.current_turn_attempt)
  );

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

  should_advance_player :=
    member_record.status = 'eliminated'
    or game_record.current_turn_attempt >= game_record.max_consecutive_questions;

  if should_advance_player then
    select *
    into next_member
    from public.game_members gm
    where gm.game_id = game_record.id
      and gm.status = 'active'
      and gm.points > 0
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
        and gm.points > 0
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

grant execute on function public.submit_game_answer(text, uuid, text, text) to anon, authenticated;
grant execute on function public.expire_current_turn(text) to anon, authenticated;
