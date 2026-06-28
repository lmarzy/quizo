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
    jsonb_build_object('points_delta', -game_record.wrong_answer_penalty)
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

  if member_record.status = 'eliminated' then
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

grant execute on function public.expire_current_turn(text) to anon, authenticated;
