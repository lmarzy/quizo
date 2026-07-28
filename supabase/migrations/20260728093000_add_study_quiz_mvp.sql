create table public.study_quizzes (
  id uuid primary key default gen_random_uuid(),
  owner_user_id uuid not null references public.profiles(id) on delete cascade,
  title text not null check (char_length(trim(title)) between 1 and 120),
  subject text not null default 'General' check (char_length(trim(subject)) between 1 and 80),
  description text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.study_questions (
  id uuid primary key default gen_random_uuid(),
  quiz_id uuid not null references public.study_quizzes(id) on delete cascade,
  prompt text not null check (char_length(trim(prompt)) > 0),
  option_a text not null check (char_length(trim(option_a)) > 0),
  option_b text not null check (char_length(trim(option_b)) > 0),
  option_c text not null check (char_length(trim(option_c)) > 0),
  correct_option text not null check (correct_option in ('A', 'B', 'C')),
  explanation text,
  position integer not null default 0 check (position >= 0),
  created_at timestamptz not null default now()
);

create table public.study_attempts (
  id uuid primary key default gen_random_uuid(),
  quiz_id uuid not null references public.study_quizzes(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  mode text not null default 'full' check (mode in ('full', 'mistakes')),
  correct_count integer not null check (correct_count >= 0),
  question_count integer not null check (question_count > 0 and correct_count <= question_count),
  duration_seconds integer not null default 0 check (duration_seconds between 0 and 14400),
  completed_at timestamptz not null default now()
);

create table public.study_answers (
  id uuid primary key default gen_random_uuid(),
  attempt_id uuid not null references public.study_attempts(id) on delete cascade,
  question_id uuid not null references public.study_questions(id) on delete cascade,
  selected_option text not null check (selected_option in ('A', 'B', 'C')),
  is_correct boolean not null,
  created_at timestamptz not null default now(),
  unique (attempt_id, question_id)
);

create index study_quizzes_owner_updated_idx on public.study_quizzes (owner_user_id, updated_at desc);
create index study_questions_quiz_position_idx on public.study_questions (quiz_id, position);
create index study_attempts_user_completed_idx on public.study_attempts (user_id, completed_at desc);
create index study_attempts_quiz_completed_idx on public.study_attempts (quiz_id, completed_at desc);
create index study_answers_question_idx on public.study_answers (question_id, created_at desc);

create trigger study_quizzes_set_updated_at
before update on public.study_quizzes
for each row execute function public.set_updated_at();

alter table public.study_quizzes enable row level security;
alter table public.study_questions enable row level security;
alter table public.study_attempts enable row level security;
alter table public.study_answers enable row level security;

create policy "Users can manage their own study quizzes"
on public.study_quizzes for all
using (owner_user_id = auth.uid())
with check (owner_user_id = auth.uid());

create policy "Users can manage questions in their own study quizzes"
on public.study_questions for all
using (
  exists (
    select 1 from public.study_quizzes quiz
    where quiz.id = study_questions.quiz_id and quiz.owner_user_id = auth.uid()
  )
)
with check (
  exists (
    select 1 from public.study_quizzes quiz
    where quiz.id = study_questions.quiz_id and quiz.owner_user_id = auth.uid()
  )
);

create policy "Users can manage their own study attempts"
on public.study_attempts for all
using (user_id = auth.uid())
with check (
  user_id = auth.uid()
  and exists (
    select 1 from public.study_quizzes quiz
    where quiz.id = study_attempts.quiz_id and quiz.owner_user_id = auth.uid()
  )
);

create policy "Users can manage answers in their own study attempts"
on public.study_answers for all
using (
  exists (
    select 1 from public.study_attempts attempt
    where attempt.id = study_answers.attempt_id and attempt.user_id = auth.uid()
  )
)
with check (
  exists (
    select 1
    from public.study_attempts attempt
    join public.study_questions question on question.quiz_id = attempt.quiz_id
    where attempt.id = study_answers.attempt_id
      and attempt.user_id = auth.uid()
      and question.id = study_answers.question_id
  )
);
