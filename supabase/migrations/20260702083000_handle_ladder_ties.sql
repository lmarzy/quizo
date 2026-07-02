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
  lowest_score integer;
  lowest_count integer;
  highest_score integer;
  highest_count integer;
  is_scoring_boundary boolean;
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
  is_scoring_boundary := question_in_round >= game_record.questions_per_round or ladder_round >= game_record.elimination_rounds;

  select count(*)
  into active_count
  from public.game_members
  where game_id = game_record.id
    and status = 'active';

  if is_scoring_boundary and active_count > 1 then
    select min(points)
    into lowest_score
    from public.game_members
    where game_id = game_record.id
      and status = 'active';

    select count(*)
    into lowest_count
    from public.game_members
    where game_id = game_record.id
      and status = 'active'
      and points = lowest_score;

    if lowest_count = 1 and ladder_round < game_record.elimination_rounds then
      select *
      into eliminated_member
      from public.game_members
      where game_id = game_record.id
        and status = 'active'
        and points = lowest_score
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
    elsif lowest_count > 1 then
      insert into public.game_events (game_id, event_type, message, metadata)
      values (
        game_record.id,
        case when ladder_round >= game_record.elimination_rounds then 'ladder_final_tied' else 'ladder_round_tied' end,
        'Scores are tied. No one is eliminated yet.',
        jsonb_build_object('ladder_round', ladder_round, 'points', lowest_score, 'tied_member_count', lowest_count)
      );
    end if;
  end if;

  select count(*)
  into remaining_count
  from public.game_members
  where game_id = game_record.id
    and status = 'active';

  select max(points)
  into highest_score
  from public.game_members
  where game_id = game_record.id
    and status = 'active';

  select count(*)
  into highest_count
  from public.game_members
  where game_id = game_record.id
    and status = 'active'
    and points = highest_score;

  if remaining_count <= 1 or (ladder_round >= game_record.elimination_rounds and highest_count = 1) then
    select *
    into winner_record
    from public.game_members
    where game_id = game_record.id
      and status = 'active'
    order by points desc
    limit 1;

    if winner_record.id is null then
      select *
      into winner_record
      from public.game_members
      where game_id = game_record.id
      order by points desc
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

do $$
declare
  function_definition text;
begin
  function_definition := pg_get_functiondef('public.get_game_room(text)'::regprocedure);
  function_definition := replace(
    function_definition,
    'event_type = ''player_eliminated''',
    'event_type in (''player_eliminated'', ''ladder_round_tied'', ''ladder_final_tied'')'
  );
  execute function_definition;
end;
$$;
