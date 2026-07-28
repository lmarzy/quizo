alter table public.daily_challenge_attempts
add column puzzles_correct integer not null default 0
check (puzzles_correct between 0 and 3);

update public.daily_challenge_attempts
set puzzles_correct = case when bonus_correct then 1 else 0 end;

alter table public.daily_challenge_attempts
drop constraint daily_challenge_attempts_score_check;

alter table public.daily_challenge_attempts
add constraint daily_challenge_attempts_score_check
check (score between 0 and 1100);
