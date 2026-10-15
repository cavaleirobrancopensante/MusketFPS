# MusketFPS

A first-person musket game for phones, made in Godot: you are an officer in a
fantasy world with gunpowder, leading a company of musketeers against hordes
of lizardmen. Think Mount & Blade: Warband's Napoleonic Wars mod, with the
mass musket battles of the *Destroyermen* books.

The long-term plan is two layers: a top-down 2D world map, and first-person
battles. This repo starts with the battle.

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
| **VOLLEY!** | Every loaded man in the company fires at once |
| **FOLLOW** | The line moves with you and wheels when you turn more than 40° |
| **HOLD** | The line forms where you are, facing where you look, and stays put |
| **ON COMMAND / AT WILL** | Toggle whether your men wait for your volley order or fire on their own |

Keyboard for testing on a PC: WASD move, mouse-drag on the right half to look,
Space fire, F volley, 1 follow, 2 hold, 3 toggle fire mode.

### How it's built

Everything is created in code, so the only scene is `scenes/battle.tscn` with
one script. No art files yet: sprites are generated pixel art.

- **3D world, 2D sprites (Doom/Daggerfall style).** Soldiers and lizardmen are
  billboard sprites that always face the camera, so there's no 3D modelling or
  rigging, and dozens fit on screen cheaply.
- **Your musket is a 2D overlay** drawn by the HUD, which is where the future
  directional melee swings will live too.
- **Squad brain, dumb bodies.** `battle.gd` owns the line (an anchor point and a
  facing) and hands each soldier a slot. Soldiers just walk to their slot, load,
  fire, and use the bayonet up close. Lizardmen just charge the nearest man.
- **No physics for walking.** Units steer directly on the flat field with a
  simple push-apart rule; collision shapes exist only so your musket ball can
  hit them. Trees are drawn with MultiMesh (two draw calls for all of them).

| File | Purpose |
|---|---|
| `scripts/battle.gd` | The battle: world, waves, the company's line and orders, smoke |
| `scripts/player.gd` | First-person movement, looking, your musket |
| `scripts/unit.gd` | Shared base for soldiers and lizardmen: sprite, damage, death |
| `scripts/soldier.gd` | A musketeer: hold slot, load, fire, bayonet |
| `scripts/lizardman.gd` | A lizardman: charge and hack |
| `scripts/hud.gd` | Multi-touch controls, musket viewmodel, status and messages |
| `scripts/sprite_factory.gd` | Generates the placeholder pixel-art sprites |

### Tuning knobs

Most of the feel lives in constants at the top of each script: `WAVES`,
`LINE_SPACING` and `COMPANY_SIZE` in `battle.gd`; `RELOAD_TIME` and `SPREAD`
in `player.gd`; `reload_time`, `RANGE` and the hit-chance formula in
`soldier.gd`; `speed` and `ATTACK_DAMAGE` in `lizardman.gd`.

### Headless smoke test

`godot --headless --path . --fixed-fps 60 -- --autotest` plays the battle with
automatic volleys and prints the result, which catches script errors without
a phone.

## Next steps

1. Directional melee: the FIRE button becomes a swing joystick when you switch
   to bayonet or sword (press, drag up/down/left/right, release to strike).
2. Sound: musket cracks, volley ripples, lizard roars.
3. A second rank, and "present arms" before the volley.
4. The world map layer.
