alter table public.daily_challenge_attempts
add column connections_correct integer not null default 0
check (connections_correct between 0 and 3),
add column final_correct boolean not null default false;

alter table public.daily_challenge_attempts
drop constraint daily_challenge_attempts_score_check;

alter table public.daily_challenge_attempts
add constraint daily_challenge_attempts_score_check
check (score between 0 and 1850);
