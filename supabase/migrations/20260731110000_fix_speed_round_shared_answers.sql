-- Speed Round is a simultaneous mode: every active contestant gets exactly one
-- private answer per question. A later buzzer-recovery migration accidentally
-- advanced after the first answer and locked the next question to that player.

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
  submitted_answer jsonb;
begin
  selected_option := upper(trim(p_selected_option));
  if selected_option not in ('A', 'B', 'C') then
    raise exception 'Invalid answer option';
  end if;

  select * into game_record
  from public.games
  where join_code = upper(trim(p_join_code))
  for update;

  if game_record.id is null or game_record.status <> 'active' or game_record.game_mode <> 'speed_round' then
    raise exception 'Speed round is not active';
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
  if exists (
    select 1 from public.speed_round_answers
    where round_id = round_record.id and member_id = member_record.id
  ) then
    raise exception 'Your answer is already locked for this round';
  end if;

  select * into question_record from public.questions where id = round_record.question_id;
  answer_correct := question_record.correct_option = selected_option;
  points_delta := case when answer_correct then game_record.recovery_points else -game_record.wrong_answer_penalty end;

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
      when answer_correct then ' answered correctly and gained ' || points_delta || ' points'
      else ' answered incorrectly and lost ' || abs(points_delta) || ' points'
    end,
    jsonb_build_object(
      'selected_option', selected_option,
      'is_correct', answer_correct,
      'points_delta', points_delta,
      'attempt', 1,
      'game_mode', game_record.game_mode
    )
  );

  select * into winner_record
  from public.game_members
  where game_id = game_record.id and status = 'active' and points >= game_record.target_points
  order by points desc, updated_at asc
  limit 1;

  if winner_record.id is not null then
    update public.speed_rounds set completed_at = now() where id = round_record.id;
    update public.games
    set status = 'finished', current_member_id = null, current_question_id = null,
        timer_ends_at = null, finished_at = now()
    where id = game_record.id;
    insert into public.game_events (game_id, member_id, event_type, message)
    values (game_record.id, winner_record.id, 'game_finished', winner_record.display_name || ' reached ' || game_record.target_points || ' points');
    return public.get_game_room(game_record.join_code) || jsonb_build_object('submitted_answer', submitted_answer);
  end if;

  select count(*) into active_count
  from public.game_members where game_id = game_record.id and status = 'active';

  select count(distinct sra.member_id) into answered_count
  from public.speed_round_answers sra
  join public.game_members gm on gm.id = sra.member_id
  where sra.round_id = round_record.id and gm.status = 'active';

  if answered_count >= active_count then
    update public.speed_rounds set completed_at = now() where id = round_record.id;

    select * into next_question
    from public.questions q
    where q.pack_id = game_record.question_pack_id
      and q.id <> question_record.id
      and not exists (
        select 1 from public.speed_rounds previous
        where previous.game_id = game_record.id and previous.question_id = q.id
      )
    order by random()
    limit 1;

    if next_question.id is null then
      select * into next_question
      from public.questions
      where pack_id = game_record.question_pack_id and id <> question_record.id
      order by random()
      limit 1;
    end if;
    if next_question.id is null then
      raise exception 'Selected question pack has no questions';
    end if;

    select coalesce(max(round_number), 0) + 1 into next_round_number
    from public.speed_rounds where game_id = game_record.id;

    next_timer_ends_at := now() + make_interval(secs => game_record.question_time_limit_seconds + answer_reveal_delay_seconds);
    insert into public.speed_rounds (game_id, question_id, round_number, timer_ends_at)
    values (game_record.id, next_question.id, next_round_number, next_timer_ends_at);
    update public.games
    set current_member_id = null, current_question_id = next_question.id,
        current_turn_attempt = 1, timer_ends_at = next_timer_ends_at
    where id = game_record.id;
    insert into public.game_events (game_id, event_type, message, metadata)
    values (
      game_record.id, 'speed_round_started', 'Next speed round started',
      jsonb_build_object('question_id', next_question.id, 'round_number', next_round_number)
    );
  end if;

  return public.get_game_room(game_record.join_code) || jsonb_build_object('submitted_answer', submitted_answer);
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
  question_record public.questions;
  next_question public.questions;
  missing_member public.game_members;
  next_round_number integer;
  next_timer_ends_at timestamptz;
begin
  select * into game_record
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

  select * into round_record
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

  select * into question_record from public.questions where id = round_record.question_id;

  for missing_member in
    select gm.* from public.game_members gm
    where gm.game_id = game_record.id
      and gm.status = 'active'
      and not exists (
        select 1 from public.speed_round_answers sra
        where sra.round_id = round_record.id and sra.member_id = gm.id
      )
    for update
  loop
    insert into public.speed_round_answers (
      game_id, round_id, member_id, question_id, selected_option, is_correct, points_delta, attempt
    ) values (
      game_record.id, round_record.id, missing_member.id, question_record.id,
      'TIMEOUT', false, -game_record.wrong_answer_penalty, 1
    );
    update public.game_members
    set points = points - game_record.wrong_answer_penalty
    where id = missing_member.id;
    insert into public.game_events (game_id, member_id, event_type, message, metadata)
    values (
      game_record.id, missing_member.id, 'speed_round_timed_out',
      missing_member.display_name || ' ran out of time and lost ' || game_record.wrong_answer_penalty || ' points',
      jsonb_build_object('points_delta', -game_record.wrong_answer_penalty, 'attempt', 1, 'game_mode', game_record.game_mode)
    );
  end loop;

  update public.speed_rounds set completed_at = now() where id = round_record.id;

  select * into next_question
  from public.questions q
  where q.pack_id = game_record.question_pack_id
    and q.id <> question_record.id
    and not exists (
      select 1 from public.speed_rounds previous
      where previous.game_id = game_record.id and previous.question_id = q.id
    )
  order by random()
  limit 1;

  if next_question.id is null then
    select * into next_question
    from public.questions
    where pack_id = game_record.question_pack_id and id <> question_record.id
    order by random()
    limit 1;
  end if;
  if next_question.id is null then
    raise exception 'Selected question pack has no questions';
  end if;

  select coalesce(max(round_number), 0) + 1 into next_round_number
  from public.speed_rounds where game_id = game_record.id;

  next_timer_ends_at := now() + make_interval(secs => game_record.question_time_limit_seconds);
  insert into public.speed_rounds (game_id, question_id, round_number, timer_ends_at)
  values (game_record.id, next_question.id, next_round_number, next_timer_ends_at);
  update public.games
  set current_member_id = null, current_question_id = next_question.id,
      current_turn_attempt = 1, timer_ends_at = next_timer_ends_at
  where id = game_record.id;
  insert into public.game_events (game_id, event_type, message, metadata)
  values (
    game_record.id, 'speed_round_started', 'Next speed round started',
    jsonb_build_object('question_id', next_question.id, 'round_number', next_round_number)
  );

  return public.get_game_room(game_record.join_code);
end;
$$;

grant execute on function public.expire_current_turn(text) to anon, authenticated;
