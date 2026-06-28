alter table public.games
  alter column question_time_limit_seconds set default 10;

do $$
declare
  function_sql text;
begin
  select pg_get_functiondef('public.get_game_room(text)'::regprocedure)
  into function_sql;

  if position('''question_time_limit_seconds'', game_record.question_time_limit_seconds' in function_sql) = 0 then
    function_sql := replace(
      function_sql,
      '      ''current_question_id'', game_record.current_question_id,',
      '      ''current_question_id'', game_record.current_question_id,
      ''question_time_limit_seconds'', game_record.question_time_limit_seconds,'
    );
  end if;

  execute function_sql;
end;
$$;
