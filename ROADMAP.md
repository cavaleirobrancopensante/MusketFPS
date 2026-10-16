# MusketFPS roadmap

A Mount & Blade: Warband-style sandbox in a fantasy world with gunpowder.
You lead a company of musketeers across a frontier overrun by lizardmen
hordes: march on a campaign map, fight the battles yourself in first or third
person, and keep your men alive, paid and fed between fights.

**Decisions so far**

- Sandbox, Warband-like: no fixed story; you make your own career.
- 3D only. Sprites stay only as far-distance stand-ins for performance.
- You choose your background when starting a new game (see M6). Now that
  every campaign opens as Harrow's Ensign at Cinder Ford, the background
  becomes who you were before the battle (and what that gives you).

## The core loop

1. **Campaign map:** march your company across the region; find towns,
   villages, roads, lizard warbands and nests. Days pass, food runs down,
   wages come due.
2. **Battle:** the existing battle, using the real numbers on both sides and
   ground that matches where on the map the fight happens.
3. **Aftermath:** casualties, wounded, loot and pay. Survivors gain
   experience.
4. **Company:** recruit, resupply, equip, promote veterans. Back to the map.

## Milestones

Each milestone ends with something playable.

### M0: Clean-up for 3D only ✅ done

- Remove the 2D game mode and its viewmodel/arms code from the HUD.
- Keep the sprite atlas only as the far stand-in for 3D units.
- Menu: New Game / Continue / Stress test.

### M1: A company that remembers ✅ done

The battle becomes a chain of linked fights before the map exists.

- Every soldier is a named person with his traits (reaction, pace,
  steadiness), experience and rank: recruit, musketeer, veteran, sergeant.
- Experience makes men steadier, quicker to reload, better with the bayonet.
- Wounds keep a man out for some days; deaths are permanent.
- Aftermath screen: who fell, who's wounded, who was promoted, pay and loot.
- Save and load (JSON in `user://`), autosave after every battle.

### Projectiles ✅ done

- Real ballistic musket balls (gravity, drag) that hit whoever is in the way,
  with friendly fire both ways and men holding fire when the line is blocked.
- Hand grenades: thrown, bouncing, fused, with blast and knockback.
- A kinds table ready for javelins, arrows and round shot (M5).

### Prologue, kit and logistics ✅ done

- Cinder Ford: you start as the Ensign, the captain falls and gives you the
  company, you lead the survivors out.
- Kit per man (head, torso, primary, secondary, pack) handed out from the
  wagon on the Company screen, and visible on the 3D models.
- Levels with attribute points (aim, strength, constitution, fitness),
  morale, health, hunger, thirst, foul water, sickness, grog, fair shares,
  desertion and mutiny. The Logistics window on the wagon.

### M2: Campaign map

- A small region: a tilted 3D tabletop map, tap to march.
- Two or three towns, a handful of villages, one lizard nest.
- Lizard warbands spawn from the nest, roam, raid villages and grow.
- Time in days: food is eaten every day, wages are due every week.
- Meeting a warband: attack or try to slip away. Battles use the real
  roster of both parties.

### M3: Towns

- Recruit (raw recruits are cheap and shaky), buy food, sell loot.
- Rest to heal the wounded.
- Contracts board: clear a road, defend a village, hunt a war leader.
- Tavern rumours point at warbands and nests.

### M4: Battle variety

- Terrain sets chosen from the map: open field, forest edge, river ford,
  village, fort walls.
- Objectives: defend a village until relief arrives, storm a nest, escort a
  wagon.
- Morale and rout on both sides: units break and flee when it goes badly.
- Retreat: pull out of a lost fight at a cost.
- Deployment: choose where the line forms before contact.

### M5: Enemy and troop variety

- Lizard skirmishers with javelins, armoured shield-wall brutes, raptor
  riders (fast flankers), war leaders and shamans who stiffen a warband.
- Your side: grenadiers (bigger, steadier, hand grenades), riflemen (slow to
  load, very accurate), a drummer whose presence steadies the line.

### M6: Backgrounds and the officer

New-game screen with three backgrounds:

| Background | Starts with | Trade-off |
|---|---|---|
| Mercenary captain | Veteran musketeers, more money | No friends; lives on contracts |
| Colonial officer | Regulars, steady wages from the crown | Must follow orders; obligations to a faction |
| Monster hunter | A small band of riflemen | Little money; earns bounties on nests and leaders |

Officer skills that grow with use: Leadership (company size, morale), Tactics
(volley speed, line discipline), Marksmanship, Bladework, Surgery (fewer
deaths), Logistics (march speed, food). Renown unlocks a bigger company.

### M7: Living world

- Colonies and the lizard hordes as forces on the map: villages burn and are
  rebuilt, warbands grow into hordes if left alone, forts can fall.
- Relations with colonies, towns and factions; reputation follows your deeds.

### M8: Polish and release

- Tutorial battle, music, UI and touch polish, balance pass, Android export.

## Open questions

- The world's name, its colonies, and whether rival human factions exist
  (deserters, bandits, a rival crown) as enemies too.
- What happens when you fall in battle: knocked out and captured, Warband
  style, or game over.
- How big a company can get on a phone (the stress test gives the ceiling).
