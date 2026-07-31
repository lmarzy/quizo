alter table public.study_workspaces
drop constraint study_workspaces_study_level_check;

alter table public.study_workspaces
add constraint study_workspaces_study_level_check
check (study_level in (
  'gcse',
  'a_level',
  'degree',
  'ib',
  'ap',
  'secondary',
  'pre_university',
  'vocational',
  'undergraduate',
  'postgraduate',
  'professional',
  'personal',
  'custom'
));

alter table public.study_workspaces
add column curriculum text,
add column country_region text;
