alter table public.learning_question_progress
add column exposure_count integer not null default 0 check (exposure_count >= 0),
add column last_exposed_at timestamptz,
add column self_reported_familiar boolean;
