do $$
declare
  function_sql text;
begin
  select pg_get_functiondef('public.submit_game_answer(text, uuid, text, text)'::regprocedure)
  into function_sql;

  execute replace(
    function_sql,
    'answer_reveal_delay_seconds integer := 3;',
    'answer_reveal_delay_seconds integer := 5;'
  );

  select pg_get_functiondef('public.expire_current_turn(text)'::regprocedure)
  into function_sql;

  execute replace(
    function_sql,
    'answer_reveal_delay_seconds integer := 3;',
    'answer_reveal_delay_seconds integer := 5;'
  );
end;
$$;
