do $$
declare
  function_definition text;
begin
  function_definition := pg_get_functiondef('public.submit_speed_round_answer(text, uuid, text, text)'::regprocedure);

  function_definition := replace(
    function_definition,
    'select count(*)
  into locked_count
  from (
    select member_id
    from public.speed_round_answers
    where round_id = round_record.id
    group by member_id
    having bool_or(is_correct)
      or bool_or(selected_option = ''TIMEOUT'')
      or count(*) >= game_record.max_consecutive_questions
  ) locked;',
    'select count(*)
  into locked_count
  from (
    select sra.member_id
    from public.speed_round_answers sra
    where sra.round_id = round_record.id
    group by sra.member_id
    having bool_or(sra.is_correct)
      or bool_or(sra.selected_option = ''TIMEOUT'')
      or count(*) >= game_record.max_consecutive_questions
  ) locked;'
  );

  execute function_definition;
end;
$$;
