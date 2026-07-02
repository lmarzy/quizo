create or replace function public.pick_unused_question_for_game(p_game_id uuid, p_pack_id uuid)
returns public.questions
language plpgsql
security definer
set search_path = public
as $$
declare
  question_record public.questions;
  total_questions integer;
begin
  select *
  into question_record
  from public.questions q
  where q.pack_id = p_pack_id
    and not exists (
      select 1
      from public.game_turns gt
      where gt.game_id = p_game_id
        and gt.question_id = q.id
    )
    and not exists (
      select 1
      from public.speed_rounds sr
      where sr.game_id = p_game_id
        and sr.question_id = q.id
    )
  order by random()
  limit 1;

  if question_record.id is null then
    select count(*)
    into total_questions
    from public.questions
    where pack_id = p_pack_id;

    if total_questions = 0 then
      raise exception 'Selected question pack has no questions';
    end if;

    raise exception 'No unused questions remain in this pack';
  end if;

  return question_record;
end;
$$;

grant execute on function public.pick_unused_question_for_game(uuid, uuid) to anon, authenticated;

do $$
declare
  function_definition text;
  patched_definition text;
  previous_question_block text := 'select *
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
  end if;';
  previous_turn_block text := 'select *
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
  end if;';
  unused_next_block text := 'select *
  into next_question
  from public.pick_unused_question_for_game(game_record.id, game_record.question_pack_id);';
  first_question_block text := 'select *
  into first_question
  from public.questions
  where pack_id = game_record.question_pack_id
  order by random()
  limit 1;';
  unused_first_block text := 'select *
  into first_question
  from public.pick_unused_question_for_game(game_record.id, game_record.question_pack_id);';
begin
  function_definition := pg_get_functiondef('public.start_game(uuid)'::regprocedure);
  patched_definition := replace(function_definition, first_question_block, unused_first_block);
  if patched_definition = function_definition then
    raise exception 'Could not patch start_game question selection';
  end if;
  execute patched_definition;

  function_definition := pg_get_functiondef('public.submit_game_answer(text, uuid, text, text)'::regprocedure);
  patched_definition := replace(function_definition, previous_question_block, unused_next_block);
  if patched_definition = function_definition then
    raise exception 'Could not patch submit_game_answer question selection';
  end if;
  execute patched_definition;

  function_definition := pg_get_functiondef('public.expire_current_turn_turn_based(text)'::regprocedure);
  patched_definition := replace(function_definition, previous_turn_block, unused_next_block);
  if patched_definition = function_definition then
    raise exception 'Could not patch expire_current_turn_turn_based question selection';
  end if;
  execute patched_definition;

  function_definition := pg_get_functiondef('public.submit_speed_round_answer(text, uuid, text, text)'::regprocedure);
  patched_definition := replace(function_definition, previous_question_block, unused_next_block);
  if patched_definition = function_definition then
    raise exception 'Could not patch submit_speed_round_answer question selection';
  end if;
  execute patched_definition;

  function_definition := pg_get_functiondef('public.expire_current_turn_non_ladder(text)'::regprocedure);
  patched_definition := replace(function_definition, previous_question_block, unused_next_block);
  if patched_definition = function_definition then
    raise exception 'Could not patch expire_current_turn_non_ladder question selection';
  end if;
  execute patched_definition;

  function_definition := pg_get_functiondef('public.advance_elimination_ladder(uuid)'::regprocedure);
  patched_definition := replace(function_definition, previous_question_block, unused_next_block);
  if patched_definition = function_definition then
    raise exception 'Could not patch advance_elimination_ladder question selection';
  end if;
  execute patched_definition;
end;
$$;
