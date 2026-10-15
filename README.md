# MusketFPS

A first-person musket game for phones, made in Godot: you are an officer in a
fantasy world with gunpowder, leading a company of musketeers against hordes
of lizardmen. Think Mount & Blade: Warband's Napoleonic Wars mod, with the
mass musket battles of the *Destroyermen* books.

The long-term plan is two layers: a top-down 2D world map, and first-person
battles. This repo starts with the battle.

Built and tested with **Godot 4.7.1**.

## Prototype 1: the firing line

A flat field, you in the centre of a line of 8 musketeers, and three waves of
lizardmen charging from the distance (8, 14, then 20). The question it answers:
**do musket volleys feel good on a phone?**

### Touch controls

| Control | What it does |
|---|---|
| Left side of screen | Floating joystick: put your thumb down anywhere and drag to walk |
| Right side of screen | Drag to look around |
| **FIRE** | Fire your musket. Keep your thumb down and drag to aim, like CoD Mobile. The gold ring is your reload. |
| **BAYONET / MUSKET** | Switch between shooting and melee (half a second; you can't reload while the bayonet is out) |
| **SWING** (melee) | The FIRE button becomes a swing joystick, see below |
| **BLOCK** (melee) | Hold to parry. Stops hacks from the front and makes the lizardman reel back |
| **VOLLEY!** | Every loaded man in the company fires at once |
| **FOLLOW** | The line moves with you and wheels when you turn more than 40° |
| **HOLD** | The line forms where you are, facing where you look, and stays put |
| **ON COMMAND / AT WILL** | Toggle whether your men wait for your volley order or fire on their own |

### Melee: Mount & Blade swings on a touchscreen

In melee mode, press **SWING** to start winding up. Without lifting your thumb,
drag to choose where the blow comes from, then let go to strike:

| Drag | Blow | Good for |
|---|---|---|
| Up | **Overhead** chop | Heaviest hit, one target |
| Left / Right | **Sweep** from that side | Wide arc, can hit two at once |
| Down (or just tap) | **Thrust** with the bayonet | Longest reach, one target |

Hold longer before releasing to charge the blow (the ring around the stick
fills; a full charge kills a lizardman outright). A gold marker by the
crosshair shows which side the blow will come from. Every hit knocks the
lizardman back and cancels his attack.

Lizardmen telegraph their hacks: they **rear up and glow orange** for half a
second. Hit them first, step back, or hold BLOCK.

Keyboard for testing on a PC: WASD move, mouse-drag on the right half to look,
Space fire (in melee: hold to wind up, release to strike), arrow keys pick the
blow, Q switch weapon, E block, F volley, 1 follow, 2 hold, 3 toggle fire mode.

### How it's built

Everything is created in code, so the only scene is `scenes/battle.tscn` with
one script. No art files yet: sprites are generated pixel art.

- **3D world, 2D sprites (Doom/Daggerfall style).** Soldiers and lizardmen are
  billboard sprites that always face the camera, so there's no 3D modelling or
  rigging, and dozens fit on screen cheaply.
- **Your weapon is a 2D overlay** drawn by the HUD. Each swing direction is
  just two poses (wind-up and strike end) and the HUD eases between them, so
  adding a new weapon or blow means adding poses, not animations.
- **Squad brain, dumb bodies.** `battle.gd` owns the line (an anchor point and a
  facing) and hands each soldier a slot. Soldiers just walk to their slot, load,
  fire, and use the bayonet up close. Lizardmen just charge the nearest man.
- **No physics for walking.** Units steer directly on the flat field with a
  simple push-apart rule; collision shapes exist only so your musket ball can
  hit them. Trees are drawn with MultiMesh (two draw calls for all of them).

| File | Purpose |
|---|---|
| `scripts/battle.gd` | The battle: world, waves, the company's line and orders, smoke |
| `scripts/player.gd` | First-person movement, looking, musket, melee and blocking |
| `scripts/unit.gd` | Shared base for soldiers and lizardmen: sprite, damage, death |
| `scripts/soldier.gd` | A musketeer: hold slot, load, fire, bayonet |
| `scripts/lizardman.gd` | A lizardman: charge, telegraphed hack, stagger |
| `scripts/hud.gd` | Multi-touch controls, swing joystick, weapon viewmodel, status |
| `scripts/sprite_factory.gd` | Generates the placeholder pixel-art sprites |

### Tuning knobs

Most of the feel lives in constants at the top of each script: `WAVES`,
`LINE_SPACING` and `COMPANY_SIZE` in `battle.gd`; `RELOAD_TIME` and `SPREAD`
in `player.gd`, plus the `SWINGS` table (reach, arc, damage, knockback per
blow) and the wind-up/strike timings; `reload_time`, `RANGE` and the hit-chance formula in
`soldier.gd`; `speed`, `ATTACK_DAMAGE` and `WINDUP_TIME` in `lizardman.gd`.

### Headless smoke test

`godot --headless --path . --fixed-fps 60 -- --autotest` plays the battle with
automatic volleys, bayonet fighting and blocking, and prints the result,
which catches script errors without a phone.

## Next steps

1. Sound: musket cracks, volley ripples, lizard roars, steel on scales.
2. A sword or sabre as a second melee weapon (faster, no reach).
3. Directional blocking, if the simple block turns out too easy.
4. A second rank, and "present arms" before the volley.
5. The world map layer.
