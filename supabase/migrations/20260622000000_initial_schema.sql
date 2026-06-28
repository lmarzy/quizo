create extension if not exists pgcrypto;

create type public.game_status as enum ('draft', 'lobby', 'active', 'finished', 'cancelled');
create type public.member_status as enum ('invited', 'joined', 'ready', 'active', 'eliminated', 'left');
create type public.turn_status as enum ('pending', 'answered', 'timed_out', 'skipped');
create type public.subscription_status as enum ('free', 'trialing', 'active', 'past_due', 'cancelled', 'unpaid');

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text,
  display_name text,
  role text not null default 'host' check (role in ('host', 'platform_admin')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.plans (
  id text primary key,
  name text not null,
  monthly_game_limit integer,
  max_players_per_game integer not null,
  custom_question_packs_enabled boolean not null default false,
  premium_packs_enabled boolean not null default false,
  branding_enabled boolean not null default false,
  created_at timestamptz not null default now()
);

create table public.subscriptions (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  plan_id text not null references public.plans(id),
  status public.subscription_status not null default 'free',
  stripe_customer_id text,
  stripe_subscription_id text,
  stripe_price_id text,
  current_period_end timestamptz,
  cancel_at_period_end boolean not null default false,
  updated_at timestamptz not null default now()
);

create table public.question_packs (
  id uuid primary key default gen_random_uuid(),
  owner_user_id uuid references public.profiles(id) on delete cascade,
  name text not null,
  description text,
  visibility text not null default 'public' check (visibility in ('public', 'private')),
  tier text not null default 'free' check (tier in ('free', 'premium')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.questions (
  id uuid primary key default gen_random_uuid(),
  pack_id uuid not null references public.question_packs(id) on delete cascade,
  prompt text not null,
  option_a text not null,
  option_b text not null,
  option_c text not null,
  option_d text not null,
  correct_option text not null check (correct_option in ('A', 'B', 'C')),
  difficulty text not null default 'easy' check (difficulty in ('easy', 'medium', 'hard')),
  created_at timestamptz not null default now()
);

create table public.games (
  id uuid primary key default gen_random_uuid(),
  host_user_id uuid not null references public.profiles(id) on delete cascade,
  question_pack_id uuid references public.question_packs(id) on delete set null,
  name text not null,
  join_code text not null unique,
  status public.game_status not null default 'draft',
  starting_points integer not null default 100 check (starting_points > 0),
  wrong_answer_penalty integer not null default 10 check (wrong_answer_penalty >= 0),
  recovery_points integer not null default 10 check (recovery_points >= 0),
  question_time_limit_seconds integer not null default 30 check (question_time_limit_seconds between 5 and 300),
  max_consecutive_questions integer not null default 3 check (max_consecutive_questions between 1 and 20),
  current_member_id uuid,
  current_question_id uuid references public.questions(id) on delete set null,
  timer_ends_at timestamptz,
  started_at timestamptz,
  finished_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.game_members (
  id uuid primary key default gen_random_uuid(),
  game_id uuid not null references public.games(id) on delete cascade,
  user_id uuid references public.profiles(id) on delete set null,
  display_name text not null,
  invite_token uuid not null default gen_random_uuid(),
  guest_session_token_hash text,
  points integer not null default 100,
  status public.member_status not null default 'invited',
  turn_order integer not null default 0,
  joined_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (game_id, display_name),
  unique (game_id, invite_token)
);

alter table public.games
  add constraint games_current_member_id_fkey
  foreign key (current_member_id) references public.game_members(id) on delete set null;

create table public.game_turns (
  id uuid primary key default gen_random_uuid(),
  game_id uuid not null references public.games(id) on delete cascade,
  member_id uuid not null references public.game_members(id) on delete cascade,
  question_id uuid not null references public.questions(id) on delete restrict,
  turn_number integer not null,
  status public.turn_status not null default 'pending',
  timer_ends_at timestamptz,
  created_at timestamptz not null default now(),
  completed_at timestamptz,
  unique (game_id, turn_number)
);

create table public.game_answers (
  id uuid primary key default gen_random_uuid(),
  game_id uuid not null references public.games(id) on delete cascade,
  turn_id uuid not null references public.game_turns(id) on delete cascade,
  member_id uuid not null references public.game_members(id) on delete cascade,
  question_id uuid not null references public.questions(id) on delete restrict,
  selected_option text not null check (selected_option in ('A', 'B', 'C')),
  is_correct boolean not null,
  points_delta integer not null default 0,
  answered_at timestamptz not null default now(),
  unique (turn_id, member_id)
);

create table public.game_events (
  id uuid primary key default gen_random_uuid(),
  game_id uuid not null references public.games(id) on delete cascade,
  member_id uuid references public.game_members(id) on delete set null,
  event_type text not null,
  message text not null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index profiles_email_idx on public.profiles(email);
create index games_host_user_id_idx on public.games(host_user_id);
create index games_join_code_idx on public.games(join_code);
create index game_members_game_id_idx on public.game_members(game_id);
create index game_turns_game_id_idx on public.game_turns(game_id);
create index game_events_game_id_created_at_idx on public.game_events(game_id, created_at desc);

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger profiles_set_updated_at
before update on public.profiles
for each row execute function public.set_updated_at();

create trigger subscriptions_set_updated_at
before update on public.subscriptions
for each row execute function public.set_updated_at();

create trigger question_packs_set_updated_at
before update on public.question_packs
for each row execute function public.set_updated_at();

create trigger games_set_updated_at
before update on public.games
for each row execute function public.set_updated_at();

create trigger game_members_set_updated_at
before update on public.game_members
for each row execute function public.set_updated_at();

create or replace function public.create_profile_for_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, email, display_name)
  values (
    new.id,
    new.email,
    coalesce(new.raw_user_meta_data->>'display_name', split_part(new.email, '@', 1))
  );

  insert into public.subscriptions (user_id, plan_id, status)
  values (new.id, 'free', 'free');

  return new;
end;
$$;

create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.create_profile_for_new_user();

create or replace function public.generate_join_code()
returns text
language plpgsql
as $$
declare
  alphabet text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  code text := '';
  i integer;
begin
  for i in 1..6 loop
    code := code || substr(alphabet, 1 + floor(random() * length(alphabet))::integer, 1);
  end loop;
  return code;
end;
$$;

create or replace function public.assign_game_join_code()
returns trigger
language plpgsql
as $$
begin
  if new.join_code is null or length(trim(new.join_code)) = 0 then
    loop
      new.join_code := public.generate_join_code();
      exit when not exists (select 1 from public.games where join_code = new.join_code);
    end loop;
  end if;

  new.join_code := upper(new.join_code);
  return new;
end;
$$;

create trigger games_assign_join_code
before insert on public.games
for each row execute function public.assign_game_join_code();

alter table public.profiles enable row level security;
alter table public.plans enable row level security;
alter table public.subscriptions enable row level security;
alter table public.question_packs enable row level security;
alter table public.questions enable row level security;
alter table public.games enable row level security;
alter table public.game_members enable row level security;
alter table public.game_turns enable row level security;
alter table public.game_answers enable row level security;
alter table public.game_events enable row level security;

create policy "Users can read their own profile"
on public.profiles for select
using (auth.uid() = id);

create policy "Users can update their own profile"
on public.profiles for update
using (auth.uid() = id)
with check (auth.uid() = id);

create policy "Anyone can read plans"
on public.plans for select
using (true);

create policy "Users can read their own subscription"
on public.subscriptions for select
using (auth.uid() = user_id);

create policy "Hosts can read available question packs"
on public.question_packs for select
using (
  visibility = 'public'
  or owner_user_id = auth.uid()
);

create policy "Hosts can manage their own question packs"
on public.question_packs for all
using (owner_user_id = auth.uid())
with check (owner_user_id = auth.uid());

create policy "Hosts can read questions in available packs"
on public.questions for select
using (
  exists (
    select 1
    from public.question_packs qp
    where qp.id = questions.pack_id
      and (qp.visibility = 'public' or qp.owner_user_id = auth.uid())
  )
);

create policy "Hosts can manage questions in own packs"
on public.questions for all
using (
  exists (
    select 1
    from public.question_packs qp
    where qp.id = questions.pack_id
      and qp.owner_user_id = auth.uid()
  )
)
with check (
  exists (
    select 1
    from public.question_packs qp
    where qp.id = questions.pack_id
      and qp.owner_user_id = auth.uid()
  )
);

create policy "Hosts can manage their games"
on public.games for all
using (host_user_id = auth.uid())
with check (host_user_id = auth.uid());

create policy "Hosts can manage their game members"
on public.game_members for all
using (
  exists (
    select 1 from public.games g
    where g.id = game_members.game_id
      and g.host_user_id = auth.uid()
  )
)
with check (
  exists (
    select 1 from public.games g
    where g.id = game_members.game_id
      and g.host_user_id = auth.uid()
  )
);

create policy "Hosts can read turns for their games"
on public.game_turns for select
using (
  exists (
    select 1 from public.games g
    where g.id = game_turns.game_id
      and g.host_user_id = auth.uid()
  )
);

create policy "Hosts can read answers for their games"
on public.game_answers for select
using (
  exists (
    select 1 from public.games g
    where g.id = game_answers.game_id
      and g.host_user_id = auth.uid()
  )
);

create policy "Hosts can read events for their games"
on public.game_events for select
using (
  exists (
    select 1 from public.games g
    where g.id = game_events.game_id
      and g.host_user_id = auth.uid()
  )
);

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
  ('pro', 'Pro', null, 50, true, true, false),
  ('business', 'Business', null, 200, true, true, true)
on conflict (id) do nothing;

insert into public.question_packs (id, owner_user_id, name, description, visibility, tier)
values
  ('00000000-0000-0000-0000-000000000101', null, 'General Knowledge', 'A simple starter pack for testing live games.', 'public', 'free'),
  ('00000000-0000-0000-0000-000000000102', null, 'Family Fun', 'Light questions for friends and family groups.', 'public', 'free'),
  ('00000000-0000-0000-0000-000000000103', null, 'Movies and TV', 'Entertainment questions for casual games.', 'public', 'premium')
on conflict (id) do nothing;

insert into public.questions (pack_id, prompt, option_a, option_b, option_c, option_d, correct_option, difficulty)
values
  ('00000000-0000-0000-0000-000000000101', 'Which planet is closest to the Sun?', 'Venus', 'Mercury', 'Mars', 'Jupiter', 'B', 'easy'),
  ('00000000-0000-0000-0000-000000000101', 'How many sides does a hexagon have?', 'Five', 'Six', 'Seven', 'Eight', 'B', 'easy'),
  ('00000000-0000-0000-0000-000000000101', 'What is the capital city of Japan?', 'Seoul', 'Beijing', 'Tokyo', 'Bangkok', 'C', 'easy'),
  ('00000000-0000-0000-0000-000000000102', 'Which fruit is traditionally used in a banana split?', 'Apple', 'Banana', 'Orange', 'Pear', 'B', 'easy'),
  ('00000000-0000-0000-0000-000000000102', 'What color do you get by mixing red and white?', 'Pink', 'Green', 'Purple', 'Orange', 'A', 'easy'),
  ('00000000-0000-0000-0000-000000000103', 'Which movie features a character named Darth Vader?', 'Star Wars', 'Jurassic Park', 'Toy Story', 'The Matrix', 'A', 'easy')
on conflict do nothing;
