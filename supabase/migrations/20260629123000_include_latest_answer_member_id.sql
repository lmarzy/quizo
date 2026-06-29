do $$
declare
  function_definition text;
begin
  function_definition := pg_get_functiondef('public.get_game_room(text)'::regprocedure);

  function_definition := replace(
    function_definition,
    '''member_name'', latest_answer_member.display_name,',
    '''member_id'', latest_answer_member.id,
        ''member_name'', latest_answer_member.display_name,'
  );

  execute function_definition;
end;
$$;
