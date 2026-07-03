do $$
declare
  function_definition text;
  patched_definition text;
  current_finish_block text := 'if game_record.game_mode = ''race_to_points'' and member_record.points >= game_record.target_points then';
  target_finish_block text := 'if (
    game_record.game_mode = ''race_to_points''
    or (
      game_record.game_mode = ''classic''
      and game_record.target_points > game_record.starting_points
    )
  ) and member_record.points >= game_record.target_points then';
begin
  update public.games
  set target_points = greatest(target_points, starting_points + 50)
  where game_mode = 'classic'
    and status in ('draft', 'lobby')
    and target_points <= starting_points;

  function_definition := pg_get_functiondef('public.submit_game_answer(text, uuid, text, text)'::regprocedure);
  patched_definition := replace(function_definition, current_finish_block, target_finish_block);

  if patched_definition = function_definition then
    raise exception 'Could not patch submit_game_answer target finish condition';
  end if;

  execute patched_definition;
end;
$$;
