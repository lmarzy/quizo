create or replace function public.get_question_pack_counts()
returns table (
  pack_id uuid,
  question_count bigint
)
language sql
stable
security invoker
set search_path = public
as $$
  select questions.pack_id, count(*) as question_count
  from public.questions
  group by questions.pack_id;
$$;

revoke all on function public.get_question_pack_counts() from public;
grant execute on function public.get_question_pack_counts() to authenticated;
