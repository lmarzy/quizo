create table public.learning_attempts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  correct_count integer not null check (correct_count >= 0),
  question_count integer not null check (question_count between 1 and 20 and correct_count <= question_count),
  duration_seconds integer not null default 0 check (duration_seconds between 0 and 3600),
  completed_at timestamptz not null default now()
);

create table public.learning_question_progress (
  user_id uuid not null references public.profiles(id) on delete cascade,
  question_id uuid not null references public.questions(id) on delete cascade,
  attempts integer not null default 0 check (attempts >= 0),
  correct_attempts integer not null default 0 check (correct_attempts between 0 and attempts),
  mastery_level integer not null default 0 check (mastery_level between 0 and 5),
  next_review_at timestamptz not null default now(),
  last_answered_at timestamptz,
  last_was_correct boolean,
  primary key (user_id, question_id)
);

create table public.learning_answers (
  id uuid primary key default gen_random_uuid(),
  attempt_id uuid not null references public.learning_attempts(id) on delete cascade,
  question_id uuid not null references public.questions(id) on delete cascade,
  selected_option text not null check (selected_option in ('A', 'B', 'C')),
  is_correct boolean not null,
  created_at timestamptz not null default now(),
  unique (attempt_id, question_id)
);

create index learning_attempts_user_completed_idx on public.learning_attempts (user_id, completed_at desc);
create index learning_progress_user_review_idx on public.learning_question_progress (user_id, next_review_at);
create index learning_answers_attempt_idx on public.learning_answers (attempt_id);

alter table public.learning_attempts enable row level security;
alter table public.learning_question_progress enable row level security;
alter table public.learning_answers enable row level security;

create policy "Users can manage their own learning attempts"
on public.learning_attempts for all
using (user_id = auth.uid())
with check (user_id = auth.uid());

create policy "Users can manage their own learning progress"
on public.learning_question_progress for all
using (user_id = auth.uid())
with check (user_id = auth.uid());

create policy "Users can manage answers in their own learning attempts"
on public.learning_answers for all
using (
  exists (
    select 1 from public.learning_attempts attempt
    where attempt.id = learning_answers.attempt_id and attempt.user_id = auth.uid()
  )
)
with check (
  exists (
    select 1 from public.learning_attempts attempt
    where attempt.id = learning_answers.attempt_id and attempt.user_id = auth.uid()
  )
);
