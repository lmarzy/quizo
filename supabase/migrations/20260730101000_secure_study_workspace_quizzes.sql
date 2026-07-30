drop policy "Users can manage their own study quizzes"
on public.study_quizzes;

create policy "Users can manage their own study quizzes"
on public.study_quizzes for all
using (
  owner_user_id = auth.uid()
  and exists (
    select 1 from public.study_workspaces workspace
    where workspace.id = study_quizzes.workspace_id
      and workspace.owner_user_id = auth.uid()
  )
)
with check (
  owner_user_id = auth.uid()
  and exists (
    select 1 from public.study_workspaces workspace
    where workspace.id = study_quizzes.workspace_id
      and workspace.owner_user_id = auth.uid()
  )
);
