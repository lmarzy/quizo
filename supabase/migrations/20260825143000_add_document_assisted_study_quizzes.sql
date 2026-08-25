alter table public.study_quizzes
add column source_name text,
add column ai_generated boolean not null default false,
add column study_plan jsonb;

alter table public.study_quizzes
add constraint study_quizzes_source_name_length
check (source_name is null or char_length(source_name) <= 255),
add constraint study_quizzes_study_plan_shape
check (
  study_plan is null
  or (
    jsonb_typeof(study_plan) = 'object'
    and study_plan ? 'summary'
    and study_plan ? 'sessions_per_week'
    and study_plan ? 'minutes_per_session'
    and study_plan ? 'focus_topics'
  )
);
