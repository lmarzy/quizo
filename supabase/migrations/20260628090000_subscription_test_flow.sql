update public.subscriptions
set plan_id = 'creator'
where plan_id = 'business';

insert into public.plans (
  id,
  name,
  monthly_game_limit,
  max_players_per_game,
  custom_question_packs_enabled,
  premium_packs_enabled,
  branding_enabled
)
values
  ('free', 'Free', 3, 8, false, false, false),
  ('pro', 'Pro', null, 50, false, true, false),
  ('creator', 'Creator', null, 100, true, true, true)
on conflict (id) do update
set
  name = excluded.name,
  monthly_game_limit = excluded.monthly_game_limit,
  max_players_per_game = excluded.max_players_per_game,
  custom_question_packs_enabled = excluded.custom_question_packs_enabled,
  premium_packs_enabled = excluded.premium_packs_enabled,
  branding_enabled = excluded.branding_enabled;

delete from public.plans
where id = 'business';

alter table public.question_packs
drop constraint if exists question_packs_tier_check;

update public.question_packs
set tier = 'pro'
where tier = 'premium';

alter table public.question_packs
add constraint question_packs_tier_check
check (tier in ('free', 'pro', 'creator'));

insert into public.question_packs (id, owner_user_id, name, description, visibility, tier)
values
  ('00000000-0000-0000-0000-000000000103', null, 'Movies and TV', 'Entertainment questions for casual games.', 'public', 'pro'),
  ('00000000-0000-0000-0000-000000000104', null, 'Sports Night', 'Competitive sports questions for pub-quiz style games.', 'public', 'pro'),
  ('00000000-0000-0000-0000-000000000105', null, 'Music Legends', 'Artists, albums, lyrics, and chart trivia.', 'public', 'pro'),
  ('00000000-0000-0000-0000-000000000106', null, 'Geography', 'Countries, capitals, landmarks, and world facts.', 'public', 'pro'),
  ('00000000-0000-0000-0000-000000000107', null, 'History', 'People, events, and moments from across the ages.', 'public', 'pro'),
  ('00000000-0000-0000-0000-000000000108', null, 'Science and Nature', 'Space, animals, inventions, and natural wonders.', 'public', 'pro'),
  ('00000000-0000-0000-0000-000000000109', null, 'Food and Drink', 'Kitchen classics, world dishes, and tasty trivia.', 'public', 'pro'),
  ('00000000-0000-0000-0000-000000000110', null, '90s and 00s', 'Throwback TV, music, tech, toys, and pop culture.', 'public', 'pro'),
  ('00000000-0000-0000-0000-000000000111', null, 'Custom Pack Builder', 'Create your own question packs for private games.', 'public', 'creator')
on conflict (id) do update
set
  name = excluded.name,
  description = excluded.description,
  visibility = excluded.visibility,
  tier = excluded.tier;

create or replace function public.set_test_subscription_plan(p_plan_id text)
returns public.subscriptions
language plpgsql
security definer
set search_path = public
as $$
declare
  sub_record public.subscriptions;
begin
  if auth.uid() is null then
    raise exception 'You must be signed in to change plan.';
  end if;

  if p_plan_id not in ('free', 'pro', 'creator') then
    raise exception 'Unsupported test plan.';
  end if;

  insert into public.subscriptions (
    user_id,
    plan_id,
    status,
    stripe_customer_id,
    stripe_subscription_id,
    stripe_price_id,
    current_period_end,
    cancel_at_period_end
  )
  values (
    auth.uid(),
    p_plan_id,
    case
      when p_plan_id = 'free' then 'free'::public.subscription_status
      else 'active'::public.subscription_status
    end,
    null,
    null,
    null,
    case
      when p_plan_id = 'free' then null
      else now() + interval '30 days'
    end,
    false
  )
  on conflict (user_id) do update
  set
    plan_id = excluded.plan_id,
    status = excluded.status,
    stripe_customer_id = null,
    stripe_subscription_id = null,
    stripe_price_id = null,
    current_period_end = excluded.current_period_end,
    cancel_at_period_end = false,
    updated_at = now()
  returning * into sub_record;

  return sub_record;
end;
$$;

grant execute on function public.set_test_subscription_plan(text) to authenticated;
