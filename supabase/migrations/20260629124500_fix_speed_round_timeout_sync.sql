do $$
begin
  alter publication supabase_realtime add table public.speed_rounds;
exception
  when duplicate_object then null;
end $$;

do $$
begin
  alter publication supabase_realtime add table public.speed_round_answers;
exception
  when duplicate_object then null;
end $$;

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

  if game_record.current_member_id is not null then
    select *
    into member_record
    from public.game_members
    where id = game_record.current_member_id
      and game_id = game_record.id
    for update;

    if member_record.id is not null then
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
        2
      );

      update public.game_members
      set points = points - game_record.wrong_answer_penalty
      where id = member_record.id;

      insert into public.game_events (game_id, member_id, event_type, message, metadata)
      values (
        game_record.id,
        member_record.id,
        'speed_round_timed_out',
        member_record.display_name || ' ran out of time on the second chance and lost ' || game_record.wrong_answer_penalty || ' points',
        jsonb_build_object('points_delta', -game_record.wrong_answer_penalty, 'attempt', 2, 'game_mode', game_record.game_mode)
      );
    end if;
  else
    insert into public.game_events (game_id, event_type, message, metadata)
    values (
      game_record.id,
      'speed_round_timed_out',
      'No one answered in time',
      jsonb_build_object('points_delta', 0, 'attempt', 1, 'game_mode', game_record.game_mode)
    );
  end if;

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

  if next_question.id is null then
    raise exception 'Selected question pack has no questions';
  end if;

  select coalesce(max(round_number), 0) + 1
  into next_round_number
  from public.speed_rounds
  where game_id = game_record.id;

  next_timer_ends_at := now() + make_interval(secs => game_record.question_time_limit_seconds);

  insert into public.speed_rounds (game_id, question_id, round_number, timer_ends_at)
  values (game_record.id, next_question.id, next_round_number, next_timer_ends_at);

  update public.games
  set current_member_id = null,
      current_question_id = next_question.id,
      current_turn_attempt = 1,
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
