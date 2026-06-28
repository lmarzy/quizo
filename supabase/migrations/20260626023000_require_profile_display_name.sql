update public.profiles
set display_name = 'Host'
where display_name is null
  or length(trim(display_name)) < 2;

alter table public.profiles
alter column display_name set not null;

alter table public.profiles
drop constraint if exists profiles_display_name_required;

alter table public.profiles
add constraint profiles_display_name_required
check (length(trim(display_name)) >= 2);

create or replace function public.create_profile_for_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  submitted_display_name text;
begin
  submitted_display_name := trim(coalesce(new.raw_user_meta_data->>'display_name', ''));

  if length(submitted_display_name) < 2 then
    raise exception 'Display name is required';
  end if;

  insert into public.profiles (id, email, display_name)
  values (
    new.id,
    new.email,
    submitted_display_name
  );

  insert into public.subscriptions (user_id, plan_id, status)
  values (new.id, 'free', 'free');

  return new;
end;
$$;

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
begin
  select *
  into profile_record
  from public.profiles
  where id = p_user_id;

  select
    raw_user_meta_data->>'display_name',
    raw_user_meta_data->>'username',
    coalesce(raw_user_meta_data->>'name', raw_user_meta_data->>'full_name')
  into auth_display_name, auth_username, auth_name
  from auth.users
  where id = p_user_id;

  return coalesce(
    nullif(trim(profile_record.display_name), ''),
    nullif(trim(auth_display_name), ''),
    nullif(trim(auth_username), ''),
    nullif(trim(auth_name), ''),
    'Host'
  );
end;
$$;

grant execute on function public.resolve_host_display_name(uuid) to authenticated;
