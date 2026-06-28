create or replace function public.get_game_room(p_join_code text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  game_record public.games;
  question_record public.questions;
  active_member public.game_members;
  latest_answer_record public.game_answers;
  latest_answer_member public.game_members;
  latest_answer_question public.questions;
  members jsonb;
  events jsonb;
begin
  select *
  into game_record
  from public.games
  where join_code = upper(trim(p_join_code))
  limit 1;

  if game_record.id is null then
    raise exception 'Game not found';
  end if;

  if game_record.current_question_id is not null then
    select *
    into question_record
    from public.questions
    where id = game_record.current_question_id;
  end if;

  if game_record.current_member_id is not null then
    select *
    into active_member
    from public.game_members
    where id = game_record.current_member_id;
  end if;

  select *
  into latest_answer_record
  from public.game_answers
  where game_id = game_record.id
  order by answered_at desc
  limit 1;

  if latest_answer_record.id is not null then
    select *
    into latest_answer_member
    from public.game_members
    where id = latest_answer_record.member_id;

    select *
    into latest_answer_question
    from public.questions
    where id = latest_answer_record.question_id;
  end if;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', gm.id,
        'display_name', gm.display_name,
        'points', gm.points,
        'status', gm.status,
        'turn_order', gm.turn_order
      )
      order by gm.points desc, gm.turn_order
    ),
    '[]'::jsonb
  )
  into members
  from public.game_members gm
  where gm.game_id = game_record.id;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', ge.id,
        'event_type', ge.event_type,
        'message', ge.message,
        'created_at', ge.created_at
      )
      order by ge.created_at desc
    ),
    '[]'::jsonb
  )
  into events
  from (
    select *
    from public.game_events
    where game_id = game_record.id
    order by created_at desc
    limit 8
  ) ge;

  return jsonb_build_object(
    'game',
    jsonb_build_object(
      'id', game_record.id,
      'name', game_record.name,
      'join_code', game_record.join_code,
      'status', game_record.status,
      'timer_ends_at', game_record.timer_ends_at,
      'current_member_id', game_record.current_member_id,
      'current_question_id', game_record.current_question_id
    ),
    'active_member',
    case
      when active_member.id is null then null
      else jsonb_build_object(
        'id', active_member.id,
        'display_name', active_member.display_name,
        'points', active_member.points
      )
    end,
    'question',
    case
      when question_record.id is null then null
      else jsonb_build_object(
        'id', question_record.id,
        'prompt', question_record.prompt,
        'option_a', question_record.option_a,
        'option_b', question_record.option_b,
        'option_c', question_record.option_c,
        'option_d', question_record.option_d
      )
    end,
    'latest_answer',
    case
      when latest_answer_record.id is null then null
      else jsonb_build_object(
        'id', latest_answer_record.id,
        'member_name', latest_answer_member.display_name,
        'selected_option', latest_answer_record.selected_option,
        'is_correct', latest_answer_record.is_correct,
        'points_delta', latest_answer_record.points_delta,
        'correct_option', latest_answer_question.correct_option,
        'correct_answer',
          case latest_answer_question.correct_option
            when 'A' then latest_answer_question.option_a
            when 'B' then latest_answer_question.option_b
            when 'C' then latest_answer_question.option_c
            when 'D' then latest_answer_question.option_d
          end,
        'answered_at', latest_answer_record.answered_at
      )
    end,
    'members', members,
    'events', events
  );
end;
$$;

grant execute on function public.get_game_room(text) to anon, authenticated;
