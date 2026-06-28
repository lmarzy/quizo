create or replace function public.resolve_host_display_name(p_user_id uuid)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  profile_record public.profiles;
  auth_display_name text;
  auth_username text;
  auth_name text;
  auth_email text;
  email_prefix text;
begin
  select *
  into profile_record
  from public.profiles
  where id = p_user_id;

  select
    raw_user_meta_data->>'display_name',
    raw_user_meta_data->>'username',
    coalesce(raw_user_meta_data->>'name', raw_user_meta_data->>'full_name'),
    email
  into auth_display_name, auth_username, auth_name, auth_email
  from auth.users
  where id = p_user_id;

  email_prefix := split_part(coalesce(profile_record.email, auth_email, ''), '@', 1);

  return coalesce(
    nullif(profile_record.display_name, ''),
    nullif(auth_display_name, ''),
    nullif(auth_username, ''),
    nullif(auth_name, ''),
    nullif(email_prefix, ''),
    'Host'
  );
end;
$$;

create or replace function public.update_host_display_name(p_display_name text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  next_display_name text;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  next_display_name := trim(coalesce(p_display_name, ''));

  if length(next_display_name) < 2 then
    raise exception 'Display name must be at least 2 characters';
  end if;

  update public.profiles
  set display_name = next_display_name
  where id = auth.uid();

  update public.game_members gm
  set display_name = next_display_name
  from public.games g
  where gm.game_id = g.id
    and gm.user_id = auth.uid()
    and g.host_user_id = auth.uid()
    and g.status in ('draft', 'lobby', 'active');

  return jsonb_build_object('display_name', next_display_name);
end;
$$;

create or replace function public.add_host_as_player(p_game_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  game_record public.games;
  member_record public.game_members;
  next_order integer;
  host_display_name text;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  select *
  into game_record
  from public.games
  where id = p_game_id
  for update;

  if game_record.id is null then
    raise exception 'Game not found';
  end if;

  if game_record.host_user_id <> auth.uid() then
    raise exception 'Only the host can join this way';
  end if;

  if game_record.status not in ('draft', 'lobby') then
    raise exception 'Host can only join before the game starts';
  end if;

  host_display_name := public.resolve_host_display_name(auth.uid());

  select *
  into member_record
  from public.game_members
  where game_id = game_record.id
    and user_id = auth.uid()
  limit 1;

  if member_record.id is not null then
    update public.game_members
    set
      display_name = host_display_name,
      status = 'joined',
      joined_at = coalesce(joined_at, now())
    where id = member_record.id
    returning * into member_record;
  else
    select coalesce(max(turn_order), 0) + 1
    into next_order
    from public.game_members
    where game_id = game_record.id;

    insert into public.game_members (
      game_id,
      user_id,
      display_name,
      points,
      status,
      turn_order,
      joined_at
    )
    values (
      game_record.id,
      auth.uid(),
      host_display_name,
      game_record.starting_points,
      'joined',
      next_order,
      now()
    )
    returning * into member_record;
  end if;

  insert into public.game_events (game_id, member_id, event_type, message, metadata)
  values (
    game_record.id,
    member_record.id,
    'member_joined',
    member_record.display_name || ' joined the lobby',
    jsonb_build_object('member_id', member_record.id, 'user_id', auth.uid())
  );

  return jsonb_build_object(
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

grant execute on function public.resolve_host_display_name(uuid) to authenticated;
grant execute on function public.update_host_display_name(text) to authenticated;
grant execute on function public.add_host_as_player(uuid) to authenticated;
