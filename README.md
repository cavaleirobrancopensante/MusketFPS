# MusketFPS

A first-person musket game for phones, made in Godot: shipwrecked on an
unknown coast, you lead what's left of a company of musketeers through a
land of lizard hordes, warring kingdoms and dwarves, where your muskets are
the best weapons anyone has seen. Think Mount & Blade: Warband's Napoleonic Wars mod, with the
mass musket battles of the *Destroyermen* books.

It's growing into a Warband-style sandbox: see [ROADMAP.md](ROADMAP.md).

Built and tested with **Godot 4.7.1**. No art or audio files: every model,
sprite, animation and sound is generated in code.

## The campaign

### Prologue: the wreck and the beach (also the tutorial)

**NEW CAMPAIGN** opens with a cutscene played in the engine: the troopship
*Steadfast* in a night storm, the strike on uncharted rocks, the survivors
rowing ashore at dawn, and the regiment digging in on the beach (SKIP jumps
ahead). All names are placeholders in `scripts/lore.gd`.

Then **Wreck Beach**. You are the **Ensign** of Major Harrow's company,
behind earthworks with the sea at your back, a company on either side and
four guns in the embrasures. The guns fire round shot at range (it ploughs
through ranks and skips on) and canister close in. Lizards wading over the
earthworks are slowed. The Major gives the orders: FOLLOW, HOLD, CHARGE and
VOLLEY are locked while he lives, and he calls the volleys.

The battle is the tutorial: each beat shows a **HOW TO** box for the
controls it needs (moving and looking, firing and aiming, the bayonet and
blocking, grenades, going to the Major, and the orders once they're yours).

In the second wave a lizard javelin brings the Major down. Go to him (follow
the gold marker): he makes you captain with his last words. The left breaks,
the guns are overrun, and you lead what's left along the beach to **the
cliff path** (the red colour marks it) and inland. You start the campaign
as castaways: low morale, a few days' food, and the ship's stores (muskets,
powder, two guns, rum) in the lizards' hands. Getting them back is the
first great objective.

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
- **Scouts:** send one man a day's ride, or two men twice as far, in any of
  eight directions. They come back to the company wherever it is with what
  they found (land, towns, warbands) and map it, unless they don't come
  back at all (likelier in the lizards' country or near a warband).
- **Water:** passing rivers and lakes refills the barrels with clean water,
  swamps with foul water; a dry day leaves you with what you carry.
- **The land's powers** (placeholder names in `lore.gd`): the Kingdom of
  Aurest in the west and the Vellish Marches in the east (at war), the
  dwarf holds of the Greyspine mountains in the north, and the lizard nests
  in the south-west swamps. One nest holds the ship's stores.
- **A living world:** nests send out warbands that roam and raid villages;
  cities send patrols that hunt them (and each other, across the war);
  caravans travel between towns and holds; villagers go to market; dwarf
  traders come down from the mountains. Parties that meet fight it out,
  and you hear of what you see.
- **Encounters:** a lizard warband that catches you means battle (fought on
  ground that matches the map: forest, hills, swamp, beach, plains) or a
  chance to slip away, better in cover. Tap any party to go after it.
- **Settlements:** visit villages, towns, cities and holds to buy food and
  rum, refill water and rest. Raided villages have nothing left. You can
  only buy where someone sells (the wagon's Logistics shows what's on offer
  where you stand), recruits are found only in towns and cities, and nobody
  in this land has heard of gunpowder, so cartridges can't be bought at all.
- **Controls:** tap to march; drag to pan; pinch or mouse wheel to zoom
  (from a single village to the whole land); CENTRE to follow the company;
  COMPANY, WAGON, CAMP and MENU at the top right.

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
you on FOLLOW and stays put on HOLD. Before a fight you saw coming, the
encounter offers **PLAN** first. An **ambush** (a warband you never saw
coming) gives no time: the men start scattered.

**Attacked in camp.** At night the company sleeps on bedrolls in a ring
round the fire, the wagon parked to one side, and two men stand watch at
the edge of the firelight. Whether they see the lizards coming depends on
their eyes (aim, a little fitness), whether they're hungry, thirsty or sick,
the ground (the lizards creep right up through forest and swamp) and luck.
**Seen:** the alarm goes up, the men throw off their blankets and are on
their feet in a second or two, and the warband comes out of the dark from
the front (or you abandon the camp and try to slip away). **Not seen:** you
wake on your back by the fire with the lizards already among the bedrolls;
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
recruit with a spear, under the Natives tag.

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

### Real projectiles

Every musket ball is a real projectile: it leaves the muzzle at about 330 m/s,
drops under gravity, slows with air drag, and hits the first body in its
path, **friend or foe**. A faint streak shows where each shot went. Shoot
through your own line and you will hit your own men (the HUD tells you); a
careless volley from behind you can hit you too. Your men hold their fire
when a comrade is in the way (steadier men are more careful). Aimed shots
are tight, hip shots scatter. Lizard shields don't stop balls, but they will
stop thrown javelins once the skirmishers arrive.

All of it lives in `projectiles.gd`: a new weapon (arrow, javelin, round
shot) is one row in its `KINDS` table.

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
| `scripts/battle.gd` | The battle: world, waves, the company's line and orders, the beach prologue (guns, tutorial), smoke, sound |
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

### Performance: big battles on a phone

The menu's **STRESS TEST** starts 50 musketeers against 200 lizardmen with an
FPS counter, so you can see what your own phone handles.

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

Measured on the 50 vs 200 stress test (game logic per frame on a desktop
CPU; a phone is roughly 2–3× slower; draw calls with real rendering):

| Logic before | Logic after | Draw calls before | Draw calls after |
|---|---|---|---|
| 33.9 ms | 12.7 ms | 5,739 | 42 |

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
linked campaign battles (buying, sharing out and marching in between), `--stress` for the 50 vs 200 battle, or `--tp` for
third person. `-- --company` opens the Company screen after the prologue,
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
and logistics, the shipwreck prologue, and the first playable map. Next:
recruiting natives, then the stash.
