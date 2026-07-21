update public.question_packs
set description = 'A 500-question family-friendly mix across animals, food, nature, space, stories, films, music, sport, games, geography, science, words, numbers, and everyday life.'
where id = '00000000-0000-0000-0000-000000000102'::uuid;

delete from public.questions
where pack_id = '00000000-0000-0000-0000-000000000102'::uuid;

with category_data(category, clues, answers) as (
values
  ('animal',
    array['the fastest animal on land','the tallest living land animal','building dams across streams','carrying its baby in a pouch','changing colour to blend into its surroundings','having black and white stripes','being the largest living bird','having eight arms and three hearts','sleeping upside down and flying at night','having a long trunk','being a black and white bear that eats bamboo','spinning a web from silk','having a shell and moving very slowly','turning from a caterpillar into a winged adult','being a flightless bird strongly associated with Antarctica','having a horn on its nose','being known as a ship of the desert','having a laugh-like call in Australia','being covered in sharp protective spines','being the largest animal ever known','being a large fruit-eating bat sometimes called a fruit bat','using a pouch and hopping on powerful back legs','being a clever marine mammal that uses echolocation','having a mane and being called the king of the jungle','being the largest living reptile'],
    array['cheetah','giraffe','beaver','kangaroo','chameleon','zebra','ostrich','octopus','bat','elephant','giant panda','spider','snail','butterfly','penguin','rhinoceros','camel','kookaburra','hedgehog','blue whale','flying fox','wallaby','dolphin','lion','saltwater crocodile']
  ),
  ('baby_animal',
    array['goat','horse','cow','sheep','pig','dog','cat','deer','duck','chicken','swan','frog','butterfly','kangaroo','lion','elephant','bear','fox','rabbit','owl','eagle','goose','shark','whale','seal'],
    array['kid','foal','calf','lamb','piglet','puppy','kitten','fawn','duckling','chick','cygnet','tadpole','caterpillar','joey','cub','elephant calf','bear cub','kit','bunny','owlet','eaglet','gosling','pup','whale calf','seal pup']
  ),
  ('food',
    array['the main ingredient in hummus','the fruit mashed to make guacamole','the herb that gives traditional pesto its main flavour','the fruit dried to make raisins','the grain popped to make popcorn','the main ingredient in an omelette','the vegetable commonly carved for Halloween','the food made by bees from nectar','the Japanese dish made with vinegared rice','the Italian dish built with pasta sheets and layers of sauce','the Mexican folded or rolled tortilla dish','the French crescent-shaped breakfast pastry','the Indian flatbread often baked in a tandoor','the Spanish rice dish traditionally cooked in a wide pan','the Middle Eastern dish of fried chickpea balls','the Korean dish of seasoned fermented vegetables','the Greek dip made with yoghurt and cucumber','the Canadian dish of chips, cheese curds, and gravy','the Vietnamese noodle soup often called pho','the Indonesian fried rice dish called nasi goreng','the Malaysian noodle soup with a spicy coconut broth','the Turkish layered pastry sweetened with syrup','the Scottish dish traditionally made with oats and offal','the Italian frozen dessert similar to ice cream','the Ethiopian sour flatbread used to scoop up food'],
    array['chickpeas','avocado','basil','grape','corn','egg','pumpkin','honey','sushi','lasagne','burrito','croissant','naan','paella','falafel','kimchi','tzatziki','poutine','pho','nasi goreng','laksa','baklava','haggis','gelato','injera']
  ),
  ('kitchen',
    array['draining water from cooked pasta','beating air into eggs or cream','removing the skin from a carrot','grating cheese into small shreds','rolling pastry into a flat sheet','lifting soup from a pot into a bowl','turning food in a frying pan','measuring the temperature of cooked meat','opening a sealed metal food can','crushing garlic into tiny pieces','sifting flour to remove lumps','measuring a small amount of vanilla extract','cutting a pizza into neat wedges','drying washed salad leaves by spinning them','protecting a hand from a hot baking tray','mashing boiled potatoes','removing bread from a toaster safely','squeezing juice from a lemon half','mixing cake batter by hand','scraping dough from a work surface','removing stones from cherries','separating an egg yolk from its white','brushing melted butter onto pastry','timing how long biscuits bake','checking the weight of flour'],
    array['colander','whisk','vegetable peeler','grater','rolling pin','ladle','spatula','meat thermometer','can opener','garlic press','sieve','measuring spoon','pizza wheel','salad spinner','oven glove','potato masher','wooden tongs','citrus juicer','mixing spoon','bench scraper','cherry pitter','egg separator','pastry brush','kitchen timer','kitchen scales']
  ),
  ('body',
    array['pumping blood around the body','helping you breathe by filling with air','protecting the brain','joining the upper arm to the forearm','containing the smallest bones in the human body','detecting light so you can see','detecting smells','holding most of your teeth','digesting food after it is swallowed','helping clean the blood and make urine','being the largest organ of the human body','connecting muscles to bones','connecting one bone to another','allowing the leg to bend between thigh and shin','forming the bony structure of the chest','being the hard outer layer of a tooth','carrying messages between the brain and the body','helping the body balance inside the ear','being the coloured part of the eye','storing bile made by the liver','helping control blood sugar with insulin','being the main muscle used for breathing','joining the hand to the arm','joining the foot to the leg','cushioning the ends of bones in a joint'],
    array['heart','lungs','skull','elbow','middle ear','retina','nose','jaw','stomach','kidneys','skin','tendon','ligament','knee','rib cage','enamel','spinal cord','inner ear','iris','gallbladder','pancreas','diaphragm','wrist','ankle','cartilage']
  ),
  ('nature',
    array['water falling from clouds','a bright flash during a storm','the sound caused by lightning heating the air','a funnel-shaped rotating column of air reaching the ground','a huge sea wave usually caused by an underwater disturbance','molten rock flowing on Earth''s surface','molten rock beneath Earth''s surface','water vapour cooling into liquid droplets','liquid water changing into vapour','plants releasing water vapour through their leaves','a long period with very little rain','a mass of snow sliding rapidly down a mountain','a rainbow''s outermost colour','a rainbow''s innermost colour','the calm centre of a tropical cyclone','frozen balls of ice falling from a storm cloud','a cloud that forms at ground level','the regular rise and fall of sea level','the wearing away of rock by wind or water','rock broken down in its original location','a scientist who studies weather','the instrument used to measure rainfall','the instrument used to measure wind speed','the instrument used to measure air pressure','the line joining places of equal air pressure on a weather map'],
    array['rain','lightning','thunder','tornado','tsunami','lava','magma','condensation','evaporation','transpiration','drought','avalanche','red','violet','eye','hail','fog','tide','erosion','weathering','meteorologist','rain gauge','anemometer','barometer','isobar']
  ),
  ('space',
    array['the planet humans live on','the planet closest to the Sun','the hottest planet in the solar system','the planet famous for its rings','the largest planet in the solar system','the planet often called the Red Planet','the farthest recognised planet from the Sun','the planet that rotates on its side','Earth''s natural satellite','the star at the centre of our solar system','the galaxy containing our solar system','the first human to walk on the Moon','the first human to travel into space','the first woman to travel into space','the force that keeps planets in orbit','a rock from space that reaches the ground','a streak of light made by space rock burning in the atmosphere','an icy body that grows a tail near the Sun','a group of stars forming a recognised pattern','the nearest star to the Sun','the dwarf planet once classed as the ninth planet','the largest moon of Jupiter','the largest moon of Saturn','the planet with the shortest year','the planet with the Great Red Spot'],
    array['Earth','Mercury','Venus','Saturn','Jupiter','Mars','Neptune','Uranus','Moon','Sun','Milky Way','Neil Armstrong','Yuri Gagarin','Valentina Tereshkova','gravity','meteorite','meteor','comet','constellation','Proxima Centauri','Pluto','Ganymede','Titan','Mercury year','Jupiter']
  ),
  ('geography',
    array['the largest ocean on Earth','the smallest ocean on Earth','the largest continent by area','the smallest continent by land area','the longest river in South America','the world''s largest hot desert','the highest mountain above sea level','the country shaped like a boot','the country famous for maple syrup','the country containing the Great Wall','the country containing the pyramids of Giza','the country containing Machu Picchu','the country containing Mount Fuji','the country containing the Taj Mahal','the country containing the city of Venice','the country containing the city of Barcelona','the country containing the city of Rio de Janeiro','the country containing the city of Nairobi','the country containing the city of Bangkok','the country containing the city of Auckland','the sea between Europe and Africa','the imaginary line around Earth''s middle','the direction opposite east','the point where a river begins','the point where a river enters a sea or lake'],
    array['Pacific Ocean','Arctic Ocean','Asia','Australia','Amazon River','Sahara Desert','Mount Everest','Italy','Canada','China','Egypt','Peru','Japan','India','Italy country','Spain','Brazil','Kenya','Thailand','New Zealand','Mediterranean Sea','Equator','west','source','mouth']
  ),
  ('landmark',
    array['the Eiffel Tower','the Statue of Liberty','the Sydney Opera House','the Colosseum','Big Ben and the Palace of Westminster','the Christ the Redeemer statue','the Burj Khalifa','the Golden Gate Bridge','the Sagrada Familia','the Acropolis','the Petronas Twin Towers','the Merlion statue','the CN Tower','the Brandenburg Gate','the Anne Frank House','the Little Mermaid statue','the Blue Mosque','the Forbidden City','the Space Needle','the Gateway Arch','the Leaning Tower of Pisa','the Alhambra','the Table Mountain cableway','the Palace of Versailles','the Moai statues on Easter Island'],
    array['Paris','New York City','Sydney','Rome','London','Rio de Janeiro','Dubai','San Francisco','Barcelona','Athens','Kuala Lumpur','Singapore','Toronto','Berlin','Amsterdam','Copenhagen','Istanbul','Beijing','Seattle','St Louis','Pisa','Granada','Cape Town','Versailles','Hanga Roa']
  ),
  ('story',
    array['the girl who loses a glass slipper at a royal ball','the girl who follows a white rabbit down a hole','the wooden puppet whose nose grows when he lies','the girl with very long hair locked in a tower','the princess who sleeps after pricking her finger','the boy who never grows up in Neverland','the girl who visits the Land of Oz','the girl who meets three bears in their cottage','the tiny girl born inside a flower','the boy who climbs a giant beanstalk','the girl who wears a red hood to visit her grandmother','the princess who befriends seven dwarfs','the clever cat who wears boots','the poor boy who finds a magic lamp','the boy raised by wolves in the jungle','the bear from Peru who loves marmalade sandwiches','the bear who lives in the Hundred Acre Wood and loves honey','the young wizard with a lightning-shaped scar','the hobbit who carries the One Ring toward Mordor','the nanny who arrives with an umbrella','the girl with magical powers who loves reading books','the owner of a magical chocolate factory','the spider who writes words in her web to save a pig','the detective whose best friend is Dr Watson','the shipwrecked sailor who lives alone on an island'],
    array['Cinderella','Alice','Pinocchio','Rapunzel','Sleeping Beauty','Peter Pan','Dorothy Gale','Goldilocks','Thumbelina','Jack','Little Red Riding Hood','Snow White','Puss in Boots','Aladdin','Mowgli','Paddington Bear','Winnie-the-Pooh','Harry Potter','Frodo Baggins','Mary Poppins','Matilda Wormwood','Willy Wonka','Charlotte','Sherlock Holmes','Robinson Crusoe']
  ),
  ('screen',
    array['the snowman called Olaf','the cowboy toy called Woody','the lion cub called Simba','the ogre who lives in a swamp','the clownfish father searching for Nemo','the blue alien also known as Experiment 626','the robot left to clean an abandoned Earth','the family whose home and gifts are magical in Colombia','the emotions Joy and Sadness inside a girl''s mind','the super-family led by Mr Incredible and Elastigirl','the rat who dreams of becoming a chef in Paris','the sea voyager who returns the heart of Te Fiti','the arcade villain who wants to become a hero','the old man who flies his house using balloons','the dragon trainer named Hiccup','the panda who becomes the Dragon Warrior','Anna and Elsa travelling into an enchanted forest to discover the origin of Elsa''s powers','the toys whose owner is Andy','the monsters Sulley and Mike','the fish Dory who has short-term memory loss','the young musician Miguel visiting the Land of the Dead','the princess Merida who is skilled with a bow','the rabbit police officer Judy Hopps','the inventor Gru and his yellow helpers','the friendly ghost who lives in Whipstaff Manor'],
    array['Frozen','Toy Story','The Lion King','Shrek','Finding Nemo','Lilo & Stitch','WALL-E','Encanto','Inside Out','The Incredibles','Ratatouille','Moana','Wreck-It Ralph','Up','How to Train Your Dragon','Kung Fu Panda','Frozen II','Toy Story 2','Monsters, Inc.','Finding Dory','Coco','Brave','Zootopia','Despicable Me','Casper']
  ),
  ('music',
    array['an instrument with 88 black and white keys','a six-stringed instrument commonly strummed','a small four-stringed instrument associated with Hawaii','a brass instrument played with a slide','a woodwind instrument held sideways','a single-reed woodwind common in orchestras and jazz','the largest and lowest-pitched orchestral string instrument','a string instrument tucked under the chin and played with a bow','a brass instrument with three valves and a bright sound','a percussion instrument made of wooden bars','a pair of metal discs crashed together','a handheld percussion instrument with jingles around its frame','a small instrument played by blowing through holes and sliding it across the mouth','a Scottish wind instrument fed by an air bag','a keyed instrument whose bellows push air through reeds','a large tuned percussion instrument found in orchestras','a tall hand drum shaped like a goblet','a Caribbean instrument made from an oil drum','an electronic keyboard instrument named after its sound production method','a long Australian Aboriginal wind instrument','the highest female singing voice','the lowest male singing voice','the speed of a piece of music','the steady pulse you tap along to','the person who leads an orchestra'],
    array['piano','guitar','ukulele','trombone','flute','clarinet','double bass','violin','trumpet','xylophone','cymbals','tambourine','harmonica','bagpipes','accordion','timpani','djembe','steelpan','synthesizer','didgeridoo','soprano','bass','tempo','beat','conductor']
  ),
  ('sport',
    array['Wimbledon','the Tour de France','a slam dunk','a home run','a touchdown','a scrum and a try','a hole in one','a strike and a spare','a bullseye worth 50 points','a shuttlecock','a puck','a pommel horse','an épée and a foil','an ippon','a cue and coloured balls on a table','a bat, wickets, and an over','a net, spikes, and sets to 25 points','a penalty corner and curved sticks','a saddle, bridle, and stirrups','a board, waves, and a waxed deck','stones and sweeping on ice','a target face with concentric scoring rings and arrows','pins called a jack and woods rolled across grass','a piste, ski poles, and gates','a balance beam and uneven bars'],
    array['tennis','cycling','basketball','baseball','American football','rugby','golf','ten-pin bowling','darts','badminton','ice hockey','gymnastics','fencing','judo','snooker','cricket','volleyball','field hockey','equestrianism','surfing','curling','archery','lawn bowls','alpine skiing','artistic gymnastics']
  ),
  ('game',
    array['buying properties and collecting rent','forming words from letter tiles on a board','removing wooden blocks from a tower','calling out a word when one card remains','asking whether a person has a particular facial feature','solving a murder involving rooms, suspects, and weapons','moving pieces diagonally and jumping captures on an eight-by-eight board','saying checkmate to win','matching numbered tiles into runs and groups','placing coloured pegs to crack a hidden code','drawing clues while teammates guess','acting out a word without speaking','placing domino tiles with matching ends','spinning a pointer and placing hands and feet on coloured circles','finding matching pairs of face-down cards','rolling five dice up to three times for score combinations','guessing letters before a stick figure is completed','joining dots to complete and claim boxes','racing four coloured counters around a cross-shaped board','placing ships secretly on a grid and calling coordinates','asking up to twenty yes-or-no questions','using a pop-up dome to roll dice and race pegs home','building settlements and roads while trading resources','connecting four coloured discs in a vertical grid','giving one-word clues so teammates identify agents on a word grid'],
    array['Monopoly','Scrabble','Jenga','Uno','Guess Who?','Cluedo','draughts','chess','Rummikub','Mastermind','Pictionary','charades','dominoes','Twister','Concentration','Yahtzee','Hangman','Dots and Boxes','Ludo','Battleship','Twenty Questions','Trouble','Catan','Connect Four','Codenames']
  ),
  ('job',
    array['designing buildings','treating sick animals','putting out fires and rescuing people','flying an aircraft','baking bread and cakes professionally','repairing water pipes and taps','installing and repairing electrical wiring','cutting and styling hair','taking professional photographs','reporting news stories','studying stars and planets','studying ancient objects and sites','forecasting weather','creating maps','growing crops and raising livestock','making and repairing wooden objects','serving as an official in a court of law','helping library visitors find books','testing eyesight and prescribing glasses','preparing and dispensing medicines','designing visual layouts and logos','translating spoken language in real time','protecting swimmers at a beach or pool','repairing car engines','directing actors and scenes in a film'],
    array['architect','veterinarian','firefighter','pilot','baker','plumber','electrician','hairdresser','photographer','journalist','astronomer','archaeologist','meteorologist','cartographer','farmer','carpenter','judge','librarian','optometrist','pharmacist','graphic designer','interpreter','lifeguard','mechanic','film director']
  ),
  ('transport',
    array['travelling underwater for long periods','carrying many passengers on rails beneath a city','rising using hot air inside a large fabric envelope','flying with spinning rotor blades','travelling over snow on runners','carrying cars and passengers across water','moving along a suspended cable above the ground','travelling on one wheel using pedals','moving over water using a sail and wind','being propelled through space by powerful engines','carrying injured patients to hospital','putting out fires with pumps, hoses, and ladders','collecting household rubbish','pulling a separate passenger carriage behind a bicycle','travelling on two parallel rails between cities','carrying cargo in large containers across oceans','taking off vertically using several small rotors','gliding through air with a fabric wing and harness','travelling on ice with a sail attached to a runner frame','being pushed along by kicking while standing on two small wheels','using pedals to move along water like a bicycle','travelling across marshy ground on a cushion of air','climbing steep railway slopes using a cable','carrying passengers through a city on street rails','moving farm equipment and pulling heavy trailers'],
    array['submarine','metro train','hot-air balloon','helicopter','sleigh','ferry','cable car','unicycle','sailboat','rocket','ambulance','fire engine','bin lorry','bicycle trailer','intercity train','container ship','quadcopter','hang glider','iceboat','kick scooter','pedal boat','hovercraft','funicular','tram','tractor']
  ),
  ('word',
    array['ancient','noisy','generous','victory','expand','arrive','borrow','include','maximum','shallow','rough','transparent','rare','temporary','innocent','optimistic','flexible','vertical','artificial','ordinary','identical','accept','remember','create','entrance'],
    array['modern','quiet','selfish','defeat','contract','depart','lend','exclude','minimum','deep','smooth','opaque','common','permanent','guilty','pessimistic','rigid','horizontal','natural','unusual','different','reject','forget','destroy','exit']
  ),
  ('number',
    array['6 multiplied by 7','the number of sides on an octagon','half of 100','the next prime number after 7','a dozen plus a baker''s dozen','the square root of 81','three quarters of 20','the number of minutes in two hours','the number of months in three years','the Roman numeral XL','15 percent of 200','the missing number in 5, 10, 15, 20, ...','the perimeter of a square with sides of 6 cm','the number of degrees in a right angle','the number of faces on a cube','the number of zeros in one million','the result of 144 divided by 12','the smallest three-digit number','the number of items in five pairs','the result of 9 squared','the number of days in a leap year','the number of centimetres in one metre','the number of hours in three days','the result of 1,000 minus 375','the value of seven cubed'],
    array['42','8','50','11','25','9','15','120','36','40','30','25 next','24','90','6','6 zeros','12','100','10','81','366','100 centimetres','72','625','343']
  ),
  ('time',
    array['the month directly before August','the month with the fewest days','the first month of the calendar year','the final month of the calendar year','the day directly after Friday','the day directly before Monday','the season after spring in the Northern Hemisphere','the season after autumn in the Northern Hemisphere','the number of days in a standard year','the number of days in April','the number of hours in one day','the number of seconds in one minute','the number of years in a decade','the number of years in a century','the number of months in a quarter of a year','the time shown as 14:30 on a 12-hour clock','midnight on a 24-hour clock','the name for a period of two weeks','the calendar date of New Year''s Day','the calendar date of Halloween','the calendar date of Christmas Day','the extra date added in a leap year','the season when leaves commonly fall in temperate regions','the part of day between afternoon and night','the point when day and night are approximately equal in length'],
    array['July','February','January','December','Saturday','Sunday','summer','winter','365 days','30 days','24 hours','60 seconds','10 years','100 years','3 months','2:30 p.m.','00:00','fortnight','1 January','31 October','25 December','29 February','autumn','evening','equinox']
  ),
  ('science',
    array['the gas people breathe in to survive','the gas plants take in during photosynthesis','water in its solid state','water boiling at sea level in degrees Celsius','water freezing in degrees Celsius','the force pulling objects toward Earth','the process plants use to make food from light','the centre of an atom','the negatively charged particle in an atom','the positively charged particle in an atom','the hardest natural substance','the metal that is liquid at ordinary room temperature','the nearest planet to the Sun','the instrument used to view tiny cells','the instrument used to view distant stars','the change from solid directly to gas','the change from gas to liquid','the movement of heat through direct contact','the bending of light as it enters a different material','the splitting of white light into colours','the energy stored in food','the substance with a pH below 7','the substance with a pH above 7','the organelle often called the powerhouse of the cell','the green pigment that absorbs light in plants'],
    array['oxygen','carbon dioxide','ice','100 degrees','0 degrees','gravity','photosynthesis','nucleus','electron','proton','diamond','mercury','Mercury planet','microscope','telescope','sublimation','condensation','conduction','refraction','dispersion','chemical energy','acid','alkali','mitochondrion','chlorophyll']
  )
),
facts as (
  select
    cd.category,
    u.clue,
    u.answer,
    u.idx,
    cd.answers,
    cardinality(cd.answers) as answer_count
  from category_data cd
  cross join lateral unnest(cd.clues, cd.answers) with ordinality as u(clue, answer, idx)
),
questions as (
  select
    f.category,
    f.clue,
    f.answer,
    f.answers[(f.idx % f.answer_count) + 1] as wrong_one,
    f.answers[((f.idx + 7) % f.answer_count) + 1] as wrong_two,
    f.idx,
    case
      when f.idx <= 9 then 'easy'
      when f.idx <= 18 then 'medium'
      else 'hard'
    end as difficulty,
    case f.category
      when 'animal' then 'Which animal is known for ' || f.clue || '?'
      when 'baby_animal' then 'What is the usual name for a baby ' || f.clue || '?'
      when 'food' then 'Which food best matches this clue: ' || f.clue || '?'
      when 'kitchen' then 'Which kitchen tool is best suited to ' || f.clue || '?'
      when 'body' then 'Which body part or organ is responsible for ' || f.clue || '?'
      when 'nature' then 'What is the name for ' || f.clue || '?'
      when 'space' then 'Which space answer matches this clue: ' || f.clue || '?'
      when 'geography' then 'Which geography answer matches this clue: ' || f.clue || '?'
      when 'landmark' then 'In which city would you find ' || f.clue || '?'
      when 'story' then 'Which story character matches this description: ' || f.clue || '?'
      when 'screen' then 'Which family film features ' || f.clue || '?'
      when 'music' then 'Which musical answer matches this clue: ' || f.clue || '?'
      when 'sport' then 'Which sport is associated with ' || f.clue || '?'
      when 'game' then 'Which game involves ' || f.clue || '?'
      when 'job' then 'Which job mainly involves ' || f.clue || '?'
      when 'transport' then 'Which form of transport is designed for ' || f.clue || '?'
      when 'word' then 'Which word is the best opposite of ' || f.clue || '?'
      when 'number' then 'What is ' || f.clue || '?'
      when 'time' then 'Which time or calendar answer matches ' || f.clue || '?'
      when 'science' then 'Which science answer matches this clue: ' || f.clue || '?'
    end as prompt
  from facts f
)
insert into public.questions (pack_id, prompt, option_a, option_b, option_c, option_d, correct_option, difficulty)
select
  '00000000-0000-0000-0000-000000000102'::uuid,
  prompt,
  case idx % 3 when 0 then answer when 1 then wrong_one else wrong_two end,
  case idx % 3 when 1 then answer when 2 then wrong_one else wrong_two end,
  case idx % 3 when 2 then answer when 0 then wrong_one else wrong_two end,
  '',
  case idx % 3 when 0 then 'A' when 1 then 'B' else 'C' end,
  difficulty
from questions;

do $$
declare
  question_count integer;
  unique_prompt_count integer;
  invalid_option_count integer;
begin
  select count(*), count(distinct lower(trim(prompt)))
  into question_count, unique_prompt_count
  from public.questions
  where pack_id = '00000000-0000-0000-0000-000000000102'::uuid;

  select count(*)
  into invalid_option_count
  from public.questions
  where pack_id = '00000000-0000-0000-0000-000000000102'::uuid
    and (option_a = option_b or option_a = option_c or option_b = option_c);

  if question_count <> 500 or unique_prompt_count <> 500 then
    raise exception 'Family Fun migration expected 500 questions and 500 unique prompts, got % questions and % unique prompts', question_count, unique_prompt_count;
  end if;

  if invalid_option_count <> 0 then
    raise exception 'Family Fun migration generated % questions with duplicate answer options', invalid_option_count;
  end if;
end
$$;
