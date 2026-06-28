create or replace function public.get_joinable_game(p_join_code text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  game_record public.games;
  members jsonb;
begin
  select *
  into game_record
  from public.games
  where join_code = upper(trim(p_join_code))
    and status in ('draft', 'lobby', 'active', 'finished')
  limit 1;

  if game_record.id is null then
    raise exception 'Game not found';
  end if;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', gm.id,
        'display_name', gm.display_name,
        'points', gm.points,
        'status', gm.status,
        'turn_order', gm.turn_order,
        'joined_at', gm.joined_at
      )
      order by gm.turn_order, gm.created_at
    ),
    '[]'::jsonb
  )
  into members
  from public.game_members gm
  where gm.game_id = game_record.id;

  return jsonb_build_object(
    'game',
    jsonb_build_object(
      'id', game_record.id,
      'name', game_record.name,
      'join_code', game_record.join_code,
      'status', game_record.status,
      'starting_points', game_record.starting_points,
      'question_time_limit_seconds', game_record.question_time_limit_seconds
    ),
    'members',
    members
  );
end;
$$;

grant execute on function public.get_joinable_game(text) to anon, authenticated;
