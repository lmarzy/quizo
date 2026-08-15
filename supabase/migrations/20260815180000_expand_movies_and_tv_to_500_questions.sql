update public.question_packs
set description = 'A 500-question entertainment mix spanning classic and modern films, television, performers, directors, animation, settings, creators, famous objects, and screen history.'
where id = '00000000-0000-0000-0000-000000000103'::uuid;

delete from public.questions
where pack_id = '00000000-0000-0000-0000-000000000103'::uuid;

with category_data(category, subjects, answers) as (
values
  ('film_performers',
    array['Forrest Gump in Forrest Gump','Erin Brockovich in Erin Brockovich','Maximus in Gladiator','Elle Woods in Legally Blonde','Jack Sparrow in Pirates of the Caribbean','Katniss Everdeen in The Hunger Games','Neo in The Matrix','Miranda Priestly in The Devil Wears Prada','Wolverine in the X-Men films','Hermione Granger in the Harry Potter films','Black Panther in the Marvel films','Wonder Woman in the DC films','Freddie Mercury in Bohemian Rhapsody','Elvis Presley in Elvis','Barbie in Barbie','Oppenheimer in Oppenheimer','Amelie Poulain in Amelie','Rocky Balboa in Rocky','Evelyn Wang in Everything Everywhere All at Once','Lydia Tar in Tar','James Bond in Casino Royale','Mia Dolan in La La Land','Andy Dufresne in The Shawshank Redemption','Clarice Starling in The Silence of the Lambs','Indiana Jones in Raiders of the Lost Ark'],
    array['Tom Hanks','Julia Roberts','Russell Crowe','Reese Witherspoon','Johnny Depp','Jennifer Lawrence','Keanu Reeves','Meryl Streep','Hugh Jackman','Emma Watson','Chadwick Boseman','Gal Gadot','Rami Malek','Austin Butler','Margot Robbie','Cillian Murphy','Audrey Tautou','Sylvester Stallone','Michelle Yeoh','Cate Blanchett','Daniel Craig','Emma Stone','Tim Robbins','Jodie Foster','Harrison Ford']
  ),
  ('film_directors',
    array['Jaws','The Godfather','Pulp Fiction','Spirited Away','Parasite','The Lord of the Rings: The Fellowship of the Ring','Do the Right Thing','Lost in Translation','Pan''s Labyrinth','The Hurt Locker','Get Out','Nomadland','The Grand Budapest Hotel','Moonlight','Selma','The Piano','Slumdog Millionaire','Gravity','Mad Max: Fury Road','Portrait of a Lady on Fire','Lady Bird','Decision to Leave','The Farewell','Women Talking','Anatomy of a Fall'],
    array['Steven Spielberg','Francis Ford Coppola','Quentin Tarantino','Hayao Miyazaki','Bong Joon Ho','Peter Jackson','Spike Lee','Sofia Coppola','Guillermo del Toro','Kathryn Bigelow','Jordan Peele','Chloe Zhao','Wes Anderson','Barry Jenkins','Ava DuVernay','Jane Campion','Danny Boyle','Alfonso Cuaron','George Miller','Celine Sciamma','Greta Gerwig','Park Chan-wook','Lulu Wang','Sarah Polley','Justine Triet']
  ),
  ('film_release_years',
    array['The Wizard of Oz','Casablanca','Singin'' in the Rain','Seven Samurai','Psycho','The Sound of Music','The Godfather','Jaws','Star Wars','Alien','E.T. the Extra-Terrestrial','Back to the Future','The Princess Bride','Goodfellas','Jurassic Park','Toy Story','Titanic','The Truman Show','Gladiator','The Lord of the Rings: The Fellowship of the Ring','Finding Nemo','The Dark Knight','Inception','Get Out','Everything Everywhere All at Once'],
    array['1939','1942','1952','1954','1960','1965','1972','1975','1977','1979','1982','1985','1987','1990','1993','1995','1997','1998','2000','2001','2003','2008','2010','2017','2022']
  ),
  ('film_settings',
    array['Amelie','Lost in Translation','The Third Man','Roman Holiday','Trainspotting','City of God','In Bruges','The Full Monty','Whale Rider','The Motorcycle Diaries','The Lives of Others','The Banshees of Inisherin','The Lunchbox','Tsotsi','Roma','Monsoon Wedding','Once','Theeb','The Salesman','The Raid','Crouching Tiger, Hidden Dragon','The Battle of Algiers','Mustang','A Fantastic Woman','The Worst Person in the World'],
    array['Paris','Tokyo','Vienna','Rome','Edinburgh','Rio de Janeiro','Bruges','Sheffield','Whangara','Buenos Aires','East Berlin','Inisherin','Mumbai','Johannesburg','Mexico City','Delhi','Dublin','Wadi Rum','Tehran','Jakarta','Qing dynasty China','Algiers','northern Turkey','Santiago','Oslo']
  ),
  ('animation',
    array['Woody and Buzz Lightyear','Chihiro and No-Face','Shrek and Donkey','Marlin searching for his son','Remy cooking in Paris','Carl flying his house with balloons','Hiccup befriending Toothless','Joy and Sadness','Miguel visiting the Land of the Dead','Miles Morales becoming Spider-Man','Kiki running a delivery service','Wallace and Gromit confronting a villainous penguin','Coraline finding a button-eyed other family','Mr Fox outwitting three farmers','Moana restoring the heart of Te Fiti','Po training to become the Dragon Warrior','Judy Hopps joining the police','Hiro Hamada and Baymax','Mei Lee turning into a red panda','Mirabel and the magical Madrigal family','Haru entering a kingdom of cats','Marcel living inside a shell','Nimona helping a disgraced knight','Mahito entering a mysterious tower','Puss seeking the Last Wish'],
    array['Toy Story','Spirited Away','Shrek','Finding Nemo','Ratatouille','Up','How to Train Your Dragon','Inside Out','Coco','Spider-Man: Into the Spider-Verse','Kiki''s Delivery Service','The Wrong Trousers','Coraline','Fantastic Mr. Fox','Moana','Kung Fu Panda','Zootopia','Big Hero 6','Turning Red','Encanto','The Cat Returns','Marcel the Shell with Shoes On','Nimona','The Boy and the Heron','Puss in Boots: The Last Wish']
  ),
  ('famous_film_objects',
    array['a sled named Rosebud','a ruby-slippered journey along the Yellow Brick Road','a glowing briefcase whose contents are never shown','a DeLorean time machine','a spinning top used to test reality','a golden ticket to a chocolate factory','a red pill and a blue pill','a volleyball named Wilson','a fedora and a bullwhip','a neuralyzer that erases memories','a One Ring that must be destroyed','a board game that brings jungle dangers to life','a glass slipper left at a royal ball','a hockey mask worn by Jason Voorhees','a proton pack used to catch ghosts','a sonic screwdriver used by a time traveller','a Maltese Falcon statuette','a boombox held above Lloyd Dobler''s head','a burn book filled with school gossip','a lamp containing a wish-granting Genie','a hoverboard ridden through Hill Valley','a red stapler treasured by Milton','a suit that shrinks its wearer','a cursed videotape followed by a phone call','a briefcase handcuffed to a courier in Ronin'],
    array['Citizen Kane','The Wizard of Oz','Pulp Fiction','Back to the Future','Inception','Willy Wonka & the Chocolate Factory','The Matrix','Cast Away','Raiders of the Lost Ark','Men in Black','The Lord of the Rings','Jumanji','Cinderella','Friday the 13th','Ghostbusters','Doctor Who: The Movie','The Maltese Falcon','Say Anything...','Mean Girls','Aladdin','Back to the Future Part II','Office Space','Ant-Man','The Ring','Ronin']
  ),
  ('tv_performers',
    array['Walter White in Breaking Bad','Eleven in Stranger Things','Fleabag in Fleabag','Don Draper in Mad Men','Olivia Pope in Scandal','Ted Lasso in Ted Lasso','Wednesday Addams in Wednesday','Kendall Roy in Succession','Villanelle in Killing Eve','Rue Bennett in Euphoria','The Doctor in the first 2005 series of Doctor Who','Leslie Knope in Parks and Recreation','Omar Little in The Wire','June Osborne in The Handmaid''s Tale','Jimmy McGill in Better Call Saul','Mare Sheehan in Mare of Easttown','David Rose in Schitt''s Creek','Beth Harmon in The Queen''s Gambit','Loki in Loki','Ava Coleman in Abbott Elementary','Carmy Berzatto in The Bear','Nandor in What We Do in the Shadows','Lucifer Morningstar in Lucifer','Eve Polastri in Killing Eve','Din Djarin in The Mandalorian'],
    array['Bryan Cranston','Millie Bobby Brown','Phoebe Waller-Bridge','Jon Hamm','Kerry Washington','Jason Sudeikis','Jenna Ortega','Jeremy Strong','Jodie Comer','Zendaya','Christopher Eccleston','Amy Poehler','Michael K. Williams','Elisabeth Moss','Bob Odenkirk','Kate Winslet','Dan Levy','Anya Taylor-Joy','Tom Hiddleston','Janelle James','Jeremy Allen White','Kayvan Novak','Tom Ellis','Sandra Oh','Pedro Pascal']
  ),
  ('tv_locations',
    array['the coffee shop Central Perk','the paper company Dunder Mifflin','the island of Westeros','the town of Hawkins, Indiana','the Springfield Nuclear Power Plant','the Crawley family estate','the advertising agency Sterling Cooper','the Sacred Heart teaching hospital','the town of Stars Hollow','the prison Litchfield Penitentiary','the kingdom of Bel-Air','the town of Twin Peaks','the precinct numbered 99','the Arconia apartment building','the Wessex school Moordale Secondary','the theme park containing Westworld','the island community of Craggy Island','the newsroom of ACN','the luxury Waystar Royco company','the Wernham Hogg paper merchant','the boarding house at 221B Baker Street','the post-apocalyptic Jackson settlement','the Good Place neighbourhood','the bar called Paddy''s Pub','the fast-food chain Los Pollos Hermanos'],
    array['Friends','The Office (US)','Game of Thrones','Stranger Things','The Simpsons','Downton Abbey','Mad Men','Scrubs','Gilmore Girls','Orange Is the New Black','The Fresh Prince of Bel-Air','Twin Peaks','Brooklyn Nine-Nine','Only Murders in the Building','Sex Education','Westworld','Father Ted','The Newsroom','Succession','The Office (UK)','Sherlock','The Last of Us','The Good Place','It''s Always Sunny in Philadelphia','Breaking Bad']
  ),
  ('tv_creators',
    array['The Twilight Zone','Star Trek','The Sopranos','The Wire','Grey''s Anatomy','Mad Men','Breaking Bad','Downton Abbey','Black Mirror','Girls','Peaky Blinders','Fleabag','Atlanta','The Good Place','Insecure','Succession','Ted Lasso','Abbott Elementary','The Bear','Severance','Reservation Dogs','Derry Girls','Squid Game','Baby Reindeer','I May Destroy You'],
    array['Rod Serling','Gene Roddenberry','David Chase','David Simon','Shonda Rhimes','Matthew Weiner','Vince Gilligan','Julian Fellowes','Charlie Brooker','Lena Dunham','Steven Knight','Phoebe Waller-Bridge','Donald Glover','Michael Schur','Issa Rae','Jesse Armstrong','Bill Lawrence','Quinta Brunson','Christopher Storer','Dan Erickson','Sterlin Harjo','Lisa McGee','Hwang Dong-hyuk','Richard Gadd','Michaela Coel']
  ),
  ('tv_formats',
    array['contestants baking in a white tent','entrepreneurs pitching businesses to investors','masked celebrities performing songs','drag performers competing for a crown','teams racing around the world','single contestants answering increasingly valuable multiple-choice questions','celebrities learning ballroom dances with professional partners','home cooks facing mystery-box challenges','designers creating outfits under time pressure','survivors voting one another off an island','amateur potters completing ceramic challenges','families searching for a new home abroad','comedians completing strange tasks for points','musicians turning chairs during blind auditions','contestants identifying traitors at a castle','teams restoring neglected gardens','aspiring interior designers transforming rooms','inventors presenting prototypes to business experts','players dropping counters into a giant arcade machine','celebrities living together under constant camera surveillance','couples meeting for the first time at the altar','quizzers taking on expert Chasers','contestants choosing sealed boxes containing cash amounts','players completing missions while a hidden saboteur disrupts them','pairs hunting for antiques to sell at auction'],
    array['The Great British Bake Off','Shark Tank','The Masked Singer','RuPaul''s Drag Race','The Amazing Race','Who Wants to Be a Millionaire?','Strictly Come Dancing','MasterChef','Project Runway','Survivor','The Great Pottery Throw Down','A Place in the Sun','Taskmaster','The Voice','The Traitors','Garden Rescue','Interior Design Masters','Dragons'' Den','Tipping Point','Celebrity Big Brother','Married at First Sight','The Chase','Deal or No Deal','The Mole','Bargain Hunt']
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
    case when f.idx <= 9 then 'easy' when f.idx <= 18 then 'medium' else 'hard' end as difficulty,
    case f.category
      when 'film_performers' then case v.variant when 1 then 'Which performer played ' || f.subject || '?' else 'Who portrayed ' || f.subject || ' on film?' end
      when 'film_directors' then case v.variant when 1 then 'Who directed the film ' || f.subject || '?' else f.subject || ' was directed by whom?' end
      when 'film_release_years' then case v.variant when 1 then 'In which year was ' || f.subject || ' first released?' else 'What was the original release year of ' || f.subject || '?' end
      when 'film_settings' then case v.variant when 1 then 'Which place provides the main setting for ' || f.subject || '?' else f.subject || ' is chiefly set in which location?' end
      when 'animation' then case v.variant when 1 then 'Which animated film features ' || f.subject || '?' else f.subject || ' appear in which animated movie?' end
      when 'famous_film_objects' then case v.variant when 1 then 'Which screen story features ' || f.subject || '?' else 'In which film or screen story would you encounter ' || f.subject || '?' end
      when 'tv_performers' then case v.variant when 1 then 'Which performer played ' || f.subject || '?' else 'Who portrayed ' || f.subject || ' on television?' end
      when 'tv_locations' then case v.variant when 1 then 'Which television series features ' || f.subject || '?' else f.subject || ' belongs to which television programme?' end
      when 'tv_creators' then case v.variant when 1 then 'Who created the television series ' || f.subject || '?' else f.subject || ' was created by whom?' end
      when 'tv_formats' then case v.variant when 1 then 'Which television programme is built around ' || f.subject || '?' else f.subject || ' describes the format of which show?' end
    end as prompt
  from facts f
  cross join (values (1), (2)) as v(variant)
)
insert into public.questions (pack_id, prompt, option_a, option_b, option_c, option_d, correct_option, difficulty, topic)
select
  '00000000-0000-0000-0000-000000000103'::uuid,
  prompt,
  case (idx + variant) % 3 when 0 then answer when 1 then wrong_one else wrong_two end,
  case (idx + variant) % 3 when 1 then answer when 2 then wrong_one else wrong_two end,
  case (idx + variant) % 3 when 2 then answer when 0 then wrong_one else wrong_two end,
  '',
  case (idx + variant) % 3 when 0 then 'A' when 1 then 'B' else 'C' end,
  difficulty,
  replace(category, '_', ' ')
from questions;

do $$
declare
  question_count integer;
  unique_prompt_count integer;
  topic_count integer;
  invalid_option_count integer;
begin
  select count(*), count(distinct lower(trim(prompt))), count(distinct topic)
  into question_count, unique_prompt_count, topic_count
  from public.questions
  where pack_id = '00000000-0000-0000-0000-000000000103'::uuid;

  select count(*)
  into invalid_option_count
  from public.questions
  where pack_id = '00000000-0000-0000-0000-000000000103'::uuid
    and (option_a = option_b or option_a = option_c or option_b = option_c);

  if question_count <> 500 or unique_prompt_count <> 500 or topic_count <> 10 then
    raise exception 'Movies and TV migration expected 500 questions, 500 unique prompts, and 10 topics; got %, %, and %', question_count, unique_prompt_count, topic_count;
  end if;

  if invalid_option_count <> 0 then
    raise exception 'Movies and TV migration generated % questions with duplicate answer options', invalid_option_count;
  end if;
end
$$;
