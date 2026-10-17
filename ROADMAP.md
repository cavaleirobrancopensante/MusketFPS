# MusketFPS roadmap

A Mount & Blade: Warband-style sandbox about castaways with muskets. A
troopship of the Kingdom of Calder (names are placeholders, see
`scripts/lore.gd`) is wrecked on an unknown coast. The regiment entrenches
on the beach, is overrun by a lizard horde, and the survivors flee inland
with their Major's last order and almost nothing else. You are the young
officer he gave the company to.

The land is huge, unmapped and a little behind you in technology. Your
muskets, powder and cannon are the best weapons on the continent, and
every one you lose is hard to replace. That makes you weak in numbers, and
valuable to everyone who learns what you carry.

**Decisions so far**

- Sandbox, Warband-like: one opening story, then you make your own way.
- 3D only. Sprites stay only as far-distance stand-ins for performance.
- Every campaign opens with the shipwreck and the battle on the beach (also
  the tutorial). Who you were before the voyage is your background (M7).
- Your own nation is far away and absent. The land's powers are the lizard
  hordes, two human nations at war with each other, and the dwarves. You
  can side with any of them, or none.

## The core loop

1. **The map:** march across a huge land hidden by fog of war; scout it,
   find villages, towns, dwarf holds, warbands and nests.
2. **Battle:** the existing battle, with the real numbers on both sides and
   ground that matches the map.
3. **Aftermath:** casualties, wounded, loot, muskets recovered (or lost).
4. **Company:** recruit, feed, equip, level up, keep morale above mutiny.

## The arc of a campaign

- **Act 1, castaways:** low morale, little food, few cartridges, the ship's
  stores carried off by the lizards. Survive, find friends, recruit natives
  with spears and bows, and gather a force big enough to storm the nest
  and **recover the stash** (muskets, powder, the ship's guns).
- **Act 2, the newcomers:** with the stash back, the factions take notice.
  Hire out as mercenaries, pick a side in the human war (or not), and trade
  your secret: **teaching a faction to make gunpowder and firearms** buys
  its friendship, but arms it, perhaps against you later.
- **Act 3, a power in the land:** smiths (dwarves first) make muskets for
  you; your trained natives become musketeers; you hold ground of your own.

## Milestones

Each milestone ends with something playable.

### Done

- **M0 3D only** and **M1 a company that remembers** (names, ranks, wounds,
  death, saves).
- **Projectiles:** real musket balls, grenades, javelins; friendly fire.
- **Kit and logistics:** per-man kit and pack from the wagon, the Company
  screen, levels and attribute points, morale, hunger, thirst, foul water,
  grog, sickness, desertion and mutiny.
- **The shipwreck prologue:** storm cutscene, the entrenched beach with
  cannons, a tutorial woven into the waves, the Major's fall, the rout
  inland. You start with low morale and supplies, and the stash is lost.

### Battle plan, pikemen, the wagon in battle, loot, music ✅

- Battle plan with tags, lines and individual places; pikemen; the wagon
  (looters, bait) in every map battle; loot screen with weight and space;
  selling goods; an original soundtrack and music player.

### M2: The map (first playable ✅)

Done: a seeded 512 × 512 land in 3D with coast, plains, forest, swamp, hills,
mountains, rivers, lakes, fords, bridges and roads in three states; terrain
speeds; line of sight on the heightmap and fog of war; Warband time that
runs only while you move; day and night; villages, towns, cities, dwarf
holds and lizard nests; roaming warbands, patrols, caravans, villagers and
dwarf traders that fight each other and raid; encounters into battles on
matching ground; buying food and rum in settlements (only there); camp at
nightfall; events on the road by terrain and region; scouts; a new layout
for every campaign; four save slots. Still to do: smaller "lost"
settlements in the lizard lands, rumours, a minimap.


- **Warband-style:** your party is a figure walking on the map. Tap where to
  go and it marches there; time (the clock, the calendar, food and water,
  wages, healing) runs only while you move and stops when you stop. Other
  parties (warbands, caravans, armies) move in the same time.
- A tilted 3D tabletop map built from **regions**, so the land can be very
  large and still run on a phone. Each region has terrain (coast, forest,
  hills, marsh, plains, mountains), and battles there use matching ground.
- **Fog of war:** everything starts black except the beach. Regions are
  revealed by marching and scouting; scouts and high ground see further.
- Time in days, food and water by region (rivers, wells, dry country),
  foul water and grog as now.
- Lizard warbands roam out from the nest that holds the stash.

### M3: Natives and primitive arms ✅

Done: recruits come with their own weapons by trade and people (spears,
hunting and war bows, crossbows, dwarf crossbows; tunics, padded jacks,
hoods, kettle hats); arrows and bolts as real projectiles (archers arc over
the line); a MIXED preset in the battle plan; separate cartridges, arrows
and bolts; cartridges made from powder (sold only by the dwarves) and lead;
a town market for all of it. Muskets lost in battle are gone unless their
kit is carried back.

The plan was:

- Recruit in villages: **spearmen, archers, crossbowmen**, cheap and
  numerous, worse than your musketeers. Bows and crossbows are new
  projectile kinds (the table is ready for them).
- Kit becomes scarce: muskets lost in battle are gone unless recovered from
  the field. Cartridges are made from powder and lead, not bought.
- Mixed lines in battle: pikes in front, muskets behind, archers on the
  flanks.

### M4: The stash (done)

- Find the nest (scouting, rumours from villages).
- Every nest can be besieged a day at a time (the garrison starves and
  deserts, the stakes fall, they may sally at night) and stormed: a
  palisade, a gate to batter down, javelin throwers on platforms, sallies
  in waves, defenders holding inside.
- Storming the stash nest recovers the ship's stores: muskets, cartridges,
  rum and the two guns, which then march with you and fight with crews.
- A burned nest sends out no more warbands.

### M5: The land's powers

- **Two human nations** at war (names to come), each with towns, lords,
  armies and a war front that moves.
- **Dwarves:** holds in the mountains; the best smiths in the land.
- Relations and reputation; contracts; joining a side, or playing both.
  Started: standing with each nation (attack their men and they turn on
  you; their patrols hunt you), human parties as field battles, and joining
  a nation's patrol in its fight (its regiments beside yours, yours to
  command when you choose); lords with seats, armies that march to war,
  burn the border and come back when beaten, each with his own account of
  you. Next: contracts and pay for fighting under a lord, formations, and
  sieges of towns by the nations' armies.
- **Teaching gunpowder:** a deal with real consequences. A faction you teach
  fields musketeers of its own, and may later turn them on you.

### M6: Production

- Hire smiths (dwarves are the best) to make muskets, bayonets and powder.
- Saltpetre, sulphur and charcoal as resources found on the map.
- Training natives into musketeers.

### M7: Backgrounds and the officer

Who you were before the wreck, chosen at a new game: a gentleman's son who
bought his commission, a sergeant promoted from the ranks, a ship's officer,
an engineer... Each starts with different skills and men.

Done: your character sheet (YOU): six attributes, nine skills (Marksmanship,
Bladework, Leadership, Tactics, Surgery, Logistics, Pathfinding, Trade,
Training), each wired into battle, the march or the company; your own kit
and cartridge box; levels. Still to come: backgrounds, and Diplomacy and
Engineering (gunpowder and fortification) once factions and production
exist.

### M8: Battle variety

- Terrain sets from the map; objectives (defend a village, storm a nest,
  escort a wagon); morale and rout on both sides; retreat; deployment.
- Enemy variety: lizard skirmishers (javelins), shield brutes, raptor riders,
  shamans; human pikes, archers, knights; dwarf crossbows and axes.

### The Total War layer (one battle system)

The **Field battle** (built first in Tests) is now how the campaign fights:
regiments (muskets, pikes, bows, crossbows, cavalry, cannon; lizard
warriors, javelin throwers, brutes, raptor riders) on five maps (open
field, hills, a river with a bridge and a ford, a town, woods), morale and
rout on both sides, deployment, an enemy general, and the command view
beside first person. In the campaign your fit men muster by weapon into
regiments (your company is the muskets), the guns join when you have them,
the wagon and its crew stand behind, and the warband you met is the army
you face. The map's terrain picks the battle map. The prologue on Wreck
Beach is a field battle too: you get the command partway through.

The night camp (and a besieged nest's sortie) and the nest assaults are
field battles too: men asleep in rings round the fire who wake and form up,
and a nest whose palisade is in the paths, whose garrison holds behind the
stakes and whose gate the guns batter. Next:

- Big battles when your company fights beside a nation's army (M5), with
  you commanding the allied regiments.
- Formations (line, column, square against horse), skirmish order, and
  dismounting dragoons.
- Riding yourself: you on a horse, leading the cavalry.

### M9: Polish and release

- Music, UI and touch polish, balance, Android export.

## Open questions

- The real names: our nation, the ship, the land, the two human nations,
  the dwarves (placeholders live in `scripts/lore.gd`).
- What happens when you fall in battle: captured, Warband style, or game
  over.
- How far the tech gap goes: do the human nations have crossbows and
  armour, cannon of their own, or nothing like them?
