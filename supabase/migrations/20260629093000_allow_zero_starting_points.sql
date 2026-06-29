alter table public.games
drop constraint if exists games_starting_points_check;

alter table public.games
add constraint games_starting_points_check
check (starting_points >= 0);
