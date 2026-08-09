-- Let invited players claim a game slot with their Quizo account while keeping
-- the existing anonymous guest-token flow available.

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
  current_user_id uuid := auth.uid();
begin
  select * into game_record
  from public.games
  where join_code = upper(trim(p_join_code)) and status in ('draft', 'lobby')
  limit 1;

  if game_record.id is null then
    raise exception 'Game is not open for joining';
  end if;

  select * into member_record
  from public.game_members
  where id = p_member_id and game_id = game_record.id
  for update;

  if member_record.id is null then
    raise exception 'Member slot not found';
  end if;
  if member_record.status <> 'invited' then
    raise exception 'This member has already joined';
  end if;

  if current_user_id is not null and exists (
    select 1 from public.game_members
    where game_id = game_record.id and user_id = current_user_id and status in ('joined', 'active')
  ) then
    raise exception 'Your account has already joined this game';
  end if;

  if current_user_id is null then
    session_token := gen_random_uuid()::text || '-' || gen_random_uuid()::text;
    session_hash := encode(digest(session_token, 'sha256'), 'hex');
  end if;

  update public.game_members
  set status = 'joined',
      joined_at = now(),
      user_id = current_user_id,
      guest_session_token_hash = case when current_user_id is null then session_hash else null end
  where id = member_record.id
  returning * into member_record;

  insert into public.game_events (game_id, member_id, event_type, message, metadata)
  values (
    game_record.id,
    member_record.id,
    'member_joined',
    member_record.display_name || ' joined the lobby',
    jsonb_build_object('member_id', member_record.id, 'account_join', current_user_id is not null)
  );

  return jsonb_build_object(
    'session_token', session_token,
    'game', jsonb_build_object(
      'id', game_record.id,
      'name', game_record.name,
      'join_code', game_record.join_code,
      'status', game_record.status
    ),
    'member', jsonb_build_object(
      'id', member_record.id,
      'display_name', member_record.display_name,
      'points', member_record.points,
      'status', member_record.status,
      'turn_order', member_record.turn_order,
      'account_join', current_user_id is not null
    )
  );
end;
$$;

grant execute on function public.claim_game_member(text, uuid) to anon, authenticated;

create or replace function public.get_my_game_member(p_join_code text)
returns jsonb
language sql
security definer
set search_path = public
stable
as $$
  select case when auth.uid() is null then null else (
    select jsonb_build_object('id', gm.id, 'display_name', gm.display_name, 'status', gm.status)
    from public.game_members gm
    join public.games g on g.id = gm.game_id
    where g.join_code = upper(trim(p_join_code))
      and gm.user_id = auth.uid()
      and gm.status in ('joined', 'active')
    limit 1
  ) end;
$$;

revoke all on function public.get_my_game_member(text) from public, anon;
grant execute on function public.get_my_game_member(text) to authenticated;
