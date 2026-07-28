alter table public.study_questions
add column mastery_level integer not null default 0 check (mastery_level between 0 and 5),
add column next_review_at timestamptz not null default now(),
add column last_reviewed_at timestamptz;

alter table public.study_attempts
drop constraint study_attempts_mode_check;

alter table public.study_attempts
add constraint study_attempts_mode_check
check (mode in ('full', 'mistakes', 'smart'));

create index study_questions_review_queue_idx
on public.study_questions (quiz_id, next_review_at);
