alter table public.profiles
  add column if not exists learning_path_id text,
  add column if not exists learning_weekly_goal integer not null default 3;

alter table public.profiles drop constraint if exists profiles_learning_path_id_check;
alter table public.profiles add constraint profiles_learning_path_id_check
  check (learning_path_id is null or learning_path_id in ('world-explorer', 'science-nature', 'history-culture', 'modern-world'));

alter table public.profiles drop constraint if exists profiles_learning_weekly_goal_check;
alter table public.profiles add constraint profiles_learning_weekly_goal_check
  check (learning_weekly_goal between 1 and 7);

alter table public.learning_question_progress
  add column if not exists incorrect_attempts integer not null default 0,
  add column if not exists last_selected_option text,
  add column if not exists misconception_count integer not null default 0;

alter table public.learning_question_progress drop constraint if exists learning_question_progress_last_selected_option_check;
alter table public.learning_question_progress add constraint learning_question_progress_last_selected_option_check
  check (last_selected_option is null or last_selected_option in ('A', 'B', 'C'));
