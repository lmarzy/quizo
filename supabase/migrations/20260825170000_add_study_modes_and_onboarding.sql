alter table public.study_attempts
drop constraint study_attempts_mode_check;

alter table public.study_attempts
add constraint study_attempts_mode_check
check (mode in ('full', 'learn', 'practice', 'exam', 'smart', 'rapid', 'mistakes'));

alter table public.profiles
add column onboarding_goal text,
add column onboarding_completed_at timestamptz;

alter table public.profiles
add constraint profiles_onboarding_goal_check
check (onboarding_goal is null or onboarding_goal in ('knowledge', 'study', 'create', 'play', 'mixed'));

-- Keep the new flow focused on future sign-ups rather than interrupting existing members.
update public.profiles
set onboarding_goal = 'mixed', onboarding_completed_at = now()
where onboarding_completed_at is null;

alter table public.learning_attempts
add column session_type text not null default 'lesson' check (session_type in ('lesson', 'checkpoint')),
add column path_id text;
