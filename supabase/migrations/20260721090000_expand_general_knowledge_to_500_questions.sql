update public.question_packs
set description = 'A 500-question pub-quiz mix across geography, science, history, literature, sport, food, technology, nature, film, and everyday knowledge with varied difficulty.'
where id = '00000000-0000-0000-0000-000000000101'::uuid;

delete from public.questions
where pack_id = '00000000-0000-0000-0000-000000000101'::uuid;

with category_data(category, subjects, answers) as (
values
  ('capital',
    array['Canada','Australia','New Zealand','Brazil','Argentina','Chile','Peru','Colombia','Egypt','Kenya','Morocco','Ethiopia','India','Pakistan','Thailand','Vietnam','Indonesia','South Korea','Norway','Finland','Poland','Hungary','Greece','Portugal','Ireland'],
    array['Ottawa','Canberra','Wellington','Brasilia','Buenos Aires','Santiago','Lima','Bogota','Cairo','Nairobi','Rabat','Addis Ababa','New Delhi','Islamabad','Bangkok','Hanoi','Jakarta','Seoul','Oslo','Helsinki','Warsaw','Budapest','Athens','Lisbon','Dublin']
  ),
  ('element_symbol',
    array['hydrogen','helium','carbon','nitrogen','oxygen','sodium','magnesium','aluminium','silicon','phosphorus','sulfur','chlorine','potassium','calcium','iron','copper','zinc','silver','tin','iodine','gold','mercury','lead','uranium','neon'],
    array['H','He','C','N','O','Na','Mg','Al','Si','P','S','Cl','K','Ca','Fe','Cu','Zn','Ag','Sn','I','Au','Hg','Pb','U','Ne']
  ),
  ('landmark_country',
    array['Machu Picchu','the Taj Mahal','the Colosseum','Petra','Angkor Wat','Christ the Redeemer','the Acropolis','Stonehenge','the Alhambra','Chichen Itza','the Blue Mosque','Mount Fuji','Uluru','the Louvre Museum','Neuschwanstein Castle','the Forbidden City','Burj Khalifa','the Parthenon','the Leaning Tower of Pisa','the Sagrada Familia','Table Mountain','the Palace of Versailles','the Moai statues of Easter Island','the Dome of the Rock','the Potala Palace'],
    array['Peru','India','Italy','Jordan','Cambodia','Brazil','Greece','United Kingdom','Spain','Mexico','Turkey','Japan','Australia','France','Germany','China','United Arab Emirates','Greece','Italy','Spain','South Africa','France','Chile','Israel','China']
  ),
  ('author_work',
    array['Pride and Prejudice','1984','Things Fall Apart','To Kill a Mockingbird','The Great Gatsby','Moby-Dick','Jane Eyre','Frankenstein','The Hobbit','The Catcher in the Rye','Beloved','One Hundred Years of Solitude','The Handmaid''s Tale','The Old Man and the Sea','Great Expectations','The Odyssey','The Trial','Mrs Dalloway','The Stranger','The Color Purple','Brave New World','Dracula','The Picture of Dorian Gray','The Bell Jar','A Brief History of Time'],
    array['Jane Austen','George Orwell','Chinua Achebe','Harper Lee','F. Scott Fitzgerald','Herman Melville','Charlotte Bronte','Mary Shelley','J. R. R. Tolkien','J. D. Salinger','Toni Morrison','Gabriel Garcia Marquez','Margaret Atwood','Ernest Hemingway','Charles Dickens','Homer','Franz Kafka','Virginia Woolf','Albert Camus','Alice Walker','Aldous Huxley','Bram Stoker','Oscar Wilde','Sylvia Plath','Stephen Hawking']
  ),
  ('history_year',
    array['the Battle of Hastings','the signing of Magna Carta','the fall of Constantinople','Columbus first reached the Americas','the Spanish Armada was defeated','the Gunpowder Plot','the Great Fire of London','the American Declaration of Independence','the French Revolution began','the Battle of Waterloo','the first modern Olympic Games','the Wright brothers first powered flight','World War I began','the Russian Revolution','the Wall Street Crash','World War II began in Europe','India gained independence','the first human reached space','the first Moon landing','the Berlin Wall fell','Nelson Mandela became president of South Africa','the Euro was introduced as electronic currency','Wikipedia launched','the first iPhone was announced','the Paris Agreement was adopted'],
    array['1066','1215','1453','1492','1588','1605','1666','1776','1789','1815','1896','1903','1914','1917','1929','1939','1947','1961','1969','1989','1994','1999','2001','2007','2015']
  ),
  ('river_city',
    array['London','Paris','Rome','Cairo','Vienna','Budapest','New York City','Washington, D.C.','Dublin','Glasgow','Bristol','Prague','Warsaw','Lisbon','Seville','Florence','Baghdad','Basel','Cologne','Shanghai','Bangkok','Delhi','Lahore','Melbourne','Brisbane'],
    array['Thames','Seine','Tiber','Nile','Danube','Danube','Hudson','Potomac','Liffey','Clyde','Avon','Vltava','Vistula','Tagus','Guadalquivir','Arno','Tigris','Rhine','Rhine','Huangpu','Chao Phraya','Yamuna','Ravi','Yarra','Brisbane River']
  ),
  ('sport_term',
    array['LBW','birdie','albatross','scrum','try','deuce','love','hat-trick','offside','home run','slam dunk','touchdown','icing','bullseye','checkmate','gambit','ippon','peloton','bogey','maiden over','puck','frame','parry','vault','spare'],
    array['cricket','golf','golf','rugby union','rugby','tennis','tennis','football','football','baseball','basketball','American football','ice hockey','darts','chess','chess','judo','cycling','golf','cricket','ice hockey','snooker','fencing','gymnastics','ten-pin bowling']
  ),
  ('food_origin',
    array['sushi','paella','kimchi','poutine','moussaka','pho','tagine','haggis','pierogi','goulash','ceviche','falafel','bibimbap','baklava','gelato','tacos','croissant','biryani','pad thai','injera','feijoada','arepas','laksa','churros','sauerbraten'],
    array['Japan','Spain','South Korea','Canada','Greece','Vietnam','Morocco','Scotland','Poland','Hungary','Peru','Middle East','South Korea','Turkey','Italy','Mexico','France','India','Thailand','Ethiopia','Brazil','Venezuela','Malaysia','Spain','Germany']
  ),
  ('computing',
    array['CPU','RAM','URL','HTML','CSS','HTTP','HTTPS','SQL','API','DNS','GPU','SSD','USB','VPN','LAN','IP address','2FA','JSON','XML','SaaS','BIOS','CLI','GUI','NFC','OCR'],
    array['central processing unit','random access memory','uniform resource locator','hypertext markup language','cascading style sheets','hypertext transfer protocol','secure hypertext transfer protocol','structured query language','application programming interface','domain name system','graphics processing unit','solid-state drive','universal serial bus','virtual private network','local area network','internet protocol address','two-factor authentication','JavaScript Object Notation','extensible markup language','software as a service','basic input output system','command-line interface','graphical user interface','near-field communication','optical character recognition']
  ),
  ('animal_fact',
    array['true sustained flight among mammals','changing color using chromatophores','the largest living land animal','the tallest living land animal','black and white stripes','carrying young in a pouch','building dams in rivers','using echolocation in the ocean','being the fastest land animal','having a long prehensile trunk','spinning silk webs','being a flightless bird from Antarctica','laying eggs despite being a mammal','having a powerful black and white spray defense','slow movement and algae-tinted fur','a venomous bite and hood display','the largest living bird by height','the largest living reptile','long-distance migration from North America to Mexico','using tools to crack shellfish','a laugh-like call in Australia','a black and white bear that eats mostly bamboo','a marsupial sometimes called a native bear','a horn made from keratin on its nose','living in highly organized colonies with a queen'],
    array['bat','chameleon','African elephant','giraffe','zebra','kangaroo','beaver','dolphin','cheetah','elephant','spider','penguin','platypus','skunk','sloth','cobra','ostrich','saltwater crocodile','monarch butterfly','sea otter','kookaburra','giant panda','koala','rhinoceros','ant']
  )
),
facts as (
  select
    cd.category,
    u.subject,
    u.answer,
    u.idx,
    cd.answers,
    cardinality(cd.answers) as answer_count
  from category_data cd
  cross join lateral unnest(cd.subjects, cd.answers) with ordinality as u(subject, answer, idx)
),
questions as (
  select
    f.category,
    f.subject,
    f.answer,
    f.answers[((f.idx + v.variant) % f.answer_count) + 1] as wrong_one,
    f.answers[((f.idx + v.variant + 7) % f.answer_count) + 1] as wrong_two,
    f.idx,
    v.variant,
    case
      when f.idx <= 8 then 'easy'
      when f.idx <= 18 then 'medium'
      else 'hard'
    end as difficulty,
    case f.category
      when 'capital' then case v.variant when 1 then 'What is the capital city of ' || f.subject || '?' else 'Which city is the national capital of ' || f.subject || '?' end
      when 'element_symbol' then case v.variant when 1 then 'What is the chemical symbol for ' || f.subject || '?' else 'On the periodic table, which symbol represents ' || f.subject || '?' end
      when 'landmark_country' then case v.variant when 1 then 'In which country would you find ' || f.subject || '?' else f.subject || ' is located in which country?' end
      when 'author_work' then case v.variant when 1 then 'Who wrote ' || f.subject || '?' else f.subject || ' was written by which author?' end
      when 'history_year' then case v.variant when 1 then 'In which year did ' || f.subject || ' happen?' else 'What year is associated with ' || f.subject || '?' end
      when 'river_city' then case v.variant when 1 then 'Which river flows through ' || f.subject || '?' else f.subject || ' is associated with which river?' end
      when 'sport_term' then case v.variant when 1 then 'In which sport is the term ' || f.subject || ' used?' else 'The term ' || f.subject || ' belongs mainly to which sport?' end
      when 'food_origin' then case v.variant when 1 then 'Which country or region is most associated with ' || f.subject || '?' else f.subject || ' is most commonly linked with which place?' end
      when 'computing' then case v.variant when 1 then 'In computing, what does ' || f.subject || ' stand for or refer to?' else 'Which phrase best matches the computing term ' || f.subject || '?' end
      when 'animal_fact' then case v.variant when 1 then 'Which animal is known for ' || f.subject || '?' else 'What animal best fits this clue: ' || f.subject || '?' end
    end as prompt
  from facts f
  cross join (values (1), (2)) as v(variant)
)
insert into public.questions (pack_id, prompt, option_a, option_b, option_c, option_d, correct_option, difficulty)
select
  '00000000-0000-0000-0000-000000000101'::uuid,
  prompt,
  case (idx + variant) % 3 when 0 then answer when 1 then wrong_one else wrong_two end,
  case (idx + variant) % 3 when 1 then answer when 2 then wrong_one else wrong_two end,
  case (idx + variant) % 3 when 2 then answer when 0 then wrong_one else wrong_two end,
  '',
  case (idx + variant) % 3 when 0 then 'A' when 1 then 'B' else 'C' end,
  difficulty
from questions;
