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
      'timer_ends_at', game_record.timer_ends_at,
      'current_member_id', game_record.current_member_id,
      'current_question_id', game_record.current_question_id
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
        'option_c', question_record.option_c,
        'option_d', question_record.option_d
      )
    end,
    'members', members,
    'events', events
  );
end;
$$;

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
begin
  selected_option := upper(trim(p_selected_option));

  if selected_option not in ('A', 'B', 'C', 'D') then
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

  session_hash := encode(digest(p_session_token, 'sha256'), 'hex');

  if member_record.guest_session_token_hash is distinct from session_hash then
    raise exception 'Player session is invalid';
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
  points_delta := case when answer_correct then 0 else -game_record.wrong_answer_penalty end;
  new_points := greatest(0, member_record.points + points_delta);

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
        when answer_correct then ' answered correctly'
        else ' answered incorrectly and lost ' || game_record.wrong_answer_penalty || ' points'
      end,
    jsonb_build_object(
      'selected_option', selected_option,
      'is_correct', answer_correct,
      'points_delta', points_delta
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

  if answer_correct or member_record.status = 'eliminated' then
    select *
    into next_member
    from public.game_members gm
    where gm.game_id = game_record.id
      and gm.status = 'active'
      and gm.points > 0
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
      order by gm.turn_order
      limit 1;
    end if;
  else
    next_member := member_record;
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
    now() + make_interval(secs => game_record.question_time_limit_seconds)
  );

  update public.games
  set
    current_member_id = next_member.id,
    current_question_id = next_question.id,
    timer_ends_at = now() + make_interval(secs => game_record.question_time_limit_seconds)
  where id = game_record.id;

  insert into public.game_events (game_id, member_id, event_type, message, metadata)
  values (
    game_record.id,
    next_member.id,
    'turn_started',
    'Next turn: ' || next_member.display_name,
    jsonb_build_object('member_id', next_member.id, 'question_id', next_question.id)
  );

  return public.get_game_room(game_record.join_code);
end;
$$;

grant execute on function public.get_game_room(text) to anon, authenticated;
grant execute on function public.submit_game_answer(text, uuid, text, text) to anon, authenticated;
