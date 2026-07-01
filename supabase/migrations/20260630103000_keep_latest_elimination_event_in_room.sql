do $$
declare
  function_definition text;
begin
  function_definition := pg_get_functiondef('public.get_game_room(text)'::regprocedure);
  function_definition := replace(
    function_definition,
    'from (
    select *
    from public.game_events
    where game_id = game_record.id
    order by created_at desc
    limit 8
  ) ge;',
    'from (
    select *
    from (
      select *
      from public.game_events
      where game_id = game_record.id
      order by created_at desc
      limit 16
    ) recent_events
    union
    select *
    from (
      select *
      from public.game_events
      where game_id = game_record.id
        and event_type = ''player_eliminated''
      order by created_at desc
      limit 1
    ) latest_elimination_event
  ) ge;'
  );
  execute function_definition;
end;
$$;
