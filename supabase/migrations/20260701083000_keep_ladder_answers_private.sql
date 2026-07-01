do $$
declare
  function_definition text;
begin
  function_definition := pg_get_functiondef('public.get_game_room(text)'::regprocedure);
  function_definition := replace(
    function_definition,
    '''selected_option'', sra.selected_option,
            ''is_correct'', sra.is_correct,
            ''points_delta'', sra.points_delta,',
    '''selected_option'', case when game_record.game_mode = ''elimination_ladder'' then ''LOCKED'' else sra.selected_option end,
            ''is_correct'', case when game_record.game_mode = ''elimination_ladder'' then null else sra.is_correct end,
            ''points_delta'', case when game_record.game_mode = ''elimination_ladder'' then 0 else sra.points_delta end,'
  );
  function_definition := replace(
    function_definition,
    'when game_record.game_mode in (''speed_round'', ''elimination_ladder'') and latest_speed_answer_record.id is not null then jsonb_build_object(',
    'when game_record.game_mode = ''speed_round'' and latest_speed_answer_record.id is not null then jsonb_build_object('
  );
  execute function_definition;

  function_definition := pg_get_functiondef('public.submit_elimination_ladder_answer(text, uuid, text, text)'::regprocedure);
  function_definition := replace(
    function_definition,
    'answered_count integer;',
    'answered_count integer;
  submitted_answer jsonb;'
  );
  function_definition := replace(
    function_definition,
    'points_delta := case when answer_correct then game_record.recovery_points else -game_record.wrong_answer_penalty end;',
    'points_delta := case when answer_correct then game_record.recovery_points else -game_record.wrong_answer_penalty end;
  submitted_answer := jsonb_build_object(
    ''id'', gen_random_uuid(),
    ''member_id'', member_record.id,
    ''member_name'', member_record.display_name,
    ''selected_option'', selected_option,
    ''is_correct'', answer_correct,
    ''points_delta'', points_delta,
    ''attempt'', 1,
    ''correct_option'', question_record.correct_option,
    ''correct_answer'',
      case question_record.correct_option
        when ''A'' then question_record.option_a
        when ''B'' then question_record.option_b
        when ''C'' then question_record.option_c
      end,
    ''answered_at'', now()
  );'
  );
  function_definition := replace(
    function_definition,
    'return public.advance_elimination_ladder(game_record.id);',
    'return public.advance_elimination_ladder(game_record.id) || jsonb_build_object(''submitted_answer'', submitted_answer);'
  );
  function_definition := replace(
    function_definition,
    'return public.get_game_room(game_record.join_code);',
    'return public.get_game_room(game_record.join_code) || jsonb_build_object(''submitted_answer'', submitted_answer);'
  );
  execute function_definition;
end;
$$;
