# MusketFPS

A first-person musket game for phones, made in Godot: you are an officer in a
fantasy world with gunpowder, leading a company of musketeers against hordes
of lizardmen. Think Mount & Blade: Warband's Napoleonic Wars mod, with the
mass musket battles of the *Destroyermen* books.

The long-term plan is two layers: a top-down 2D world map, and first-person
battles. This repo starts with the battle.

Built and tested with **Godot 4.7.1**. No art or audio files: every sprite,
model, animation and sound is generated in code.

## Two versions, one game

The main menu lets you pick how the battle looks. Everything else (AI,
combat, orders, sounds) is shared, so they can be compared like for like.

| | **2D sprites** | **3D models** |
|---|---|---|
| Soldiers & lizardmen | Doom-style pixel sprites with front, side and back views | Low-poly 3D bodies with procedural animation |
| Your weapon | Hand-drawn first-person musket and arms (2D overlay) | Your own 3D body: arms and musket in first person, the whole officer in third |
| Camera | First person | First person or third person (over the shoulder), switch with **VIEW** |
| Cost on a phone | Very cheap | More draw calls (each body is ~25 small meshes) |

## The battle

A flat field, you in the centre of a line of 8 musketeers, and three waves of
lizardmen charging from the distance (8, 14, then 20).

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
| **VOLLEY!** | Every loaded man in the company fires at once |
| **FOLLOW** | The line moves with you and wheels when you turn more than 40° |
| **HOLD** | The line forms where you are, facing where you look, and stays put |
| **CHARGE** | Break ranks: every man picks his own fight, fires if he has a shot, and falls back to you when badly wounded. With no enemies left they regroup on you. |
| **ON COMMAND / AT WILL** | Toggle whether your men wait for your volley order or fire on their own |
| **MENU** | Back to the main menu |
| **1ST / 3RD PERSON** | 3D only: switch camera |

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
blow, right mouse button or Z aim, Q fix/unfix bayonet, E block, V switch view (3D), F volley, 1 follow,
2 hold, 3 toggle fire mode, 4 charge.

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
lizard roars, hisses and death cries, men's grunts. All synthesised in
`sound_factory.gd`; swap any of them for a recorded .wav by loading it into
the same dictionary key.

## How it's built

Everything is created in code; the scenes are just a menu node and a battle
node.

- **3D world in both versions.** Only the characters differ: billboard
  sprites (2D) or primitive-mesh bodies (3D). Trees are drawn with MultiMesh.
- **Units drive a swappable "visual".** AI code only sets a facing and an
  animation name (`walk`, `aim`, `reload`...). In 2D that picks a sprite frame
  for the right view; in 3D the rig turns it into a pose.
- **3D rig (`rig3d.gd`):** the musket (or cleaver hand) is posed in body space
  and eased toward the target pose every frame; arms reach it with two-bone
  IK; legs run a walk cycle from movement speed.
- **Squad brain, dumb bodies.** `battle.gd` owns the line (an anchor point and
  a facing) and hands each soldier a slot. Soldiers walk to their slot, load,
  fire, and use the bayonet up close. Lizardmen charge the nearest man.
- **No physics for walking.** Units steer directly on the flat field with a
  simple push-apart rule; collision shapes exist only so your musket ball can
  hit them.

| File | Purpose |
|---|---|
| `scripts/menu.gd` | Main menu: pick 2D or 3D |
| `scripts/settings.gd` | `Settings` autoload: which version, camera mode |
| `scripts/battle.gd` | The battle: world, waves, the company's line and orders, smoke, sound playback |
| `scripts/player.gd` | Movement, looking, camera, musket, melee and blocking |
| `scripts/player_body.gd` | 3D: poses your own officer's body from your actions |
| `scripts/unit.gd` | Shared base for soldiers and lizardmen: visual, animation state, damage, death |
| `scripts/soldier.gd` | A musketeer: hold slot, load, fire, bayonet |
| `scripts/lizardman.gd` | A lizardman: charge, telegraphed hack, stagger |
| `scripts/rig3d.gd` | 3D bodies (soldier, officer, lizardman) and their animation |
| `scripts/batcher.gd` | Draws every unit in a few instanced batches (3D parts, sprite atlases) |
| `scripts/hud.gd` | Multi-touch controls, swing joystick, 2D viewmodel and arms, status |
| `scripts/sprite_factory.gd` | Generates the pixel-art sprite frames |
| `scripts/sound_factory.gd` | Synthesises the sound effects |

### Performance: big battles on a phone

The menu's **STRESS TEST 2D / 3D** buttons start 50 musketeers against 200
lizardmen with an FPS counter, so you can see what your own phone handles.

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
- **Far stand-ins** (`unit.gd`): in 3D, units beyond 40 m are drawn as their
  sprite and switch back to the full model as you approach.

Measured on the 50 vs 200 stress test (game logic per frame on a desktop
CPU; a phone is roughly 2–3× slower; draw calls with real rendering):

| | Logic before | Logic after | Draw calls before | Draw calls after |
|---|---|---|---|---|
| 2D | 17.7 ms | 6.2 ms | 233 | 78 |
| 3D | 33.9 ms | 12.7 ms | 5,739 | 42 |

Most remaining 2D draw calls are musket smoke puffs.

### Tuning knobs

Most of the feel lives in constants at the top of each script: `WAVES`,
`LINE_SPACING` and `COMPANY_SIZE` in `battle.gd`; `RELOAD_TIME`, `SPREAD`,
`AIM_SPREAD`, `AIM_FOV`, `FIX_TIME` and the `SWINGS` table (reach, arc, damage, knockback per blow) in
`player.gd`; `reload_time`, `RANGE` and the hit-chance formula in
`soldier.gd`; `speed`, `ATTACK_DAMAGE` and `WINDUP_TIME` in `lizardman.gd`.
First-person 3D poses are the tables at the top of `player_body.gd`.

### Headless smoke test

`godot --headless --path . --fixed-fps 60 -- --autotest` plays the 2D battle
with automatic volleys, bayonet fighting and blocking, and prints the result.
Add `--3d` for the 3D version, and `--tp` for third person. This catches
script errors without a phone.

## What's next

See [ROADMAP.md](ROADMAP.md): a Warband-style sandbox, 3D only, built in
playable milestones (persistent company, campaign map, towns, battle variety,
enemy types, backgrounds, a living world).
