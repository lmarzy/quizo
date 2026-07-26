create table public.daily_challenge_attempts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  challenge_date date not null,
  quiz_correct integer not null check (quiz_correct between 0 and 5),
  bonus_correct boolean not null default false,
  score integer not null check (score between 0 and 800),
  duration_seconds integer not null check (duration_seconds between 0 and 3600),
  completed_at timestamptz not null default now(),
  unique (user_id, challenge_date)
);

create index daily_challenge_attempts_user_date_idx
on public.daily_challenge_attempts (user_id, challenge_date desc);

alter table public.daily_challenge_attempts enable row level security;

create policy "Users can read their own daily challenge attempts"
on public.daily_challenge_attempts for select
using (auth.uid() = user_id);

create policy "Users can create their own daily challenge attempts"
on public.daily_challenge_attempts for insert
with check (
  auth.uid() = user_id
  and challenge_date between current_date - 1 and current_date + 1
);

create policy "Users can update their own daily challenge attempts"
on public.daily_challenge_attempts for update
using (auth.uid() = user_id)
with check (
  auth.uid() = user_id
  and challenge_date between current_date - 1 and current_date + 1
);
