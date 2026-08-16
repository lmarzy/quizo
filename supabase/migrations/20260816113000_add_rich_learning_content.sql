create table public.question_learning_content (
  question_id uuid primary key references public.questions(id) on delete cascade,
  title text not null,
  summary text not null,
  context text not null,
  memory_hook text not null,
  created_at timestamptz not null default now()
);

alter table public.question_learning_content enable row level security;

create policy "Users can read learning content for available questions"
on public.question_learning_content for select
using (
  exists (
    select 1
    from public.questions q
    join public.question_packs qp on qp.id = q.pack_id
    where q.id = question_learning_content.question_id
      and (qp.visibility = 'public' or qp.owner_user_id = auth.uid())
  )
);

with content_data(topic, subjects, titles, summaries, contexts) as (
values
  ('food',
    array['sushi','paella','kimchi','poutine','moussaka','pho','tagine','haggis','pierogi','goulash','ceviche','falafel','bibimbap','baklava','gelato','tacos','croissant','biryani','pad thai','injera','feijoada','arepas','laksa','churros','sauerbraten'],
    array['Sushi','Paella','Kimchi','Poutine','Moussaka','Pho','Tagine','Haggis','Pierogi','Goulash','Ceviche','Falafel','Bibimbap','Baklava','Gelato','Tacos','Croissant','Biryani','Pad Thai','Injera','Feijoada','Arepas','Laksa','Churros','Sauerbraten'],
    array[
      'Sushi is a Japanese dish built around vinegared rice, often served with seafood, vegetables, or egg. The word describes the rice preparation, not raw fish alone.',
      'Paella is a Spanish rice dish traditionally cooked in a wide, shallow pan. It originated around Valencia and may contain seafood, meat, vegetables, or a mixture.',
      'Kimchi is a Korean preparation of salted and fermented vegetables, commonly napa cabbage or radish. Chilli, garlic, and ginger give many versions their distinctive flavour.',
      'Poutine is a Canadian dish of chips topped with cheese curds and hot gravy. It originated in Quebec in the 1950s and became a well-known Canadian comfort food.',
      'Moussaka is a layered baked dish associated with Greece. A common Greek version combines aubergine, minced meat, and a creamy bechamel topping.',
      'Pho is a Vietnamese noodle soup with a fragrant broth, rice noodles, herbs, and usually beef or chicken. Its name is commonly pronounced closer to “fuh” than “foe”.',
      'A tagine is both a North African stew and the cone-lidded earthenware pot used to cook it. Moroccan versions often combine meat or vegetables with warm spices and fruit.',
      'Haggis is a savoury Scottish dish traditionally made from sheep offal mixed with oats, onion, and spices. It is especially associated with Burns Night.',
      'Pierogi are filled dumplings strongly associated with Poland. Common fillings include potato and cheese, meat, mushrooms, fruit, or sauerkraut.',
      'Goulash is a Hungarian soup or stew seasoned prominently with paprika. It developed as a practical meal made by cattle herders.',
      'Ceviche is a seafood dish associated with Peru in which raw fish is cured in citrus juice. Chilli, onion, and coriander are common accompaniments.',
      'Falafel consists of deep-fried balls or patties made from chickpeas, broad beans, or both. It is eaten across the Middle East, often inside flatbread with salad and sauce.',
      'Bibimbap is a Korean rice dish topped with arranged vegetables, often meat and egg, and chilli paste. Its name refers to mixing the rice before eating.',
      'Baklava is a layered pastry made with thin filo, chopped nuts, and syrup or honey. Variations are found across Turkey, Greece, the Balkans, and the Middle East.',
      'Gelato is an Italian-style frozen dessert. It is generally churned with less air and served slightly warmer than standard ice cream, producing a dense texture.',
      'A taco is a Mexican dish made by folding or rolling a tortilla around a filling. Fillings vary widely and the tortilla may be corn or wheat.',
      'A croissant is a laminated, crescent-shaped pastry associated with France. Repeated layers of butter and dough create its flaky structure.',
      'Biryani is a layered rice dish from South Asia, typically combining fragrant rice, spices, and meat or vegetables. Regional versions differ throughout the Indian subcontinent.',
      'Pad Thai is a Thai stir-fried rice-noodle dish commonly flavoured with tamarind, fish sauce, egg, and peanuts. Sweet, sour, salty, and savoury flavours are balanced together.',
      'Injera is a soft, sour, spongy flatbread central to Ethiopian and Eritrean food. It is commonly made from teff and doubles as both plate and eating utensil.',
      'Feijoada is a slow-cooked bean stew strongly associated with Brazil. It usually combines black beans with several cuts of pork or beef.',
      'Arepas are round maize cakes eaten especially in Venezuela and Colombia. They can be split and filled or served alongside a meal.',
      'Laksa is a spicy Southeast Asian noodle soup especially associated with Malaysia and Singapore. Major styles use either a rich coconut broth or a sour tamarind-based broth.',
      'Churros are ridged lengths of fried dough, commonly dusted with sugar. They are associated with Spain and are often eaten with thick hot chocolate.',
      'Sauerbraten is a German pot roast marinated for several days before slow cooking. Its characteristic sauce balances sour and sweet flavours.'
    ],
    array['Japan','Spain','Korea','Canada','Greece','Vietnam','Morocco','Scotland','Poland','Hungary','Peru','the Middle East','Korea','Turkey and neighbouring regions','Italy','Mexico','France','South Asia','Thailand','Ethiopia and Eritrea','Brazil','Venezuela and Colombia','Malaysia and Singapore','Spain','Germany']
  ),
  ('technology',
    array['CPU','RAM','URL','HTML','CSS','HTTP','HTTPS','SQL','API','DNS','GPU','SSD','USB','VPN','LAN','IP address','2FA','JSON','XML','SaaS','BIOS','CLI','GUI','NFC','OCR'],
    array['CPU','RAM','URL','HTML','CSS','HTTP','HTTPS','SQL','API','DNS','GPU','SSD','USB','VPN','LAN','IP address','2FA','JSON','XML','SaaS','BIOS','CLI','GUI','NFC','OCR'],
    array[
      'The central processing unit is the main processor that executes instructions and coordinates much of a computer’s work. It is often described as the computer’s brain.',
      'Random access memory is a computer’s short-term working space. It temporarily holds data for active programs and is cleared when power is removed.',
      'A uniform resource locator is the address used to locate a resource on the web. It can include the protocol, domain, path, and other information.',
      'Hypertext Markup Language gives a web page its structure and meaning. Headings, paragraphs, links, and images are represented with HTML elements.',
      'Cascading Style Sheets control how structured web content looks. CSS handles layout, colours, spacing, typography, and responsive presentation.',
      'Hypertext Transfer Protocol defines how web clients and servers exchange requests and responses. It underpins everyday web browsing.',
      'HTTPS is HTTP protected by encryption, normally using TLS. It helps prevent outsiders reading or altering data moving between browser and server.',
      'Structured Query Language is used to create, read, update, and analyse data in relational databases. SQL works with tables, rows, and relationships.',
      'An application programming interface is a defined way for software systems to communicate. It exposes operations or data without revealing every internal detail.',
      'The Domain Name System translates human-friendly domain names into network addresses. It acts like a distributed directory for the internet.',
      'A graphics processing unit performs many calculations in parallel. It is important for graphics, video, scientific computing, and modern AI workloads.',
      'A solid-state drive stores data in flash memory with no moving parts. It is generally faster and more resistant to shock than a mechanical hard drive.',
      'Universal Serial Bus is a standard for connecting and powering devices. The same family supports keyboards, drives, phones, cameras, and many other peripherals.',
      'A virtual private network creates an encrypted connection between a device and another network. It can protect traffic on untrusted networks and enable remote access.',
      'A local area network connects devices across a limited area such as a home, office, or school. Ethernet and Wi-Fi are common LAN technologies.',
      'An Internet Protocol address identifies a device or interface on an IP network. Routers use these addresses to direct data toward its destination.',
      'Two-factor authentication requires two different kinds of evidence before access is granted. A password plus an authenticator code is a common example.',
      'JavaScript Object Notation is a lightweight text format for structured data. It represents information with objects, arrays, strings, numbers, and other simple values.',
      'Extensible Markup Language is a text format that labels structured data with custom tags. It is designed to be both machine-readable and human-readable.',
      'Software as a service delivers software over the internet, usually through a browser or app. The provider operates and updates the underlying service.',
      'The Basic Input/Output System is firmware that helps initialise hardware when a computer starts. Modern computers often use UEFI as its successor.',
      'A command-line interface lets users control software by typing commands. It is efficient for automation, scripting, and precise technical work.',
      'A graphical user interface lets people interact through windows, icons, menus, and pointers. It contrasts with a text-based command line.',
      'Near-field communication is a short-range wireless technology. It enables contactless payments, travel cards, and quick device pairing at very close distances.',
      'Optical character recognition converts text in images or scans into machine-readable characters. It makes printed documents searchable and editable.'
    ],
    array['the computer processor','temporary working memory','a web address','web-page structure','visual web styling','web communication','encrypted web communication','relational databases','software communication','internet name lookup','parallel graphics processing','flash storage','device connections','encrypted networking','nearby connected devices','network identification','account security','lightweight data exchange','tagged structured data','cloud-delivered software','startup firmware','typed commands','visual interaction','very short-range wireless','reading text from images']
  ),
  ('animals',
    array['true sustained flight among mammals','changing color using chromatophores','the largest living land animal','the tallest living land animal','black and white stripes','carrying young in a pouch','building dams in rivers','using echolocation in the ocean','being the fastest land animal','having a long prehensile trunk','spinning silk webs','being a flightless bird from Antarctica','laying eggs despite being a mammal','having a powerful black and white spray defense','slow movement and algae-tinted fur','a venomous bite and hood display','the largest living bird by height','the largest living reptile','long-distance migration from North America to Mexico','using tools to crack shellfish','a laugh-like call in Australia','a black and white bear that eats mostly bamboo','a marsupial sometimes called a native bear','a horn made from keratin on its nose','living in highly organized colonies with a queen'],
    array['Bat','Chameleon','African elephant','Giraffe','Zebra','Kangaroo','Beaver','Dolphin','Cheetah','Elephant','Spider','Penguin','Platypus','Skunk','Sloth','Cobra','Ostrich','Saltwater crocodile','Monarch butterfly','Sea otter','Kookaburra','Giant panda','Koala','Rhinoceros','Ant'],
    array[
      'Bats are the only mammals capable of true, sustained flight. Their wings are formed from skin stretched across greatly elongated finger bones.',
      'Chameleons adjust colour using specialised skin structures, including cells called chromatophores. Colour changes are used for communication and temperature control as well as camouflage.',
      'The African elephant is the largest living land animal. Its huge ears also help release body heat in warm climates.',
      'The giraffe is the tallest living land animal. Its long neck helps it browse leaves high in trees, but it still has seven neck vertebrae like most mammals.',
      'Zebras are African members of the horse family recognised by black-and-white stripes. Every zebra’s stripe pattern is different.',
      'Kangaroos are marsupials, so their underdeveloped young continue growing inside a pouch. Powerful hind legs make hopping an efficient way to travel.',
      'Beavers build dams from branches, mud, and vegetation. The resulting ponds provide safer access to food and protection around their lodges.',
      'Dolphins use echolocation by producing clicks and interpreting returning echoes. This helps them navigate and locate prey underwater.',
      'The cheetah is the fastest land animal over short distances. Its light build, flexible spine, and long legs are specialised for acceleration.',
      'An elephant’s trunk combines its nose and upper lip. It is strong enough to move branches yet sensitive enough to pick up small objects.',
      'Spiders produce silk from organs called spinnerets. Different silks can be used for webs, egg sacs, safety lines, and wrapping prey.',
      'Penguins are flightless seabirds found mainly in the Southern Hemisphere. Their wings evolved into flippers suited to powerful underwater swimming.',
      'The platypus is a monotreme: a mammal that lays eggs. It also has a duck-like bill and detects electrical signals made by prey in water.',
      'Skunks can spray a strong-smelling defensive liquid from glands near the tail. Their bold colouring warns potential predators.',
      'Sloths move slowly to conserve energy on a low-calorie leaf diet. Algae can grow in their fur and help provide camouflage.',
      'Cobras are venomous snakes known for spreading their neck ribs into a hood when threatened. The display makes the animal appear larger.',
      'The ostrich is the tallest and heaviest living bird. It cannot fly, but its long, powerful legs make it an exceptional runner.',
      'The saltwater crocodile is the largest living reptile. It inhabits coastal waters, rivers, and wetlands across South and Southeast Asia and northern Australia.',
      'Monarch butterflies migrate thousands of kilometres between North America and central Mexico. No single butterfly completes the entire multi-generation round trip.',
      'Sea otters use stones as tools to open hard-shelled prey. They often rest while floating on their backs and may wrap themselves in kelp.',
      'The kookaburra is an Australian kingfisher famous for a territorial call resembling loud laughter. It often hunts insects, reptiles, and small animals.',
      'Giant pandas are bears whose diet consists mainly of bamboo. They have a modified wrist bone that works like a thumb for gripping stems.',
      'Koalas are Australian marsupials rather than bears. They feed mainly on eucalyptus leaves and spend much of the day sleeping to conserve energy.',
      'A rhinoceros horn is made from keratin, the same protein found in human hair and nails. It is not made of bone.',
      'Ant colonies are organised around one or more reproductive queens and many workers. Ants coordinate using chemical signals called pheromones.'
    ],
    array['the only flying mammal','colour-changing skin','the largest land animal','the tallest land animal','unique stripes','a marsupial pouch','natural dam building','underwater echolocation','short-distance speed','a versatile trunk','specialised silk','a swimming seabird','an egg-laying mammal','defensive spray','energy-saving movement','a warning hood','the largest bird','the largest reptile','multi-generation migration','tool use','a laughing call','a bamboo-eating bear','an Australian marsupial','keratin horns','a social colony']
  ),
  ('landmarks',
    array['Machu Picchu','the Taj Mahal','the Colosseum','Petra','Angkor Wat','Christ the Redeemer','the Acropolis','Stonehenge','the Alhambra','Chichen Itza','the Blue Mosque','Mount Fuji','Uluru','the Louvre Museum','Neuschwanstein Castle','the Forbidden City','Burj Khalifa','the Parthenon','the Leaning Tower of Pisa','the Sagrada Familia','Table Mountain','the Palace of Versailles','the Moai statues of Easter Island','the Dome of the Rock','the Potala Palace'],
    array['Machu Picchu','Taj Mahal','Colosseum','Petra','Angkor Wat','Christ the Redeemer','Acropolis of Athens','Stonehenge','Alhambra','Chichen Itza','Blue Mosque','Mount Fuji','Uluru','Louvre Museum','Neuschwanstein Castle','Forbidden City','Burj Khalifa','Parthenon','Leaning Tower of Pisa','Sagrada Familia','Table Mountain','Palace of Versailles','Moai of Easter Island','Dome of the Rock','Potala Palace'],
    array[
      'Machu Picchu is a 15th-century Inca citadel high in the Andes of Peru. Its terraces, temples, and precisely fitted stonework sit above the Urubamba Valley.',
      'The Taj Mahal is a white-marble mausoleum in Agra, India. Mughal emperor Shah Jahan commissioned it in memory of his wife Mumtaz Mahal.',
      'The Colosseum is a vast Roman amphitheatre in Italy. It hosted public spectacles including gladiatorial contests nearly two thousand years ago.',
      'Petra is an ancient city in Jordan famous for buildings carved into rose-coloured rock. It prospered as a trading centre of the Nabataean kingdom.',
      'Angkor Wat is an enormous temple complex in Cambodia. Originally built as a Hindu temple, it later became an important Buddhist site.',
      'Christ the Redeemer is the monumental statue overlooking Rio de Janeiro, Brazil. It stands with outstretched arms on Mount Corcovado.',
      'The Acropolis is the fortified hill above Athens, Greece, containing major ancient buildings. Its best-known structure is the Parthenon.',
      'Stonehenge is a prehistoric stone circle in southern England. Its huge stones were placed in stages thousands of years ago, though its full purpose remains debated.',
      'The Alhambra is a palace and fortress complex in Granada, Spain. It is celebrated for intricate Islamic architecture, courtyards, water features, and decoration.',
      'Chichen Itza is a major ancient Maya city in Mexico. The stepped pyramid known as El Castillo is its most recognisable monument.',
      'The Blue Mosque is an Ottoman-era mosque in Istanbul, Turkey. Its nickname comes from the blue tiles decorating much of its interior.',
      'Mount Fuji is Japan’s highest mountain and an active volcano. Its symmetrical cone has long been important in Japanese art, religion, and culture.',
      'Uluru is a massive sandstone monolith in central Australia. It is sacred to the Anangu people, its traditional owners.',
      'The Louvre is a major museum in Paris, France, housed in a former royal palace. Its collection includes the Mona Lisa and works spanning thousands of years.',
      'Neuschwanstein is a 19th-century castle in Bavaria, Germany. King Ludwig II commissioned its dramatic towers and romantic medieval styling.',
      'The Forbidden City is a vast imperial palace complex in Beijing, China. It served as the home and ceremonial centre of Chinese emperors for almost five centuries.',
      'Burj Khalifa is the world’s tallest building, located in Dubai in the United Arab Emirates. Its tiered design rises more than 800 metres.',
      'The Parthenon is an ancient temple on the Acropolis in Athens, Greece. It was dedicated to Athena, the city’s patron goddess.',
      'The Leaning Tower of Pisa is the bell tower of Pisa Cathedral in Italy. It began tilting during construction because of unstable ground beneath its foundations.',
      'The Sagrada Familia is a monumental basilica in Barcelona, Spain. Architect Antoni Gaudi combined organic forms, symbolic detail, and soaring towers in its design.',
      'Table Mountain is a flat-topped mountain overlooking Cape Town, South Africa. Its plateau and surrounding slopes support unusually rich plant life.',
      'The Palace of Versailles is a vast former royal residence near Paris, France. Louis XIV transformed it into a symbol of royal power and court life.',
      'The moai are enormous human figures carved by the Rapa Nui people on Easter Island, Chile. Many represented important ancestors and once stood on ceremonial platforms.',
      'The Dome of the Rock is an Islamic shrine in Jerusalem, recognisable by its golden dome. Completed in the late seventh century, it is among the oldest surviving Islamic monuments.',
      'The Potala Palace is a monumental hilltop complex in Lhasa, Tibet. It served as the winter residence of successive Dalai Lamas.'
    ],
    array['Peru','India','Italy','Jordan','Cambodia','Brazil','Greece','the United Kingdom','Spain','Mexico','Turkey','Japan','Australia','France','Germany','China','the United Arab Emirates','Greece','Italy','Spain','South Africa','France','Chile','Jerusalem','Tibet']
  )
),
facts as (
  select cd.topic, u.subject, u.title, u.summary, u.context
  from content_data cd
  cross join lateral unnest(cd.subjects, cd.titles, cd.summaries, cd.contexts) as u(subject, title, summary, context)
)
insert into public.question_learning_content (question_id, title, summary, context, memory_hook)
select
  q.id,
  f.title,
  f.summary,
  f.context,
  case f.topic
    when 'food' then 'Picture the dish, then connect it to ' || f.context || '.'
    when 'technology' then 'Connect ' || f.title || ' with ' || f.context || '.'
    when 'animals' then 'Connect ' || f.title || ' with ' || f.context || '.'
    when 'landmarks' then 'Place ' || f.title || ' in ' || f.context || '.'
  end
from public.questions q
join facts f
  on q.topic = f.topic
 and lower(q.prompt) in (
   lower(case f.topic
     when 'food' then 'Which country or region is most associated with ' || f.subject || '?'
     when 'technology' then 'In computing, what does ' || f.subject || ' stand for or refer to?'
     when 'animals' then 'Which animal is known for ' || f.subject || '?'
     when 'landmarks' then 'In which country would you find ' || f.subject || '?'
   end),
   lower(case f.topic
     when 'food' then f.subject || ' is most commonly linked with which place?'
     when 'technology' then 'Which phrase best matches the computing term ' || f.subject || '?'
     when 'animals' then 'What animal best fits this clue: ' || f.subject || '?'
     when 'landmarks' then f.subject || ' is located in which country?'
   end)
 )
where q.pack_id = '00000000-0000-0000-0000-000000000101'::uuid;

do $$
declare
  enriched_question_count integer;
  enriched_fact_count integer;
begin
  select count(*), count(distinct lower(title))
  into enriched_question_count, enriched_fact_count
  from public.question_learning_content content
  join public.questions question on question.id = content.question_id
  where question.pack_id = '00000000-0000-0000-0000-000000000101'::uuid;

  if enriched_question_count <> 200 or enriched_fact_count <> 100 then
    raise exception 'Expected rich content for 200 question variants and 100 unique facts, got % and %', enriched_question_count, enriched_fact_count;
  end if;
end
$$;
