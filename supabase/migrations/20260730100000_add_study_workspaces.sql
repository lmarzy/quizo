create table public.study_workspaces (
  id uuid primary key default gen_random_uuid(),
  owner_user_id uuid not null references public.profiles(id) on delete cascade,
  title text not null check (char_length(trim(title)) between 1 and 120),
  study_level text not null default 'personal' check (study_level in ('gcse', 'a_level', 'degree', 'professional', 'personal')),
  organisation text,
  target text,
  assessment_date date,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger study_workspaces_set_updated_at
before update on public.study_workspaces
for each row execute function public.set_updated_at();

alter table public.study_workspaces enable row level security;

create policy "Users can manage their own study workspaces"
on public.study_workspaces for all
using (owner_user_id = auth.uid())
with check (owner_user_id = auth.uid());

alter table public.study_quizzes
add column workspace_id uuid references public.study_workspaces(id) on delete cascade,
add column module_name text,
add column topic_name text;

insert into public.study_workspaces (owner_user_id, title, study_level)
select distinct owner_user_id, 'My studies', 'personal'
from public.study_quizzes;

update public.study_quizzes quiz
set workspace_id = workspace.id
from public.study_workspaces workspace
where workspace.owner_user_id = quiz.owner_user_id
  and workspace.title = 'My studies'
  and workspace.study_level = 'personal'
  and quiz.workspace_id is null;

alter table public.study_quizzes
alter column workspace_id set not null;

create index study_workspaces_owner_idx on public.study_workspaces (owner_user_id, updated_at desc);
create index study_quizzes_workspace_idx on public.study_quizzes (workspace_id, updated_at desc);
