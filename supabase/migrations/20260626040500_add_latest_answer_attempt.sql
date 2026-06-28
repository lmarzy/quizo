do $$
declare
  function_sql text;
begin
  select pg_get_functiondef('public.get_game_room(text)'::regprocedure)
  into function_sql;

  function_sql := replace(
    function_sql,
    '  latest_answer_question public.questions;
  members jsonb;',
    '  latest_answer_question public.questions;
  latest_answer_attempt integer := 1;
  members jsonb;'
  );

  function_sql := replace(
    function_sql,
    '    select *
    into latest_answer_question
    from public.questions
    where id = latest_answer_record.question_id;
  end if;',
    '    select *
    into latest_answer_question
    from public.questions
    where id = latest_answer_record.question_id;

    select coalesce((ge.metadata->>''attempt'')::integer, 1)
    into latest_answer_attempt
    from public.game_events ge
    where ge.game_id = latest_answer_record.game_id
      and ge.member_id = latest_answer_record.member_id
      and ge.event_type = ''answer_submitted''
      and ge.created_at between latest_answer_record.answered_at - interval ''2 seconds''
        and latest_answer_record.answered_at + interval ''2 seconds''
    order by ge.created_at desc
    limit 1;
  end if;'
  );

  function_sql := replace(
    function_sql,
    '        ''points_delta'', latest_answer_record.points_delta,
        ''correct_option'', latest_answer_question.correct_option,',
    '        ''points_delta'', latest_answer_record.points_delta,
        ''attempt'', latest_answer_attempt,
        ''correct_option'', latest_answer_question.correct_option,'
  );

  execute function_sql;
end;
$$;
