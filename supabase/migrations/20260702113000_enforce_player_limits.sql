update public.plans
set max_players_per_game = case id
  when 'free' then 6
  when 'pro' then 20
  when 'creator' then 50
  else max_players_per_game
end
where id in ('free', 'pro', 'creator');

create or replace function public.get_effective_plan_id(p_user_id uuid)
returns text
language sql
security definer
set search_path = public
as $$
  select coalesce(
    (
      select case
        when s.plan_id = 'free' then 'free'
        when s.status in ('active', 'trialing') then s.plan_id
        else 'free'
      end
      from public.subscriptions s
      where s.user_id = p_user_id
    ),
    'free'
  );
$$;

create or replace function public.enforce_game_member_player_limit()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  host_id uuid;
  effective_plan_id text;
  plan_limit integer;
  plan_name text;
  existing_count integer;
begin
  select g.host_user_id
  into host_id
  from public.games g
  where g.id = new.game_id;

  if host_id is null then
    return new;
  end if;

  effective_plan_id := public.get_effective_plan_id(host_id);

  select p.max_players_per_game, p.name
  into plan_limit, plan_name
  from public.plans p
  where p.id = effective_plan_id;

  if plan_limit is null then
    return new;
  end if;

  select count(*)
  into existing_count
  from public.game_members gm
  where gm.game_id = new.game_id;

  if existing_count >= plan_limit then
    raise exception '% plan supports up to % players per game.', coalesce(plan_name, 'Current'), plan_limit;
  end if;

  return new;
end;
$$;

drop trigger if exists enforce_game_member_player_limit on public.game_members;

create trigger enforce_game_member_player_limit
before insert on public.game_members
for each row
execute function public.enforce_game_member_player_limit();
