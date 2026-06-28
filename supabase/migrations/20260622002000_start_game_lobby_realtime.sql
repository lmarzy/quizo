do $$
begin
  alter publication supabase_realtime add table public.games;
exception
  when duplicate_object then null;
end $$;

do $$
begin
  alter publication supabase_realtime add table public.game_members;
exception
  when duplicate_object then null;
end $$;

do $$
begin
  alter publication supabase_realtime add table public.game_events;
exception
  when duplicate_object then null;
end $$;

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
  next_turn_number integer;
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

  select *
  into first_member
  from public.game_members
  where game_id = game_record.id
    and status = 'joined'
  order by turn_order, created_at
  limit 1;

  if first_member.id is null then
    raise exception 'At least one joined member is required to start';
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

  select coalesce(max(turn_number), 0) + 1
  into next_turn_number
  from public.game_turns
  where game_id = game_record.id;

  update public.game_members
  set status = 'active'
  where game_id = game_record.id
    and status = 'joined';

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
    now() + make_interval(secs => game_record.question_time_limit_seconds)
  );

  update public.games
  set
    status = 'active',
    current_member_id = first_member.id,
    current_question_id = first_question.id,
    timer_ends_at = now() + make_interval(secs => game_record.question_time_limit_seconds),
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
      'question_id', first_question.id
    )
  );

  return jsonb_build_object(
    'game',
    jsonb_build_object(
      'id', game_record.id,
      'status', game_record.status,
      'current_member_id', game_record.current_member_id,
      'current_question_id', game_record.current_question_id,
      'timer_ends_at', game_record.timer_ends_at
    )
  );
end;
$$;

grant execute on function public.start_game(uuid) to authenticated;
