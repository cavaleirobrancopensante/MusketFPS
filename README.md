# MusketFPS

A first-person musket game for phones, made in Godot: shipwrecked on an
unknown coast, you lead what's left of a company of musketeers through a
land of lizard hordes, warring kingdoms and dwarves, where your muskets are
the best weapons anyone has seen. Think Mount & Blade: Warband's Napoleonic Wars mod, with the
mass musket battles of the *Destroyermen* books.

It's growing into a Warband-style sandbox: see [ROADMAP.md](ROADMAP.md).

Built and tested with **Godot 4.7.1**. The version (`config/version` in
project.godot) shows at the bottom of the main menu. No art or audio files: every model,
sprite, animation and sound is generated in code.

**Play it in the browser:** <https://cavaleirobrancopensante.github.io/MusketFPS/>.
Every push to `main` rebuilds it (`.github/workflows/web.yml` exports the
Web preset and publishes it on the `gh-pages` branch), so the link is
always the latest version. (GitHub Pages must be set once to serve the
`gh-pages` branch: Settings → Pages → Deploy from a branch → gh-pages / root.)

**Languages:** English, Português (Brasil) and Español: the three flags in
the top-right corner of the main menu switch the whole game (remembered).
Every piece of text goes through `Lang.t()` (`scripts/lang.gd`), with the
English as the key and the translations in `data/i18n/pt_BR.json` and
`data/i18n/es.json`. `python3 tools/i18n.py wrap` wraps new text in the
scripts, `extract` refreshes `data/i18n/en.json`, and `missing` lists what
each language still lacks.

## The campaign

### A new campaign: who you are

**NEW CAMPAIGN** (after picking a slot) opens the new-campaign screen
(`scripts/creation.gd`):

- A die beside your name rolls a random one; dice beside Attributes and
  Skills spend the points at random (within the rules). Every attribute
  and skill has a **?** that explains it in plain words, with the exact
  numbers underneath. Each kind of officer lists plainly what you get:
  your two units, your own kit, the skills, and how you fight. The
  colours (coat, flag pattern, field and device) are big enough to tap.

- **Your name**, and the **difficulty**: Easy, Normal, Hard or Ironman.
  It scales the enemy's numbers and toughness (bigger warbands, braver and
  harder to kill), the damage you and your men take, money (the starting
  purse, bounties, the pay chest) and how fast the food goes. Ironman is
  Hard with one save that keeps itself: leave a battle half fought and,
  when you come back, it counts as lost.
- **What kind of officer you are**, each with its own skills, kit, men and
  first battle (`officer.gd` BRANCHES). Every officer leads two units: a
  company of musketeers and his own kind (the line officer's second unit is
  another company of muskets; in every battle his muskets stand as two
  companies):
  - *Officer of the Line*: two companies of musketeers (+4 men), Marksmanship +3, Leadership +1.
  - *Officer of Pikes*: +6 pikemen and a pike of your own (THRUST reaches
    furthest; BLOCK braces it, so whatever runs at you lands on the point),
    Bladework +3, Leadership +1.
  - *Officer of Artillery*: a light gun (a galloper) and its crew, which
    you lay and fire yourself: every battle starts with you at its trail
    (LEAVE THE GUN to fight on foot; walk back to its trail and MAN THE GUN
    shows on the left); look to
    traverse and elevate (it follows, a little slowly), a gold ring shows
    where the ball will land, BALL or CANISTER. The crew are flat behind
    the gun when it fires: your own shot never hits them, even striking the
    works close in front. You can take over any of your guns the same
    way. Gunnery +3 (every crew reloads faster, your shot scatters less),
    Tactics +1.
  - *Officer of Horse*: you start mounted, with a lance (COUCH it at the
    gallop: the point takes the horse's speed), a sabre and a pistol, and
    a troop of six (dragoons and lancers). Push the stick the way to go:
    the further, the faster, with momentum and a turning circle that
    widens at the gallop. Sabre and pistol from the saddle (the horse's
    speed is in the blow, and you reach further); at speed you ride men
    down. Blows often land on the horse; if it's killed you're thrown, and
    a town's market sells another. MOUNT/DISMOUNT. Riding +3, Bladework +1.
- **Your colours**: the coat your men wear (Calder blue, scarlet, rifle
  green, grey, white, buff, black, brown, purple; your own coat is a
  darker shade of it) and your flag: a pattern (cross, centre cross,
  saltire, quarters, stripes, bands, border, plain), a field colour and a
  device colour, previewed as you pick. They follow you everywhere: the
  cutscene, every battle, the saddle cloths, the camp on the menu, your
  marker on the map (`scripts/colours.gd`).
- **Attributes and skills**: 4 attribute points and 5 skill points to
  spend (− gives one back), on top of what your branch gives. Two new
  skills: Riding and Gunnery.

### Prologue: the wreck and the beach (also the tutorial)

The beach battle starts the same for everyone, but its first beats teach
your branch: in the front rank with the musket (line); your pike block on
the right of the line with raptor riders coming for it (pikes); at your gun
in an embrasure (artillery); mounted behind the works, sent out to ride
down their skirmishers and called back (cavalry).

**NEW CAMPAIGN** opens with a film played in the engine (letterboxed, a
little over a minute; Skip jumps ahead):

1. The troopship *Steadfast* rolling through a night storm.
2. She strikes uncharted rocks; the mainmast comes down.
3. Golden dawn over the wreck: a spar is run out over the high rail and a
   gun is swayed out on a tackle and lowered into a boat, men hauling on
   deck and two in the boat reaching up to guide it in.
4. The flotilla pulls for the shore: every oar dips, sweeps and feathers in
   time, the rowers lean back into each stroke, the cox beats the time, a
   gun lashed amidships and the colours in the stern.
5. The landing: boats grounded in the shallows, men wading ashore, two guns
   dragged up the sand on ropes, the Major against the rising sun, sabre
   out, waving them on.
6. The works: a crane shot over a line of men digging (drive the spade,
   lever, throw), the rampart rising, gun crews at their pieces.
7. The Major on a crate before the colours, sabre raised at the forest:
   "Not one step back from this sand."
8. From behind the rampart, sentries looking out at the trees; birds burst
   out of the forest, and the drums begin.

All names are placeholders in `scripts/lore.gd`.

Then **Wreck Beach**, fought as a field battle (the same system as every
fight in the campaign: regiments, morale, the command view). You are the
**Ensign** of Major Harrow's company, behind earthworks with the sea at
your back: your company in the centre, a company on either side, and a
battery of two guns in the embrasures between them. The guns fire round
shot at range and canister close in; they're dug in, so they lay and fire
but never march (none of them walks over the works); lizards wading over
the earthworks are slowed. The Major gives the orders: FOLLOW, HOLD, CHARGE and VOLLEY are
locked while he lives, the command view isn't yours yet, and he calls the
volleys.

The battle is the tutorial: each beat shows a **HOW TO** box for the
controls it needs (moving and looking, firing and aiming, the bayonet and
blocking, grenades, the orders and the command view). No markers or
arrows: the story moves on by itself, in short cutscenes (`story_scene.gd`).

1. **The Major's battle:** two waves out of the forest.
2. **The javelin:** in the second wave it brings the Major down. A
   cutscene: the sergeant's shout, you come through the smoke and kneel by
   him in the sand, and with his last words he gives you the regiment.
3. **Your command:** the command view opens, paused, with a short lesson
   (GOT IT closes it; select a regiment by its card or on the field; tap the ground to march,
   drag along the ground to form a line, tap an enemy to attack). A third wave comes on,
   brutes in the centre and raptor riders on the right. Fight it from above
   or in the line, as you like.
4. **The collapse:** after a while (sooner if the regiment bleeds) a horde
   comes round the left end of the works. A cutscene over the left flank:
   the left company breaks, the horde pours over the earthworks and in
   among the guns, and the battle ends there.

Straight on into the retreat cutscene: the run along the sand with men
turning round to fire, stragglers caught by the lizards fighting it out
with the bayonet, a volley at the foot of the path; then more of them come
on, the line fixes bayonets (you see each man draw and fix his) and the
sergeant calls the charge. **The charge is yours to play**, in first
person, whatever kind of officer you are: on foot, musket and bayonet, no
horse or gun (`field_rearguard.gd`, the bayonet lesson: fix bayonets, strike
from a side, block when one rears up glowing, finish them; nothing counts
on the books). Then the cutscene carries on: the charge throws them back,
the beach through the Major's glass (the lizards stripping the dead, and
worse), the ammunition cart recovered from a gully, the horde pulling down
the works and breaking up the boats, and the column turning inland.
Everyone who speaks in the cutscenes and in battle has a voice: a run of
short voice blips while the line is up, the way Robot Fighting's
characters talk (`SoundFactory.talk`: clean, gravel, smooth or nasal, each
speaker at his own pitch). Shouted orders are a quick hard burst of the same
blips (the old sung "HAA-ah" came out as a moan), and a man going down
gives a short dry grunt. A gun's shot never strikes our own men or guns
within 9 m of its muzzle: the crew lie flat when it fires.

You start the campaign as castaways: low morale, a few days' food, and the
ship's stores (muskets, powder, two guns, rum) in the lizards' hands.
Getting them back is the first great objective.

### The map

After the beach, **TO THE MAP** takes the company inland. Every new
campaign draws a new land: 512 × 512 cells of real 3D terrain (coast,
forest, swamp, plains, hills, mountains). The story's plan is kept (a coast
where you wash up, lizard swamps behind it, two nations at war, a mountain
range with the dwarves), but the whole layout is turned and mirrored at
random, and its proportions, ranges, ridges, rivers and borders change
with every seed.

- **Warband time:** tap where to go and the company marches there along the
  best route. The clock (and the calendar, food, water, wages, healing and
  every other party) runs only while you march or **WAIT**; it stops when
  you stop. Day and night pass with the sun.
- **Geography matters.** Pace depends on the ground: open plains, slow
  forest and hills, very slow swamp and mountain passes, impassable peaks,
  sea and lakes. Rivers can only be crossed at **fords** (slow) or
  **bridges**. **Roads** come in three states: good (fast) in the nations'
  heartlands, worn on the frontiers, ruined in the lizard lands. The men's
  fitness sets the pace, and carrying wounded or sick men slows it.
- **Line of sight and fog of war.** Everything starts unknown. What you can
  see is worked out on the real heightmap: hills and mountains see far,
  forests block sight and shorten it, night shortens it too. Land you've
  seen stays mapped (dimmed when out of sight); parties show only while you
  can see them.
- **Nightfall:** at 18:00 on the march you're asked: **make camp** and
  sleep until 06:00 (the night passes quickly; rested men gain a little
  morale), or **march on in the dark**, slower, half blind, and the men
  resent it. A warband can still find your camp: see **attacked in camp**.
- **Events on the road**, picked by where you are: wreckage from the ship on
  the coast, hunting and berries and lost men in the forest, fever mist and
  bogs in the swamp, lizard tracks and ambushes in their country, farmers,
  pedlars, refugees and deserters in the nations' lands, a crag to climb in
  the hills, fishing on the rivers, floods at the fords, ruins, dwarf
  prospectors. Each has choices with consequences.
- **What you can see of a party** depends on how close it is and on your
  **Tactics**: far off, only that something is there (**?**); nearer, a
  rough count ("about 10–16"); close, the exact number; and close with
  Tactics 3 or more, what it's made of (warriors, javelins, brutes,
  raptor riders). Scouts report rough counts. The warband you meet is the
  army you fight: its make-up becomes the enemy regiments.
- **Scouts:** choose how many **days** they're out (1 to 8: the longer, the
  further they go) and **who goes** (soldiers or labourers, listed best
  first by their scouting: fitness, stamina, a good eye, more for a hunter
  by trade or someone born here), and a direction. They take a ration and a
  day's water each for every day. They come back to the company wherever it
  is with what they found (land, towns, warbands) and map it: more of them
  sweep a wider circle and are safer; longer trips are riskier, and so are
  the lizards' country and warbands nearby. Some don't come back.
- **Water:** passing rivers and lakes refills the barrels with clean water,
  swamps with foul water; a dry day leaves you with what you carry.
- **The land's powers** (placeholder names in `lore.gd`): the Kingdom of
  Aurest in the west and the Vellish Marches in the east (at war), the
  dwarf holds of the Greyspine mountains in the north, and the lizard nests
  in the south-west swamps. One nest holds the ship's stores.
- **Weather** (`weather.gd`), from the land the map generator made, so it
  makes sense on every map. Each map has a prevailing wind off its own sea.
  Storms form over the sea near the coast (most in winter and autumn) and
  drift inland with it, raining hardest where the land rises and spending
  themselves over high ground, so the far side of a ridge lies in a rain
  shadow; summer afternoons brew short thunderstorms over the hills. Fog
  lies in low wet ground (swamps, lakes, river bottoms, the beach) on some
  mornings, likelier in autumn and after rain, and lifts by mid-morning.
  Summer hot spells bake the open ground in the afternoon. Rain and fog
  cut how far you see; rain and heat slow the march; rain **washes out
  tracks**; a good soaking fills the water barrels, and a hot day's march
  costs extra water. On the 3D map: storm clouds riding the wind, rain
  falling from them, lightning (and thunder after it), fog lying in the
  hollows, a greyer light in the rain and a yellow one in the heat. The
  HUD's bottom line names the weather. **Rivers rise after rain**: what
  falls on a river's course runs off into it (faster off steep high ground)
  and travels downstream, so a storm in the hills is a flood at the ford
  further down hours later. A swollen river shuts its fords (nobody
  crosses: parties wait at the bank) and, well over, floods the low ground
  beside it (wading, a third of the pace); the map draws the brown water
  over them, so the river grows wider. March into a shut ford and you
  choose: WAIT FOR IT TO FALL, CROSS NOW (rations and powder spoiled, a man
  may drown; worse the higher it runs) or FIND ANOTHER WAY (a bridge or
  another ford). **What the weather does to you**: rain soaks the
  company's powder (less in camp or with the powder covered; dry air and
  sun dry it out), and in battle damp powder misfires and loads slowly;
  rain slackens bowstrings (archers shoot wide and soft); the battlefield
  takes the weather of where it's fought (rain falling round you, a greyer
  light, fog, heat haze, a storm's lightning and thunder) and the battle
  opens with a line saying so. Rain on a work party stops most of the work
  (charcoal pits, saltpetre beds, sulphur, fields; mines less) and fish
  bite better after it. On the march the weather asks you: a squall
  (COVER THE POWDER, an hour, or PUSH ON: damp powder and soaked rations),
  fog (WAIT FOR IT TO LIFT or MARCH ON: a man may wander off, the wagon may
  go into a ditch), the heat (REST IN THE SHADE or PUSH ON: men drop, water
  goes) and, in camp in a storm, lightning (a man burned, the wagon's
  stores crushed by a tree, or just a sleepless night).
- **Tracks** (`World.tracks`, as in Mount & Blade): every party on the
  move leaves a trail of arrows on the map, pointing the way it went, that
  fades over two days. You only see tracks near you (5 cells, +2 a level of
  Pathfinding), coloured by who made them: red for a lizard warband, orange
  for lizard hunters, a nation's colour for its soldiers, pale for caravans
  and country people. Tap one to read it: who, roughly how many (closer
  with Pathfinding), which way and how old. The **Lizard tracks** event
  only comes when you cross a real fresh lizard trail; FOLLOW THE TRAIL
  (2 h) leads to the warband that made it and keeps it on your map for a
  day, to fall on it or keep out of its way.
- **Warband sizes swing** (`World.warband_size`): most are a few dozen,
  but a nest may send a **raiding band** of 6 to 14 or, now and then, a
  **war host** of 55 to 85, or even the whole nest on the march, 100 and
  more. The big ones grow likelier over the first two weeks, and every
  warband grows a little as the days go by. Fed nests send more.
- **A living world:** nests send out warbands that roam and raid villages;
  cities send patrols that hunt them (and each other, across the war);
  caravans travel between towns and holds; villagers go to market; dwarf
  traders come down from the mountains. Parties that meet fight it out,
  and you hear of what you see.
- **The nations and you.** Aurest and Vell each keep a **standing** with
  you (hostile, wary, neutral, friendly). Walk up to a patrol, a caravan or
  a band of deserters and you can **ATTACK** them: a field battle against
  their real make-up (spearmen, crossbowmen, archers and horse in their
  nation's coats and kettle hats; nobody in this land has gunpowder). It
  costs you with that nation (deserters are fair game) and warms the other
  side a little, since they're at war. Fall to hostile and the nation's
  patrols hunt you like warbands. No bounty on men: their kit and purses go
  on the loot pile.
- **Lords.** Each nation has three lords (Count Aldric de Valtier,
  Margrave Konrad von Kelstad...), each with a seat in one of its cities or
  towns. A lord raises an army there (40 to 70 men, more as the war goes
  on: spearmen, crossbows, archers and his household horse) and marches it
  to war: he burns the other nation's villages near the border and lays
  waste round its towns, and hunts warbands and enemy patrols on the way.
  Beaten, he gets away with his household and raises another army in a
  week or so. Each lord keeps his own account of you besides his nation's
  standing: fight beside him and he warms to you (he'll greet you by name);
  attack his army and he swears to see you hanged, and his army hunts you.
  **LORDS** on the map lists them all: where you stand with each nation and
  lord, and what you know of their armies. Their armies show gold on the
  map; anyone out to get you shows red.
- **Sieges and the war front.** An army that reaches an enemy town or
  city sits down before it (the label shows "besieged"): a town holds 4
  days, a city 7, a little less against a big army. If the besiegers are
  still there at the end, it falls and flies their banner from then on
  (towns change hands back and forth as the war goes; a lord who lost his
  seat raises his men elsewhere). The town's own nation sends armies to
  break the siege. Walk up to a besieged town and the gates are shut:
  **ATTACK THE BESIEGERS** (the garrison sallies to fight beside you), or,
  if you're on good terms with the besiegers, **HELP THE SIEGE** (your guns
  bring the walls down in a day). Either side remembers.
- **Whose banner a town flies** matters: where its nation thinks you
  hostile, the gates are shut and villagers bar their doors; wary, its
  markets charge a quarter more; friendly, a tenth less. Its people are
  readier to join you the better their lords think of you. A town taken in
  the war still speaks its old tongue.
- **Truces.** Every few weeks heralds ride between the camps and Aurest and
  Vell agree a truce for a week or two: their men don't fight each other,
  sieges are lifted and the armies go home. Then the war starts again.
- **An army at your side.** A lord who's a friend (or who has hired you)
  will **MARCH WITH US** for four days: his army keeps close, camps beside
  you, and fights in your line in any battle you fight, even when they're
  in among the bedrolls at night. Turn on his nation's men and he leaves.
- **Contracts.** Meet a lord's army when he and his nation think well
  enough of you (not cold, not wary) and you can **OFFER YOUR SERVICE**: he
  hires the company for three weeks at a weekly wage (more for more men and
  for the guns), with one duty: hunt down the lizard warbands raiding his
  lands (two bands, or burn a nest), or beat the other nation's men in the
  field (a patrol or an army, or join a fight against them). Do it and he
  pays a bonus and his nation warms to you; let it run out undone and he
  thinks less of you. The other nation hears you've signed on, and turning
  on your employer's men tears the contract up. LORDS shows the contract
  and how the duty stands.
- **Joining a fight.** When a nation's patrol or a lord's army is about to fight close by
  (a warband, or the other nation's men) and it isn't your enemy, the clock
  stops: **JOIN** them and their regiments deploy in your line, following
  their own officers until you give them an order from the command view
  (then they're yours), or **STAY OUT**. They remember the help; the other
  nation remembers too.
- **Encounters:** a lizard warband that catches you means battle or a
  chance to slip away, better in cover. Tap any party to go after it. The
  battle is a field battle (see **Field battle** under Tests: the same
  regiments, morale and command view) on a map picked by where you stand:
  a town or village nearby, a river, forest or swamp, hills or mountains,
  or open ground. Your fit men muster by weapon (muskets with you, pikes,
  bows and crossbows as regiments of their own; a handful of one kind
  stands with your company), the guns join when you have them back, and
  the wagon stands behind with its crew. Bigger fights deploy further
  apart; an ambush starts close, with no time to deploy. Men who run off
  the field come back after it. The night camp and the nest assaults are
  field battles too (below).
- **Settlements:** visit villages, towns, cities and holds to buy food and
  rum, refill water and rest. Raided villages have nothing left. You can
  only buy where someone sells (the wagon's Logistics shows what's on offer
  where you stand), recruits are found only in towns and cities, and nobody
  in this land has heard of gunpowder, so cartridges can't be bought at all.
- **Controls:** tap to march; drag to pan; pinch or mouse wheel to zoom
  (from a single village to the whole land); CENTRE to follow the company;
  COMPANY, WAGON, CAMP and MENU at the top right.

### The calendar and the pay

**The Church's calendar.** The map's clock is a date: the wreck is in the
spring of 1761, Day 1 being Monday 2 February, Candlemas. Under it is the
day's celebration in its liturgical colour, from the traditional Roman
calendar (the 1960 rubrics, as in the TCG-RPG: `calendar.gd`,
`data/calendar.json`): Septuagesima, Lent and Passiontide, Easter and its
octave, Pentecost, the Sundays after it, Advent and Christmastide, Ember
Days, and the saints' feasts of the I, II and III class, with their
commemorations. Tap the clock panel for THE CALENDAR: the next four weeks.
On a feast of the I class the men keep the day (morale rises); on Sundays a
little.

**Lent, Easter and the Lord's day.** The wreck falls at the start of Lent
(Ash Wednesday 1761 is 4 February, Easter 22 March). On fast days (the
weekdays of Lent, the Ember Days, most of all Ash Wednesday and Good Friday)
many of the men keep the fast on a crust, and the food goes further. Easter
Sunday is the company's great joy. On Sundays and feasts of the I class,
rest (don't march) and the men are glad of it and the wounded mend; march
and they grumble.

**A chaplain.** In a town or city of Aurest or Vell you can ASK THE CHURCH
FOR A CHAPLAIN (40 crowns, then 3 a week). He says Mass on Sundays and
feasts (the men's spirits rise more) and keeps them steadier: fewer desert,
mutiny is rarer.

**Seasons.** The calendar's month is the season, shown under the date:
winter (little to hunt or harvest, cold nights: men sicken more easily),
spring (fish running), summer, autumn (the harvest: fields and hunting give
the most). Every site's yield follows it, yours and the villages'.

**Time faster.** The ▶ ×1 button beside WAIT runs the map's clock at ×1, ×2
or ×4: marching, waiting and sleeping all go faster.

**The first week.** The wagon holds about a week's food. The foragers'
first report puts the nearest hunting ground and fishing water on the map,
and for the first fortnight the road is full of game and berries for
whoever looks.

**The ship's stores.** The map's panel says what you know of where the
lizards took them, a piece at a time: people in the towns talk (the first
time you visit a place), scouts who range near it see it, and beaten
warbands from that nest carry plunder from it. First a direction, then the
nest's name and the country round it, then its very place.

**Pay in the wilds.** Wages fall due every seven days. Until the company
finds people (it enters a village or a town), the men understand there's
nothing to be had: the pay is only *owed*, and it adds up. The first time,
they come to your fire with their hats in their hands, and the sergeant
says they'll wait, since a man can't eat gold out here, but once there's
somewhere to spend it they'll want every week of it. After that, a missed
week makes them angry. Whenever there's money on pay day, they're paid
everything owed (back pay lifts their spirits). The map shows "pay owed".

### Between battles

- **Every soldier is a person**: a name, his own reaction, pace and
  steadiness, experience, rank (Recruit, Musketeer, Veteran, Sergeant),
  battles fought and kills.
- **Levels and attributes.** Every 100 experience is a level and gives 1
  point to spend on his four attributes:

  | Attribute | What it does |
  |---|---|
  | Aim | Accuracy with the musket |
  | Strength | Bayonet damage and parrying |
  | Constitution | Hit points, how fast wounds and sickness heal, holding out against hunger and foul water |
  | Fitness | Pace in battle and on the march (a fit company marches a day faster), striking again sooner in melee |

- **Morale** (0–100) rises with victories, pay, full bellies and grog, and
  falls with defeats, missed pay, hunger, thirst, sickness and unfairness.
  It makes a man steadier or shakier in battle. Men below 12 desert; a
  company below 30 may **mutiny**, and the angriest third breaks into the
  wagon and leaves with food, powder and money.
- **Hunger and thirst** kill slowly: first morale, then every attribute, then
  health, and at 0 health a man dies on the road. Thirst works in days,
  hunger in about a week.
- **Water** is found on most days of the march, but some days are dry and some
  streams are foul. Foul water makes men sick unless it's served as **grog**:
  one tot of rum a man a day. Rum is bought from the sutler.
- **Fair shares.** Men who starve while their comrades eat, or who carry far
  less than the rest, resent it.
- **Battles have consequences.** A man who goes down is either wounded (out
  for 3 to 10 days) or killed. The dead go on the **roll of honour**.
- **Camp:** hire recruits (25 crowns; raw, with a worn musket and no
  cartridges), look after the company, then **MARCH ON**. Wages fall due every
  week. A beaten company loses a quarter of its purse and half its baggage.
- The campaign saves itself after every battle and every day on the map.
  There are **four save slots**, each its own campaign in its own land:
  **CONTINUE** picks up the last one, **LOAD** any other, **NEW CAMPAIGN**
  asks which slot to use (and a second tap to overwrite).

### The battle plan (PLAN on the map)

Where every man stands when a fight starts. The tactical map fills the left
and centre of the screen: you are the star, the enemy's side is at the top,
every man is a dot in his tag's colour, the wagon is a box. On the right:

- **MIXED** (with ONE LINE and PIKES AHEAD): spears and pikes two paces in
  front, muskets in the line with crossbows on its wings, bows in a rank
  behind (they shoot over the line).
- **Tags**: a dropdown of groups (Musketeers and Pikes to begin with); **NEW**
  makes another (Ranged 2, Reserve, whatever you like). Tap a man's tag
  button to put him in the selected tag.
- **LINE**: drag across the field and the selected tag forms a line along
  it, evenly spaced, in more ranks if the line is too short (a tap makes a
  line centred there).
- **MAN**: pick a man in the list, tap the field to place him.
- **WAGON**: tap to place the wagon. Any dot (or the wagon) can be dragged.
- **ONE LINE** and **PIKES AHEAD** presets.

In battle the formation keeps its shape around you: it moves and wheels with
you on FOLLOW and stays put on HOLD. Every battle starts on HOLD: your
company stands its ground until you give the word to FOLLOW. Before a fight you saw coming, the
encounter offers **PLAN** first. An **ambush** (a warband you never saw
coming) gives no time: the men start scattered.

**Attacked in camp** (a field battle: your regiments, the command view, no
time to deploy). At night the company sleeps on bedrolls in rings
round the fire, the wagon parked to one side, and two men stand watch at
the edge of the firelight. Whether they see the lizards coming depends on
their eyes (aim, a little fitness), whether they're hungry, thirsty or sick,
the ground (the lizards creep right up through forest and swamp) and luck.
**Seen:** the alarm goes up, the men throw off their blankets and are on
their feet in a second or two, form on their regiments' ground in front of
the fire, and the warband comes out of the dark from the front (or you abandon the camp and try to slip away). **Not seen:** you
wake on your back by the fire with the lizards' mobs already among the
bedrolls, all round the fire;
each man wakes when the noise reaches him (a lizard close by or a blow wakes
him at once; steady men sooner), and some die where they lie. Night battles
are dark: firelight and muzzle flashes show the way.

**Pikemen.** Three of the ship's sailors carry boarding pikes. Pikemen don't
shoot; they kneel in the front rank (the muskets fire over them), meet the
lizards at nine feet and hold them off the musketeers.

**The wagon** comes to every battle on the map, dragged by two porters to
its place in the plan (at the rear, usually). Some lizards would rather
plunder than fight: they make for the wagon, put the cleaver in their belt
and the shield on their back, dig through the stores, then pull out a
ration sack and start eating. Kill a looter and what he grabbed goes back in
the wagon; only the rations already eaten are lost, so the sooner you deal
with them the less it costs. Lose the fight and the survivors carry their
share off. Out in front the wagon is bait: looters stand still for a volley.

**The wagon crew** are ordinary men of the company with the **Wagon** tag
(two at the shafts, any others as guards beside it). A new company gives the
tag to its two greenest musketeers; change it in the battle plan. When
lizards come within nine metres of the wagon, each man reacts by his own
nerve (steadiness, plus a little strength, plus luck): a shaky man **drops
the shafts and runs** for you, a middling one **stands** and shoots or
bayonets the looters from his spot, a steady one (or a man with a pike or
no cartridges left) **goes at them**. Porters can be wounded or killed like
anyone else, and with nobody at the shafts the wagon stops where it is.
Afterwards a man who ran loses some morale and a man who fought gains some;
the camp lists who did what under "At the wagon".

**After a victory** the men cheer, then spread over the field: some kneel by
fallen comrades to bind their wounds, others go through the dead lizards'
things.

### Loot and the wagon's load

**The kit of the dead comes home.** When a man falls in a fight you win, his
comrades carry everything he had (musket, bayonet, hat, coat, cartridges,
rations, water) back to the wagon, ready to arm the next man, a native
recruit in time. The camp lists it under "Their kit, back in the wagon".
If the wagon is full, whatever doesn't fit stays on the field: it heads the
loot screen in gold, marked "(our fallen)", so you can DROP something from
the wagon and take it. TAKE EVERYTHING THAT FITS takes it right after powder
and money, and DONE asks once before you leave any of it behind. A man who
dies of hunger, thirst or sickness in camp leaves his kit in the wagon too,
or, if it's full, by his grave (CAMP, then LOOT THE FIELD) until you march
on. Lose the fight and the dead are left on the field with their
muskets; men drowned or lost on the march, or lost scouting, are gone with
theirs; deserters and mutineers take theirs with them.

After a won fight, **LOOT THE FIELD**: on the left what's there (lizard
cleavers and spears, shields, scaled hides, bone charms, whatever they had
stolen, and the kit of your own fallen), on the right the wagon with its
weight (900 kg) and space (60) bars. TAKE one, ALL, or TAKE EVERYTHING THAT
FITS (the most valuable for its weight first); DROP from the wagon to make
room. Crowns go straight into the purse. A cleaver or a spear can be
issued as a weapon; the rest are goods: **SELL LOOT** in villages (cheap),
towns, cities and dwarf holds. The wagon's full cargo is under **CARGO** in
the Logistics window; buying stops when the wagon is full.

### Music

An original soundtrack composed and synthesised by code (tools/music, built
on the TCG-RPG music engine): 15 pieces on four themes, the Regiment (fife
and drum marches, horns, a soldiers' chorus), the Coast (lute, recorder,
harp airs), the Camp (night pieces) and the Horde (war drums, shawms and
horns in a Phrygian dominant). It follows the game (menu, the wreck, the
map by day, the camp at night, battle) with crossfades, resumes where each
place left off, and drops in battle so the muskets carry. The ♪ button opens
the player: previous, pause, next, random or in order, Auto, music on/off,
volume and the track list.

### Scenes in the pop-ups

Pop-ups on the map show a small live 3D scene of what's happening beside
the text (`scripts/vignette.gd`), on ground matching where you are and lit
for the time of day, with the camera drifting slowly across it: the warband
coming at you, the night camp with lizards among the bedrolls, the camp at
dusk, your scouts running back down the road (or an empty road and a
dropped hat), merchants' carts, a foreign patrol, dwarf traders with their
pony, a burned village, the nest, and every event on the road (the column
wading a ford, a river in flood, wreckage in the surf, a beast with too many
horns, berries, the wagon in the bog, fever mist, a crag with a man on top).

### Settlements: walking in, people, languages

Walking anywhere inside a village, town, city or dwarf hold on the map (not
just its centre) takes you there. **The first visit is on foot**, in first
person; after that you arrive to the **town menu** over a slow camera
drifting above the roofs (market, talk to someone, walk the streets, rest a
day, leave). TOWN MENU and WALK THE STREETS switch between the two.

**The place is built from the map** (`scripts/town.gd`): a village round a
well, a palisaded town with a church and market, a walled city with a keep,
a dwarf hold cut into the rock; Aurest plaster and red tiles, Vellish timber,
Dwarvish stone. A river on the map runs through the streets with a bridge;
a coast gives a shore, jetties and boats; forest crowds the walls; hills
stand behind. The same town every visit. Your men wait at the gate.

**Its people** (`scripts/folk.gd`) are generated too, and remembered: a
name, age, trade (ferrymen where there's a river, fishers on the coast,
charcoal burners by the forest, miners in the holds), two traits, a need,
and a history tied to real places on the map. Walk up and TALK, or pick
them from the menu. A conversation is a run of tries: greet, ask their
name, let them talk, give bread or coin, ask about the lizards or the land,
ask what they need, show the musket, ask them to join.

**You don't speak their language** (`scripts/tongue.gd`). Each people has
its own generated tongue. At first you can only use **signs**, and signs are
misread: a wave taken for a warding sign, bread taken for an insult, the
musket taken for a threat. Their speech is shown as you hear it; words you
know appear in English. You pick up words in context, fluency grows, and
once you know the words for something you can say it, which is far clearer.
The **Tongues** skill speeds it up.

Each try rolls against their traits, their need, your standing in the town
and luck: trust rises or falls, and you may learn a word, a piece of their
story, a rumour that marks a nest or a town on your map, or a task (bring
food for a hungry family, pay a debt, fight the lizards who took a brother).
Now and then something else happens (a child, a dog, a guard, a drink).
Win enough trust, or help with what they need, and they **join you**: a real
recruit with the weapon they brought from home (see below).

### The dwarves of the Greyspine

The dwarves keep their holds in the feet of the mountains to the north and
fight nobody but the lizards. They have their own account of you (the
nations panel shows it), which warms slowly: every 60 crowns you spend at a
hold, every band of their traders you save from the lizards on the road,
every duty done for a thane. Attack their traders and every thane hears of
it; turn them hostile and the great doors of the holds are shut against you.

Each hold has a **thane** in his hall (THE THANE'S HALL in the hold's menu).
He'll hire the company for three weeks against the lizards: destroy the
warbands, or guard the dwarf traders on the roads.

**The forge** is where the best smiths in the land work:

- on your own kit: bore your musket's barrel true (your shots fly
  straighter), temper your bayonet and sword (your blows land harder), and,
  once they count you a friend, fit a dwarf-made lock (it hardly ever
  misfires, even in the rain). The YOU sheet shows what's been done;
- muskets for the company, once they count you a friend: 2, 5 or 10 at a
  time, ready in six days at that hold. The first order costs you a spare
  musket, which they keep to copy (and once they can make muskets...).

Dwarf traders fight beside you when you save them: crossbowmen with their
own heavy crossbows and shieldmen in mail, short, broad and bearded, in round steel helms with a nose guard.

### The kingdoms' armies (medieval) and your horse

Aurest and Vell are centuries behind you: no gunpowder. Their armies
(`world.gd` party_comp, `field.gd` NATION_KINDS) are:

- **Men-at-arms**: mail, nasal helms, arming sword and a heater shield in
  their lord's colours. The shield catches arrows and bolts (and blades)
  from in front, but a musket ball goes through it.
- **Spearmen** in mail, **crossbowmen**, and **longbowmen** who out-range a
  musket (95 m).
- **Knights**: plate, great helms, barded horses, lances couched in the
  charge. Very hard to bring down with a blade (plate halves it), a ball
  less so; their charge hits harder than anything else on the field.
  Braced pikes and squares still stop them.
- **Catapults** (a lord's army has one for every thirty men): lob a stone
  high over the lines; it crushes whoever it lands among (no fire, no
  smoke, a cloud of dust). Slow to wind, wild, deadly to a packed square.

Their men drop their arms when they fall: swords, shields, mail and helms
turn up on the loot pile, and your men can wear them.

**Your horse** (the cavalry officer's troop, and the Tests' field battle):
**dragoons** fire carbines from the saddle at a halt (45 m), skirmishing
until the mark wavers or is caught in a melee, then charge; **lancers**
charge with lances couched, a harder shock than sabres.

### Natives: spears, bows and crossbows

What a recruit brings depends on their trade and people:

- **Hunters, herders, woodcutters** bring a **hunting bow** (the Vellish a
  tall **war bow**) and a hatchet or long knife. Tag: Bows.
- **The town watch** brings a **crossbow**, a padded jack and a kettle hat
  (Vellish guards, war bows). Tag: Crossbows.
- **Dwarves** fight with **dwarf crossbows** and spears, never bows.
- **Everyone else** brings a **spear** and a wool tunic. Tag: Spears.

They're cheaper and weaker than your musketeers, but there are more of them
and their arrows can be bought. In battle:

- **Bows** loose every 2 to 3 seconds out to 36 m (war bows 46 m, harder
  hitting). With a comrade in the way, an archer **arcs his arrow over the
  line** instead of holding fire, so bows can stand behind the muskets.
  Arrows show in flight and stay stuck in the ground. A raised lizard shield
  catches them.
- **Crossbows** take longer to span than a musket (nose down, winding the
  windlass), shoot flat and hit hard, and wait for a clear line like a musket.
- **Spears** fight like the pikes: in front, long reach.
- Up close, archers and crossbowmen fight with the knife or hatchet.
- After a win, about half the arrows and bolts can be picked up again (they
  go on the loot pile).

Each man's pouch holds what his weapon shoots: cartridges, arrows or bolts.
SHARE EVENLY gives each kind to the men who use it. Change a man's weapon on
the Company screen and his old ammunition goes back to the wagon.

### Powder and lead

Nobody in this land sells cartridges. You **make them**: 1 lb of powder and
3 lb of lead make 40 (MAKE CARTRIDGES in the wagon's logistics, and in a
town's menu). **Lead** is sold in towns, cities and holds. **Powder** is sold
only by the **dwarves**, who blast their mines with it, and it's dear.
You start with a pound of powder and a little lead saved from the wreck.

### Living off the land: resources and CRAFT

The land has places that give what the company needs (`world_gen.gd`
places about a hundred, `world.gd` RESOURCES): **saltpetre caves** and
**sulphur springs** in the hills, **woodland** to burn for charcoal,
**lead outcrops**, **hunting grounds** and **fishing water**, and **fresh
springs**. Each has a small model on the map and its name once you're
close. Tap one to march there and choose how many **hands** to put to it
(labourers first, then fit soldiers): CONFIRM (at the top or the bottom of the panel) sets them to work for some hours and fills
the wagon; then it's worked out for days (a spring just fills the water
cart with clean water).

**Tools.** Each site wants its tool: a **felling axe** for woodland, a
**pickaxe** for lead, sulphur and saltpetre (or a **shovel** for the
saltpetre earth and sulphur crust), a **fishing rod** for fishing water.
Nobody can do the work without the right tool: as many work as there are
tools (a hunting ground needs none, the men take their muskets). The wagon
starts with a few, saved from the ship: 2 axes, 2 pickaxes, 3 shovels and
2 fishing rods. Every tool in use has a 3% chance a day of breaking; a broken tool is kept
in the wagon to be mended (CRAFT), and you can forge new ones at a camp
forge from ore and charcoal. Markets sell
them (villages and towns: all four; dwarf holds: picks and shovels), and
CRAFT makes a fishing rod from 3 lb of hardwood.

**Work parties.** POST A WORK PARTY posts the hands you chose at the site,
with the wagon's tools for the work: they leave the roll and work it every
day (a tent and your flag mark the spot, with how many are there). Come
back to COLLECT what they've made, or RECALL THEM. Hunters and fishers
smoke what they bring in, so their stock is rations. They feed themselves,
but they're still paid, and now and then lizards come for them: a hunting
party is seen making for the site, and you can catch it on the way. If it
gets there, two or more soldiers drive it off, but a party of labourers
alone loses a third of its people and half its stock. Leave some men at the lead and
some at the fishing, and march on with the rest.

**Choosing who.** The site's panel lists everyone who can work, best at
this site first (★: strength and stamina, more for a labourer at his own
trade): slide the bar (like a volume bar) to choose how many, and the best
are ticked as it moves; or tap someone to send him, tap again to take him
off. There's a place
for each tool (a dozen at a hunting ground). THE BEST fills the places with
the best, NOBODY clears them, LABOURERS ONLY keeps the soldiers back. The same goes for scouts and runners: the list is
always ranked by the skill that matters.

**Calling them back costs a man.** Either march back to the site and RECALL
THEM (or tap a single person to bring just him), or, on the COMPANY screen,
SEND A RUNNER: pick one (the quickest first); he goes to them, and the
whole party marches back to wherever you are. On the road they can be
caught by lizards.

**Labourers.** HIRE LABOURERS in a village or town (12 crowns, then a
crown a week; a few each week). They have the soldiers' attributes and
their own morale: they eat a ration and drink a day's water (foul water
can make them sick, and a sick man works at half pace), are glad of their
pay and angry without it, and hungry, thirsty or sullen they go home. On
the COMPANY screen tap one to see him, or let him go. When lizards get
into the camp at night some may be killed or run off. Trades: **woodcutters, miners, hunters, fishers**
(by what's round the place) and **farmhands**. They don't fight and never
go into battle; they follow the wagon, eat a ration a day (unfed, they go
home), and work half again as hard at their own trade's sites. Beating a
lizard warband often frees **captives** roped together in its train (a
burned nest always has some); most of them stay with you as labourers.

**CRAFT** (on the map, and at any site) turns materials into what you need,
the hours passing while the men work (Logistics shortens them):

| Recipe | Takes | Makes |
|---|---|---|
| Grind black powder | 8 saltpetre, 2 charcoal, 1 sulphur | 10 lb powder |
| Smelt lead | 6 lead ore, 3 charcoal | 4 lb lead |
| Roll cartridges | 1 lb powder, 3 lb lead | 40 cartridges |
| Smoke meat | 6 meat, 1 charcoal | 6 rations |
| Make a fishing rod | 3 hardwood | a fishing rod |
| Forge an axe / a pickaxe / a shovel | ore, charcoal, hardwood | the tool |
| Mend an axe, pickaxe, shovel or rod | the broken tool, hardwood (charcoal for the pick) | the tool |

Fresh meat and fish lose a third a day until smoked.

**No lead?** Woodland also gives hardwood: *Carve wooden balls* (1 lb
powder, 4 hardwood → 40 cartridges). They're mixed in with the rest; each
of your side's shots has the wooden share's chance of being one, which
flies slower and hits for half.

**Hunt or fish yourself** (optional; CONFIRM still sends the men): at
a hunting ground or fishing water, or from the "Game in the trees" event on
the road (HUNT YOURSELF), HUNT/FISH YOURSELF takes you into the
woods with your musket, or to a river with a rod (you need one in the
wagon). Deer graze in small herds and bolt when you come close (closer
still on a horse) or a shot rings out. Fishing: hold CAST to wind the rod
back (the longer, the further) and let go; the float lands on the water
and fish nose up to it. It twitches while one nibbles; when it goes under,
STRIKE at once. Hooked, hold REEL to bring it in and let go when it runs:
reeling against a run pulls the line past the red, and it snaps (the rod
may break with it). Tire it and bring it to the bank. A deer is 30-45 lb
of meat, a fish 3-6. END THE HUNT puts it in the wagon
(four hours pass). With these a company
can keep itself in powder, shot, food and water without a market.

### The land's economy

Every village has its own sites near it (fields, and a wood, a pit, a
fishing water or a hunting ground by what's round it), dwarf holds their
mines, towns a field or a wood (`world_gen.gd`), and wild sites belong to
the nearest village. Each settlement keeps stores (`economy.gd`):

- **Labourers** walk out from the village to one of its sites, work it a
  day and carry what they got home (you'll see them on the map: "Aurest
  labourers, with ore and charcoal").
- **Villagers** take a village's surplus to market in the nearest towns.
- Towns, cities and holds **refine** it: lead from ore and charcoal, powder
  from saltpetre, sulphur and charcoal (cities and holds), tools at the
  smithy, bread and smoked meat, arrows. **Caravans** carry what a town has
  spare to the next, and dwarf **traders** bring the holds' powder, lead
  and tools. Everyone eats, tools wear out, gluts rot.
- **The lizards** have their own: hunting parties bring meat and hides home
  to the nest, warbands carry off half of a raided village's stores. A nest
  with meat in it sends out bigger warbands. Beat a party and what it
  carried is on the loot pile; burn a nest and its hoard is yours. Lizards
  who beat a caravan or labourers take their goods home.

- **Wars eat it too.** The nations' armies and patrols eat from their home
  city's stores (an army that can't be fed loses men); a besieged town
  eats its stores with nothing coming in, and falls sooner once the food is
  gone; a town that falls is sacked of a third of what it had.
- **On the road** you can TRADE with caravans, dwarf traders, villagers and
  labourers: buy from what they're carrying (a little dearer than a market)
  and sell them your raw goods. Your Trade skill raises what anyone pays
  you.
- **Lizards falling on people near you** (labourers, villagers, a caravan,
  your own work party): you're asked whether to go to their aid. A
  caravan's guards fight beside you; their nation remembers it. A lord may
  hire you for exactly that (the duty: protect his people on the roads).
- A nest's larder shows when you look at it: well fed (big warbands), a few
  carcasses, or bare racks (hungry, smaller warbands). Kill its hunting
  parties to starve it.

A settlement's **market** follows its stores: what it has plenty of is
cheap, what's scarce is dear, and what it hasn't got isn't for sale. Raw
goods it has spare are for sale by the 10 lb, and it buys the raw goods it
is short of (THEY'LL BUY). Your site's panel shows whose it is and their
stores; the market shows them too.

### Markets

A town's MARKET sells food and rum, arrows (villages and towns), bolts and
lead (towns and holds), bows, spears, crossbows, padded jacks and kettle
hats (towns), war bows (Vellish towns), and powder and dwarf crossbows (dwarf
holds). Your Trade skill lowers every price.

### Lizard nests: sieges and assaults

Walk up to any lizard nest on the map and you get its measure: a guess at
the garrison, how sound the stakes are, and the choices **PLAN**,
**ASSAULT**, **BESIEGE A DAY** and **LEAVE**.

- **Besieging** costs a day each time. Shut in, the garrison loses lizards
  to hunger and desertion, and the stakes rot and are pulled down (more
  breaches when you storm it). They may **sally at night**: a camp battle in
  the dark. A besieged nest sends out no warbands. Walk away and it regrows.
- **The assault** is a field battle. The nest stands in the far half of
  the field, in a levelled clearing: a ring of leaning stakes on a mud bank
  with one log gate facing you. You deploy your regiments first. Nobody
  walks through the stakes; everyone goes round by the gate (once it's
  down) or a breach. Order an attack on the garrison and the regiment
  marches to the gate (or the nearest gap) and goes in.
  - **The gate** has hit points (shown on the status strip). Round shot
    smashes it, grenades blow chunks out of it, and men within reach hack at
    it (you count double). Musket balls barely mark it.
  - **The garrison** splits: javelin throwers on platforms behind the
    stakes (you can shoot them), mobs holding inside (you can't: the stakes
    cover them; a grenade lobbed over still works) until the gate falls or
    your men reach a gap, and sallies that burst out of the gate in waves (the next
    one comes when the last is spent or the gate starts to give).
  - **Your guns** (if you have them) are a battery like any other: they
    fire canister and round shot at what comes out, and batter the gate
    whenever there's nothing outside the stakes to shoot.
  - Win when every lizard is dead and no sally is left to come. The nest
    burns and sends out no more warbands; you get pay and plunder.
- **The stash nest** holds the ship's stores. Storm it and you recover
  muskets, cartridges, rum and **the two guns**, which march with you from then
  on and fight in every battle.

### Your character sheet (YOU)

Opened with **YOU** on the map, in camp and on the Company screen.

- **You:** a live 3D figure in your own kit, your name (tap to rename), rank,
  level, experience and record.
- **Attributes** (1-10): Aim (a steadier shot), Strength (harder blows),
  Constitution (+8 hit points a point over 5), Fitness (+3% speed), Wits (an
  extra skill point every level at 7+) and Presence. Each also caps the
  skills it governs.
- **Skills** (0-10), each feeding a real mechanic:
  Marksmanship (your spread and reload), Bladework (your blade damage and
  parry arc), Leadership (your men's steadiness; fewer desertions and
  mutinies), Tactics (orders ripple down the line faster; the night watch
  sees attacks sooner; slipping away is likelier), Surgery (faster healing;
  after a victory some "dead" men pull through), Logistics (the wagon carries
  more), Pathfinding (faster march, further sight, fewer scouts lost), Trade
  (cheaper food and rum, better prices for loot) and Training (your men gain
  more experience). Each card shows what it does for you now.
- **Your kit:** head, coat, firearm and blade, changed from the wagon like
  your men's (a rifle shoots tighter but loads slower; a buff coat turns
  hacks but slows you), and your **cartridge box**: your own shots in battle
  now come from it, shown as "Your shot" in the battle status line.
- **In battle:** the numbers it all adds up to (hit points, speed, reload,
  spread, misfires, blade, parry) and what you give your men.
- **Levels:** experience from every battle, your kills and victories; each
  level gives 1 attribute point and 2 skill points (3 with Wits 7+).

### Loading screen

Going to the map, into a battle or into the shipwreck covers the screen with
a title, a bar, what's being done ("Raising hills and mountains...",
"Mustering the company...") and a tip. The heavy scenes build in stages
and move the bar after each one, weighted by how long that stage takes, so
it fills at the pace of the wait; a new land is generated phase by phase.
The battle sounds are synthesised once per run and kept. Run with
`-- --loadtimes` to print how long each stage took.

### Graphics (GRAPHICS on the main menu)

Everything is still built in code, with no art files, but it no longer looks
like flat blocks:

- **Sky**: a shader sky with drifting clouds, a sun disc and haze at the
  horizon; stars at night, an orange sky at dusk.
- **Ground**: a shader that mixes two greens and bare earth by noise at
  two scales, so the land has patches and worn spots, coloured by the map's
  terrain (forest, hills, swamp, beach, mountain).
- **Grass**: thousands of grass tufts that sway in the wind and fade out with
  distance, drawn as one batch. In towns they keep off streets, houses,
  water and the beach, and are thinner inside the walls.
- **Trees**: pines in three tiers, broadleaf trees with clusters of round
  crowns, dead trees, bushes and rocks, each a slightly different colour, all
  gently swaying, a few draw calls for a whole forest. Low hills stand all
  round on the horizon.
- **People**: rounded body parts instead of sharp boxes, and a soft rim of
  light on the edges, so soldiers and lizardmen read as figures. Each one
  has a soft shadow under the feet.
- **Towns**: plaster, timber and stone have a grain.
- The **scenes in the pop-ups** use the same sky, ground, grass and trees.

GRAPHICS cycles **LOW / MEDIUM / HIGH** (saved):

| | Grass tufts | Grass reach | Shadows | Glow |
|---|---|---|---|---|
| Low | 3,000 | 28 m | soft blobs | off |
| Medium (default) | 9,000 | 50 m | soft blobs | off |
| High | 15,000 | 70 m | real sun shadows | on |

Hordes don't get dearer: all the bodies in a battle are still drawn in a
handful of batches, whatever the setting. Real sun shadows (HIGH) can't be
checked on this computer, so try them on the phone and drop back to MEDIUM
if they flicker or slow it down. Testing: `-- --gfxq=low|medium|high`
overrides the setting for a run.

### The look of the screens

The menus wear the regiment's coat: blue wool panels edged with a thin
pipeclay line, brass for headings and the main action on each screen,
madder red for what's pressed or wrong. Titles and headings are set in
**IM Fell** (old printers' type, like the headings in an order book; it has
true small capitals); everything else in **Alegreya Sans**, which stays
readable small on a phone. Both are free fonts in `fonts/` (the only files in
the game not made in code). `scripts/ui.gd` builds the theme once and
Settings applies it to every screen; a big label becomes a heading on its own.

The **main menu** opens on the company's camp at night, live: the fire, the
wagon, the colours, a sentry, men asleep on their blankets, the camera
drifting slowly. Continue (brass), New campaign and Load sit on the left,
Skirmish and Stress test under them, and View and Graphics along the foot.

In battle the HUD's buttons are rounded and translucent, brass when an
order is in force, madder when you press them; your health and the status
line sit on a strip of night at the top left.

### The Company screen (COMPANY & KIT)

- **Left:** the man himself, a live 3D figure wearing his actual kit (drag to
  turn him). Under it: name, rank, level, his four attributes (with **+**
  buttons while he has points), morale, health, HP, and anything wrong with
  him (wounded, sick, hungry, thirsty).
- **Middle:** his kit on a body diagram: **Head** (shako, tricorne, forage
  cap), **Torso** (regulation coat, linen shirt, buff coat), **Primary
  weapon** (land musket, worn musket, rifle), **Secondary weapon** (socket or
  sword bayonet; without one he clubs with the butt). Tap a slot to swap in
  something from the wagon. His **Pack**: water (up to 2 days), rations (up
  to 8 days), cartridges (up to 40 shots) with − / + / FILL. In battle a
  man can fire only the cartridges he carries.
- **Right:** every man, with his status, morale, shot and food at a glance.
  Below: **the wagon**. Tap it (or LOGISTICS, or WAGON in camp) for the
  **Logistics** window: water, rations, cartridges and rum in the wagon and
  in the packs, what a day costs, how many days it lasts, SHARE EVENLY for
  each, the sutler, the grog switch, whether the water is foul, how fair the
  rations are, and the company's morale.

Kit shows on the 3D models in battle too: hats, coats, the rifle's brass
patchbox, the longer sword bayonet, and a canteen, haversack and cartridge
box only when he actually carries water, food and shot.

## The battle

A flat field, you in the centre of your line, and a lizard warband charging
from the distance, sometimes in two groups.

### Touch controls

| Control | What it does |
|---|---|
| Left side of screen | Floating joystick: put your thumb down anywhere and drag to walk |
| Right side of screen | Drag to look around |
| **FIRE** | Fire your musket. Keep your thumb down and drag to aim, like CoD Mobile. The gold ring is your reload. |
| **AIM** | Raise the musket and sight down the barrel: the view zooms in, shots are far more accurate, but you move and turn slower. Stays on between shots: the musket comes back up after each reload. |
| **BAYONET / MUSKET** | Fix or unfix the bayonet (about a second, fully animated). You can't reload with the bayonet out. |
| **OVER / LEFT / RIGHT / THRUST** (melee) | Four swing buttons replace FIRE, see below |
| **BLOCK** (melee) | Hold to parry. Stops hacks from the front and makes the lizardman reel back |
| **GRENADE** | Throw a hand grenade (3 per battle). It arcs, bounces, fizzes for about 2.5 s and bursts: deadly within 2 m, wounding out to 5 m, and it knocks men down. Mind your own line. |
| **VOLLEY!** | Every loaded man in the company fires at once |
| **FOLLOW** | The line moves with you and wheels when you turn more than 40° |
| **HOLD** | The line forms where you are, facing where you look, and stays put |
| **CHARGE** | Break ranks: every man picks his own fight, fires if he has a shot, and falls back to you when badly wounded. With no enemies left they regroup on you. |
| **ON COMMAND / AT WILL** | Toggle whether your men wait for your volley order or fire on their own |
| **MENU** | Back to the main menu (in a campaign, the battle isn't counted) |
| **1ST / 3RD PERSON** | Switch camera: your arms and musket, or the whole officer over the shoulder |

### Melee: Mount & Blade swings on a touchscreen

In melee mode, FIRE turns into four buttons in a diamond. The button you press
is where the blow comes from: press to wind up, hold to charge, release to
strike. Dragging from the button keeps turning you, so you can track a target
while you wind up.

| Button | Blow | Good for |
|---|---|---|
| OVER | **Overhead** chop | Heaviest hit, one target |
| LEFT / RIGHT | **Sweep** from that side | Wide arc, can hit two at once |
| THRUST | **Thrust** with the bayonet | Longest reach, one target |

Hold longer before releasing to charge the blow (the ring around the button
fills, white when full; a full charge kills a lizardman outright). A gold marker by the
crosshair shows which side the blow will come from. Every hit knocks the
lizardman back and cancels his attack.

Lizardmen telegraph their hacks: they **rear up, cleaver high, and glow
orange** for half a second. Hit them first, step back, or hold BLOCK.

They also carry **shields**. Wind up a blow close in front of one and he may
bring his shield up (you'll see it, and "SHIELD!" if you hit it); while it's
up he blocks frontal blows and won't attack. A blow charged to 70% or more
smashes through the guard and sends him reeling. Shields don't stop musket
balls.

Keyboard for testing on a PC: WASD move, mouse-drag on the right half to look,
Space fire (in melee: hold to wind up, release to strike), arrow keys pick the
blow, right mouse button or Z aim, Q fix/unfix bayonet, G grenade, E block, V switch view, F volley, 1 follow,
2 hold, 3 toggle fire mode, 4 charge.

### Your weapons: musket, bayonet, pistol, sabre

A row of small buttons along the very bottom of the battle screen switches
weapons: **MUSKET**, **BAYONET** (fixed on the musket), and, as an officer,
your **PISTOL** and **SABRE** (both on your character sheet's kit; take one
off and its button goes). Drawing the pistol from your sash or the sabre
from its scabbard slings the musket across your back; the button of the
weapon in hand is gold, and an unloaded gun's button fills as it reloads.

- **The musket reload** is a full drill: bite the cartridge, prime the pan
  and shut it, stand the musket up and pour, ram three times, return the
  rod, bring it up and cock the hammer. About 5.5 seconds for you (your
  Marksmanship and a rifle change that), two seconds longer for your men
  than before. In exchange **a ball goes through**: it can pass through two
  bodies and hit a third, losing speed and punch each time, so a volley
  into a packed rank does real damage (and a careless one hits the men
  behind your target too).
- **The pistol:** one quick shot, wild beyond close range, through one body
  at most; it only reloads while in your hand, from the same cartridge box.
  AIM takes the duellist's stance of the period: turned side-on, right arm
  straight out, left hand in the small of the back, the front sight on your
  crosshair.
- **The sabre:** a truly curved blade (and scabbard), the same four
  directional cuts and block as the bayonet, recovering faster, a little
  shorter, and made for cutting: the thrust is weaker. Each cut is a full
  movement: the arm raised high and back with the body twisted away, then
  swept through and down past the other side as the body unwinds; the free
  hand rests on the hip and swings out for balance. Damage follows your
  Strength and Bladework.

### Where a shot strikes

Every ball, arrow, bolt and javelin hits a part of the body, worked out from
where it entered: the **head** (top of the body) and the **chest** kill (a
ball there is more than any man or lizard can take), an **arm** (out to the
sides at chest height) or a **leg** (below the waist) mostly wounds. A man
hit in the leg limps at half speed; hit in the arm, he loads slower, shoots
wider and strikes slower (a lizard hacks slower). Riders: above the saddle
is the man, below it the horse. You take the same, gentler: head shots hurt
you most. Round shot takes whatever it hits.

### Real projectiles

Every musket ball is a real projectile: it leaves the muzzle at about 330 m/s,
drops under gravity, slows with air drag, and hits the first body in its
path, **friend or foe**. A faint streak shows where each shot went. Shoot
through your own line and you will hit your own men (the HUD tells you); a
careless volley from behind you can hit you too. Your men hold their fire
when a comrade is anywhere near the line of fire, a corridor that widens
with the range like a smoothbore's scatter (only now and then does a jumpy
man let fly anyway), and never fire with **you** in the way; the guns hold
too. The rear rank stands in the gaps of the front rank and fires through
them. So a friend is hit mostly in a melee, where a miss flies on into the
scrum. Aimed shots are tight, hip shots scatter.

**Powder smoke** hangs: each shot leaves a slow, low cloud a pace or two in
front of the muzzle that spreads, drifts with the battle's breeze and takes
ten seconds or more to thin, so a volley lays a bank along the front that
hides what's coming for a while. (Shots into an old cloud thicken it rather
than piling up more.) Lizard shields don't stop balls, but they will
stop thrown javelins once the skirmishers arrive.

All of it lives in `projectiles.gd`: a new weapon is one row in its `KINDS`
table. Arrows and bolts are there now: drawn as shafts with pale
fletching, arcing (an archer works out the angle, and a high arc to clear
the line), stuck in the ground for a while after they land.

### Your men are not robots

They obey, but each at his own pace. Every soldier has his own reaction time,
walking pace, steadiness and reload speed. He sees where the line is a moment
late, so when you wheel or halt the company the movement ripples through it.
Volleys come out as a ragged ripple as each man presents and takes aim. Shaky
men fire sooner when firing at will, steady men wait and hit more. Muskets
occasionally misfire (a flash in the pan) and must be re-primed. Standing men
glance along the line, and nobody walks or rams in step.

In close combat they fight to survive: when a lizardman rears up at a man he
raises his musket to parry and steps back (steadier men parry more often), he
keeps a bayonet's length of distance, and he thrusts when the enemy is open,
straight after a parry or while it reels. In FOLLOW and HOLD they give ground
only a couple of metres before standing; under CHARGE they press the attack.

### Animations

- **You:** reload (prime the pan, draw the ramrod, three strokes, return it),
  fix bayonet (draw it from the hip, raise it over the muzzle, slide it on and
  lock), unfix, four swing directions, block, recoil. Arms are solved with
  inverse kinematics so both hands stay on the musket throughout.
- **Soldiers:** idle, march, present (aim), fire, reload (ramming), bayonet
  guard and thrust.
- **Lizardmen:** idle, charge, wind-up, strike, stagger.

### Sounds

Musket shots (yours close, the company's positional, so a volley ripples down
the line), ramrod clinks, bayonet scrape-and-click, stabs, parries, swishes,
lizard roars, hisses and death cries, men's grunts, grenade blasts and
thuds. All synthesised in
`sound_factory.gd`; swap any of them for a recorded .wav by loading it into
the same dictionary key.

## How it's built

Everything is created in code; the scenes are just a menu, a battle and an
aftermath node.

- **Bodies are low-poly 3D** built from primitives; far away they swap to
  pixel-art sprites as cheap stand-ins. Trees are drawn with MultiMesh.
- **Units drive their look indirectly.** AI code only sets a facing and an
  animation name (`walk`, `aim`, `reload`...); the rig turns it into a pose,
  or the stand-in sprite picks the frame for the right view.
- **The campaign lives in an autoload** (`company.gd`): the battle reads the
  fit men from it and reports casualties, kills and the result back.
- **3D rig (`rig3d.gd`):** the musket (or cleaver hand) is posed in body space
  and eased toward the target pose every frame; arms reach it with two-bone
  IK; legs run a walk cycle from movement speed.
- **Squad brain, dumb bodies.** `battle.gd` owns the line (an anchor point and
  a facing) and hands each soldier a slot. Soldiers walk to their slot, load,
  fire, and use the bayonet up close. Lizardmen charge the nearest man.
- **No physics engine.** Units steer directly on the flat field with a
  simple push-apart rule. Projectiles are light records stepped every
  physics tick; each step sweeps the segment it travelled against the upright
  cylinders of nearby bodies (found through the spatial grid), so hundreds
  of balls in flight stay cheap.

| File | Purpose |
|---|---|
| `scripts/menu.gd` | Main menu: continue, new campaign, stress test |
| `scripts/lore.gd` | Placeholder names: nation, regiment, ship, land, beach, commander, the lost stash |
| `scripts/intro.gd` | The shipwreck cutscene |
| `scripts/world_gen.gd` | Generates the land from a seed: height, terrain, rivers, lakes, fords, bridges, roads, settlements |
| `scripts/world.gd` | `World` autoload: the map's clock, your march, sight and fog, every roaming party, encounters, saving |
| `scripts/events.gd` | Events on the road: where they can happen, their choices and outcomes |
| `scripts/battleplan.gd` | The battle plan: tactical map, tags, lines, presets, the wagon's place |
| `scripts/loot.gd` | The loot screen: the field's pickings against the wagon's weight and space |
| `scripts/music.gd` | `Music` autoload: playlists per place, crossfades, resume, its own bus |
| `scripts/music_bar.gd` | The ♪ music player |
| `scripts/ui.gd` | Touch helpers: lists you can swipe anywhere |
| `tools/music/` | The composer and synthesiser that make `music/*.ogg` (`python3 tools/music/musket_music.py`) |
| `scripts/map.gd` | The 3D map: terrain chunks, fog shader, trees, settlements, parties, camera, taps, HUD, visits |
| `scripts/props.gd` | Scenery from primitives: ship, longboats, cannon, earthworks, rocks, the sea |
| `scripts/settings.gd` | `Settings` autoload: camera mode, stress test |
| `scripts/company.gd` | `Company` autoload: the men, kit, the wagon, the march, money, results, saving |
| `scripts/men.gd` | A soldier's attributes, levels, morale, health and conditions, and what they do in battle |
| `scripts/aftermath.gd` | Between battles: results, the company, hiring, marching on |
| `scripts/officer.gd` | You: attributes, skills, levels and the effects they feed |
| `scripts/officer_sheet.gd` | Your character sheet screen (YOU) |
| `scripts/company_screen.gd` | The Company screen: portrait, kit, pack, attributes, the men |
| `scripts/logistics_popup.gd` | The wagon: stocks, days left, sharing out, sutler, grog |
| `scripts/battle.gd` | The battle: world, the company's line and orders, the beach's scenery, dialogue and hints, smoke, sound (the old company battle only with `-- --oldbattle`) |
| `scripts/nest_assault.gd` | A lizard nest: the palisade, the gate and its hit points, the garrison, the sallies, the ways in (in a field battle its garrison and sallies are regiments, and its ring is in the paths) |
| `scripts/field_prologue.gd` | Wreck Beach as a field battle: the Major's battle, his fall, your command (with the lesson), the collapse and the retreat |
| `scripts/projectiles.gd` | Musket balls, grenades and future arrows/javelins: flight, hits, tracers |
| `scripts/player.gd` | Movement, looking, camera, musket, melee and blocking |
| `scripts/player_body.gd` | Poses your own officer's body from your actions |
| `scripts/unit.gd` | Shared base for soldiers and lizardmen: visual, animation state, damage, death |
| `scripts/soldier.gd` | A musketeer: hold slot, load, fire, bayonet |
| `scripts/lizardman.gd` | A lizardman: charge, telegraphed hack, stagger |
| `scripts/rig3d.gd` | 3D bodies (soldier, officer, lizardman) and their animation |
| `scripts/batcher.gd` | Draws every unit in a few instanced batches (3D parts, sprite atlases) |
| `scripts/hud.gd` | Multi-touch controls, swing buttons, status and messages |
| `scripts/sprite_factory.gd` | Generates the pixel-art frames used as far stand-ins |
| `scripts/sound_factory.gd` | Synthesises the sound effects |
| `scripts/look.gd` | The look of the land: sky, ground, grass, trees, bushes, far hills, quality levels |

### Gun crews

Every field gun (the four on Wreck Beach, the one on the weapon range) is
worked by a crew of four, the way a Napoleonic piece was served
(`gun_crew.gd`):

- the **sponger-rammer**, right of the muzzle, swabs the bore after each
  shot, then rams the new charge home with the rammer;
- the **loader**, on the left, runs back to the ammunition box, brings a
  cartridge (powder bag and shot) and puts it in the muzzle;
- the **gunner** kneels at the trail and lays the gun, shifting the trail
  with a handspike until it bears;
- the **firer** holds the linstock clear, and touches the match to the vent
  once the gun is loaded and laid.

The gun fires only when the drill is done and it's laid on the target, so
the battery's shots come raggedly, gun by gun. Lizards that reach a gun cut
the crew down and it falls silent.

Each gun has an **ammunition box** behind it on the left (30 round shot and
10 canister; a light gun 20 and 8). The crew draws every round from it, and
when it's empty the gun is done. When a crew is cut down they drop the
rammer and the linstock, and you can **work the gun alone**: pick them up,
then at the muzzle a gold button walks you through it (SPONGE OUT THE BORE,
TAKE A ROUND at the box, LOAD THE ROUND, RAM IT HOME), and at the trail MAN
THE GUN, lay it and FIRE with the linstock. Leaving a gun is never final:
walk back to its trail and MAN THE GUN shows again.

### Picking things up

Whatever a fallen man or lizard carried lies on the ground where he fell
(`pickups.gd`): his weapon, what's left of his cartridges, arrows or bolts,
a skirmisher's javelins, a crew's gun tools. Walk over it and press PICK UP:
cartridges fill your box, arrows and bolts go to the stores, javelins are
thrown with JAVELIN, a bow, crossbow, sword or pistol joins your kit, and
anything else goes on the wagon after the fight.

### Tests (on the main menu)

**Tests** opens a list of fights outside the campaign:

- **Field battle**: Total War with you on foot in it (see below).
- **Weapon range**: you alone with every weapon (musket, bayonet, pistol,
  sabre, **bow**, **crossbow**, and 99 grenades), and you can't die. Down the
  left: +1 TARGET and +5 TARGETS (lizards that stand still at 12 to 40 m),
  +5 and +20 CHARGING, and CLEAR. The bow: AIM draws it to your cheek (the
  bow arm out, canted clear of your sight), FIRE looses, and you nock the
  next arrow from the quiver over your shoulder in under two seconds. The
  crossbow: sight along the stock, then nose down and wind the windlass for
  seven seconds.
- A **field gun** stands a few paces to your right, worked by its crew; the
  gunner lays it wherever you look, and **FIRE GUN** (it shows LOADING
  while the crew works) fires it at the lizard nearest your line of sight,
  or the ground you're looking at. Canister close in, round shot further out.
- **Skirmish**: the mixed company against three waves.
- **Nest assault**: twenty men and two guns against a fortified nest of 50.
- **Stress test**: 50 against 200, with a frame counter.

### Field battle: Total War on a phone (Tests)

A setup screen first: the **battlefield** (open field, hills, river crossing,
a town of streets and a square, woods), **men in a regiment** (12, 20 or 30), **your army** (how
many regiments of musketeers, pikemen, bowmen, crossbowmen, cavalry and
cannon, on top of your own company of musketeers, which you lead) and **the
enemy**: a lizard warband (warriors, javelin throwers, brutes, raptor
riders) or a rival army in red coats with the same kinds as yours. The count
at the bottom warns when it gets big for a phone.

**Square.** Foot (muskets, pikes, bows, crossbows; 8 men or more) can form
**SQUARE** (in the command view's orders, or the army bar on foot): a hollow
box with every face outward. Horse can't break it: riders that gallop into
it rear and are hurt. It shoots all round and can't be taken in the flank
or rear; but it can't march (any move order opens it out again), and it's a
fat target for shot. When horse charge one of your regiments the alert says
"Form square!"; the computer's generals form square when horse bear down on
their foot, and their horse won't ride at a square.

**Deployment.** The battle opens paused in the command view. Tap a regiment
(or its card), then **tap** the ground to stand it there in a **column of
twos**, or **drag** along the ground to lay out its **line** there: as long
as your drag, facing away from you (select several and they share the line
out). BEGIN THE BATTLE when you're ready.

**Pace** (on the setup screen): Brisk, Steady (the default) or Slow. Marching,
loading and blows all scale with it, so there's time to fight on foot and
to command.

**On foot** (first or third person) you command too:

- **Your army** across the top right: a card for every regiment (kind, men
  left, a bar coloured by its nerve, WAVERING, ⚔ when fighting). Tap cards to
  select them (several at once), tap again to let go; ✕ lets go of all.
- With nothing selected, the row under the cards is your own company's
  orders (FOLLOW, HOLD, CHARGE, AT WILL). With regiments selected, it's
  theirs (HALT, CHARGE, FIRE, VOLLEY, RUN, FALL BACK), and a **quick tap in
  the world** sends them: on an enemy regiment, at it; on the ground, there.
  You turn to it, point (musket across your chest in your left hand and your
  right arm out; with the pistol the left hand points; with the sabre, the
  blade) and shout the order.
- The **minimap** on the left shows the ground and every regiment; tap it to
  open the command view over that spot.
- The **SPYGLASS** in the weapon row: the view closes in to a brass circle,
  and you can tap distant regiments through it to send your men at them.

**COMMAND** (top left) lifts you into the command view:

- **Time**: PAUSE, SLOW (a quarter speed) or PLAY.
- **Your regiments**: a card each along the bottom (what they are, men
  left, nerve, WAVERING / ROUTING / FIGHTING). Tap cards or regiments on the
  field to add them to the selection (tap again to drop one); ALL takes every
  one, NONE lets go. Each block is drawn on the ground in its side's colour,
  with a banner; a selected shooter shows its reach as a fan on the ground
  (its range and the arc it can fire into). The selection is the same in
  the command view and on foot.
- **Orders**: tap the ground to march there (in column for a long march,
  forming line at the end; round houses and through the bridge or the ford);
  drag along the ground (6 m or more) to form a line there as long as the
  drag, facing away from you, or a short drag to march and face the way you
  dragged; tap an enemy regiment (its
  block, its banner or its men) to attack it: they keep after it, shooters
  closing to their range and firing, blades and horse closing to charge.
  Buttons: HALT, CHARGE, FIRE: AT WILL / HOLDING (everyone starts at will),
  VOLLEY, RUN (double time), FALL BACK, and FOLLOW ME for your own company.
- **Camera**: drag with one finger (nothing selected), two fingers to pan,
  pinch to zoom, twist to turn; or the + − ⟲ ⟳ buttons.
- **Alerts** at the top left: a regiment wavering, breaking, hit from
  behind, or enemy horse charging one of yours. With **AUTO-PAUSE** on (off
  unless you turn it on), the important ones open the command view, paused,
  at most once every half minute.
- **TO YOUR MEN** goes back down to first person. If you fall, you keep
  commanding from above.

How it fights:

- **Regiments** (regiment.gd) own the plan; their men own their feet and
  blades. A man keeps his slot in the block, shoots at a man of the regiment
  his officers point at (so fire spreads along their line), and up close
  parries, thrusts and gives ground like any of your company.
- **Muskets** fire at 60 m, **bows** at 78 m (lofting over their own line),
  **crossbows** at 66 m; shots stop in hills and walls, and a regiment that
  can't see its target moves closer.
- **Pikes** stand braced when they're not moving: horse charging their front
  is stopped on the points, and every pike thrust hurts a horse.
- **Cavalry** walks in formation, trots to close and charges at a gallop:
  a fast charge rides men down, knocks them flying and shakes their
  regiment; then the riders lose their speed and cut, and if the melee
  drags on they pull out, wheel and charge again.
- **Cannon**: a battery of two guns with crews, round shot to 240 m, canister
  close in; hits thin the crew and slow the loading; overrun, it falls silent.
- **Lizards**: warriors come on in a mob, javelin throwers stand off at 30 m,
  brutes (half again as big, three times as tough) knock men flat, raptor
  riders go round the flanks for your guns and shooters.
- **Morale** decides it: losses, a melee it's losing, a charge into its
  flank or rear, horse crashing in, a neighbour breaking. Near you, your
  regiments steady. Under 40% a regiment wavers (slower, shoots worse);
  broken, it runs for its own edge of the field, and rallies if nobody chases
  it; a regiment cut to a quarter never comes back. The battle is won when
  every enemy regiment is running or gone.
- **The enemy's general** (field.gd): lizards come straight on with their
  skirmishers in front; a rival army advances its line to musket range,
  pikes going for your horse, its own horse round your flanks.
- **The ground** (field_terrain.gd) is a heightmap with a nav grid: deep
  water and houses block, the ford and woods slow, uphill is slower.
  Regiments find their way with Godot's AStarGrid2D; men slide along walls.
- **Far sprites** for every kind (pikemen with pikes, red coats, horse and
  rider, raptors, brutes) are rendered from the 3D models at the start of
  the battle (impostor.gd), seen from a little above for the command view,
  on a magenta key the sprite shader cuts out (a transparent render isn't
  reliable on every phone). If the render comes back empty, the hand-drawn
  sprites stand in.

`-- --fieldtest[=map] [--humans] [--fieldsize=N]` plays a field battle with
the computer on both sides and reports every ten seconds (headless).

### Performance: big battles on a phone

The menu's **STRESS TEST** starts 50 musketeers against 200 lizardmen with an
FPS counter, so you can see what your own phone handles. (**SKIRMISH** on
the menu is a smaller stand-alone fight with a mixed company: muskets,
spears, bows and crossbows against three waves.)

What makes large battles affordable:

- **Spatial grid** (`battle.gd`): units are sorted into 4 m cells every
  physics frame, so crowd spacing and "who's nearest" look only at
  neighbouring cells instead of every unit on the field.
- **Instanced drawing** (`batcher.gd`): every 3D body part is a unit box,
  cylinder or sphere stretched by its transform, so all bodies in the battle
  are three MultiMeshes. Every sprite lives in one atlas texture per kind,
  drawn as one MultiMesh with a billboard shader.
- **Level of detail** (`rig3d.gd`): bodies within 12 m re-pose every frame,
  to 25 m every 2nd frame, beyond that every 4th, off-screen every 8th; small
  details (faces, buttons, teeth) are skipped beyond 16 m.
- **Scenery in batches** (`look.gd`): grass, trees, bushes, rocks and far
  hills are MultiMeshes with vertex shaders for the wind, so a forest is a
  few draw calls; grass fades out by distance instead of popping.
- **Far stand-ins** (`unit.gd`): units beyond 40 m are drawn as their sprite
  and switch back to the full model as you approach.
- **Time-sliced thinking** (`unit.gd`): a unit decides every 2nd physics
  frame (a lizard far from the fight every 4th), each on its own beat so the
  work spreads evenly; walking still happens every rendered frame, so it
  looks smooth.
- **Waves arrive over several frames** (`battle.gd`): 16 bodies a frame, so
  200 lizards don't freeze the game for a moment when they appear.
- **Cheap far bodies** (`batcher.gd`): beyond 16 m, body parts are plain
  boxes (12 triangles) instead of rounded ones (about 100).

Measured on the 50 vs 200 stress test (game logic per frame on a desktop
CPU; a phone is roughly 2–3× slower; draw calls with real rendering):

| Logic before | Logic after | Draw calls before | Draw calls after |
|---|---|---|---|
| 33.9 ms | 12.7 ms | 5,739 | 42 |

The speed pass (time-slicing, staggered waves, cheap far bodies) took the
200-lizard wave from 7.3 to 4.6 ms a frame on the same desktop, and its
worst frame (the wave appearing) from 40 to 9 ms.

### Tuning knobs

Most of the feel lives in constants at the top of each script: ranks,
experience, wages, recruit cost and wound chance in `company.gd`;
`LINE_SPACING` in `battle.gd`; `RELOAD_TIME`, `SPREAD`,
`AIM_SPREAD`, `AIM_FOV`, `FIX_TIME` and the `SWINGS` table (reach, arc, damage, knockback per blow) in
`player.gd`; `reload_time`, `RANGE` and the hit-chance formula in
`soldier.gd`; `speed`, `ATTACK_DAMAGE` and `WINDUP_TIME` in `lizardman.gd`.
First-person 3D poses are the tables at the top of `player_body.gd`.

### Headless smoke test

`godot --headless --path . --fixed-fps 60 -- --autotest` plays a stand-alone
battle with automatic volleys, bayonet fighting and blocking, and prints the
result. Add `--campaign` to play the beach prologue and then four
linked campaign battles (buying, sharing out and marching in between), `--stress` for the 50 vs 200 battle, `--mixed` for the
skirmish with a mixed company (muskets, spears, bows, crossbows), or `--tp` for
third person. `--camp` (add `--spotted` for the watch seeing them) is
the night camp attacked, and `--assault` (with `--walls=0.3` for a broken
palisade) storms a nest with two guns, `--patrol` (`--vell` for the
other nation, `--army` for a lord's army of 60) fights a nation's patrol,
and `--patrol --allied` fights a warband beside one; all start a fresh campaign after the prologue and
then march on to more battles. `-- --company` opens the Company screen after the prologue,
swaps kit, spends points, uses the wagon and marches six times without food
to check hunger, desertion and mutiny. This catches script errors without a
phone. `-- --intro` plays the cutscene at 4x speed. `-- --plantest` and
`-- --loottest` exercise the battle plan and the loot screen. `-- --maptest` makes a
new land, marches to the nearest village, buys food, then heads for the
stash nest, slipping away from (or fighting) warbands on the way.

## What's next

See [ROADMAP.md](ROADMAP.md): castaways in a huge unknown land, a
Warband-style map under fog of war, lizards, two human nations at war,
dwarves, and the edge your muskets give you. Done: M0, M1, projectiles, kit
and logistics, the shipwreck prologue, the first playable map, settlements,
M3 (native spearmen, archers and crossbowmen, powder and lead) and M4 (nest
sieges and assaults, the stash and the ship's guns). Next: the land's powers
(M5).
