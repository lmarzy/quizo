-- Account creation is prompted after play. Securely attach the completed guest
-- player to the newly authenticated account using the browser's guest token.

create or replace function public.link_guest_game_member_to_account(
  p_join_code text,
  p_member_id uuid,
  p_session_token text
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  game_record public.games;
  member_record public.game_members;
  session_hash text;
  current_user_id uuid := auth.uid();
begin
  if current_user_id is null then
    raise exception 'Sign in to save this result';
  end if;

  select * into game_record
  from public.games
  where join_code = upper(trim(p_join_code)) and status = 'finished'
  limit 1;

  if game_record.id is null then
    raise exception 'Completed game not found';
  end if;

  select * into member_record
  from public.game_members
  where id = p_member_id and game_id = game_record.id
  for update;

  if member_record.id is null then
    raise exception 'Player result not found';
  end if;
  if member_record.user_id = current_user_id then
    return jsonb_build_object('id', member_record.id, 'display_name', member_record.display_name, 'status', member_record.status);
  end if;
  if member_record.user_id is not null then
    raise exception 'This result is already connected to another account';
  end if;
  if exists (
    select 1 from public.game_members
    where game_id = game_record.id and user_id = current_user_id and id <> member_record.id
  ) then
    raise exception 'Your account is already connected to another player in this game';
  end if;

  session_hash := encode(digest(coalesce(p_session_token, ''), 'sha256'), 'hex');
  if member_record.guest_session_token_hash is distinct from session_hash then
    raise exception 'Player session is invalid';
  end if;

  update public.game_members
  set user_id = current_user_id,
      guest_session_token_hash = null
  where id = member_record.id
  returning * into member_record;

  insert into public.game_events (game_id, member_id, event_type, message, metadata)
  values (
    game_record.id,
    member_record.id,
    'result_saved',
    member_record.display_name || ' saved this result to a Quizo account',
    jsonb_build_object('member_id', member_record.id)
  );

  return jsonb_build_object('id', member_record.id, 'display_name', member_record.display_name, 'status', member_record.status);
end;
$$;

revoke all on function public.link_guest_game_member_to_account(text, uuid, text) from public, anon;
grant execute on function public.link_guest_game_member_to_account(text, uuid, text) to authenticated;

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
      and gm.status <> 'invited'
    limit 1
  ) end;
$$;

revoke all on function public.get_my_game_member(text) from public, anon;
grant execute on function public.get_my_game_member(text) to authenticated;
