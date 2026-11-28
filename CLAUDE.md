# CLAUDE.md
Guidance for Claude Code working in this repository.

See [README.md](README.md) for the tuning defaults table and the design docs
(`듀얼게이트_퀴즈러너_기획서_*.md`). This file covers how to *work* here.

## What this is

A Godot 4.7 mobile prototype: 480x854 portrait, `mobile` renderer, one main
scene. Tap anywhere to flap; fly through the gate whose answer matches the
quiz prompt. Four visual concepts share the mechanic — `SKY`, `JUNGLE`,
`OCEAN`, `DREAM` — picked on the mode-select screen.

Three quizzes exist: flag (SKY), math (JUNGLE), Stroop colour (OCEAN).
`DREAM` is the MIX mode and rolls all three, one per gate. Which quiz a gate
asks is therefore a property of the **gate**, carried in `gate.quiz_kind`,
not of `current_mode` — two gates on screen at once can be different kinds,
and the draw code has to know which is which long after the roll. Anything
that reaches for `current_mode` to decide how to render a question or an
answer is a bug waiting for MIX to expose it.

MIX is also **hidden until earned**: `HIDDEN_UNLOCK_GATES` (20) gates passed
in each of the other three, counted cumulatively across runs and persisted
per mode. Cumulative rather than per-run because the whole game is hard mode
— the condition is meant to ask "have you met all three quizzes", not "are
you good".

It was 10 until 2026-10-02, and **raising it did not re-lock anyone who had
already opened MIX** — a card that locks itself after an update reads as a
bug. That takes more than comparing counts, because each count stops at the
threshold: a tester who opened MIX under the old rule saved `10/10/10`, and so
does a new player halfway there under the new one. So the save also records
which threshold the counts were kept under (`gates_rule`; a save without it
predates the key and used `HIDDEN_UNLOCK_GATES_LEGACY`), and once MIX opens,
`hidden_unlocked` keeps it open. Raising the threshold again needs only a new
`HIDDEN_UNLOCK_GATES_LEGACY` if old saves without the key are still around —
everyone who unlocked since then is already carrying the flag. A locked card is covered by a translucent panel carrying the lock
art, which fills the gap between the name plate and the BEST plate — sized
from that gap, not from the card, because those two plates do not grow when
the card does. A corner badge was tried first and said only "this card has a
marking on it". The panel then carried `LOCKED` and a darker `Unlock to
play!` strip under a lock squeezed to 54% of the gap; both lines were removed
at the owner's request and the lock took their space, so how to open the card
is now told only by the explain bar when it is tapped. The
veil stops just inside the card's white border and leaves it alone, so a
locked card wears the same white frame as the other three. Covering the
border with the veil leaves white reading as a bright ring (254 through the
veil is still 117 against an interior of 70) and painting over it adds a
black frame the other cards do not have; both were tried and both looked
like a mistake.

**All of the above is 1.x, and its code is gone** (2026-11-27): the three
quizzes, MIX and its unlock, the lock veil and the `debug_force_hidden_locked`
switch that showed it (with its guard in `check_tutorial.gd`). `Mode`
survives only to index the per-mode best scores, their save keys and the
leaderboards. Old saves still carry `gates_cleared_<mode>`, `gates_rule` and
`hidden_unlocked`; nothing reads them. The code is on `release/1.x`.

The whole game is "Hard mode". There is no difficulty selector; each cycle
of the space game (`SpaceRun.cycle`) brings more gates a wave and a tougher
boss.

**2.0 is being built on `main`; 1.x is kept.** The last 1.x release (1.2.1,
version code 6) is tagged `v1.2.1`, and `release/1.x` branches from it for any
1.x hotfix. 2.0 ships as an update to the same Play listing.

### 2.0 is a space game

Decided 2026-11-26, after a landscape side view with a slider and a 3D
jungle dragon were both built and dropped: the owner could not keep the
character's cute face in a chase view, so the character became a ship. The
2.0 work before that point was reverted, back to the portrait game with
hearts (`4a84936`).

A ship seen from behind is steered up, down, left and right by **dragging
anywhere**. The drag is relative, so the thumb never covers the ship. The
ship fires on its own in FEVER and at the boss; during a pattern its guns hold,
since nothing there can be hit and the bullets only crossed the gates being
read, and a power-up fires one short volley so the new weapon is seen
(`VOLLEY_TIME`, 2026-11-28, owner). Portrait, 480x854, as 1.x. For testing on PC, a
debug build also steers with the arrow keys or WASD (`KEY_STEER_SPEED`); a
release build ignores the keyboard.

The same evening the owner said plainly that **the quiz itself is not fun**,
which is why 1.x failed. The quiz was therefore made a gate to something
else. One run goes round a cycle (`SpaceRun.Phase`). It was quiz → roulette
loot → boss → fever until 2026-11-27, when the owner replaced the one-off
questions (a sum, a rock-paper-scissors hand, an arrow) with **patterns**:
the quiz box states one rule, and a row of gate steps is flown under it,
borrowing the rhythm of an endless-stairs game — many quick calls in a row,
the next few in sight, faster the longer the run of right ones.

1. **PATTERN.** `PATTERN_LEN` (12) steps, one rule for the whole pattern,
   twelve since 2026-11-27: ten felt short, a rule over just as it was
   learned, and twelve divides by the memory rounds' 3, 4 and 6;
   one pattern kind per pattern (mixing kinds within one was judged too
   hard).

   **The patterns live in a bank** (`SpaceRun.BANK`, 2026-11-27), each
   at its own levels, kept apart from where they are placed in a run. The
   owner is filling the bank first and drawing up the placement after;
   until then `_pick_pattern` is a stand-in: the first cycle is plain
   colour then plain arrow, and after that any pattern in the bank at one
   level higher each cycle. A level is a Dictionary of knobs, every one
   with `gates` (2-4 a step); the numbers are all in that one table.
   `tools/capture_pattern_bank.gd` shoots every pattern at every level on
   one sheet, and `check_space` walks the whole bank.
   **To play one pattern**, set `debug_force_pattern` on Main in the
   inspector: every pattern of the run is that one, a level higher each
   pattern (L1, L2, ... L5) unless `debug_force_level` fixes it. Debug
   builds only, and the same `@export` trap as the other debug switches,
   so `check_tutorial` fails while it is on.

   | Pattern | What the box shows / what to fly through | Levels 1 → 5 |
   |---|---|---|
   | `COLOR` | a colour; that colour's gate | gates 2, 3, 4; then 4 with the colour changing every 5 steps, then every 3 (`switch`), the box flashing and a low chime at each change (`_note_rule_change`) |
   | `MIX` | a colour, sometimes under a red no-entry sign: then any gate but that colour | gates 3, 3, 4, 4, 4; avoid chance 0.2, 0.3, 0.3, 0.4, 0.5 |
   | `SPOT` | the step's gates as coloured dots laid out like the slots; one dot is not its gate's colour, fly through that gate | gates 2, 3, 4, 4, 4; at 4 and 5 the dots go blank once the step is 0.82 / 0.70 of the way in (`hide`) |
   | `MEMORY` | a round of colours, shown until the round's first gate, then "?" for the rest; flown in order from memory | colours a round 3, 4, 4, 5, 6 (`len`); gates 3, 3, 4, 4, 4. Six at most: colours seen once are held about four at a time, and four colours in a long round repeat. It went to 7 at first |
   | `SHELL` | the shell game: a colour; the gates come in wearing theirs, go dark at 0.6 of the way in and swap places until 0.88; fly through the one that wore the colour. Colours come back once judged | gates 2, 3, 3, 4, 4; swaps 1, 1, 2, 2, 3 (`_shell_moves`, `_shell_place`) |
   | `ARROW` | an arrow; the gate it points at | gates 2, 3, 4, 4, 4; the diamond at 1-3, either layout step by step at 4, the grid at 5 (`layout`), where the arrows go diagonal |
   | `ARROW_MIX` | an arrow, sometimes under the no-entry sign: then any gate but that way | gates 3, 3, 4, 4, 4; avoid chance 0.2, 0.3, 0.3, 0.4, 0.5 |
   | `ARROW_SUM` | two arrows with a plus, up or down and left or right; the grid corner they add up to | always the grid; gates 2, 3, 4, 4, 4; at 4 and 5 the box goes blank once the step is 0.82 / 0.70 of the way in |
   | `ARROW_MEMORY` | a round of arrows, shown until its first gate, then "?" | arrows a round 3, 4, 4, 5, 6; gates 3, 3, 4, 4, 4; diagonals (on grid steps) at 4 and 5 |

   - Every gate in a step wears a different one of `GATE_COLORS`.
   - `MIX`'s sign is a red ring and one slash round the swatch
     (`_draw_cross`). A bold X was tried first and hid the colour it was
     crossing out; on a red swatch it hardly showed at all. The avoid step
     exists because with one colour for twelve steps a player stops reading
     the box after the first.
   - `SPOT` was built after the owner asked for colour quizzes that use
     the box; "the odd colour out", which needs none, was the other idea.
     Its dots sit inside the frame's dark middle (`_draw_spot`); the first
     layout had the top and bottom dots on the frame.
   - `MEMORY` is the owner's design. The colours flown through stay,
     dimmed, so the player can tell how far into the round they are. Each
     round brings new colours (`_memory_rounds`, never one colour twice in
     a row), so at five a round a pattern runs 5 + 5 + 2, and the last
     round shows only its own steps. The world slows on a round's first
     step, if it has to, so the colours are up `MEMORY_SECONDS_EACH`
     (0.5 s) a colour: at full streak speed a step is 1.1 s away, and
     six colours cannot be learned in that (`_update_memory_slow`). A
     colour sequence with the current one marked was turned down: it is
     only the colour pattern with a colour that changes.
   - `Kind.SEQUENCE`, a row of symbols in the box flown through in order
     with each mark in its gate's hole, was dropped the same evening at the
     owner's call: reading a symbol off a gate in flight was too hard. Its
     code, the ten `Crest_Symbol` marks the UI kit baked for it and its
     checks are gone.
   - **Layouts** (2026-11-27): a step's gates stand either in the diamond
     (left, right, up, down; slots 0-3) or the 2x2 grid of corners (slots
     4-7, 3.2 apart), `Layout`/`LAYOUT_SLOTS`. The quarter that decides
     the answer follows the layout (`region_of`): the diamond's field is cut
     along its diagonals, the grid's along its middle lines. A level picks
     its layout, or MIXED for either step by step; SPOT's dots and the
     arrows follow it. Rocks keep off all eight slots.
   - **The no-entry sign means "anything but this" everywhere.** The red
     arrow, which meant "the opposite one", was replaced by ARROW_MIX's
     sign on 2026-11-27: the owner had not understood the red arrow the
     first time, and the patterns are meant to read at a glance.
     The tutorial's box step names it and shows it: the box's colour
     wears the sign every other 1.2 s while that step is up (`"demo":
     "avoid"` on the step, `SpaceRun.demo_avoid`).
   - The odd arrow out was turned down: finding it is plain, but that its
     direction is the answer would need explaining.
   - Still to come, in the owner's list: a colour-and-shape pair and a
     route drawn as a little path.

   A right gate lights up gold, adds to the **streak** and pays stardust
   (`STARDUST_PER_GATE` × the streak, so a whole pattern pays 78 against
   12 for one broken every step). Every `POWER_EVERY` (3) in a row the
   weapon steps up a level. A wrong gate, or a quarter with none, **only
   breaks the streak and the combo** — no heart, no weapon, no stardust.
   Bullets pass through the gates; only flying through counts. Hearts are
   spent only on boss shots. Asteroids flew in the gaps between steps
   until 2026-11-27 and cost a heart on contact; the owner took them out
   because reading and steering for the gates was enough to ask. The
   asteroid itself is kept, unspawned, for a shooter mode.
   The roulette and the old LOOT phase went with this change; the weapon
   grows only with the streak and never drops.

   The targets were planets to ram at first, and became gates on
   2026-11-26 at the owner's call. The game is called Dual Gate, and the
   Synty pack has a warp gate in the same blue-and-orange as the ship. Only
   its inner ring and glow band are used (`GATE_RING_NODE`/`GATE_GLOW_NODE`),
   and the band only when the portal kit is missing: with a portal filling
   the hole in the gate's colour, the band around it only doubled it, and
   it was dropped at the owner's call (2026-11-27).
   The outer ring's spurs reach 1.8 times the hole, and neighbouring slots
   are 2.95 apart. The hole is 1.08 (`GATE_RADIUS`), as big as it goes
   before two diagonal neighbours' rings meet at 1.10; since the ship is
   drawn in (below), the size is only how it looks. An arrow gate glows
   the plain cyan until judged, since a colour that differed would give
   the answer away; a colour gate wears its colour, which is the
   question's language. A passed gate shrinks
   away past the plane like the planets did: left at full size, the camera
   flew through the top slot's ring and it filled the screen. Fever planets and asteroids are still
   planets and rocks.
2. **FEVER.** Earned by the right gates of the pattern before it
   (2026-11-27, the owner's idea), in proportion: `FEVER_FULL` (9 s) for all
   twelve, half of it for half, none under `FEVER_MIN_RIGHT` (6)
   (`fever_for`). The gauge under the question box shows it (2026-11-28,
   owner): it fills with the right gates, and the fever drains it from
   where the pattern left it (`gauge_fill`), so the length is read off the
   gauge. It was all or nothing at first, 8 s for every step right and none
   for a miss, which the owner found too tight for what is meant to be the
   fun part; then 0.6 s a right gate with 1.8 s more for all twelve, a bonus
   that broke the proportion the gauge shows and went. Every step right
   still also brings the next weapon, then drones
   (`_power_up(true)`). At speed with no gates; every planet touched or
   shot is smashed for points and `STARDUST_FEVER_SMASH`, and nothing
   costs a heart. It opens to an ElevenLabs ship surging into hyperdrive
   (`fever_start.wav`, 2026-11-28, owner; the 1.x boost ignition before). A smash bursts with one of BinbunVFX's explosions
   (Stylized Explosion FX, CC0; `SpaceRun._smash_fx`, 2026-11-28, owner:
   "more dazzling"): the orange-ringed air explosion, the white-cored burst
   for the biggest planets, at most `SMASH_FX_MAX` at once since each is
   eight particle systems. They drift with the world but stop short of the
   camera (`SMASH_FX_NEAR_Z`) and one born near is drawn smaller: drifting
   on, a burst at the ship's plane came into the lens and covered the bottom
   of the screen. `tools/build_vfx_kit.gd` copies the pack in at the path
   its scenes name, `assets/BinbunVFX_Vol2/` (gitignored, like the portal
   pack; it is CC0 and could be committed, but every kit travels the same
   way). Not yet measured on a phone. Its sound is one of three takes of a
   heavy sci-fi explosion from ElevenLabs (`planet_explode_1..3.wav`), picked
   at random at a slightly varied pitch on the next of four players, so
   smashes overlap instead of cutting each other off (2026-11-28, owner).
   The space turns "supernova" for it (2026-11-28, owner): the nebula
   crimson, the streaks orange and the glow brighter, eased in over 0.5 s and
   out over 0.9 s (`_update_fever_mood`, `FEVER_*` tints). A deeper blue and a
   rainbow sky were compared; the blue was too near the painted sky.
3. **BOSS.** After `PATTERNS_PER_CYCLE` (2) patterns an enemy ship comes.
   A strong weapon melts it, and a weak one can still win by dodging. Its
   shots cost a heart. Down, it pays points and `STARDUST_BOSS` × the
   cycle, and the next cycle starts, a level higher in the bank (for now:
   see `_pick_pattern`), with more rocks, a faster world and a tougher
   boss. It goes down to one of two cinematic ship-destruction takes
   from ElevenLabs, picked at random (`boss_explode_1..2.wav`, 2026-11-28,
   owner; it went down in silence before).

Stardust is won in a run (`Main.run_stardust`, shown in the slot right of
the question box) and banked into the saved total (`[meta] stardust`) when
the run is left, by game over or the pause menu (`_bank_stardust`). The
mode select's top bar shows the total. It is what the upgrades and the
BATTLE mode will spend.

Flags, Stroop and MIX were removed with the rest of the 1.x code on
2026-11-27 (phase 2).

The ship is Synty's `Fighter_05`, chosen from all 18 small ships rendered
from the game's angle. `Fighter_03`, the first pick, looked good from above
and was two thin lines from behind. The camera sits well above the plane
for the same reason: from nearly level, every flat fighter is a line.

`scripts/SpaceRun.gd` owns the 3D world and the rules of contact. Main
still owns the run: score, combo, hearts, popups and the
question box. SpaceRun reports each outcome through Main's `_space_*`
handlers. `space` is null only before boot. The old gate code that sat in
Main, unreached, was removed on 2026-11-27.

**The ship's quarter decides, not its aim** (2026-11-27). The answer used to
be whichever hole the ship's centre was inside on the plane, and the owner
found it both hard and unfair: lining a ship up with a hole is hard, and a
ship sitting on the right side of the screen still slid past the right
gate. Now the field is cut into four quarters along its diagonals, one per
slot (`region_of`), and when a step reaches `CAPTURE_Z` the ship is pulled
into the gate of the quarter it is in, right or wrong (`_draw_in`). At first
the gate was fixed the moment the pull began and the drag was ignored from
then on; the owner found it took hold too soon to change an answer at the
last moment. Now the player steers through the pull: `ship_pos` stays where
the finger puts it, the pull is laid over it (`ship_shown()`, which
everything drawn at or hitting the ship uses), the gate follows the
player's quarter until `CAPTURE_LOCK` (85%) of the way in, and the pull
grows as u cubed (`CAPTURE_PULL_POW`), so it only takes over near the end.
The ship shrinks and rolls one full turn into the hole, and after the pass the world lunges (`WARP_BOOST`, with an FOV kick)
before settling. A quarter with no gate pulls nothing and costs exactly
what a wrong gate does. The cut is by quarter and not by nearest gate on
purpose: with gates only left and right, a ship at the top of the screen
being drawn sideways would look wrong. Once the front step is inside
`AIM_Z`, the gate in the ship's quarter glows brighter (`GATE_GLOW_AIM`, or
a colour gate's own colour lifted by `GATE_AIM_LIFT`; the same for right
and wrong), so the player can see where they are about to go.

**The speed is the streak's.** A single question wave used to take 2.9 s at
full speed, and the owner said it was too fast both to decide and to steer;
it was slowed near the gate for a while (`SLOW_START_Z`), but with steps
`STEP_GAP` apart that pulsed the world every step. Now a
pattern starts at `PACE_START` (0.6, 2.9 s a step), each right gate in a
row adds `PACE_PER_STREAK` (0.05), up to `PACE_MAX` (1.1, 1.6 s a step),
and a miss eases the world back to the start, so whoever just missed gets
the easy speed back. Each cycle adds `CYCLE_SPEED_STEP` (5%) up to
`CYCLE_SPEED_MAX` (1.3), so a step never gets under 1.2 s (`check_space`
holds it to `STEP_FLOOR`). The gap was 22 at first, three steps in sight;
the owner found the gates too close together and it went to 34 the same
day, then 42 that evening with the rocks gone, when the owner found it
still a little too hard: at 34, 8% a cycle with no ceiling and PACE_MAX
1.25, a step was 1.1 s at full streak in the first cycle and 0.8 s by the
seventh. Two steps are in sight, so the next can still be read while this
one is flown. The table of seconds a step is beside `STEP_GAP`. `pace` scales `speed()`, so the streaks and the sky follow it. The
lunge after a pass is small (`WARP_BOOST` 0.5) for the same reason: at 1.6
it ate half the gap to the next step.

**Answer plates on gates** (`draw_labels`) are kept for patterns to come;
no gate carries a label now. From 2026-11-26 the answers
were shown at full size on the plane, in dashed rings, from the moment a
wave appeared; that covered every quarter of the screen, and it was removed
on 2026-11-27. A plate sits in its gate's hole, at least `LABEL_MIN_FONT`,
and fades in over `LABEL_FADE`; the plate of the gate the ship is being
drawn into goes see-through.

Judged gates also used to fly on into the camera; the top slot's sits
almost on its line of sight and swelled to cover half the screen. Past the
plane they shrank away in place over `PASS_SHRINK_DISTANCE` for a while,
which at speed took 0.13 s and read as the gate blinking out (owner,
2026-11-27). Now a passed gate parts outward as it flies on, each away
from the field's middle, `PASS_SPREAD` out by the camera and fast at
first (a square root of the distance), shrinking over the longer
`PASS_GATE_SHRINK`: the top gate rises past the question box instead of
covering the next step. Only the drawn place moves; `p.pos`, which
judging and the pull read, stays put.

The camera keeps its **horizontal** field of view (`KEEP_WIDTH`). The game
is 480 wide on every phone, so a taller phone sees more space above and
below. With the vertical angle fixed instead, the left and right planets
ran off the edges at 20:9.

**The Synty Sci-Fi Space pack** supplies the ship, planets, debris and sky.
The pack is paid and this repository is public, so nothing from it is ever
committed:

- `tools/build_space_kit.py` (Blender) reads the unzipped pack and writes
  `assets/synty_space/`, which `.gitignore` excludes.
- A fresh clone has to run it once with its own licensed copy:
  `blender -b --python tools/build_space_kit.py -- <repo>
  <POLYGON_Scifi_Space_SourceFiles_v2/SourceFiles>`.
- `tools/build_ship_icon.gd` (Godot, not headless) renders the lives row's
  top-down ship from the built kit into `assets/synty_space/ship_top.png`;
  run it after `build_space_kit.py`, then `--import`.
- Without the kit the game still plays on plain spheres and a wedge ship.
  A release build must be exported from a machine that has the kit.

**The play-screen HUD comes from Synty's INTERFACE Sci-Fi Menus pack**
(2026-11-27), under the same rule:

- `tools/build_ui_kit.gd` (headless Godot) reads the unzipped
  `INTERFACE_SciFi_Menus_SourceSprites_v1` zip's `SourceFiles/` and writes
  `assets/synty_ui/`, which is gitignored. Run it as `... --headless --path .
  --script res://tools/build_ui_kit.gd -- <SourceFiles>`, then `--import`.
- Without the kit, every HUD slot is an ArtSlot placeholder. A release must
  be exported from a machine that has both kits.
- The pieces were picked to match the ship's grey metal with orange accents:

  | Slot | Sprite |
  |---|---|
  | Score bar (gone on 2026-11-28, from the play screen and then from the mode select's stardust readout) | `Bar_Frame_01` |
  | Mode select's stardust readout | The explain line's frame (`explain_bar.png`, the slim `Frame_Box_Small_02` with its slot panel at both ends), as tall as the icon buttons (2026-11-28, owner). Either end wears `Button_Arrow_01`'s chevron on its black clip, glow and all, the clip laid over the frame's end (`deco_arrow_left.png`/`_right.png`, `_draw_readout_deco`, after a sample). For an hour before, `Bar_Frame_02` with the buttons' teal face; a silver capsule, the question box's frame and `Bar_Frame_03` were compared |
  | Question box | `Button_Frame_01`, orange end caps; the most important panel gets the loudest frame |
  | Health and stardust slots (until 2026-11-28; both now sit bare on the top line, and the frame stays the mode select's square buttons) | `Frame_Box_Small_07`, one frame for both, so the question box sat centred between twins |
  | Pause | `Frame_Box_Small_07` with a blue face (the menu's shared FACE_TOP/BOTTOM; teal for an hour), lit cyan while held (`pause_on.png`), like the menu's icon buttons (2026-11-28, owner; it was `Frame_Box_Small_10` with a dark face), with the II bars drawn on at build time; the pack has no pause icon |
  | Progress gauge | `Button_Frame_03`, the plain silver capsule (2026-11-28, owner), its fill drawn as a beam (`_draw_laser`: a glow, the body, a white-hot core, pulses running to a flared tip). It was `Bar_Frame_08`, an orange pill; then the same day `Bar_Frame_06`, a grey frame with a dark block and orange stripes, which did not go with the question box, and the question box's own frame small; `Bar_Frame_03` was compared too. Its two ends are sliced apart (`HUD_GAUGE_CAP_L`/`_R`, `_draw_horizontal_slice`'s `cap_right`) and the game fills its window (`gauge_window`, `GAUGE_WIN_*`, measured off the bake) |
  | Weapon readout's backing | `Menu_Item_Background_03_Blue` |
  | BEST mark (the mode select's cards; the play screen dropped it on 2026-11-28) | `Trophy_01`, tinted gold |

- Each frame is laid over its own `_Background` sprite, tinted dark, so
  white text on it reads against the space behind.
- Every frame from the pack's SciFiMenus folder has its grey metal put on one
  silver at bake time (`_unify_metal`, 2026-11-28, owner): the hue taken to
  `METAL_TINT` and the median brightness to `METAL_MEDIAN`, both blended out
  toward `METAL_SATURATION` so the orange caps and cyan lights stay. The
  frames come from different sprites, and their greys had differed, some
  bluish (the slim `Small_02`, the bevel `Small_04`), some neutral (the steel
  blocks), some darker.
- Each piece is baked at 2.25x its on-screen size, about a phone's scale.
  The bars are drawn with their ends whole and the middle stretched
  (`_draw_horizontal_slice`), the square frames as nine-patches.
- The caps and margins (`HUD_*_CAP`, `HUD_SIDE_SLOT_MARGIN`) are in baked
  pixels.

**The popups are dressed from the same kit** (2026-11-28, owner's ask).
Pause, game over, settings and about keep their layouts (the revive popup
was there too until it went on 2026-11-28); what
changed is the art and the palette (`PopupBase`):

- The panel is `Frame_Box_Large_08`, the blue-lit frame with steel corner
  caps; its face is near-opaque dark. It has a tab in the middle of its top
  and bottom edges, which a nine-patch would smear the length of the panel,
  so `build_ui_kit` cuts it down (`NINE`, `_nine_cut`) to its four corners
  joined by a short plain piece of each edge. `PANEL_CORNER` is the corner
  it prints.
- The owner went through sheets of every frame in the pack drawn as popups,
  switched to the orange-bracketed `Frame_Box_Large_01` with a title bar,
  and came back to Large_08 the same day. Any frame can be tried by swapping
  its `PIECES` row and the `NINE` row (Large_01 cut well at `[0.20, 0.31]`,
  corner 149); frames with gear on one side only (Large_04-07, 13, the
  Mediums) look lopsided stretched to a popup. The pack's own demo look,
  `Frame_Box_Large_09` (silver rails top and bottom, open sides) over a dark
  teal face with baked scanlines, was tried in the game the same day and
  the owner kept Large_08. Scanlines need the face tiled, not stretched
  (`axis_stretch_vertical` TILE_FIT), or their spacing grows with the panel.
- Every full-width button is one frame, `Frame_Box_Small_08`, and only the
  face tells them apart (2026-11-28): orange for the main button
  (`GOLD_FILE`, `popup_bar_primary.png`), blue with a cyan caption and icon
  for the others (`CREAM_FILE`, `popup_bar.png`, `SECONDARY_LABEL_COLOR`).
  - The pack's bar has a screwed steel block on its right end only; its left
    edge is a hairline meant to sit under an icon cell, and alone it read as
    cut off. `build_ui_kit` mirrors the block onto the left and squeezes both
    to 60% of their width (`MIRROR_RIGHT`, `_close_both_ends`): at full width
    the two blocks left a short button half its face.
  - The bar is three-sliced at its height (`_kit_patch`), its ends fixed at
    `BUTTON_BAR_LEFT`/`RIGHT`, and `_place` centres the icon and caption on
    the face between them (`face`), which the press glow also fills.
  - The narrow buttons, settings' LOGIN and the game over's x2, are the
    silver bevel box instead (`SMALL_GOLD_FILE`/`SMALL_CREAM_FILE`,
    `Frame_Box_Small_04`, nine-sliced on all four sides at the bake's scale):
    the bar's two ends ate almost all of them. The bevel is also the volume
    bar's handle.
  - Every button and row runs the same width, so their edges make one line
    down the panel.
  - The mode select's PLAY is the same orange bar (`PLAY_FRAME_PATH`), since
    2026-11-28: it was `Button_Frame_06` with V-notched ends, and the two
    screens' main buttons looked like different games. Its press glow and
    launch ghost follow the new art (`PLAY_FACE_SRC`, `PLAY_FRAME_CAP`). The
    menu's square icon buttons stay square: their old frame, the HUD slot's
    (`Frame_Box_Small_07`), with a blue face (teal for an hour, then the menu's one blue, `build_ui_kit` FACE_*), lit cyan while held
    (`icon_button.png`/`icon_button_on.png`, 2026-11-28, owner, after a
    sample). The plain silver bevel square (`Frame_Box_Small_04`) was tried
    in the old frame's place and the owner kept the old frame.
  - How it got here, all on 2026-11-28 and each the owner's call:
    - The main button was `Bar_Frame_02` filled orange with cyan arrow tips,
      and the secondaries `Frame_Box_Small_04`. The owner found they did not
      belong together.
    - Each frame was drawn as a whole family (main, secondary, result row)
      and the bevel kept; the `Bar_Frame_02` family was heavy.
    - The owner then found the bevel flat. The pack's `Label_Button` sample
      (an icon cell, `Frame_Box_Small_01` mirrored, clamped over the left end
      of this bar) was built for the secondaries: with the cell apart from
      the bar it read as two parts; on the taller main buttons it halved the
      caption.
    - Then every button became this bar, closed at both ends.
  - Secondaries tried earlier: the grey rounded `Button_Frame_03` (faceted
    ends that never look like a cut corner), `Button_Frame_07` (rails above
    and below), and a rounded box drawn in code.
  - The result rows were rounded boxes drawn in code with a coloured rim,
    then the bevel with a near-black face for an hour; framed like the
    buttons they looked pressable, and they became a layer drawn in the
    panel (`GameOverPopup._draw_box`): the two rows share one dark recessed
    glass plate, a faint blue edge round it and a thin line between them, so
    they read as one score sheet apart from the buttons below. A flat strip
    per row with a short coloured bar at its left (combo orange, stardust
    cyan) was drawn beside it, and the owner chose the plate.
  - A button's icon matches its caption (2026-11-28, owner): as tall as the
    caption's capitals (`ICON_CAP_LATIN` 0.72 em for Zen Dots,
    `ICON_CAP_HANGUL` 0.78 for Do Hyeon, both measured, times
    `ICON_CAP_MATCH`), centred on them rather than on the line box, and on
    the main buttons filled the caption's cream with its brown outline
    (`IconRim`, the icon stamped round a small circle). The per-button
    scales went (PLAY AGAIN 1.15, HOME at 0.52 of the button, x2 1.3, REMOVE
    ADS 1.15): bigger than the letters and unoutlined, the icons read as
    stickers. At half the caption's outline the rim filled the restart
    arrow's ring; it is a quarter (`ICON_RIM_SHARE`).
  - The names GOLD and CREAM are kept from 1.x and mean main and secondary.
  - Held, a button's inner face lights up, as the menu's PLAY does: an
    additive soft radial glow (`Glow`, `_press_glow_texture`) centred on the
    face and `PRESS_GLOW_GROW` larger than it (`face`; for the bevel,
    `BEVEL_FACE_INSET`, measured off the baked art), fading in with the press
    and out over `PRESS_GLOW_FADE` after it. It was a flat rounded box the
    size of the face until 2026-11-28; between the bar's steel blocks it read
    as a patch stuck on, and the owner called it broken.
- Button captions (and the language toggle's ENG/KOR) and the short
  capital labels (SCORE, BEST, MAX COMBO, STARDUST, SFX, MUSIC, LANGUAGE,
  `_label_font`) are in Zen Dots, the titles' face; numbers and sentences
  stay in the base font, Oxanium (2026-11-28, owner). All English in Zen Dots was
  considered and not done: it is a display face, wide and hard to read in
  sentences, and its numbers overrun the narrow score slots. Zen Dots runs
  wider than Oxanium, so settings shrinks its three labels until LANGUAGE
  fits `LABEL_COLUMN_MAX` of the row, and the game over's two result rows
  share one label size (`_row_label_size`), fitted to what the x2 button
  (narrowed to 0.26 of the row for this) leaves STARDUST. A caption with Hangul in it is set in the base font's heavy weight
  instead
  (`_caption_font`). Left to Zen Dots' `fallbacks`, Hangul came out in the
  device's thin gothic rather than the game's Do Hyeon, and the Korean buttons looked
  faint. The font is picked in `_place`, since a caption can change after it
  is built (the x2's AD NOT READY). The game over's two big numbers, the score
  and the BEST plate's value, are Zen Dots too (`_big_number_font`): they
  read as one block with GAME OVER and SCORE, and match the mode select
  card's BEST figure. Small numbers stay in Oxanium.
- GAME OVER, SETTINGS and PAUSED (and OOPS! while the revive lasted) are large gold Zen Dots letters with a dark
  rim and no plate (`_make_title`), standing just above the panel and clear
  of it (`_place_title`). They were on a header plate astride the panel's
  top edge first, then on the orange `Bar_Frame_08` above it; the owner
  asked for them clear of the panel, larger, and then for the letters
  alone. All three share one size (2026-11-28, owner; PAUSED had come out
  bigger than SETTINGS): each popup works out the largest its title can be,
  within `TITLE_WIDTH_FRAC` (0.88) of its panel and the room above it, and
  every title takes the smallest (`_title_caps`, `_shared_title_size`). The
  widest, GAME OVER, sets it. The width cap was 0.66 while the close button
  sat on the panel's top right corner (at 0.74 SETTINGS touched it).
  The game over's panel keeps its top below `PANEL_TOP_MIN` (222 px: the
  HUD's progress bar ends at 160, then the title), so GAME OVER never sits on
  the HUD; at 16:9 that moves the panel down and shortens it
  (`_panel_box`), and its rows, sized from its height, shrink with it.  The game over's title was TRY AGAIN; PLAY AGAIN under it already says
  that.
- The 1.x popups were navy on cream. Text is now a pale blue (`INK`). The toggle is cyan. The glow that breathed around the panel (gold in 1.x, then cyan) was removed at the owner's request: the kit frame carries its own light and colour.
- PAUSED was pale blue letters inside the panel until 2026-11-28, when the
  owner asked for it to match the other popups' titles; the pause panel came
  down to `(0.88, 0.56)` and its centre to 0.54 to make room above it.
- Icons are the pack's white ones (`KIT_ICONS`, and the game over's
  `*_FILE`s), the tick and lock baked tinted. The pack has no plain play
  triangle, so RESUME's is drawn (`_play_icon`). Synty's POLYGON Icons, its
  coloured low-poly 3D icons rendered to PNG, replaced them for an hour on
  2026-11-28; the owner preferred these.
- The countdown is voiced (2026-11-28, owner): a starship-AI announcer the
  owner made in ElevenLabs says "Ready." calmly as READY appears and "Go!"
  excitedly at GO! (`voice_ready.wav`, `voice_go.wav`), in place of the 1.x
  beeps.
- The countdown before a run (2026-11-28, owner) is READY, then GO!, in the
  popup titles' gold Zen Dots with its rim, between the HUD and the ship
  (`COUNTDOWN_Y_FRAC`), not over it. READY grows in and breathes; GO! pops
  and the world lunges as on a gate pass (`SpaceRun.boost`,
  `SpaceRun.punch`). For an hour on 2026-11-28 GO! sat on a
  band of blue light after the UI pack's own "GAME SAVED" banner (scanlines,
  bright edges, turning holographic rings, the word flying in); the owner
  moved that band to the weapon power-up and gave GO! back its pop. Both glow softly gold: a round light behind the word
  and a halo in the letters' shape, stacked from six faint outlines
  (`COUNTDOWN_HALO_*`; one wide outline came out a flat band). A cyan ring
  and speed lines burst out of GO! at first; the owner took them out. It was the 1.x
  READY/START banner art, deleted with the rest of 1.x, which had left a
  grey placeholder box on the ship.
- The game over's top row is written straight onto the panel (2026-11-28,
  owner), the same height either way so nothing below moves
  (`TOP_ROW_FRAC`). Not a record: a header of the kit's gold star (sized
  like a button icon), BEST in yellow and the number in Zen Dots, with thin
  lines either side fading out to the panel's edges. A new record: NEW
  BEST! (최고 기록 경신!, which was 신기록! until the owner matched it to the
  other screen's 최고 기록) in the title's gold and rim, a soft gold glow behind it
  and a small star either side twinkling half a beat apart. Before, the
  BEST sat in a framed plate that read as a button, and NEW BEST! bent
  along an orange ribbon with a gold trophy swaying at one end and a
  bobbing star (the "face" Main passed in, once the 1.x bird) at the other;
  the owner found neither belonged in the popup. The faces, the ribbon,
  the trophy and the warning-sign icon went with it.
- The volume rows (settings and pause) are `PopupBase.KitSlider` (2026-11-28,
  after a sample the owner sent): `Button_Arrow_07` with its cyan light layer
  at either end, stepping the value by `SLIDER_STEP`; between them
  `Bar_Frame_02`, three-sliced, filled cyan up to the handle. The handle is a
  small box carrying the value 0-100 in Oxanium, the secondary buttons'
  silver bevel (`popup_button.png`) nine-sliced at the bake's scale; the owner
  asked for it to move with the value and to be plainer than the
  `Frame_Box_Small_06` with steel caps it started as, which sat fixed at the
  bar's left. Grabbed, it keeps the finger's place on it; pressed elsewhere on
  the bar, it comes there and drags from there. It takes mouse
  input only, since touch arrives as emulated mouse. In settings the bars
  start after the SFX/MUSIC labels rather than the wider LANGUAGE one, or the
  fill was about 45 px long.
- Kit art never goes through the popup bake (`_bake_store`): its output sits
  under `ui_assets/`, which git tracks.

**Stardust flies to its counter** (2026-11-28, owner). A planet smashed in
FEVER throws out two pink-violet stars, the boss eight, which burst a little way
from where it broke and fly into the counter at the top right
(`SpaceRun._spawn_dust`, `_update_dust`, `DUST_*`). They are the Gems and
Crystals star as real 3D meshes (`star_mesh.res`, taken out by
`build_gem_kit.gd`), turning on their faces and rocking a little: spun
right round their upright they showed a thin edge half the time. Their path
is worked out on the screen and put back into the world each frame at a
depth closing on the camera, sized to the flat icon's pixels, so they slip
in behind the HUD counter as they land. Without the pack they are the flat
icon on the HUD (`_draw_dust`). Flying into the ship instead was tried and
turned down: planets break close in front of it, so the flight was short
and the counter's change went unseen. The count goes up as each
lands, and the counter's icon swells. The stardust is paid at once (Main), so
the run's total is right whatever becomes of a mote; only the shown count
waits (`dust_pending`). A right gate throws its stardust the same way, one star a
gate in the streak up to `DUST_PER_GATE_MAX` (4), out of the gate flown
through; at first gates paid without stars, and the owner wanted to see it
come.

**The engines burn with the run** (2026-11-28, owner). Each nozzle has a
round glow at its mouth and a jet of small flames shot out of it toward the
camera, each swelling and fading as it comes (`SpaceRun._make_jet`,
`_update_engines`, `ENGINE_*`, `JET_*`). The jet runs faster and brighter as
the streak raises the pace, and leaps on the lunge after a pass.

- The flames fly along the camera's line of sight, a touch below it
  (`JET_RISE`). Coming straight at the lens, a flame stays on its nozzle on
  screen and only grows, which reads as pouring out of the screen. Shot
  straight back (+Z), they ran down the screen, since the camera is above.
- Tried before it, the same day:
  - A CC0 flame shader from godotshaders.com on a 3D cone. Trailing back, the
    cone points into the lens and shows no length; tilted down far enough to
    show some, it hung like an icicle.
  - The glows alone stretched into a plume. Grown wide, the three ran
    together into a white blob over the hull.
  - A flame cone drawn on a camera-facing quad. It hung down the screen, and
    the owner read it as pointing down rather than out at the viewer.
    It came back short under the jet at the owner's ask (0.40; at 0.26 the
    nozzle glow swallowed it) and went again the same hour: even short, it
    still read as pointing down.
- A still frame shows the jet only as a hotter, haloed glow; the swelling
  toward the viewer is in the motion.

**A right pass bursts in colour** (2026-11-27). The gate lights up gold (red
when wrong), and a right one throws a shockwave ring, shards out of the ring
in its plane and speed lines from its centre on the screen
(`_pass_burst`, `draw_pass_lines`), while the space streaks stretch with
the lunge and Main plays a chime pitched up with the streak. It was made
finer when the owner asked for it to look more polished: soft light over
hard shapes. A bloom of light opens at the gate's middle, an OmniLight
lights the gate and the ship in the burst's colour for a moment, a wide
soft halo (a ring texture on a quad) spreads behind the crisp thin ring,
the shards are thin streaks with a glowing head flying out in the gate's
plane, a few motes linger and twinkle, and the speed lines are wedges
tapering to a point. Two things bit on the way: the billboards ignored
their node's scale until `billboard_keep_scale` was set, and the motes and
bloom came out a whole unit across, blobs; and shards flying toward the
camera swelled their heads into blurred balls (`PASS_SHARD_TOWARD`). The colours
come from `_pass_palette`: the ring wears the gate's own colour (cyan for an
arrow gate), the shards and the speed lines' tips are drawn from that
colour and white, with its opposite hue from five in a row and every hue of
`PASS_RAINBOW` from ten, when a second ring follows in the opposite hue.

A wrong gate answers the opposite way, short and dull (2026-11-27): the
camera jolts side to side (`WRONG_SHAKE`), the passed gate's portal
sputters red and goes out (`WRONG_FAULT_TIME`), and the gate that was
right, every one of them on an avoid step, is ringed in green where it was
judged for `REVEAL_TIME` (`_draw_reveals`), so the player sees at once what
it should have been. The ring first followed the gate as it parted
outward and left the screen in 0.15 s, before it could be read. Its sound
is `gate_wrong.wav`, and a right pass's is `gate_pass.wav`: ElevenLabs
sounds the owner chose (2026-11-28; `FX_SOUND_WRONG_PATH`,
`FX_SOUND_PASS_PATH`).

With it come two of the owner's three asks of that evening:

- **B**: the world holds for `HITSTOP_TIME` (0.06 s) and the camera is
  thrown forward `CAMERA_PUNCH`, then eases back.
- **C**: the passed gate's portal flares and swirls shut over
  `PORTAL_CLOSE_TIME` (its `open_amount`), so the gate itself answers.

How it got here: the burst was all one gold at first and the owner found
it flat. Three BinbunVFX packs were tried in its place the same evening,
Stylized Hit FX (CC0), Electric FX (CC0) and Magic Area, alone and then
layered, with the hit made bigger and moved in front of the gate ("A") and
a lab scene for trying them; they read as explosions and spells rather
than a gate flown through, and all of it was taken out. The burst came back
with colour instead.

**The gates' inner face comes from BinbunVFX's Portal VFX pack**
(2026-11-27), under the same rule: paid, never committed.

- `tools/build_vfx_kit.gd` (headless Godot) copies only `portal.gdshader`
  and its dithering include out of the unzipped `PortalVFXFull.zip` into
  `assets/binbun_vfx/`, which is gitignored. Run it as `... --headless
  --path . --script res://tools/build_vfx_kit.gd -- <PortalVFXFull dir>`,
  then `--import`. The owner keeps the zip under `D:\Godot\Godot VFX
  collection\`.
- The pack's scenes (particles, an OmniLight and an AnimationPlayer per
  portal) are not used. `SpaceRun._load_portal` rebuilds the noise and
  shape textures in code from the pack's own settings, and `_make_portal`
  puts one quad across each gate's hole in "Opaque" mode. "Warp", which
  bends what is behind it, was tried first: it pulled the ring's lit inner
  edge into the hole as a thin turning circle and showed the next step
  through it. The noise is the
  pack's `noise_04` (ridged, domain-warped, like smoke), picked by the
  owner from all nine patterns compared side by side.
- The portal takes the gate's glow colour every frame (`_portal_color`), so
  it gives nothing away that the ring does not.
- Without the kit the hole stays empty, as before. A release must be
  exported from a machine that has all four kits (with the icons below).
- Each portal runs eight noise layers per pixel. That has not been
  measured on a phone; `PORTAL_LAYERS` is the knob if it costs frames.

**The question box's gem and arrow come from Synty's POLYGON Icons pack**
(2026-11-28, owner), under the same rule: paid, never committed.

- The colour balls became the pack's faceted `SM_Icon_Gem_01` and the thin
  drawn arrows its chunky `SM_Icon_Arrow_03`. They are drawn by
  `SpaceRun._draw_swatch` and `_draw_arrow`, so every pattern takes them: the
  rule, SPOT's dots, MEMORY's rounds (a flown colour is a dimmed gem) and
  ARROW_SUM's pair.
- `tools/build_icon_kit.gd` renders them into `assets/polygon_icons/`
  (gitignored). The pack comes as a Godot project, so the tool runs inside it
  and not headless: `... --path <unzipped pack project> --script
  <repo>/tools/build_icon_kit.gd -- <repo>`, then `--import` here. The
  owner's copy is `POLYGON_Icons_Godot_4_6_2_v1_0_0.zip`.
- The gem and arrow are rendered grey and tinted in the game (`ICON_*_LIFT`),
  so one gem serves every gate colour. The arrow is turned as a textured quad rather than
  through `draw_set_transform`, which would replace the offset Main lays over
  the HUD while it slides in.
- MIX's no-entry sign stays drawn (`_draw_cross`). The pack's `Banned_01`
  was tried over the gem, and its thick ring hid the colour it crosses out.
- The pack has no bars, so the gauge stays the UI kit's.
- The stardust was this pack's for an hour or two on 2026-11-28 (its yellow
  sparkle, then its star mapped onto blue, and as a mesh); it comes from the Gems and
  Crystals pack now (below).
- An hour earlier the same day, the pack's icons replaced the popups' white
  ones and were turned down (see the popups).
- Without the kit the old ball and arrow are drawn. A release must be
  exported from a machine that has all four kits.

**The stardust is a faceted gem star from Aztech Games' Gems and Crystals**
(Unity Asset Store; 2026-11-28, owner), under the same rule: paid, never
committed.

- `tools/build_gem_kit.gd` reads `Meshes/Crystal_3.fbx` straight out of the
  pack (`FBXDocument`). The pack sits in a Unity project; the owner's is under
  `C:/Unity Project/My project (2)/Assets/Aztech Games/GemsAndCrystals`.
- It writes `assets/aztech_gems/` (gitignored):
  - `star_mesh.res`, the geometry with its node's place baked in;
  - `stardust.png`, the star rendered front on and mapped onto pink-violet by
    brightness (`TINT_DARK`..`TINT_LIGHT`), squared first (`FACET_CONTRAST`):
    its faces are lit evenly from the front, and a straight mapping left it
    nearly white.
- Not headless: `... --path . --script res://tools/build_gem_kit.gd --
  <GemsAndCrystals dir>`, then `--import`.
- Every screen takes the icon from `ArtSlot.stardust_icon_path()`: the menu's
  bar, the HUD counter, the game over's row. The motes flying to the counter
  are the mesh in 3D (`SpaceRun._dust_star`), in the game's own pink
  (`DUST_STAR_*`). The pack's material, Unity's white metallic Standard, does
  not come along.
- Without the pack the stardust is the UI kit's `Currency_01`, tinted the same
  pink by `build_ui_kit`, flat, motes included.
- **Pink-violet is the stardust's colour** (2026-11-28, owner): the gem, the
  motes, and the counters' numbers (`ModeSelectScreen.STARDUST_COLOR`, which
  the HUD shares). Blue, the first, and a white crystal with a rainbow sheen
  were compared in the game. Blue is one of the four gate colours and sank
  among the cyan bullets, engines and gate glow; the white read as a plain
  white star when small and sank among the streaks. Pink is the one colour on
  screen that means stardust.
- How it got here, the same day: the UI kit's currency icon; POLYGON Icons'
  yellow sparkle; its star in blue, as a mesh too; then this star, at the
  owner's pick. A gold star was passed over because the game over's BEST
  header wears one, and the question box's gem because it means "this
  colour". `Crystal_5`, a six-point stellated gem, is the other star in the
  pack.
- A release must be exported from a machine that has all five kits, and the
  Binbun explosion pack (`build_vfx_kit.gd`) for the fever's bursts.

**Stage backgrounds, debug only for now** (2026-11-28, owner). The owner plans
to warp the run between places after a pattern and its fever, and to reuse
those places as BATTLE's stages. The candidates can be flown in the game today:

- Pick one with `debug_stage` on Main, or press **B** in a debug build to step
  to the next one where you are. The stage's name shows on the plain banner.
- The stages are SPACE, then the pack's other three skyboxes (SKY_02..04,
  each tinted), the ship's two-storey HALL, the open TRENCH, and CITY,
  a cyberpunk street at a dark purple night: the towers' walls dark so the
  neon signs, billboards and their own lit strips carry the light, window-lit
  towers behind as the skyline, a wet road. Its sky shows only in the gap
  between the towers, mostly under the HUD, so what is in the gap carries it
  (2026-11-28, owner, from four tried): a ringed giant planet in the middle,
  searchlights swaying across it, and small soft twinkling stars
  (`_city_sky`, `animate`). A brighter picture hardly showed, clouds read as
  pink lumps, a flat planet sprite off to the left was mostly behind the
  towers, and cruisers drifting across flew through the towers. Purple against teal
  (owner): two of three window colours teal, a bluer fog; navy, and teal
  with orange, were compared. A tall tower
  breaks into the low front row now and then (`FRONT_TALL_CHANCE`), never two
  running: low ones all along read as the same few repeated.
  On 2026-11-28 it went from near-black towers in dense magenta fog (gloomy)
  to a bright purple-pink night after the pack's promotional shot (too
  bright) to a darker one with stronger neon (too dark), and settled
  between, each the owner's call.
- Turned down along the way:
  - a one-storey corridor, whose ceiling hid the screen;
  - two other city places (towers falling into haze over rivers of traffic
    light, and a night market), cut the same day when the owner tidied the
    city down to its street;
  - hover cars on the road and in the sky, taken out with them for now.
- In the city the run turns a corner after a pattern's fever, before the
  next pattern (2026-11-28, owner: to show flying between the towers and
  swinging round a corner). `StageScenery.begin_turn` ends the street at a
  junction ahead (a cross street opening to a random side, a wall of towers
  ahead, the other side closed), and when it reaches the ship the scenery
  stops scrolling and swings 90 degrees about a point `TURN_RADIUS` to that
  side, so the ship is carried round a quarter circle while the camera banks
  (`bank`, `TURN_*`). The cross street's segments then become the loop and the
  old street flies off behind. `SpaceRun._after_fever(true)` starts it and
  holds the next pattern (`turn_wait`) until `turn_finished`. Not before the
  boss, and not on other stages. At fever speed the arc took 0.6 s, too quick
  to see, so it takes at least a second.
- In the city, FEVER smashes holographic food signs instead of planets
  (2026-11-28, owner): noodles, burgers, pizza and bottles with their glowing
  outlines, in pink or teal, turning like a shop display (`FEVER_HOLOGRAMS`,
  `HOLO_*`). They wear `assets/shaders/hologram.gdshader`: the picture half
  greyed and tinted, scanlines rolling up, an edge glow, now and then a dim
  flicker or a band jumping sideways, each on its own beat (an instance
  `seed`). Smashed, one breaks into light, not rock or fire
  (`SpaceRun._neon_burst`, `NEON_*`): a ring and bright slices flying off
  sideways like a signal tearing; the Binbun explosion is skipped for it.
  They are 1.35 a planet across (`STAGE_TARGET_SIZE`; 1.1 read small). A stage offers its targets through
  `StageScenery.fever_targets()` as {mesh, scale, palette, spin}, and
  `SpaceRun._make_stage_target` builds one in a planet's dictionary, so it is
  hit, smashed and paid for the same way. Tried first the same day: hover cars
  and taxis, which hung at odd angles and read as wreckage (and smashing a
  taxi sat oddly), then the pack's security drones.
- The same `@export` trap as the other switches: `check_tutorial` fails while
  it is on.

How it is built:

- `scripts/StageScenery.gd` builds a stage as segments along z under one node.
  `SpaceRun` scrolls them with the world (`scenery.scroll`), and the one that
  has passed the camera goes round to the far end.
- A stage sets the sky texture, its tint and the glow outside FEVER
  (`sky_tint`, `env_glow`, which the fever mood eases from), plus the fog and
  the ambient light. It also says whether the open-space streaks and the sky
  show.
- Nothing in it touches the run's rules.

The kit:

- `tools/build_stage_kit.gd` (headless) reads both zips directly and writes
  `assets/stage_kit/` (gitignored):
  `... --headless --path . --script res://tools/build_stage_kit.gd --
  <POLYGON_Scifi_Space_SourceFiles_v2.zip> <POLYGON_SciFi_City_Godot_4_6_2_v1_0_2.zip>`,
  then `--import`.
- It takes the Space pack's interior FBX pieces, its planet ring, baked to plain
  meshes, and three skybox faces. It takes the City pack's towers, road, signs, streetlights and
  holographic food signs, re-saved with their materials cleared. One material per kind
  is laid over them in the game.
- It prints "can't open texture" errors for the FBX files' own texture links;
  those are expected and harmless.
- Without the kit every stage falls back to SPACE.

Not done yet:

- the warp itself and placing stages in a run;
- road reflections (the mobile renderer has no SSR, so the light pools show as
  dots);
- some billboards show white;
- a phone performance check. The city is heavy, with dozens of meshes and a
  few lights in every 40 m.

**The title screen is built from the same kit** (2026-11-27). It follows the
pack's own promotional banner, turned for a portrait screen; the banner
image itself is Synty's branding and is not used. The live space world
(still ticking behind the title) is dimmed to a deep blue, and a band of
blue light crosses it. "WARP" and "GATE" sit either side of a gold star
(`Crest_Star_01_Gold`) on a wreath (`Crest_Wreath_02`), in **Zen Dots**, the
pack's rounded tech face. The thin angled bar `Bar_11_Bottom` (picked on 2026-11-27 over `Bar_02` and `Bar_09`) runs under
them, with QUIZ RUN in gold beneath. The screen leads with WARP GATE
(option A, 2026-11-27), because a Korean player reads "런" as running, and
the ship does not run; QuizRun stays the store name. Zen Dots is SIL OFL and could be
committed, but it travels with the kit and its licence is copied beside it.
The words stay English, like all title art.

- The glow behind the crest is drawn as rings. The pack's glow sprite is
  meant to be added on, and laid on normally it showed as a square.
- The 1.x splash painting, its separate wordmark and the three flying
  characters are gone.

The first draw of these came out as white boxes. A texture `load()`ed inside
`_draw` and kept by nothing is freed when the draw returns, and the canvas
draws white where it was. `ArtSlot.texture` therefore keeps every texture it
hands out.

Synty paints its planets with a custom shader that glTF cannot carry.
`assets/shaders/planet.gdshader` rebuilds the look from the pack's land and
cloud masks with a sea/ground colour pair per planet, so six meshes make
many worlds.

The backdrop is the skybox's front face, which was painted to meet its
neighbouring cube faces rather than itself. Scrolled down as the ship flies,
its top edge came into view as a hard line across the screen.
`assets/shaders/space_sky.gdshader` cross-fades the picture with itself
shifted by half a height, so neither seam is ever shown. It is done in the
shader rather than in `sky.png` so that a kit built on another machine needs
no rebuild.

`check_space.gd` guards the rules and the framing. `capture_space.gd` shoots
one frame of each step of the cycle. `capture_space_wave.gd` shoots one
wave as a strip, from appearing to flying past, with the pattern, its
level, the number of gates and the ship's route chosen on the command
line. Use it for anything about how a wave looks.
`capture_pattern_bank.gd` shoots every pattern in the bank at every level
on one sheet, a row a pattern and a column a level.

**Modes and meta progression, decided 2026-11-27.** Only the menu is built
so far: `ModeSelectScreen.gd` was rewritten the same day (see its header for
the layout) and shows BATTLE, DAILY, the hangar and the upgrades locked as
COMING SOON. Everything this file says about the 1.x mode cards — four of
them, the MIX lock and its veil, the green check, the card characters — is
history.

The selected card shows it **on its face, not around it** (owner's call,
2026-11-27). The kit bakes a second frame, `card_frame_on.png`, whose face
is a see-through cyan gradient, and the menu draws scanlines and a band of
light sweeping down it (`_draw_card_face`), so the menu redraws every frame
while it is up. A locked card loses its dark veil while it is selected, or
All of the menu's faces share one blue at four brightnesses (`build_ui_kit`
`FACE_*`, `BAR_FACE_*`, `CARD_FACE_*`, 2026-11-28, owner): the icon buttons
and pause brightest, the explain line and stardust readout a step darker,
the idle cards darker still, the selected card its own lit cyan-blue. The
buttons had been teal and the bars navy, and the screen looked pieced
together. the lit face would go dark under it. The explain bar is the slim silver
`Frame_Box_Small_02` with a blue face, its right slot panel mirrored onto the
left (`explain_bar.png`, `MIRROR_RIGHT`; 2026-11-28, owner, after the pack's
Label_Button sample). Its ends are taken from just before the window's
chamfered corners (0.40 of the frame), so only plain rails and face are
stretched; cut at 0.30, the chamfers stretched and the border looked broken. It was `Button_Frame_05`, then for a moment the popups'
blue bar, which was not the sample. It holds one line and
shrinks its font to fit (`_fit_explain`); the "(COMING SOON)" it used to add
after a locked mode's line ran BATTLE's sentence out of the bar.

**The menu slides in and out over the live world** (2026-11-28, owner's
idea). The menu's background is the game's own screen, so instead of a cut:

- **Arriving.** Each time the menu comes up (after the title's tap, and on
  HOME from a run; `play_enter`, called from Main's `_set_state`), its blocks
  come in from the screen's edges one after another and land with a small
  overshoot. The top bar and emblem drop from the top, the cards and the
  explain bar come in from the sides, and PLAY, the tool row and Remove Ads
  rise from the bottom. Each block's edge and delay are in `SLIDES`.
- **Leaving.** On PLAY, once its flash is done (`PLAY_LAUNCH_TIME`), the
  blocks go back out, the lower ones first. `start_pressed` is sent only when
  the last has gone, so the run starts on an empty screen. The world's dimming
  fades with the slide (`_dim_share`).
- **The layout stays put.** `_r` never moves: `_slid_rects` lays the offsets
  over it for drawing, and `_sync_slide` moves the buttons to match. A
  full-screen `_blocker` takes taps while anything moves.
- **The run's HUD then slides in** (Main, `HUD_IN_*`, `_hud_in_offsets`). The
  score, question row, hearts and gauge drop from the top, and the weapon
  readout comes from the right a beat later (`SpaceRun.draw_weapon_hud`,
  split out of `draw_hud` for this). Only the drawn place moves; the rect
  helpers the tutorial and the checkers read still answer with where the HUD
  rests.
  - The pause button and the score-fill canvas are nodes, so `_process`
    moves them by the same offset.
  - `_start_countdown` starts the slide only when the run is not already in
    COUNTDOWN. A run started after the tutorial therefore does not slide its
    HUD in a second time.

| Mode | What it is | Currency |
|---|---|---|
| **QUIZ RUN**, the main mode | The game as it is: gate patterns, the weapon growing with the streak | The **only** source of currency |
| **BATTLE** | No quiz. The ship the player has upgraded fights enemies and bosses: a plain shooter | None |
| **DAILY** | One quiz run a day, the same for everyone | A once-a-day bonus |

Boss rush was considered and dropped.

- **Currency** is earned by answering, so the quiz is how the player grows
  and never becomes the side mode. A shooter-only mode that paid out would
  let players skip the quiz, which is the game's identity and its title.
- **Upgrades** apply in full in BATTLE and only slightly in QUIZ RUN (health
  and base attack), so growth is felt in the main mode too. QUIZ RUN's
  weapons still come from the streak alone.
- **DAILY uses no upgrades**, so its board ranks skill.
- The mode select shows **three cards**: QUIZ RUN large, BATTLE and DAILY
  smaller beneath it.
- Still to come: the hangar (Synty ships to collect), the upgrade shop, and
  more weapons; three is a short ladder for a streak to climb.

**The play-screen HUD, as laid out on 2026-11-26**, is meant to be redrawn
around these slots:

- The top row is the pause button, then the score, bare and centred on the
  screen (2026-11-28, owner), in Zen Dots like the game over's big numbers
  (`DIGIT_*` were measured again for it). The NEW BEST! banner is Zen Dots
  too (`space_banner_title`); its Korean line stays in the base font, since
  Zen Dots has no Hangul. It was a framed bar, SCORE on the left and the
  best on the right; the owner chose this over keeping the bar with SCORE
  alone. The stored best sat unchanged all run, and it is already on the mode
  select's card and the game over. During a run it appears only once, as a
  NEW BEST! banner at the moment it is beaten (`_check_new_best`, in the
  power-up banner's place). A mode with no record gets no banner. The row
  keeps the bar's scale (`SCORE_BOX_SRC`), so the pause button is the same
  size as before. A smaller pause, which let the question row rise about
  19 px, was tried and turned down as too small to press. With the bar gone,
  `SCORE_BOX_TOP` went from 16 to 10. The question row's place follows the
  top line (`_score_line_rect`); the gate field, set by the camera, did not
  move.
  - Score and stardust are still near-duplicates: a right gate pays
    `SCORE_PER_COMBO` × combo points and `STARDUST_PER_GATE` × streak
    stardust, and the two break together. Merging them would touch the
    leaderboards and the upgrade economy, so it has been left for now.
- The top line also carries the stardust, bare (and the health, until it
  went to the bottom left the same day)
  (2026-11-28, owner):
  - **Health** is the lives row at the bottom left, in line with the weapon
    readout (2026-11-28, owner: "like the old shooting games"): one ship seen
    from above for each heart left, none for the lost (`_health_rect`,
    `heart_hud_rect`, `_draw_hearts`, `LIVES_*`). A lost one swells white and
    fades where it stood. The ship is Fighter_05 rendered top down by
    `tools/build_ship_icon.gd` into the gitignored kit (`ship_top.png`;
    without it, an arrowhead), drawn brighter than rendered and over a soft
    shadow: at 30 px and as rendered, its grey hull sank into the sky. It
    slides in from the left as the weapon readout does from the right. Before,
    it was three red cells right of the pause button, and before that a
    column left of the question box.
  - **The stardust** sits at the right end: the kit's icon, then the count in
    Zen Dots (`_stardust_rect`, `SpaceRun._draw_stardust_bare`). In the corner,
    apart from the score in the middle, it reads as currency rather than as a
    second score.
- The second row is the question box alone, the row's full width
  (`_quiz_box_rect` = `_quiz_row_rect`). From 2026-11-26 it was three framed
  slots, health | question box | stardust. Moving only the stardust up was
  tried: the box then grew to the right, and the swatch sat off the screen's
  middle, away from the gates and the ship. The row kept its position and
  height, so the gate zone under it did not move.
  - **The question box** draws the pattern's rule: a colour swatch, or the
    front step's arrow. In FEVER and at the boss it writes FEVER! or BOSS! in Zen
    Dots (2026-11-28, owner).
  - **The question** keeps its old font size, which comes from the row's
    width rather than the narrower box's.
- The gauge sits under the question box (`gauge_fill`). In a pattern it
  fills from the left with the right gates and the wrong ones eat in from
  the right in red, so the gap is the steps still to fly; a mark stands at
  `FEVER_MIN_RIGHT`, and the fill is dim blue short of it, cyan past it and
  gold while every step so far was right (`GAUGE_*`). The fill is a beam
  rather than a flat bar (`_draw_laser`, owner's ask). In FEVER it is the
  fever left, on the same scale, draining from where the pattern stopped;
  at the boss, its health. Until 2026-11-28 it showed the steps flown, and
  a fever always started it full whatever its length. The combo sits on the right
  under the row, and the weapon readout bottom right.

So nothing is drawn over the middle of the field where the gates fly. The
mute button is gone, because sound belongs in settings. A weapon step is
announced by a short banner under the gauge (`_space_powered_up`), on a
slim band of blue light with bright edges and turning holographic rings
(`_draw_power_banner`, `_draw_holo_band`; 2026-11-28, owner: the band was
GO!'s for an hour and was moved here); while the
roulette showed it in its slot, that banner was dropped as a duplicate.

**Nine 1.x checkers were deleted on 2026-11-26**, once the gate game was
gone from Main: `check_gate_reach`, `check_hearts`, `check_mix_mode`,
`check_hidden_unlock`, `check_collection`, `check_boost_hold`,
`check_speed_lines`, `check_popup_overlap` and `check_ambient_density`. Each
called a function the rework had removed. A checker that hits a script error
does not exit; it sits there until killed, so a full sweep cost 2.5 minutes
per dead checker. Hearts are now covered by `check_space`. The guard against
`debug_force_hidden_locked` being committed switched on moved to
`check_tutorial`. The rule used was: delete what can no longer run, keep
what still passes. `check_tutorial` was rewritten for the three space steps.
Once the 1.x art was deleted the same day, three more went:
`check_bg_layers` and `check_sparkle_pools` (no art left to check) and
`check_ocean_prompt`. The Stroop quiz it measured is unreachable in the
space game, and it failed only because the question box got narrower.

**The rest of the 1.x code went on 2026-11-27**: about 2,800 lines of Main
(the flap physics and gate tables, the boost, backgrounds, particles,
trails and sparkles, the character sheets, the three quizzes, MIX's unlock,
the collection book and `CollectionPopup.gd`, the old ready and game over
panels in `Main.tscn`), the country-name translations, the Stroop and
collection rows of `ui.csv`, and the flap and boost sounds. With them went
`check_boost_bar_range` (its table was gone) and `check_unicorn_assets`
(DREAM's art was deleted the day before), the MIX-unlock and collection
assertions in `check_analytics`, the `debug_force_hidden_locked` guard in
`check_tutorial`, and every capture script that drove the gate game (see
*Screenshots of the running game*).

**A run has `MAX_HEARTS` (3) hearts.** In 1.x one miss ended the run; the
first 28 days of analytics showed about eight runs per player and roughly 12%
coming back the next day, and testers kept calling it too hard — the flap and
the quiz both had to be right, every gate. Now a wrong gate, the wall or the
floor takes one heart (`_take_hit`) and the run goes on; losing the last one
is the old death, so the revive offer and game over flow are unchanged. A hit
breaks the combo, so a mistake still costs points.

Two details carry the fairness. After a gate hit, `_take_gate_hit` moves
`last_zone_center` to where the character really is, because the next gate is
spawned in the same frame and its reach is planned from that value — left at
the correct hole's centre, the next gate could be out of reach from the wrong
lane and cost a second heart. And for `HURT_INVULN_DURATION` after a hit the
floor only bounces the character (the character blinks); gates are still
judged, since each asks its own question. A revive refills the hearts.

**The first gates are drawn with a bigger hole**, because the one thing the
closed test said over and over was that the game is too hard to start. The
hole is `gate_hole_start_scale` (1.20x) for the first `gate_hole_hold_gates`
(10) gates and eases back to its real size by `gate_hole_full_size_gate`
(30) — about 1% a gate, which is under the noise of one run. Nothing else
moves: the ring art, the frame overhang and the judged zone all take the
same multiplier, so the hole the player sees is the hole that judges them.
1.20x buys 98.5px of clearance for a 50px hitbox against the full-size
73.8px; the lane bands have slack to spare even at 1.4x, so the ceiling
here is difficulty, not geometry.

The multiplier is **carried on the gate** (`hole_scale`), not recomputed
while drawing. A gate is spawned one whole gate ahead of being judged, so
recomputing from `gates_passed` at draw time would shrink a gate in mid-air
as the one before it scored.

Both of these are 1.x: the wall, the floor, `_take_gate_hit` and the bigger
early hole (`gate_hole_*`) went with the gate game. In the space game a heart
is lost only to an asteroid or a boss shot (`_space_hurt`), and a wrong gate
costs a weapon step and the combo instead; the blink after a hit still makes
the ship safe for `HURT_INVULN_DURATION`.

## Language

`assets/i18n/ui.csv` holds every translated string, `en` and `ko`, and Godot
builds the `.translation` files from it on import. Strings go through `tr()`
with **the English text as the key**, so a string with no row still renders
as itself and adding English copy needs no CSV edit. The locale follows the
device, so a Korean phone gets Korean with no setting to find — and a Korean
dev machine shows Korean in the editor, which is worth knowing before you
think something is broken.

Only part of the game is translated, deliberately: the mode names and their
blurbs, the leaderboard label, the tutorial, the pause and game over
popups, and the settings and about popups. **Words that live in painted art stay English** — START, READY,
OOPS, TRY AGAIN, SETTINGS, the logo — because translating them means redrawing
them. The popup
titles are drawn now (GAME OVER, SETTINGS, PAUSED as plain lettering), but in
Zen Dots, which has no Hangul, so they stay English too.

The 1.x quiz content was translated too — the eleven Stroop colour words
(an English `RED` in front of a Korean player is a shape, not a word, so the
Stroop trap never fires) and the 193 country names in a second file,
`countries.csv`. Both went with those quizzes on 2026-11-27. The space
game's questions are arrows, hands and sums, which need nothing.

**The gap this leaves is a string that never reaches `tr()`**, and it does not
look like a bug: `tr()` returns its key when there is no translation, so a
missed string is one tidy English line in the middle of a Korean screen. Four
were found by eye before `check_translations.gd` existed, and every one of
them took a value — `"Leaderboard kept your score at %s"`, `"%s to beat your
best"` — because the `tr()` had gone on the plain constants next to them and
the `%` line was built somewhere else entirely. The checker's list of
deliberate exceptions (`ENGLISH_ON_PURPOSE`, `LEAVE_ALONE`) is the record of
which words stay English and why; adding a string now forces that decision
instead of deferring it to whoever next reads the screen in Korean.

The play screen's HUD had English `SCORE` and `BEST` labels while the game
over said 점수. Both labels went with the score bar on 2026-11-28, and the
score is now a bare number. The mid-run NEW BEST! banner goes through `tr()`
(최고 기록 경신!).

People's names in the about popup are **not** translated. Transliterating a
name is rewriting it, and that is the owner's call, not the translator's.

`scripts/AppFont.gd` is where the fonts are decided, and every screen takes
its base font from there. The base is **Oxanium**, a squared sci-fi face with
a wght axis (200-800); it has no Hangul, so a Korean face, **Do Hyeon**, is
attached as its `fallbacks` — one chain on one base font, because the weights
are `FontVariation`s over it and they look glyphs up through `base_font`.
Titles, buttons and short labels are Zen Dots instead (`TitleArt.font`; see
the popup notes above).

Both were picked on 2026-11-28, when the owner found the old pair, Fredoka
and Cafe24 Ssurround, too rounded and soft beside Zen Dots. Oxanium with
Orbit and Oxanium with Do Hyeon were tried in the real popups side by side;
Orbit, a geometric Korean face with a single 400 weight, went thin in the
Korean buttons and the "신기록!" banner. Both fonts are SIL OFL, downloaded
from Google Fonts' repository (`ofl/oxanium`, `ofl/dohyeon`).

If the Korean file goes missing the game still runs and Hangul still renders
— from whatever the device provides, which is a plain gothic and differs per
phone. Boot says so once.

Both font licences live in `licenses/`, behind a `.gdignore` like `store/`.
They are redistribution terms, not something the game opens. Keeping licences
out of `assets/` is the rule here: put the paperwork in `licenses/`, and only
what the game loads under `assets/`.

Changing that font moves every text measurement, so the fit checks — the
explain bar, card names, tutorial captions — are what to re-run afterwards,
and the glyph metrics measured off the font in Main (`DIGIT_*`,
`QUIZ_TEXT_BASELINE_FROM_CENTER_FRAC`) have to be measured again: render the
string into an off-screen `SubViewport` at a known baseline and read the ink
rows back (a draw on the root viewport is scaled by the window stretch).

## Verifying changes

There is no test suite, and the game cannot be played from the terminal.
What *is* available is a headless Godot, and it catches most regressions.
Set the editor path once per machine (it is not in the repo):

```bash
GODOT="/c/Users/<you>/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe"
```

Run these after touching GDScript or assets:

```bash
"$GODOT" --headless --path . --check-only --script res://scripts/Main.gd
```

```bash
"$GODOT" --headless --path . --quit-after 300
```

```bash
"$GODOT" --headless --path . --import --quit
```

The first is a parse check, the second boots the real game for ~5s and
surfaces runtime errors, the third regenerates `.import` sidecars after
adding or re-cutting art. `--quit-after` only reaches the logo/splash
screens, so it does not exercise `_apply_mode` or gameplay — that is what
the checkers below are for.

**Always report honestly what was and was not verified.** Headless cannot
see the screen: layout, colour, blur strength, and "does this feel right"
all need the user to play it.

### Checkers

`tools/check_*.gd` are headless simulations that guard invariants a parse
check cannot. Run them with `--script`, same as above. Each exits non-zero
on failure.

| Script | Guards | Re-run when |
|---|---|---|
| `check_ad_policy.gd` | interstitials never fire during the post-install free games, then fire on exactly the configured cycle; runs whose x2 ad was watched do not count toward it (and do not stall it either); the counter survives a relaunch; and all four ways of leaving a run increment it | `interstitial_every_restarts`, `interstitial_free_games`, `_ad_note_run_left`, `should_show_interstitial`, `_reset_game`/`_start_countdown`, or a new path out of a run |
| `check_ad_ids.gd` | both builds, asked separately because the checker itself is always a debug build: a debug build serves only Google's demo units whatever `FORCE_TEST_ADS` says, and its ad node has every real field empty; a release build serves the demo units while the flag is on and, with it off, exactly the three `AdIds.LIVE_*` values and nothing in the formats the game does not use, the banner included; the live IDs are well-formed (app ID with `~`, units with `/`) and all from one account; the test units still match Google's published values; `android_export.cfg` exists with all three keys, keeps the test app ID in `[Debug]`, and has `is_real` and `[Release]` agreeing with the flag; and no scene contains an `Admob` node for the plugin to fall back to | `AdIds` — any constant, `use_test_ads_in`, or `FORCE_TEST_ADS`; `android_export.cfg`; `Ads.make_admob_node`; or an update of the AdMob plugin |
| `check_ads_wiring.gd` | with a fake plugin feeding the results: the game over's x2 shows a rewarded ad and grants the run's stardust again only when watched to the end (and marks the run so it skips the interstitial count), once a run, grants nothing and keeps the button when closed early, grants nothing and reads AD NOT READY with no ad or a failed one, grants at once with ads removed, and on a PC debug build grants at once; a due interstitial holds the countdown until it closes and resets the counter only then, while one that is not ready or fails to show leaves the counter due and the countdown free; sound is muted for a full-screen ad and restored; no banner is ever requested (there has been none since 2026-11-27); and the consent gate: Google is asked before the SDK starts, the form shows only when consent is required and the SDK starts once it closes, a missing form or a failed lookup still starts ads, the SDK never starts twice, and settings' Ad Privacy Choices link is lit only where consent was asked and brings the form back | `Ads.gd`, `_on_double_stardust_pressed`/`_on_double_ad_finished`/`_grant_double_stardust`, `_ad_try_interstitial`/`_on_interstitial_finished`, `ad_hold_countdown`/`_update_countdown`, `_on_ads_fullscreen`, `_begin_consent`/`_on_consent_*`/`_start_sdk`, `privacy_options_available`/`show_privacy_options`, or `SettingsPopup.set_ad_privacy_available` |
| `check_mode_select_layout.gd` | the 2.0 mode select (2026-11-27): the stretch aspect is `keep_width`, so a tablet held upright keeps the 480-wide viewport with bars beside it; and across seven ratios, each viewport derived from that setting, with and without a banner: no two blocks overlap (top bar, emblem, the three cards, explain bar, PLAY, the tool row with its labels, Remove Ads), nothing leaves the screen or runs under the banner, and a requested banner is reserved **whole** or refused — 16:9 refuses, 18:9 and up take it | `ModeSelectScreen` layout constants (`*_H`, `CARD_GAP`, `FLEX_GAPS`, `MIN_GAP`/`MAX_GAP`, `BANNER_MIN_GAP_PX`), `_layout`, a block added to the menu, or `display/window/stretch/aspect` |
| `check_tutorial.gd` | the tutorial runs on the first entry to the play screen and holds the run **and the countdown clock** while it does; at 16:9 and 20:9 every step highlights a real widget rect and the caption never lands on one; the last tap starts the run; it never runs again — other modes included, relaunch included; and `debug_replay_tutorial` brings it back without writing "seen" to the save; and `debug_replay_tutorial` is not on in the shipped scene | `tutorial_seen`/`tutorial_active`/`debug_replay_tutorial`, `_begin_tutorial`/`_tutorial_steps`/`_on_tutorial_finished`, `TutorialOverlay`'s card placement, or `_quiz_box_rect` or `SpaceRun.ship_screen_rect`/`gauge_rect`/`weapon_label_rect` |
| `check_space.gd` | a run starts with full hearts on a colour pattern; every pattern in `BANK` at every level puts out its gates and the right gates its rule asks for (COLOR's colour changing exactly every `switch` steps, MIX's avoid steps and only MIX's, SPOT's one mismatched dot, MEMORY's rounds in order with no colour twice in a row, the arrow's slot, ARROW_MIX's avoid steps, ARROW_SUM's arrows adding up to the corner worked out from where it stands, ARROW_MEMORY's rounds with a diagonal only on a grid step); every step stands in the layout its level asks for, and in both layouts each slot lies in its own quarter; the top MEMORY level's round stays up `MEMORY_SECONDS_EACH` a colour before its first gate at full speed, then full speed again; each slot lies in its own quarter and no two gate rings touch, and every slot and field corner is on screen below the question box at 16:9 and 20:9; steps come exactly `STEP_GAP` apart with two or more in sight; the gate in the ship's quarter lights up, and a ship in the right quarter but off the hole is drawn into the right gate, which scores and pays stardust; an answer changed 60% of the way into the pull still counts, one changed after `CAPTURE_LOCK` does not; a streak pays more each gate, speeds the world up and every `POWER_EVERY` steps the weapon up; a wrong gate or a gate-less quarter breaks the streak and the combo and slows the world back down, costing no heart, weapon or stardust; no rocks fly between the steps, and an asteroid spawned by hand costs a heart on contact and scores when shot; a pattern holds the guns, a power-up fires a short volley, and FEVER opens them; at its fastest a step is still `STEP_FLOOR` (1.2 s) apart; FEVER is in proportion to the right gates of the pattern before it, 9 s for all twelve, none under six, and the gauge fills with the right gates, takes the wrong ones from its other end and drains from that level through the fever; a perfect pattern brings the next weapon and the whole FEVER (stardust per smash, no heart lost, then the next pattern), one with too few right goes straight on; after `PATTERNS_PER_CYCLE` patterns the boss comes, its shots cost a heart, and shooting it down scores, pays stardust and starts the next cycle with three gates a step; leaving a run banks its stardust into the saved total once; the last heart ends the run straight on the game over (there is no revive); a drag moves the ship by the finger's movement, ignores the emulated mouse twin, and stops at the field's edge | `SpaceRun.gd` (any constant, the phase machine, `spawn_wave`/`_make_step`, `_resolve_wave`, the streak and `_power_up`, asteroids, the boss, `handle_input`, `project`), the `_space_*` handlers and `_bank_stardust` in Main, `_reset_game`, the camera, or `_quiz_box_rect` |
| `check_language_toggle.gd` | the settings ENG/KOR toggle reaches `Main` at all, the chosen language is saved, every screen is **rebuilt** rather than just re-localed, the choice can be reversed, and a relaunch comes up in the saved language with the screens already built in it | `set_language_korean`/`_rebuild_for_language`/`_load_language`, `SettingsPopup`'s language row, any `rebuild()`, or the boot order in `_boot_load` change |
| `check_gameover_bgm.gd` | (skipped, passing, while there is no `gameover_bgm` — see *Asset pipeline*) the game over lays down `gameover_bgm` at `gameover_bgm_db` rather than silence, and every way out — PLAY AGAIN, HOME — comes back to the right track at full volume | `BGM_GAMEOVER_NAME`, `gameover_bgm_db`, `_play_gameover_bgm`, `_play_bgm`'s target volume, or where `_finish_run` touches the music |
| `check_button_sounds.gd` | all four popup gold buttons ask for the same cue and the file behind that name actually resolves, the cream buttons likewise, and the main screen's START keeps its own separate sound | `GOLD_SOUND_NAME`/`CREAM_SOUND_NAME`, `SFX_START_FILE`, a button changing art, or an audio file being renamed or removed |
| `check_popup_fit.gd` | nothing laid out inside a popup extends past the bottom of its panel, at 16:9 and 20:9, across the game over popup's four faces, each with and without the stardust row and its x2 button | a row is added to or removed from any popup, a `used`/`gap` sum changes, `panel_size_frac` changes, or a string gets long enough to wrap |
| `check_play_games.gd` | without the plugin, by feeding in the results it would send: a sign-in press on PC answers "failed" at once instead of waiting forever; the name arrives before the photo and the photo is taken only when *its* file lands; settings drops its LOGIN button once signed in and gives the space to the name; the mode select's person icon opens settings once signed in; losing the account on a relaunch undoes all of it; a double tap opens one sign-in window; a stale timeout cannot cut a live attempt and a lost answer cannot leave the button dead; each mode's stored best — not the run's score — goes to that mode's own leaderboard at run end and once when sign-in completes, skipping modes with no record, and a failed sign-in from the LEADERBOARD button opens nothing and leaves no waiting connection; and `debug_fake_sign_in` is off in the shipped scene | `PlayGames.gd`, `MODE_LEADERBOARD_ID`/`_submit_leaderboard`/`_show_leaderboard`, the leaderboard block in `_finish_run`, `_on_play_games_changed`/`_sign_in`/`_on_mode_select_login_pressed`, `SettingsPopup.set_account`, or `debug_fake_sign_in` |
| `check_store.gd` | with a fake BillingClient feeding Google Play's answers: the constants `Store` copied from the plugin's enums still match it; on PC the store is unavailable and the button grants nothing; on connect it asks for the product and the purchases, and will not open the sheet before the product details arrive; cancelled and pending purchases grant nothing; a completed one is **acknowledged** (or Google refunds it after three days) and removes the ads, and the save remembers it; afterwards no interstitial fires and its counter is untouched, the game over's x2 grants at once with no rewarded ad and no ad icon, settings shows a disabled ADS REMOVED and mode select hides its line; a relaunch reads it back, a failed query changes nothing, an unacknowledged purchase found by a query is acknowledged again, a purchase gone from the query (a refund) brings the ads and the line back, and "already owned" asks again | `Store.gd`, `REMOVE_ADS_PRODUCT_ID`, `_on_remove_ads_pressed`/`_on_store_ownership`/`_apply_ads_removed`, any `ads_removed` branch in Main, `SettingsPopup.set_ads_removed`, `GameOverPopup.set_stardust`, `ModeSelectScreen.set_ads_removed`, or an update of the billing plugin |
| `check_translations.gd` | every display string constant in the UI scripts has a row in `ui.csv` or a recorded reason to stay English, every use of a translated constant goes through `tr()`, no `ko` cell is empty, and no CSV row is orphaned | a string constant is added or reworded anywhere in `scripts/`, a row is added to `ui.csv`, or a string is deliberately left English |
| `check_score_format.gd` | `ScoreFormat.compact` never exceeds 5 characters anywhere in int32, matches the documented examples, and the HUD and mode-select cards actually route through it | `ScoreFormat`, `_score_digit_layout`, `_best_digit_layout`, `set_best_scores`, or the score box art/font sizes change |
| `check_analytics.gd` | with a fake Firebase: nothing is available or collected on PC; before any consent answer every signal is denied and collection is off, and events are dropped rather than queued; `NOT_REQUIRED` grants all four signals and turns collection on, once; `REQUIRED`, `OBTAINED` and `UNKNOWN` keep it off; and the game's own paths log the right events with the right values — `level_start` with the mode, `post_score` with score, gates and combo, the x2's `double_stardust` results, and both tutorial ends | `Analytics.gd`, `_log_event` or any call to it, `_on_ads_consent_changed`, `_start_countdown`/`_finish_run`, the x2 handlers, or `_begin_tutorial`/`_on_tutorial_finished` |

**A checker that plays real gates writes to the real save file.** `user://
savegame.cfg` holds the best scores, the tutorial flag and the ad counters,
and driving a run to `_finish_run` or `_reset_game` updates them on the
machine running the check. The checkers that drive runs therefore
back the whole file up and writes it
back at the end. Restoring a few chosen values is not enough — that was
tried, and a throwaway probe left this machine's SKY record sitting at the
checker's 12600 and its hidden mode unlocked without anyone having earned
it. Any new checker that runs gates copies that backup/restore pair.

Most of them instantiate the real `Main.tscn` and call its own functions
rather than re-deriving the maths, so they cannot drift from the game. Keep
it that way — if a checker needs a calculation, extract it from the draw
code and call it (as `check_tutorial` does with `_tutorial_steps`). A copy
of a table is exactly what passes while the game itself loads nothing.

Note: a headless viewport reports a **square** size, not 480x854. Read the
resolution from `ProjectSettings` instead, or a layout check passes by
being given far more room than the game has.

### Screenshots of the running game

Headless renders nothing — the dummy driver hands back a blank image — but
dropping `--headless` does not, so a script can drive the real game and save
what is actually on screen:

```bash
"$GODOT" --path . --script res://tools/capture_score_display.gd -- --out <dir>
```

`root.get_texture().get_image().save_png()` after `await
RenderingServer.frame_post_draw` is the whole trick; without that await you
save the previous frame. `capture_score_display.gd` is the worked example —
it sets a score, redraws, and shoots, once per digit count.

`capture_language_toggle.gd` shoots the mode select, settings, game
over and about screens in both languages, and drives the language switch
through `Main` rather than the popup so the rebuild path is the one being
photographed.

`capture_popups.gd` shoots every popup over the play screen in both
languages: pause, the game over with and without a record (with
the stardust row), settings and about. `--ratio 16x9` shoots the shortest
screen.

`capture_mode_select.gd` shoots four aspect ratios. That screen divides its
leftover height between blocks, so one ratio proves nothing about the others.

**Nine capture scripts drove the 1.x gate game and were deleted on
2026-11-27**: `capture_combo`, `capture_mix_mode`, `capture_ocean_quiz`,
`capture_gate_size`, `capture_hearts`, `capture_collection`, `capture_promo`,
`capture_store_screenshots` and `capture_feature_graphic`. Two techniques
from them are worth keeping for 2.0, and git has both:

- **Store screenshots** (`capture_store_screenshots`): a phone cannot take
  them — at 19.5:9 its screen is outside the 16:9 / 9:16 the store accepts —
  and the dev PC cannot open a 1080x1920 window on a 1440-tall monitor, so
  the game ran inside an off-screen `SubViewport` 1080 by 1920 whose
  `size_2d_override` told it the screen was 480x854: the layout is the
  game's own, drawn at 2.25x.
- **Promo video** (`capture_promo`): Godot's **Movie Maker**
  (`--write-movie <dir>/f.png --fixed-fps 60`) writes lossless frames plus a
  `.wav` at a fixed timestep, so the video is frame-exact at 60fps however
  slowly the PC renders. The editor binary carries the `.editor` window
  override (480x1067), which `--resolution` does not beat, so a 1080x1920
  recording needs a temporary `override.cfg` in the project root setting
  `window/size/window_width_override.editor=1080` and `..._height_...=1920` —
  delete it straight after.

Use this for anything where the question is "does it look right", and reach
for it before mocking a composite up separately. A hand-built preview of the
BOOST popup looked fine for two rounds while the real game was drawing
`TURBO!+600` with the space swallowed; one real capture found it.

## Architecture

`scripts/Main.gd` is ~3200 lines and deliberately monolithic: what it draws
is **custom-drawn** in one `_draw()` (and `draw_hud_into` for the HUD), not
built from nodes — the space world's frame, the answer plates, the combo,
the countdown and the title are `draw_*` calls over plain state. The 3D
world itself is `SpaceRun`'s, rendered in its own viewport.

Consequences worth knowing before editing:

- Anything visual is a `_draw_*` function plus a `_update_*` and some state.
  Features are self-contained in that trio and are documented as such in
  block comments ("Whole feature = these consts + ... Delete those to remove
  it").
- `Mode` still indexes the per-mode best scores, their save keys and
  `MODE_LEADERBOARD_ID` (and `MODE_BGM_NAME`); the per-mode art arrays went
  with 1.x. Adding a mode means extending those.
- `_apply_mode(mode)` sets the mode and loads the play screen's art. It runs
  in `_boot_load` and every time a run is started from the mode select.
- `_boot_load()` does the heavy loading *after* the logo fades in, not in
  `_ready`. A headless run that only survives a few frames will not have
  reached it.

**A three-step tutorial runs once per install**, on the first entry to the
play screen in any mode. `TutorialOverlay` dims the game and opens one hole
at a time — the ship, then the quiz box, then the progress gauge and the
weapon readout together — with a caption beside each.

It runs on the play screen rather than in a menu because every one of those
sentences is about *that thing on that screen*; shown as a picture in a menu,
the player still has to find the real one afterwards.

The game is held in `State.COUNTDOWN` throughout: the one state that draws
the world without running the run's rules. `tutorial_active` freezes its
clock and folds away the READY/GO! words. Main hands the overlay the rects,
read from the same helpers that place the real widgets, so moving the HUD
cannot leave a highlight behind on empty background.

**To watch the tutorial again**, tick `debug_replay_tutorial` on Main in the
inspector; it runs on every entry until you untick it, and a run forced that
way does not write "seen" to the save, so turning it off leaves the machine
where it was. It is an `@export`, so ticking it writes into `Main.tscn`, and
shipping that would make everyone sit through the tutorial every single run,
so `check_tutorial.gd` fails while it is on.

Other scripts: `PopupBase.gd` is the shared popup chrome (pause / revive /
game over / settings / about all extend it). `HudCanvas.gd` is a 34-line
node that exists **only** to give the HUD a different texture filter from
the world — the drawing logic still lives in `Main.gd` (`draw_hud_into`).
`ScoreFormat.gd` is a `class_name` with one static function, and exists
because the same score is drawn by `Main.gd` and by `ModeSelectScreen.gd`
with no node relationship between them; a private copy in each is exactly
how the two drift apart.

A score is shown in two registers, and the register is a property of the
**slot**, not of the number. Narrow slots — the HUD's SCORE and BEST, the
mode-select card plates — hold five characters, and go through
`ScoreFormat.compact` (`1250`, `123K`, `1.2M`, and never zero-padded). The
game-over popup has room, so it shows the whole number with thousands
separators via `PopupBase._group` instead. Abbreviating is what you do when
the space runs out, not a house style — do not spread it to slots that can
fit the real number.

## Asset pipeline

**All 1.x art was deleted on 2026-11-26, and every screen draws
placeholders.** The title screens, mode select, play-screen HUD and popups
are all being redrawn for 2.0. That is 400 images, counting flags,
backgrounds, characters, gates, effects and references. Only the launcher
icons (`assets/ui_assets/icon/`) and the Synty kit are left, plus the JANIJU
STUDIO logo (`ui_assets/title/logo.png`). The logo went with the rest and was
restored the next day at the owner's request: it is the studio's mark, not
1.x art, and it opens every launch and the About popup. Every load of
a screen image goes through `scripts/ArtSlot.gd`. A file that exists is used
as before; a missing one comes back as a placeholder at the size the old art
had, so layouts that size themselves off their art keep their proportions:

- Pictures (logo, characters, icons) get a blue-grey box with an X.
- Art stretched into a panel, button or bar gets a solid grey frame
  (`ArtSlot.FRAMES`). An X across a popup ran through all its text, and a
  see-through panel let the screen behind show through the words.

The path constants in Main, ModeSelectScreen and the popups are therefore
slots. New art dropped at one of those paths shows up with no code change.
Art at a new path or size needs its loader pointed there; delete the slot's
row in `ArtSlot.SIZES` once nothing should fall back to it.

The slicers and blur/bake tools that cut the deleted sheets went with them
(`slice_*`, `blur_background.ps1`, `bake_speed_line.ps1`,
`fit_gate_ring.ps1`, `validate_flags_data.ps1`). `bake_popup_art.gd` stays:
it bakes whatever popup art is in `ui_assets/popup/`, and its index and
output were deleted with the art. Without a bake the popups cut their art at
runtime, as they always could. `build_app_icon.ps1` also stays, but its
character sprites are gone, so the launcher icons can only be rebuilt from
git history or new art. Much of what follows describes the 1.x art and its
tools; it is history until new art arrives.

The code that loaded the rest of the 1.x art without a slot — the 2D gate
rings, backgrounds, ambient particles and the tap sparkles — was removed on
2026-11-27. The sparkles were last drawn as the combo burst, so a combo now
only punches and shakes until it gets new art or a drawn effect.

Art arrives as a **sheet**, is cut by a script in `tools/`, and both the
sheet and the cut pieces are committed. Never hand-edit a cut piece — change
the slicer's parameters and re-run, so the result is reproducible on another
machine.

```bash
powershell -ExecutionPolicy Bypass -File tools/slice_ambient_sheet.ps1 -Measure
```

Every slicer takes `-Measure` to report the detected layout without writing.
Use it first; the detection is alpha-band based, so a stray near-transparent
pixel can invent a row and shift the whole name mapping.

That detection assumes the sheet actually has alpha, and not every one does.
`icon_popup_2.png` renders as a checkerboard in an image viewer but is fully
opaque — the checker is the viewer's, drawn over a white background — so the
usual alpha bands find one icon spanning the sheet.
`slice_popup_icons_2.ps1` separates its icons by **saturation** instead and
generates the round cut-out from a fitted circle, because keying out
"everything near-white" would have eaten the white check mark inside the
green circle. Check what a sheet's alpha really is before assuming a slicer
can band it.

`tools/build_app_icon.ps1` produces the launcher icons from a character
sprite, and the three outputs differ by **who crops them**. An **adaptive**
icon is two 432x432 layers the launcher composites and then masks to whatever
shape it likes, and only the middle 66% survives that mask — art that fills
the canvas gets its edges eaten on a circular launcher, so the character is
fitted to 86% of a 264px safe circle. The **legacy** 192 and the **Play
Store** 512 are never masked, so they get their own composite at
`$FlatFill` (0.80 of the whole square) rather than being sized off the
adaptive canvas: built that way the character came out at 52% of the frame
and the store icon read as small and weak next to other listings. The store
file must be 32-bit PNG with no transparency and square corners, since Google
rounds it itself; it lives in `store/` behind a `.gdignore`, because it is a
listing asset and there is no reason to ship it inside the APK.

**The icon shows the character flying through its mode's gate**, the game's
signature. It uses the game's own depth trick: the ring is two halves
(`fit_gate_ring.ps1` cuts them), the right one drawn behind the character and
the left one in front, so the character reads as inside the ring rather than
pasted over it. The layout was chosen on 2026-09-12 from three candidates
rendered at launcher sizes under circle and rounded-square masks: the ring
filling the safe circle with the character in its hole (`$GateFill` 1.00,
`$GatedCharacterFill` 0.56 — the committed one), a larger character bursting
out of a smaller ring, and the ring blown up into the icon's rim. The price is
the character, at about half the size it had alone; the rim version looked
best at 192 and worst at 48, where its gold-and-white edge crowded the bird.

With the gate, the legacy and store icons are the same composition scaled by
`Store / Viewport` (the whole square standing in for the launcher's 72dp
viewport), so the store icon matches what a phone shows. The 86% and
`$FlatFill` figures above now describe `-NoGate` only. Every build prints how
far the drawing reaches from the centre against the 132px safe radius, and
warns once it passes it by a pixel or more. The committed ring's gem tips sit
exactly on the safe circle; the extra half pixel is anti-aliased fringe.

The build also writes the **monochrome layer** that Android 13+ uses for
themed icons, and `icon.png`, the project icon. Both were Godot's logo until
2026-09-12. With `launcher_icons/adaptive_monochrome_432x432` unset, the
export fills that layer with Godot's own, so a phone with themed icons on
showed a Godot robot on the home screen — found only by pulling the layer out
of a built APK, since nothing about the colour icon hints at it. The
monochrome keeps the ring but shrinks the bird (`$MonoCharacterFill` 0.42
against the colour icon's 0.56). A silhouette drops the red, the eye and the
beak, and at full size the bird fills the ring's hole, so the two melted into
one egg shape with a hairline through it; with sky between them the ring
reads as a ring. Four variants were compared tinted like a themed launcher —
the full-size bird with a 6px or a 14px gap, the small bird, the bird alone.
None reads as clearly as the colour icon; this is the one where the gate
survives.
The preset key points at it and, like every preset value, is recorded in the
release identity table. `icon.png` (256px, from the store composite) replaced
the default `icon.svg` as `application/config/icon`; it is the editor's
project-list icon and the desktop window icon, not the phone's.

The source is the in-game motion sheet, so `-Pose fly -Frame N` picks a cell
of that grid (`-Pose happy|sad` takes the single-frame faces instead).
Default is the bird's frame 2, the wings-up pose — chosen by rendering all
four as finished icons and looking at them at 48px, where the other three
read as a ball with a beak. Enlarging goes through an **integer
nearest-neighbour step before the final resample**: these are pixel art, and
a straight 1.7x bicubic turns every hard pixel edge into a gradient. Pass
`-Character dragon|shark|unicorn` to rebuild from a different mode's sprite,
and `-OutRoot <dir>` to write candidates somewhere other than the repo.

**The four mode cards are drawn, not cut.** `_draw_card_face` paints each one:
a rounded rectangle with a vertical gradient and a white border, all three
sized from `SELECT_CORNER_NATIVE` / `CARD_BORDER_NATIVE` against the card's
drawn width. They came from `modeselect_main.png` until the geometry started
to matter — the four hand-painted cards had slightly different corner radii
and border widths, and `CARD_HEIGHT_SCALE` stretched a bitmap vertically,
which turns a circular corner into an ellipse and left the lock veil's
rounded corners unable to line up with the card's at any radius. The source
sheet is kept in `assets/references/` (excluded from the export) and the
gradient colours in `CARD_FILL_TOP`/`BOTTOM` were sampled from it, so the
cards look the same and only the precision changed.

Godot has no rounded-rect-with-gradient draw call, so the face goes down in
two passes: one-pixel horizontal strips whose x-extent follows the corner
arc, then a `StyleBoxFlat` border on top. The strips have no anti-aliasing
and the StyleBox does, so the strips are tucked `CARD_FILL_TUCK_PX` under the
border and their stair-stepped edge never shows.

Music ships as **OGG** (`BGM_EXTENSIONS` resolves `.ogg` before `.wav`, so an
unconverted wav still plays and dropping the ogg beside it switches over).
Tracks arrive as wav and are converted once, at the 160k the existing tracks
use — `gameover_bgm.wav` was 15.3MB and is 1.3MB as ogg:

```bash
ffmpeg -i gameover_bgm.wav -c:a libvorbis -b:a 160k -ar 48000 assets/audio/gameover_bgm.ogg
```

The wavs are not committed; they are the raw export and nothing reads them.

**There is no music at the moment.** All six 1.x tracks were deleted on
2026-11-27, because 2.0's will be made new. The tracks were
`splash_main_bgm`, `gameover_bgm`, and `sky_`/`jungle_`/`ocean_`/`dream_bgm`.
The player code is untouched and plays nothing while they are missing:
`_resolve_audio` returns "", `_play_bgm` ignores that, and game over stops
the music. A new track dropped into `assets/audio/` under one of those names
(`BGM_MENU_NAME`, `BGM_GAMEOVER_NAME`, `MODE_BGM_NAME`) plays with no code
change. `check_gameover_bgm` reports "skipped" and passes until the game
over track exists. The sound effects were kept, except the 1.x flap and
boost sounds, which went with their code on 2026-11-27.

**Effects are baked into the files, not applied at runtime.** This project
has no blur shader in its custom-draw setup, so:

- Background softness is baked by `tools/blur_background.ps1`.
- Ambient particle blur is baked by `slice_ambient_sheet.ps1 -Sigma`.
- The boost speed-line strip is squashed to its drawn proportions by
  `tools/bake_speed_line.ps1`. No blur — that art arrives soft already (zero
  fully opaque pixels). What it does is premultiply before the resize,
  without which the black sitting in its transparent pixels averages into
  every streak.

When blurring or downscaling a cut-out, **premultiply alpha first**. Blurring
colour and alpha separately drags the transparent pixels' colour inward as a
dark fringe. `blur_background.ps1` takes a per-file `CutOut` flag for this:
`$false` blurs RGB only (correct for a full-bleed background, where there is
no alpha edge to soften), `$true` premultiplies, blurs all four channels,
then divides alpha back out.

**Far layers are blurred; near layers are barely touched.** That is depth of
field the way a camera does it, and it is deliberate — the pairs first
shipped the other way round, with the near layer as the softest thing on
screen, and it flattened the parallax, because softness is the main cue
telling the eye which layer is further away. Sigma is not comparable between
two paintings, only the sharpness it lands on: OCEAN's near layer takes 1.5
against its far layer's 1.0 purely because that art starts five times
busier. `$NearSigma` (0.5) is now only the floor — the kernel runs to
`ceil(3*sigma)`, so at 0.3 it collapses to a near-delta and does nothing at
all.

Matching every near/far **ratio** onto one number is what the metric alone
would do, and it was tried and rejected by looking at a screen. Only
JUNGLE (1.45) kept it; SKY needed more blur than the metric allowed and
OCEAN much less (2.64). SKY is therefore knowingly inverted, with the near
layer softer than the far, and gets its depth from occlusion and the 2.5x
speed split instead. It is listed in `$DepthInversionExpected` with its
reason; `-SelfTest` prints that as a note and still warns for any other mode
that inverts. DREAM used to be the second one, until its art was replaced
with a pair that orders properly (1.86).

The metric only counts pixels whose alpha is exactly 255. A cut-out from a
background-removal tool can arrive with its body at 253, which measures as
0 at every sigma — DREAM's near layer did. Check the alpha histogram of new
cut-out art before probing.

Blur strength is **measured, not eyeballed**. `blur_background.ps1
-Sharpness` reports the mean |Laplacian| over opaque RGB for every committed
blur, **measured after resampling to the 854px height the game draws it at**
— not on the source pixels. That distinction is load-bearing: SKY's far
layer is 1472x704 and gets magnified 1.21x, while every other layer is
1056 tall and minified to 0.81x, so the same sigma spreads 1.5x further on
one than the other. `-SelfTest` re-derives every file from its source and
diffs it against what is committed — anything but a residual around 1/255
means the sigma table and the PNGs have drifted apart. It also prints each
mode's near/far ratio and warns on any pair that has inverted. The table is
the only record of how each file was made, so keep it in step.

To pick a *new* sigma, use `-Probe -Mode <name>`: it reports the sharpness a
range of candidates would produce and writes nothing, so a value is chosen
from the measurement rather than by blurring, looking, and reverting.

The metric is a proxy, not a verdict: it averages over the whole image, so a
painting that is mostly flat with a few hard-outlined structures scores
softer than it looks. OCEAN's far layer is the one row where that was worth
overruling; the table says so.

Blur is not a fix for a background that **competes in shape** with gameplay.
SKY's far layer paints stone arches in the same white-and-gold-with-a-blue-gem
palette as the SKY gate ring; blurring it until the whole painting is softer
than anything else shipped still leaves an arch reading as an arch. Those
are art problems, not sigma problems.

### Texture filtering and mipmaps

Three different filters are in play:

- `project.godot` default is **Nearest** (`default_texture_filter=0`).
- `Main` overrides itself to **Linear with mipmaps** when
  `SMOOTH_WORLD_FILTER` is `true` (it is), so the whole world is linear.
- `HudCanvas` and the popups set Linear-with-mipmaps explicitly.

Mipmaps are **per-file import settings** (`mipmaps/generate` in the
`.png.import`), off by default. Linear filtering alone does not fix
minification aliasing — enable mipmaps for art that is drawn much smaller
than it was painted, then re-run `--import`.

But prefer **not needing them**: a mipmapped non-power-of-two texture drops a
fraction of a pixel at every level (687 -> 343 -> 171 ...), so a heavily
minified sub-region samples with its edge crept inward — which shows up as a
clipped border on 3-sliced UI. Cut UI art at the size it is drawn instead;
see `slice_boost_bar_sheet.ps1 -TrackHeight`, which must be re-run if
`BOOST_BAR_HEIGHT` changes.

## Conventions

- Comments explain **why**, not what, and are written in the voice of the
  surrounding code (this file mixes English and Korean — match whatever the
  block you are editing uses).
- Tunables are named `const`s or `@export`s at the top of their feature's
  block, with the reasoning for the value in the comment. Where a value was
  measured rather than guessed, the measurement is recorded — keep that up.
- Removing a feature means removing **all** of it: consts, state, update,
  draw, call sites, and the art. Dead code left behind has bitten this
  project before. Git has the removal if it needs to come back.
- Commit messages: imperative, sentence case, a short subject and a body
  explaining the reasoning. See `git log`.
- `git config user.*` is set **locally** in this repo, so it does not travel
  with a clone. On a new machine:
  ```bash
  git config --local user.name "kimmc1358-code"
  ```

## Android release identity

`export_presets.cfg` is **gitignored**, so the values below live in one
untracked file on one machine. They are written down here because two of
them cannot be changed after the first Play Store release, and rebuilding
the preset on another machine has to reproduce them exactly.

| | |
|---|---|
| Package name | `com.janiju.quizrundualgate` |
| Launcher label (`package/name`) | `QuizRun` |
| Launcher icons | `assets/ui_assets/icon/` — legacy 192, adaptive fore/back/monochrome 432 |
| Export filter | `all_resources` |
| Excluded | `assets/references/*`, `tools/*`, and 17 author-time source images listed below the table |
| Gradle build | **on** — the Play Games and AdMob plugins need it; the Android build template lives in the gitignored `/android/` |
| Play Games plugin | `addons/GodotPlayGameServices/` — godot-play-game-services v3.4.0 |
| Play Games Game ID | `554024495812` (preset option `godot_play_game_services/game_id`) |
| AdMob plugin | `addons/AdmobPlugin/` + `addons/GMPShared/` — godot-sdk-integrations/godot-admob v7.0 (`AdmobPlugin-Android-v7.0.zip`, sha256 `ce38b75a…93aee8`); gradle pulls `play-services-ads` 24.9.0 at build time |
| AdMob app ID | `ca-app-pub-6214282306800929~2199640508`, set in `addons/AdmobPlugin/android_export.cfg` (`[Release]`, `is_real = true`) and `AdIds.LIVE_APP_ID` — **not** the preset |
| Play Billing plugin | `addons/GodotGooglePlayBilling/` — godot-sdk-integrations/godot-google-play-billing 3.3.0 (sha256 `20d75623…b18568`); gradle pulls `billing-ktx` 9.1.0 |
| Firebase plugin | `addons/godotx_firebase/` + `android/firebase_core/`, `android/firebase_analytics/` — godot-x/firebase 3.1.0, Core and Analytics only; config in the gitignored `google-services.json` (project `quizrun-9a351`); needs the `build.gradle` lines in *Analytics* |
| In-app product | `remove_ads`, one-time, non-consumable — `Store.REMOVE_ADS_PRODUCT_ID`; must exist and be active in Play Console, and cannot be renamed once created |
| Export format | **AAB** (`gradle_build/export_format=1`) — Play accepts nothing else. The editor holds the preset in memory, so set it there too or an editor save puts APK back |
| Upload key | `C:\Users\user\keys\quizrun-upload.jks`, alias `quizrun`, PKCS12 — **outside the repo**, backed up separately. Its path and password live in `.godot/export_credentials.cfg` (gitignored), not in the preset. SHA-1 `5B:10:59:…` |
| App signing key | Held by Google (Play App Signing). SHA-1 `B4:41:DC:…`, read off the Play-installed APK — see *Where it stands* |

The game answers to three different names and they are not meant to match.
The **launcher label** is the one under the icon on the home screen, where
roughly ten characters survive before truncation — hence `QuizRun` rather
than the full title. The **Play Store title** is `QuizRun: Dual Gate`, set in
the Play Console and not in this repo at all. **2.0 is titled `QuizRun: Warp
Gate`** (decided 2026-11-27, after the warp gate the ship flies through). The
Play Console title changes when 2.0 ships. The feedback mail subject
already says Warp Gate. The **in-game title art** is its own
painted asset, still a placeholder.

`application/config/name` stays `QuizRunDualGate` on purpose. It also names
the `user://` folder, so changing it would start every player on an empty
save. Left empty, `package/name` falls back to
`application/config/name`, which is `QuizRunDualGate` — the Godot project
folder name leaking out as a product name.

**The package name is permanent once published.** It keys the Play Console
listing, every OAuth client, the GPGS configuration and the AdMob app
record; changing it later means recreating all four. It was
`com.kimmc1358.quizrundualgate` until the studio identity settled on
`janiju` — everything else already said JANIJU STUDIO.

`export_filter` must stay `all_resources`. The game builds asset paths at
runtime — the music by name, the menu and popup art, the Synty kits —
so nothing links them from a scene, and the scene-following export modes
drop them silently.

That is also why the **exclude filter** carries more than the two folders.
`all_resources` ships everything under `res://`, including the sources the
art tools read and the game never opens — 25.1MB of the bundle before
2026-10-06. Seventeen files are excluded by name, and this list is the only
copy that travels, since the preset does not:

- `assets/backgrounds/<world>/background_far.png` and `background_near.png`
  for all four worlds — the unblurred inputs of `blur_background.ps1`; the
  game draws the `_blur` files
- `assets/backgrounds/ambient_sheet.png`, `assets/fx/fx_small_N.png`,
  `assets/ui_assets/boost_bar_sheet.png`, `boost_button_sheet.png`,
  `hud_sheet_v7.png`, `ready_start_sheet_v2.png`, `ready_start_sheet_v3.png`
  — sheets the slicers cut
- `assets/gates/gate_ring_dream/gate_ring_dream.png` — `fit_gate_ring.ps1`'s
  source
- `assets/ui_assets/main/login_setting_button.png` — referenced by nothing

The list was proved, not guessed: with all seventeen moved out of the
project, none could be loaded even from the import cache, and the game still
booted and passed all 29 checkers. Searching scripts for file names is not
enough on its own here — paths are built at runtime, and several sheets are
named in comments. A new sheet or source image goes on this list in both
places. (`assets/fx/speed_lines/source/` needs nothing: its `.gdignore`
keeps it out of the project altogether.) Two non-art entries share the
filter: `google-services.json`, which the Firebase plugin copies into the
gradle build itself, and `addons/godotx_firebase/*`, the plugin's export-time
scripts.

### Version numbers

**`application/config/version` in `project.godot` is the only place the
version string is written.** The settings popup reads it at runtime, and the
APK's `versionName` inherits it because the preset's `version/name` is
deliberately left empty. Bumping the release therefore means editing one
tracked line.

It used to be two places — a `"Version 1.0.0"` literal in `SettingsPopup.gd`
alongside whatever the exporter defaulted to. They agreed by coincidence, and
nothing would have made them disagree loudly: ship 1.0.3 and the settings
screen keeps saying 1.0.0, with no error, no visual glitch, and a tester
reporting an already-fixed bug against the wrong number.

`version/code` is the exception and cannot be derived from anything. It is an
integer, it lives only in the (gitignored) preset, and **Google rejects an
upload whose code is not higher than the last one** — so it goes up per
upload, independently of the version string. It is at **6**, built on
2026-10-29 as `build/QuizRunDualGate-v6.aab`, carrying version 1.2.1 — the first
build with Firebase Analytics. 5 is 1.2.0 (2026-10-06), the first production
build and the first with live ads; 4 is 1.1.1 (2026-10-02), the last
closed-test build.
Code 1 went to internal testing on 2026-09-13; 2 was built the same day and
uploaded too (Play Console reported on "2 (1.0.0)"); 3 is 1.1.0, built
2026-09-24. Each upload gets a new version string as well, or testers see
two builds under one name and their reports cannot say which.
Consecutive numbering is not required, only increase.

**QuizRun 2.0 is a redesign built here, on `main`.** Decided 2026-11-25. It
ships as an **update of this same app**, so the package name, upload key,
store listing and the AdMob, Firebase and Play Games setup recorded in this
file carry over. The 1.x game is frozen: the shipped 1.2.1 is tag `v1.2.1`,
and branch `release/1.x` holds it for a hotfix. A hotfix and the 2.0 builds
are uploads of the same app, so each takes a version code above every one
before it.

**Dragon Smash is not 2.0.** It was planned on 2026-11-22 as this app's 2.0
and split out to its own project, `D:\Godot\DragonSmash` (GitHub
`kimmc1358-code/DragonSmash`, private), on 2026-11-23. On 2026-11-25 the
owner made it a **separate new game** with its own app. It no longer shares
this app's package or version codes. It may still port the wrapper scripts
(`Ads.gd`, `AdIds.gd`, `PlayGames.gd`, `Store.gd`, `Analytics.gd`) from here.
Its own `CLAUDE.md` documents it.

A built AAB will not open in `aapt`, which refuses the bundle format. To
read what it actually carries, pull the manifest out and look at it:

```bash
unzip -o -q build/QuizRunDualGate-v3.aab base/manifest/AndroidManifest.xml -d /tmp/aabchk
```

The manifest is protobuf, not binary XML, but both values are legible in
it: `versionName` sits next to the plain string `1.1.0`, and `versionCode`
is the single character right after it (`\x1a\x01` then `3`) — confirmed by
diffing the v1, v2 and v3 bundles, where only that byte changes. The
signing key is read with the JDK's own tools rather than `apksigner`, which
does not verify bundles:

```bash
keytool -printcert -file /tmp/sigchk/META-INF/QUIZRUN.RSA
```

That must print the upload key's SHA-1 (`5B:10:59:…`), not the debug key.

## Login

Sign-in is **Google Play Games Services v2**, through the
`godot-play-game-services` plugin (godot-sdk-integrations, v3.x). The game talks
only to `scripts/PlayGames.gd`; nothing else names the plugin.

The wrapper exists for the PC. Every plugin call returns silently when the
Android singleton is missing, and its result signal never arrives — so wired
straight in, a sign-in press in the editor or a headless checker waits forever.
`PlayGames` records "unavailable" and answers a press with `sign_in_finished
(false)` at once. It also loads the plugin's scripts by path and reads the
player object's fields instead of naming its classes, so a missing `addons/`
folder cannot stop the game from parsing.

**There is no sign-out, and there cannot be.** Play Games v2 removed it; neither
the plugin's GDScript nor its Kotlin side has one. The account follows the
device's Play Games profile and is dropped from the Play Games app. So the
settings popup's LOGIN button disappears once signed in and the account row
takes its width — a LOGOUT that did nothing would read as a bug. The mode
select's person icon signs in when signed out and opens settings when signed
in, for the same reason.

The profile photo arrives **after** the name. The plugin downloads it to
`user://` and emits `image_stored(path)`; the player object already carries that
path. `PlayGames` loads it if the file is there and otherwise waits for the
signal with that exact path — another player's image landing is not ours.

**To see the signed-in screens on PC**, tick `debug_fake_sign_in` on Main. It
signs in as "Test Player" with no photo, only when the plugin is unavailable,
so a real device ignores it. It is the same `@export` trap as the other two
debug switches, and `check_play_games.gd` fails while it is on.

### Leaderboards

One per mode, IDs in `MODE_LEADERBOARD_ID` (indexed by `Mode`, like every
other per-mode table). They are public — they ship inside the app — so they
live in code, not in the preset.

What goes up is **the stored per-mode best** (`leaderboard_bests`), not the
run's score, at the end of every run and once at the moment sign-in
completes. Play Games keeps only the higher score, so resending costs
nothing, and it buys two things: a submission lost offline heals on the next
run end, and records made before signing in reach the board. The best
is kept apart from the personal best (`leaderboard_bests`): while the revive
existed it was the pre-revive score, and old saves still carry those values.

The board opens from the mode select's trophy, for the selected card; the
game over had a LEADERBOARD button too until 2026-11-28. Pressed while signed out, the mode
select signs in first and opens the board only if that succeeds.

Each board's **name and icon live in the Play Console**, not here — the game
knows only the IDs, so renaming a board or swapping its icon needs no code
change and no new build. The icons are
`store/leaderboard/leaderboard_<mode>_512.png`, built by `build_app_icon.ps1
-NoGate` from each mode's character alone on that mode card's colours
(`-TopRgb` / `-BottomRgb`, from `CARD_FILL_TOP`/`BOTTOM` × 255), so the four
tell apart in one list; the store composite is the file taken. The owner
chose character-only over the app icon's gate composition. The dragon is
`-Frame 0`, its wings-up pose (the default frame 2 has the wings swept down
under the body); the other three keep the default frame.

### Where it stands

Installed on 2026-09-12: v3.4.0 from the release's `addons.zip` (sha256
`3a1af78f…265edd`), vendored whole in `addons/GodotPlayGameServices/` with its
MIT licence. `project.godot` registers the plugin's autoload and enables it;
the preset has gradle on and the Game ID. The autoload is inert on PC —
`PlayGames` only calls `initialize()` on Android.

The first gradle debug build was checked with `aapt`: the manifest carries
`com.google.android.gms.games.APP_ID`, the string behind it is
`554024495812`, and the plugin's classes and the Play Games SDK are in the
dex. Sign-in and leaderboard submission were confirmed on a phone on 2026-09-13,
both from a debug build installed over adb and from the internal-testing build
installed through Play. On that phone, after it switched from the debug-signed
build to the Play-signed one with the same account, sign-in and showing a board
worked but every **submit** failed with `26502: CLIENT_RECONNECT_REQUIRED` —
the plugin only reports a bool, and the cause is in the `LeaderboardsProxy`
lines of logcat. It cleared after the owner wiped Google Play services' cache
(cache only, not data) and some time had passed since the new credential was
added; which of the two did it is not known.

The gradle APK is 154MB against the old export's 95MB, and it is not the
assets: those are still deflated (65.7MB). Gradle stores `libgodot_android.so`
**uncompressed** (77.5MB), so Android can map it straight from the APK instead
of extracting a copy — a bigger download for a similar installed size.

Credentials: an Android OAuth client named "QuizRun Debug" holds the debug
keystore's SHA-1 (`androiddebugkey` in Godot's `keystores/debug.keystore`,
`B4:2D:28:6A:EC:19:C7:92:FD:96:F2:4C:FD:87:A1:A8:94:1E:A1:45` — confirmed by
reading the signature off a built APK, not just the keystore). Two more Android clients cover builds that do not carry the debug key:
"QuizRun Play Signing" for Google's **app signing key**
(`B4:41:DC:7E:A4:30:86:A3:06:F4:D8:03:5B:F3:04:AC:5A:D6:A1:E7`, which signs
everything installed from Play) and "QuizRun Upload" for the **upload key**
(`5B:10:59:0E:66:89:A1:A2:6E:05:E7:CF:1F:2F:AD:1B:DC:C2:2B:8C`).

**Take the app signing SHA-1 from the installed app, not from a console
page.** After the first upload, Play Console's app-integrity page listed
`3C:ED:A7:A2:22:37:6F:2B:51:BC:63:91:7D:3E:78:60:F3:9C:8C:D5` as the app
signing key, and a client was registered with it. The build installed through
the internal testing track's opt-in link then failed sign-in with
`DEVELOPER_ERROR`, and the Play Games log printed the certificate it actually
saw: `B4:41:DC:…`, the value Play Console had offered for the credential
before anything was uploaded. Pulling `base.apk` off the phone and reading it
with `apksigner verify --print-certs` agreed (signer "CN=Android,
O=Google Inc."). A full `apksigner verify -v` shows a single signer under the
v3 scheme only — no v3.1 block and no rotation lineage (`apksigner lineage`
finds none) — so this is not a key upgrade serving a newer key to newer
devices. Why the console page shows a different key is not understood; both keep an OAuth client, since an extra one costs nothing and a
missing one blocks every sign-in. The upload key's SHA-1 was read off the
signed AAB and matched the console.

`B4:41:DC:…` appears nowhere in Play Console any more, so this file, the
"QuizRun Play Signing B4" OAuth client and any Play-delivered APK are the
places it can be recovered from. To read it off the phone again:

```bash
adb shell pm path com.janiju.quizrundualgate
```

```bash
adb pull <the base.apk path printed above> base.apk
```

```bash
apksigner verify -v --print-certs base.apk
```

Play Console's App bundle explorer can also hand out a "signed universal
APK" for any uploaded version; running the same `apksigner` on it shows the
key Play signs that release with, without a phone. Done for version 1 on
2026-09-13: one v3 signer, `B4:41:DC:…`, no lineage — the same as the phone.
That settles which key Play signs with; `3C:ED:A7:…` signs nothing found so
far. A `DEVELOPER_ERROR` in
logcat prints the certificate Play Games saw, too. While Play Games
Services is unpublished, only listed tester accounts can sign in.

The first gradle export printed `[ DONE ]` and then hung on exit with
"Scan thread aborted" — the APK was complete. If it happens again, check the
APK's timestamp and end the process rather than waiting on it.

## Share — removed

The game over SHARE (an image card drawn by `ShareCard.gd` and handed to
Android's share sheet by `ShareSheet.gd`, with no plugin) was removed on
2026-11-28 with the LEADERBOARD and LOGIN WITH GOOGLE buttons and the
leaderboard note above the score ("Login to join the Leaderboard!" / "Your
best is on the Leaderboard"), at the owner's call: the game over keeps only
its result rows, x2, PLAY AGAIN and HOME, and says nothing about signing in.
Scores still go to the boards at run end. With two rows gone its panel stops
at `PANEL_MAX_H` (700, the 16:9 height), or 20:9 was mostly empty gaps. It had
never been tried on a device. Git has the whole of it, `check_share` and
`capture_share` included; the JNI notes in `ShareSheet.gd` are the part
worth reading if sharing comes back.

## Ad policy

The agreed strategy, and what of it exists in code. The ads themselves come
from the AdMob plugin through `scripts/Ads.gd` (see *How ads reach the
screen* below); the decision layer described here is testable without it.

| | Rule | Built? |
|---|---|---|
| Rewarded x2 | The game over's x2 (2026-11-27): watch an ad to get the run's stardust again, once a run, offered from `DOUBLE_DUST_MIN` (10) earned. Watched to the end grants it; closed early grants nothing and the button stays; no ad ready, or one that fails to show, grants nothing and the button reads AD NOT READY, since free on no ad would double every offline run. Ads removed: granted at once with no ad. A debug build on PC, where no ad can show, grants at once so it can be tried | Yes — `_on_double_stardust_pressed`, `_grant_double_stardust`, `GameOverPopup.set_stardust` |
| Interstitial | Every 5 runs left behind, skipping runs that used a rewarded ad, with the first 3 runs after install exempt | Yes — `_ad_*`, shown through `Ads.show_interstitial` |
| Banner | None. Dropped on 2026-11-27 | Removed; see *Banner ads — removed* |
| App-open | Not used | n/a |

**There is no revive** (removed 2026-11-28, owner's call). Until then a
rewarded ad on a revive popup continued the run once, with the leaderboard
entry frozen at the pre-revive score (`leaderboard_score`), and the x2 was
the second rewarded placement. A dead run now goes straight to the game
over: x2, PLAY AGAIN, HOME. The revive popup, `check_revive_continuity` and
the "OOPS!" title went with it; git has them. `leaderboard_bests` stays a
separate saved value because old saves carry pre-revive scores in it.

Three things about the interstitial counter are deliberate and each was
wrong at first:

- **Counting happens in `_reset_game`, not in the four button handlers.**
  Every way out of a run — game over PLAY AGAIN or HOME, pause RESTART or
  HOME — passes through it, so a fifth path added later is counted for free.
  Per-handler counting is how one path silently stops counting, and a player
  who always uses that path then never sees an ad.
- **Exempt runs are not counted at all**, rather than counted-but-suppressed.
  Suppressing only the display leaves the counter at 3 when the exemption
  ends, so the first ad lands two runs later — and with a 5-run cycle the
  first ad was at run 5 either way, making `interstitial_free_games` a knob
  that did nothing. Not counting them makes the two numbers independent:
  3 free, then every 5.
- **The counter is persisted**, in `[ads]` alongside the other saved
  settings. Session-only state means force-quitting dodges ads, and — far
  more common — Android killing the app for memory silently resets it.
  For the same reason the exemption is per **install**, not per launch: per
  launch, playing one run and closing avoids ads forever.

`run_rewarded` marks a run whose x2 ad was watched to the end; it is not
counted. (It was `run_revived` while the revive was the rewarded ad.)

### Ad unit IDs, and why they are locked

`scripts/AdIds.gd` holds every AdMob unit and decides which set a build gets.
It exists for one reason: **clicking your own live ad gets the AdMob account
suspended**, and a suspension takes every future app on that account with it.
Intent is not considered — a mis-tap while testing counts. The failure is
also invisible, because a test ad and a live ad differ by one small label.

Two independent locks, and a live unit needs both open:

- `FORCE_TEST_ADS` — **`false` since 2026-10-06**, for the 1.2.0 production
  build. Release exports now serve live ads, including a release build
  installed on the owner's own phone; that phone should be registered as a
  test device in AdMob, and its ads never tapped either way.
- `OS.is_debug_build()` — a debug export can never serve a live ad no matter
  what the flag says. This is the lock that is still closed, and it is the one
  that makes developing on top of release-state code safe.

The flag defaulted to `true` because the two mistakes cost differently.
Shipping with it on means zero revenue and a "Test Ad" badge; shipping a test
build with it off means losing the account. Turning it back on is the way to
take a build to testers who are not on a debug export.

The test units are **Google's published demo IDs**, not real units with test
devices registered. Device registration is the other supported approach and
is the wrong one for test builds: it protects only the phones you enrolled, so
the first friend to install a build serves a real impression. `check_ad_ids.gd`
keeps a copy of Google's values as an outside reference — editing `AdIds`
alone is *supposed* to fail it.

The live IDs are in `AdIds.LIVE_*`, all three from one account
(`ca-app-pub-6214282306800929`): the app, `Interstitial - Restart` and
`Rewarded - Revive`, named as in the AdMob console (the revive is gone; the
unit now serves the game over's x2). The fourth, `Banner -
Main menu`, went with the banner on 2026-11-27. They are public — they ship inside every APK — so they live in code.

`AdIds` is read in two places: `Ads.make_admob_node`, which fills the plugin's
unit fields, and the unit ID printed by `_ad_try_interstitial`, so that the
lock's state is visible in a log rather than only in a checker.

**`check_ad_ids.gd` checks both builds, not the one it runs as.** It always
runs from the editor binary, which is a debug build, so `use_test_ads()` is
true there whatever the flag says — and for the whole test period the
checker's live branch had never once run. `AdIds.use_test_ads_in(debug)` and
`Ads.make_admob_node(script, live)` take the build kind as an argument, so the
checker asks what a debug build and a release build would each do: the debug
node must hold Google's demo units with every real field empty, and the
release node, with the flag off, must carry exactly the four `LIVE_*` values
and nothing in the formats the game does not use. It also fails if the four
live IDs come from more than one account.

### How ads reach the screen

`scripts/Ads.gd` wraps the godot-admob plugin the way `PlayGames.gd` wraps
Play Games: the game calls only `Ads`, the plugin's scripts are loaded by path,
and on PC — where the plugin's calls log an error and emit nothing —
`available` stays false and every request is answered "no ad" at once. It
builds the plugin's `Admob` node in code rather than keeping one in a scene.

**Three walls decide what a build serves**, and `check_ad_ids.gd` checks each:

1. The **app ID** in the manifest comes from
   `addons/AdmobPlugin/android_export.cfg`: `is_real = true` and the live app ID
   in `[Release]` since 2026-10-06. The plugin picks the slot by `is_real`
   alone, **not by export kind**, so a debug build carries the live app ID too
   — harmless, because what is served is decided by the units, and a debug
   build's units are Google's demos. `[Debug]` keeps the test app ID for the
   day `is_real` goes off again. If the file is missing or a key is absent the
   plugin silently falls back to searching the project's scenes for an `Admob`
   node and using its Inspector values — so the checker also fails on any
   scene that contains one.
2. The **unit IDs** are set by `Ads.make_admob_node` before the node enters
   the tree, because the plugin picks its units in `_ready`: `is_real` follows
   the build, the debug fields get Google's demo units, and the real fields
   get `AdIds.LIVE_*` only in a release build. A debug build's real fields are
   empty, so an `is_real` switched on by mistake there finds nothing to load.
3. `AdIds`' own two locks, above.

Going back to test ads for everyone means turning all three back on purpose:
`FORCE_TEST_ADS = true`, and `is_real = false` with the test app ID in
`[Release]` — the checker fails until the two agree. The `LIVE_*` values can
stay; they are ignored while the flag is on.

What each format does:

- **Rewarded** — the game over's x2 shows it, and the run's stardust is
  granted again only once the ad was watched to the end. Closed early, the
  button stays. No ad ready, or an ad that fails to show, grants nothing and
  the button reads AD NOT READY (see the Rewarded x2 row above).
- **Interstitial** — shown at the existing decision point. While it is up,
  `ad_hold_countdown` stops the READY/GO! clock; otherwise the run would start
  behind the ad. The counter resets when the ad closes, not when it is asked
  for; with nothing loaded it stays due and the next exit tries again. On PC
  the old "count it as shown" path remains, because `check_ad_policy.gd`
  measures the policy there.
- **Banner**: none since 2026-11-27. It is never loaded and its unit fields
  are empty.
- Game audio is muted on the Master bus while a full-screen ad is up.

A failed load retries after 30 seconds. The test units have been seen
loading and showing on a phone; live units have never served, by design.
`check_ads_wiring.gd` drives the wiring with a fake plugin.

### Consent (Google UMP)

EEA and UK players must see a Google-certified consent form before an ad is
requested, so `Ads` asks Google first and starts the SDK only after: `start()`
calls `_begin_consent()` (`update_consent_info`), and `initialize` waits in
`_start_sdk()`, which runs once. Google decides the region; everywhere else it
answers `NOT_REQUIRED` and nothing is shown. When it answers `REQUIRED`, the
form is loaded and shown, and the SDK starts when it closes. The wording on
the form is the GDPR message made in AdMob's "Privacy & messaging" page —
without one, Google answers that no form exists and the game logs a warning.

**Failing to ask never blocks ads.** Offline, a form that fails to load, or no
message in AdMob all start the SDK anyway: the SDK keeps the consent from the
last time it was given, and for an EEA player who never gave it Google serves
limited ads itself. Blocking instead would take the x2 away for the whole
session after one bad connection.

Google also requires a way back in. Settings carries **Ad Privacy Choices**
under Privacy Policy, lit only where consent was asked for (`REQUIRED` or
`OBTAINED`) and dimmed everywhere else, the way an unset link already is. It
re-shows the same form; the SDK is not restarted. The plugin has no separate
privacy-options form, so the consent form is what comes back.

The consent flow has **not run on a device**. Seeing the form from outside
Europe needs a test build with a debug geography and the phone's hashed test
device ID, which UMP prints to logcat on first launch; neither is set today.

## Analytics

Firebase Analytics, through the **Godotx Firebase** plugin (godot-x/firebase
3.1.0, MIT; release zip sha256 `da7273de…8170c1`), Core and Analytics modules
only. The game talks only to `scripts/Analytics.gd`, which wraps the plugin the
way `Ads.gd` and `PlayGames.gd` wrap theirs: on PC the singletons are missing,
`available` stays false, and every event is dropped without an error.

**Collection starts off, and is switched on only outside Europe.** The export
option `firebase/privacy_safe_defaults` writes "collection disabled, every
Consent Mode signal denied" into the manifest, so nothing — not even the
automatic `first_open` — leaves the device before the game says so. The game
says so only when Google's UMP answers `NOT_REQUIRED` (Korea and everywhere
else outside the EEA/UK); `Main._on_ads_consent_changed` hands each answer to
`Analytics.set_consent_status`. `REQUIRED`, `OBTAINED` and `UNKNOWN` all keep it
off. `OBTAINED` means only that the form was answered, not that analytics was
agreed to, so treating it as consent would collect from people who refused;
and an offline launch does not know its region. Events while off are dropped,
not queued, so a later consent cannot send what happened before it.

Ads take the opposite default — they start even when consent could not be
asked — because blocking them takes the x2 away, while a missing day of
analytics costs a line of statistics.

What is logged, using Google's recommended game event names where one fits
(installs, sessions, retention, ad impressions and Play purchases are
collected by Firebase itself):

| Event | When | Parameters |
|---|---|---|
| `level_start` | a run starts | `level_name` |
| `post_score` | a run ends | `level_name`, `score`, `gates`, `max_combo` |
| `double_stardust` | the game over x2 | `result`: `watched`, `skipped`, `no_ad`, `ad_free`, `debug_no_ads`; `amount` when granted |
| `tutorial_begin` / `tutorial_complete` | the tutorial's two ends | |

The `revive` event, the `revived` flag on `post_score` and the `share`
event went with the revive and the SHARE button on 2026-11-28.

`level_name` comes from `Analytics.MODE_NAMES` (`flags`, `math`, `colors`,
`mix`) — fixed English names, so one mode stays one row whichever language the
player runs.

**Setup lives in three places, two of them off git:**

- `google-services.json` at the project root, from the Firebase console
  (project `quizrun-9a351`, app `com.janiju.quizrundualgate`). The repository
  is public, so the file is gitignored, and the export excludes it from the
  pack; the plugin copies it into `android/build/` at export time. A new
  machine has to download it again.
- `android/build/build.gradle` (the gitignored build template) needs a
  `buildscript` block **at the very top** with `classpath
  'com.google.gms:google-services:4.4.4'`, and `apply plugin:
  'com.google.gms.google-services'` at the very end. Reinstalling the Android
  build template wipes both.
- The preset: `firebase/android_config_file = res://google-services.json`,
  `enable_core` and `enable_analytics` on, Crashlytics and Messaging off,
  `privacy_safe_defaults` on.

The plugin's AAR wrappers sit in `android/firebase_core/` and
`android/firebase_analytics/`. `.gitignore` used to drop `/android/` whole; it
now drops `/android/*` and re-admits those two folders, so they travel with the
repo while the build template still does not. The iOS frameworks in the
release zip were left out.

The first build with it was 84.7MB against 83.6MB, and its manifest carried
the five privacy defaults, its resources the Firebase app ID, and its dex the
Firebase classes — read back from the bundle. It reached the console from
production phones within days of 1.2.1's release: by 2026-11-02 the Firebase
overview showed daily users, day-1 retention and AdMob revenue (AdMob was
linked to the Firebase project on 2026-10-29). Event parameters such as
`level_name` and `gates` appear in reports only once registered as custom
definitions in Google Analytics, and only from that day forward.

## Remove ads

A one-time purchase, `remove_ads`, sold from settings (REMOVE ADS) and from
the line under START on mode select. `scripts/Store.gd` wraps the Play Billing
plugin the same way `Ads.gd` and `PlayGames.gd` wrap theirs: on PC it is
unavailable and `buy()` answers false at once.

Owning it stops interstitials without touching their counter (there has
been no banner to remove since 2026-11-27), and makes the
game over's x2 grant at once with no rewarded ad and no ad icon — the owner's
call: someone who paid should never be shown an ad. Settings keeps the
button but disabled, reading ADS REMOVED; mode select hides its line.
Settings changes by being rebuilt, the same path a language change takes.

**Google Play decides who owns it.** `Store` asks for the purchases on
connecting and every time the app comes back to the foreground, and
`ownership_changed` carries the answer. The last answer is also saved in
`[ads] removed`, so a buyer sees no interstitial in the first seconds after launch or
while offline. A purchase that disappears from a successful query — a refund —
brings the ads back; a query that **fails** changes nothing, because losing
the connection must not take away what someone paid for.

Two rules of the Billing library shape the code:

- A one-time purchase must be **acknowledged**, or Google refunds it three
  days later. `Store` acknowledges on the purchase and again whenever a query
  finds it unacknowledged, so a failed acknowledgement heals on the next
  launch.
- The purchase sheet cannot open before the product details have been
  queried. `buy()` re-asks and returns false until they have arrived.

A **pending** purchase (paid later, at a shop counter for instance) grants
nothing until it arrives again as purchased.

**Purchases only work for a build that exists on Play.** Until a build with
the billing plugin has been uploaded to a testing track, the product is
created and active, and the phone's account is a licence tester, the product
query fails and the button does nothing visible (it logs why). The flow has
been driven only by `check_store.gd` with a fake client.

## Banner ads — removed

The bottom banner on the mode select was dropped on 2026-11-27 (owner's
call). Ads.gd no longer loads, shows or hides one, `make_admob_node` leaves
both banner unit fields empty, Main has no banner reserve, and the 2.0 mode
select lays out its full height. `check_ads_wiring` asserts that no banner
is requested, and `check_ad_ids` that the banner fields stay empty. The
`Banner - Main menu` unit still exists in the AdMob console and serves
nothing; it can be archived there.

If a banner ever comes back, git history has the whole design (in the
commits before its removal): `set_banner_reserve`/`banner_applied_px`
on the menu, `_apply_banner_height` and `_game_px_per_device_px` in Main.
Two rules from that design are worth keeping:

- **An AdMob banner is an Android View laid over the Godot surface.** It
  covers whatever is under it, so the screen has to reserve its space.
- **Reserve it whole or not at all.** Half a banner costs the space and still
  covers the content.

Convert the plugin's device pixels by the axis the stretch actually fits:
the width on a phone, the height on a pillarboxed tablet.

## Gotchas

- `.tscn` is **not XML**. Writing `&gt;` in a `text =` field stores those
  five characters literally.
- **Comments in `project.godot` do not survive.** The editor rewrites the
  whole file from its in-memory settings whenever it saves, and `;` lines are
  not part of that — every comment there has already been silently deleted
  once. Values are untouched; only the reasoning goes. So anything worth
  explaining about a project setting belongs here, not next to it. The three
  that were lost, since each cost real time to find:
  - `display/window/handheld/orientation` is an **int enum** in Godot 4
    (0=landscape, 1=portrait). Godot 3's `"portrait"` string fails the type
    check, is dropped, and falls back to 0 — the APK ran landscape while the
    file read correctly, and desktop never showed it because the window is
    sized from `viewport_width/height` anyway.
  - `window/size/window_*_override.editor` runs the editor at 480x1067 (20:9,
    what most phones actually are) while the base viewport stays 16:9. The
    `.editor` suffix keeps it out of exported builds, which have no `editor`
    feature tag. Do not "fix" this by changing the base viewport — in 1.x that
    was where the gate field took its ceiling, and the layout checkers still
    read the reference resolution from it.
  - `rendering/textures/vram_compression/import_etc2_astc` exists only
    because the Android export refuses without it. Nothing is actually
    re-encoded: all 473 textures import lossless.
- `_load_trimmed()` builds an `ImageTexture` at runtime and calls
  `generate_mipmaps()` itself, so its inputs ignore the `.import` setting.
- **The device's screen height is not the play field.** The stretch mode is
  `canvas_items` + `keep_width`, so width is pinned at 480 and only height grows
  to fit the phone: a 21:9 device runs a 480x1120 viewport, not 480x854. The
  hole (124px of ring art), the hitbox, gravity and the seconds a gate takes
  to arrive are all fixed, so letting gates spread over the taller viewport
  put the same hole in a bigger field — 18.0% of it at 16:9, 12.9% at 21:9,
  with 18% more travel per gate. Nothing became unreachable (`up_reach` is
  absolute physics) but the game was measurably harder on a long phone, and
  it took a user playing on one to notice. `_gate_field_top`/`_bottom` cap
  the field at the reference height and centre it; `max_travel` is a
  fraction of the *reference* viewport height, not `view_size.y`. Character
  clamping and the death line deliberately still use the real screen — see
  the comment on `_gate_field_top` for why an invisible floor is worse.
  That was the 1.x gate game, and `_gate_field_*` went with it. The space
  game keeps the camera's horizontal field of view instead (`KEEP_WIDTH`),
  so a taller phone sees more space above and below, and `check_space`
  checks every slot is on screen at 16:9 and 20:9.
- **Tablets get side bars, not a wider game.** The stretch aspect is
  `keep_width`: a screen taller than 9:16 grows the viewport's height exactly
  as `expand` did, and a screen fatter than 9:16 keeps the 480x854 viewport
  and pillarboxes it. That second case is every tablet held upright — 16:10
  or 4:3 — and under `expand` it widened the viewport to 534 or 641 px, where
  the mode-select screen overlapped itself (the START button over the bottom
  cards' BEST scores at 4:3). The game was never designed for tablets and
  still is not; this only keeps them from breaking.

  Rotating does not change it. The manifest carries `appCategory="game"`, and
  Android 16 exempts games from the large-screen override that ignores
  `screenOrientation`, so a tablet keeps the portrait lock rather than
  running the game landscape. Play Console still flags the lock as a
  large-screen issue; that is a warning, not a block.

  `check_mode_select_layout.gd` fails while the aspect is anything but
  `keep_width`, and derives each ratio's viewport from the setting rather
  than from a copy of the rule. A capture at 3:4 confirmed the screen lays out
  exactly as a 16:9 phone; the bars themselves cannot be photographed that
  way, because the root texture is only the game's own area.
- **The mode-select screen has no spare height, so a taller card is paid for
  out of the gaps.** It was tempting to grow the cards into space the layout
  was not using; there is none. Leftover height goes entirely into the five
  inter-block gaps and never reaches the `MAX_GAP_FRAC` cap (49px against a
  62px cap even at 21:9), so nothing is idle. `CARD_HEIGHT_SCALE` therefore
  takes from the gaps and stops at `CARD_GROW_MIN_GAP_FRAC` — which means a
  16:9 phone, whose gap is already 1.9px, gets no growth at all and 18:9 gets
  part of it. That the cards are a different height on different phones is
  the same bargain every other block on this screen already makes.

  **The growth goes to padding, not to the contents.** Everything inside a
  card — inset, name plate, BEST plate, fonts, character — is sized from the
  *pre-growth* height, and only the space around the character absorbs the
  extra. Both other ways were tried and both broke something visible: keying
  the contents to the real height stretched the BEST plate to 26.9px tall
  while the growing inset squeezed it to 147.1 wide, so it read as squashed
  rather than bigger; and letting just the character take the extra spread
  the unicorn's ink from 111 to 145px, where it ran under the green check.
  Neither shows up at 16:9, which is why this checker now sweeps two ratios.
- **A popup's panel is sized from the screen; its rows are sized from the
  panel's width.** Width is pinned at 480 on every phone, so the rows come out
  the same height everywhere while the panel gets shorter as the screen does —
  which means content that fits at 20:9 can be 13px too tall at 16:9, with the
  overflow landing on the background below the panel. Squeezing the gaps is not
  a fix: they hit their floor and the remainder still goes over the edge.
  `SettingsPopup` scales every row by one factor when `used` will not fit, and
  `check_popup_fit.gd` measures the bottom edge at both ratios. Watch for it
  whenever a row is added — the settings popup went over when the language row
  arrived, and it is the version line at the very bottom that disappears.
- **Only `check_space.gd` and `check_mode_select_layout.gd` sweep aspect
  ratios**, and neither sweeps languages (the 1.x mode-card check that did
  went with the 1.x cards on 2026-11-27). Every other checker reads the one
  resolution out of `ProjectSettings` in one locale, and therefore only ever
  sees 16:9 in whatever language the machine is set to. Before trusting a
  green suite about anything layout-shaped, check whether the thing in
  question is actually measured at more than one ratio — and in Korean,
  where the mode names and the explain line are a different length.
