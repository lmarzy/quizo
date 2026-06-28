create or replace function public.claim_game_member(p_join_code text, p_member_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  game_record public.games;
  member_record public.game_members;
  session_token text;
  session_hash text;
begin
  select *
  into game_record
  from public.games
  where join_code = upper(trim(p_join_code))
    and status in ('draft', 'lobby')
  limit 1;

  if game_record.id is null then
    raise exception 'Game is not open for joining';
  end if;

  select *
  into member_record
  from public.game_members
  where id = p_member_id
    and game_id = game_record.id
  for update;

  if member_record.id is null then
    raise exception 'Member slot not found';
  end if;

  if member_record.status not in ('invited', 'joined') then
    raise exception 'Member slot is not available';
  end if;

  if member_record.status = 'joined' then
    raise exception 'This member has already joined';
  end if;

  session_token := gen_random_uuid()::text || '-' || gen_random_uuid()::text;
  session_hash := encode(digest(session_token, 'sha256'), 'hex');

  update public.game_members
  set
    status = 'joined',
    joined_at = now(),
    guest_session_token_hash = session_hash
  where id = member_record.id
  returning * into member_record;

  insert into public.game_events (game_id, member_id, event_type, message, metadata)
  values (
    game_record.id,
    member_record.id,
    'member_joined',
    member_record.display_name || ' joined the lobby',
    jsonb_build_object('member_id', member_record.id)
  );

  return jsonb_build_object(
    'session_token', session_token,
    'game',
    jsonb_build_object(
      'id', game_record.id,
      'name', game_record.name,
      'join_code', game_record.join_code,
      'status', game_record.status
    ),
    'member',
    jsonb_build_object(
      'id', member_record.id,
      'display_name', member_record.display_name,
      'points', member_record.points,
      'status', member_record.status,
      'turn_order', member_record.turn_order
    )
  );
end;
$$;

grant execute on function public.claim_game_member(text, uuid) to anon, authenticated;
