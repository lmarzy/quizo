-- A rematch is a new game so the completed game's results and answers remain
-- immutable. Copy its rules, pack, and player roster into a fresh lobby.

create or replace function public.create_game_rematch(p_game_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  source_game public.games;
  rematch_game public.games;
begin
  select * into source_game
  from public.games
  where id = p_game_id
  for update;

  if source_game.id is null then
    raise exception 'Game not found';
  end if;
  if source_game.host_user_id <> auth.uid() then
    raise exception 'Only the host can create a rematch';
  end if;
  if source_game.status <> 'finished' then
    raise exception 'Only a finished game can be played again';
  end if;

  insert into public.games (
    host_user_id,
    question_pack_id,
    name,
    join_code,
    status,
    game_mode,
    starting_points,
    target_points,
    elimination_rounds,
    questions_per_round,
    wrong_answer_penalty,
    recovery_points,
    question_time_limit_seconds,
    max_consecutive_questions
  ) values (
    source_game.host_user_id,
    source_game.question_pack_id,
    source_game.name || ' · Rematch',
    '',
    'lobby',
    source_game.game_mode,
    source_game.starting_points,
    source_game.target_points,
    source_game.elimination_rounds,
    source_game.questions_per_round,
    source_game.wrong_answer_penalty,
    source_game.recovery_points,
    source_game.question_time_limit_seconds,
    source_game.max_consecutive_questions
  )
  returning * into rematch_game;

  insert into public.game_members (
    game_id,
    user_id,
    display_name,
    points,
    status,
    turn_order,
    joined_at
  )
  select
    rematch_game.id,
    case when gm.user_id = auth.uid() then auth.uid() else null end,
    gm.display_name,
    rematch_game.starting_points,
    case when gm.user_id = auth.uid() then 'joined'::public.member_status else 'invited'::public.member_status end,
    gm.turn_order,
    case when gm.user_id = auth.uid() then now() else null end
  from public.game_members gm
  where gm.game_id = source_game.id
    and gm.status <> 'left'
  order by gm.turn_order, gm.created_at;

  insert into public.game_events (game_id, event_type, message, metadata)
  values (
    rematch_game.id,
    'rematch_created',
    'Rematch created from ' || source_game.name,
    jsonb_build_object('source_game_id', source_game.id, 'source_join_code', source_game.join_code)
  );

  return to_jsonb(rematch_game);
end;
$$;

revoke all on function public.create_game_rematch(uuid) from public, anon;
grant execute on function public.create_game_rematch(uuid) to authenticated;
