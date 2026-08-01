-- Make Speed Round a true buzzer mode. The first correct response advances the
-- whole room; a wrong response locks out only that contestant for the question.

create or replace function public.advance_speed_round_question(
  p_game_id uuid,
  p_round_id uuid,
  p_question_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  game_record public.games;
  next_question public.questions;
  next_round_number integer;
  next_timer_ends_at timestamptz;
  answer_reveal_delay_seconds integer := 5;
begin
  select * into game_record from public.games where id = p_game_id;

  update public.speed_rounds
  set completed_at = now()
  where id = p_round_id and completed_at is null;

  select * into next_question
  from public.questions q
  where q.pack_id = game_record.question_pack_id
    and q.id <> p_question_id
    and not exists (
      select 1 from public.speed_rounds previous
      where previous.game_id = game_record.id and previous.question_id = q.id
    )
  order by random()
  limit 1;

  if next_question.id is null then
    select * into next_question
    from public.questions
    where pack_id = game_record.question_pack_id and id <> p_question_id
    order by random()
    limit 1;
  end if;

  if next_question.id is null then
    raise exception 'Selected question pack has no questions';
  end if;

  select coalesce(max(round_number), 0) + 1 into next_round_number
  from public.speed_rounds where game_id = game_record.id;

  next_timer_ends_at := now() + make_interval(
    secs => game_record.question_time_limit_seconds + answer_reveal_delay_seconds
  );

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
    'Next speed round question started',
    jsonb_build_object('question_id', next_question.id, 'round_number', next_round_number)
  );
end;
$$;

revoke all on function public.advance_speed_round_question(uuid, uuid, uuid) from public, anon, authenticated;

create or replace function public.submit_speed_round_answer(
  p_join_code text,
  p_member_id uuid,
  p_session_token text,
  p_selected_option text,
  p_question_id uuid
)
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
  winner_record public.game_members;
  submitted_answer jsonb;
begin
  selected_option := upper(trim(p_selected_option));
  if selected_option not in ('A', 'B', 'C') then
    raise exception 'Invalid answer option';
  end if;

  -- Serialising on the game row determines the authoritative buzzer order.
  select * into game_record
  from public.games
  where join_code = upper(trim(p_join_code))
  for update;

  if game_record.id is null or game_record.status <> 'active' or game_record.game_mode <> 'speed_round' then
    raise exception 'Speed round is not active';
  end if;
  if game_record.current_question_id is distinct from p_question_id then
    raise exception 'That question has already ended';
  end if;

  select * into member_record
  from public.game_members
  where id = p_member_id and game_id = game_record.id and status = 'active'
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

  select * into round_record
  from public.speed_rounds
  where game_id = game_record.id
    and question_id = p_question_id
    and completed_at is null
  order by round_number desc
  limit 1
  for update;

  if round_record.id is null then
    raise exception 'That question has already been won';
  end if;
  if now() > round_record.timer_ends_at then
    raise exception 'Round timer has expired';
  end if;
  if exists (
    select 1 from public.speed_round_answers
    where round_id = round_record.id and member_id = member_record.id
  ) then
    raise exception 'You are already out for this question';
  end if;

  select * into question_record from public.questions where id = round_record.question_id;
  answer_correct := question_record.correct_option = selected_option;
  points_delta := case
    when answer_correct then game_record.recovery_points
    else -game_record.wrong_answer_penalty
  end;

  insert into public.speed_round_answers (
    game_id, round_id, member_id, question_id, selected_option, is_correct, points_delta, attempt
  ) values (
    game_record.id, round_record.id, member_record.id, question_record.id,
    selected_option, answer_correct, points_delta, 1
  );

  update public.game_members
  set points = points + points_delta
  where id = member_record.id
  returning * into member_record;

  submitted_answer := jsonb_build_object(
    'id', gen_random_uuid(),
    'member_id', member_record.id,
    'member_name', member_record.display_name,
    'selected_option', selected_option,
    'is_correct', answer_correct,
    'points_delta', points_delta,
    'attempt', 1,
    'correct_option', question_record.correct_option,
    'correct_answer', case question_record.correct_option
      when 'A' then question_record.option_a
      when 'B' then question_record.option_b
      when 'C' then question_record.option_c
    end,
    'answered_at', now()
  );

  insert into public.game_events (game_id, member_id, event_type, message, metadata)
  values (
    game_record.id,
    member_record.id,
    case when answer_correct then 'answer_correct' else 'answer_wrong' end,
    member_record.display_name || case
      when answer_correct then ' buzzed in first with the correct answer and gained ' || points_delta || ' points'
      else ' buzzed in with a wrong answer, lost ' || abs(points_delta) || ' points, and is out for this question'
    end,
    jsonb_build_object(
      'selected_option', selected_option,
      'is_correct', answer_correct,
      'points_delta', points_delta,
      'attempt', 1,
      'game_mode', game_record.game_mode,
      'buzzer_result', case when answer_correct then 'won_question' else 'locked_out' end
    )
  );

  if answer_correct then
    select * into winner_record
    from public.game_members
    where id = member_record.id and points >= game_record.target_points;

    if winner_record.id is not null then
      update public.speed_rounds set completed_at = now() where id = round_record.id;
      update public.games
      set status = 'finished', current_member_id = null, current_question_id = null,
          timer_ends_at = null, finished_at = now()
      where id = game_record.id;
      insert into public.game_events (game_id, member_id, event_type, message)
      values (
        game_record.id,
        winner_record.id,
        'game_finished',
        winner_record.display_name || ' reached ' || game_record.target_points || ' points'
      );
    else
      perform public.advance_speed_round_question(game_record.id, round_record.id, question_record.id);
    end if;

    return public.get_game_room(game_record.join_code)
      || jsonb_build_object('submitted_answer', submitted_answer);
  end if;

  select count(*) into active_count
  from public.game_members
  where game_id = game_record.id and status = 'active';

  select count(distinct sra.member_id) into answered_count
  from public.speed_round_answers sra
  join public.game_members gm on gm.id = sra.member_id
  where sra.round_id = round_record.id and gm.status = 'active';

  -- If everybody missed, close the question and reset the buzzer for a new one.
  if answered_count >= active_count then
    perform public.advance_speed_round_question(game_record.id, round_record.id, question_record.id);
  end if;

  return public.get_game_room(game_record.join_code)
    || jsonb_build_object('submitted_answer', submitted_answer);
end;
$$;

grant execute on function public.submit_speed_round_answer(text, uuid, text, text, uuid) to anon, authenticated;
