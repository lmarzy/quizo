do $$
declare
  function_definition text;
begin
  function_definition := pg_get_functiondef('public.get_game_room(text)'::regprocedure);

  function_definition := replace(
    function_definition,
    'question_record public.questions;',
    'question_record public.questions;
  question_pack_record public.question_packs;'
  );

  function_definition := replace(
    function_definition,
    'if game_record.current_question_id is not null then',
    'if game_record.question_pack_id is not null then
    select *
    into question_pack_record
    from public.question_packs
    where id = game_record.question_pack_id;
  end if;

  if game_record.current_question_id is not null then'
  );

  function_definition := replace(
    function_definition,
    '''join_code'', game_record.join_code,
      ''status'', game_record.status,',
    '''join_code'', game_record.join_code,
      ''question_pack_id'', game_record.question_pack_id,
      ''question_pack_name'', question_pack_record.name,
      ''question_pack_tier'', question_pack_record.tier,
      ''status'', game_record.status,'
  );

  execute function_definition;
end;
$$;
