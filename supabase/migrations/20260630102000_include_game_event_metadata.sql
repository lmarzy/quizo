do $$
declare
  function_definition text;
begin
  function_definition := pg_get_functiondef('public.get_game_room(text)'::regprocedure);
  function_definition := replace(
    function_definition,
    '''event_type'', ge.event_type,
        ''message'', ge.message,
        ''created_at'', ge.created_at',
    '''event_type'', ge.event_type,
        ''member_id'', ge.member_id,
        ''message'', ge.message,
        ''metadata'', ge.metadata,
        ''created_at'', ge.created_at'
  );
  execute function_definition;
end;
$$;
