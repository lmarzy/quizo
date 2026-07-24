alter table public.questions
add column topic text;

update public.questions
set topic = case
  when prompt like 'What is the capital city of %' or prompt like 'Which city is the national capital of %' then 'capitals'
  when prompt like 'What is the chemical symbol for %' or prompt like 'On the periodic table, which symbol represents %' then 'chemistry'
  when prompt like 'In which country would you find %' or prompt like '% is located in which country?' then 'landmarks'
  when prompt like 'Who wrote %' or prompt like '% was written by which author?' then 'literature'
  when prompt like 'In which year did %' or prompt like 'What year is associated with %' then 'history'
  when prompt like 'Which river flows through %' or prompt like '% is associated with which river?' then 'rivers'
  when prompt like 'In which sport is the term %' or prompt like 'The term % belongs mainly to which sport?' then 'sport'
  when prompt like 'Which country or region is most associated with %' or prompt like '% is most commonly linked with which place?' then 'food'
  when prompt like 'In computing, what does %' or prompt like 'Which phrase best matches the computing term %' then 'technology'
  when prompt like 'Which animal is known for %' or prompt like 'What animal best fits this clue: %' then 'animals'
  else topic
end
where pack_id = '00000000-0000-0000-0000-000000000101'::uuid;

update public.questions
set topic = case
  when prompt like 'Which animal is known for %' then 'animals'
  when prompt like 'What is the usual name for a baby %' then 'baby animals'
  when prompt like 'Which food best matches this clue: %' then 'food'
  when prompt like 'Which kitchen tool is best suited to %' then 'kitchen'
  when prompt like 'Which body part or organ is responsible for %' then 'human body'
  when prompt like 'What is the name for %' then 'nature'
  when prompt like 'Which space answer matches this clue: %' then 'space'
  when prompt like 'Which geography answer matches this clue: %' then 'geography'
  when prompt like 'In which city would you find %' then 'landmarks'
  when prompt like 'Which story character matches this description: %' then 'stories'
  when prompt like 'Which family film features %' then 'film'
  when prompt like 'Which musical answer matches this clue: %' then 'music'
  when prompt like 'Which sport is associated with %' then 'sport'
  when prompt like 'Which game involves %' then 'games'
  when prompt like 'Which job mainly involves %' then 'jobs'
  when prompt like 'Which form of transport is designed for %' then 'transport'
  when prompt like 'Which word is the best opposite of %' then 'words'
  when prompt like 'What is %' then 'numbers'
  when prompt like 'Which time or calendar answer matches %' then 'time'
  when prompt like 'Which science answer matches this clue: %' then 'science'
  else topic
end
where pack_id = '00000000-0000-0000-0000-000000000102'::uuid;

do $$
declare
  general_topic_count integer;
  family_topic_count integer;
  unclassified_count integer;
begin
  select count(distinct topic)
  into general_topic_count
  from public.questions
  where pack_id = '00000000-0000-0000-0000-000000000101'::uuid;

  select count(distinct topic)
  into family_topic_count
  from public.questions
  where pack_id = '00000000-0000-0000-0000-000000000102'::uuid;

  select count(*)
  into unclassified_count
  from public.questions
  where pack_id in (
    '00000000-0000-0000-0000-000000000101'::uuid,
    '00000000-0000-0000-0000-000000000102'::uuid
  )
    and topic is null;

  if general_topic_count <> 10 or family_topic_count <> 20 or unclassified_count <> 0 then
    raise exception 'Question topic migration expected 10 General Knowledge topics, 20 Family Fun topics, and no unclassified questions; got %, %, and %', general_topic_count, family_topic_count, unclassified_count;
  end if;
end
$$;
