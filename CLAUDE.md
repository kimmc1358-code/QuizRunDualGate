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

The whole game is "Hard mode". There is no difficulty selector; the phase
system (`_get_phase_index`) scales difficulty by gates passed.

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
| `check_gate_reach.gd` | every hole `_spawn_gate` places is somewhere the character can actually get to **with the boost held**, in all four modes and every phase — and that gate placement is identical on a 16:9 phone and a 21:9 one | `GATE_SPEED`, `base_gate_spacing`, `BOOST_BUTTON_MULTIPLIER`, `flap_velocity`, `gravity`, `max_fall_speed`, `reach_tap_interval`, `max_move_ratio_*`, `phase_gate_counts`, or the gate zone/lane bands change |
| `check_ad_policy.gd` | interstitials never fire during the post-install free games, then fire on exactly the configured cycle; runs that used a rewarded ad do not count toward it (and do not stall it either); the counter survives a relaunch; and all four ways of leaving a run increment it | `interstitial_every_restarts`, `interstitial_free_games`, `_ad_note_run_left`, `should_show_interstitial`, `_reset_game`/`_start_countdown`, or a new path out of a run |
| `check_mode_select_layout.gd` | across seven ratios: no two blocks on the mode-select screen overlap, nothing leaves the screen, the explain bar stays glued to the cards at the card gap, the top block takes a share of a tall screen's extra height, and a requested bottom banner is either reserved **whole** with no content under it or refused outright | `ModeSelectScreen` layout constants, `banner_reserve_px`/`BANNER_MIN_GAP_PX`, the title/card/explain/START art proportions, or `LINK_TEXTS` change |
| `check_mode_card_check.gd` | the selected mode card's green check clears the name plate, the character's ink and the card's own edge on **all four** cards, is big enough to read, and the selected card really is at `CARD_SELECTED_SCALE` | `CARD_CHECK_*`, `CARD_SELECTED_SCALE`, the card name plate/character layout, `CARD_NAMES`, or `CARD_CHARACTER_SCALE` change |
| `check_mix_mode.gd` | the three single modes still ask exactly one quiz each, MIX rolls all three evenly with no run past 2, every gate carries a `quiz_kind` matching the colour data it holds, and MIX's difficulty measurably rides the **same** phase curve as the single modes | `_next_quiz_kind`, `MODE_QUIZ_KIND`, the shuffle bag, `_get_phase_index`, `phase_gate_counts`, or any of the three problem generators change |
| `check_score_format.gd` | `ScoreFormat.compact` never exceeds 5 characters anywhere in int32, matches the documented examples, and the HUD and mode-select cards actually route through it | `ScoreFormat`, `_score_digit_layout`, `_best_digit_layout`, `set_best_scores`, or the score box art/font sizes change |
| `check_boost_bar_range.gd` | all three boost bonus tiers are reachable | `BOOST_BUTTON_MULTIPLIER`, `GATE_SPEED`, `base_gate_spacing`, or the `boost_bonus_*` thresholds change |
| `check_popup_overlap.gd` | the BOOST popup never touches the combo readout or leaves the gate zone, and its gradient-fill text texture assembles to real glyphs rather than filled boxes | popup sizes/anchors, combo tier fonts, or `_gate_zone_top` change |
| `check_ambient_density.gd` | the fixed-size ambient particle pool stays on screen with the boost held | particle speeds, `PARTICLE_BOOST_WIND_X`, or the spawn-edge logic change |
| `check_sparkle_pools.gd` | every sparkle sprite loads and the per-mode colour mix is right | `TRAIL_COLORS_PER_MODE` or `FX_BURST_COLOR_WEIGHTS_PER_MODE` change |
| `check_bg_layers.gd` | every mode's background layers load, a near layer is a real cut-out, and it outruns its far layer | `MODE_BG_TEXTURE_PATH`, `MODE_BG_NEAR_TEXTURE_PATH`, `bg_speed_ratio`, `bg_near_speed_ratio`, or a background is re-cut/re-blurred |
| `check_speed_lines.gd` | the boost speed lines draw nothing at rest, stay inside their top/bottom bands AND out of the gate zone's middle half, populate both bands, outrun the gates, and recycle only once a streak's trailing edge is off screen | `BOOST_SPEEDLINE_*`, `_gate_zone_top`, `GATE_SPEED`/`BOOST_BUTTON_MULTIPLIER`, or the strip art change |
| `check_boost_hold.gd` | the looping hold sound really loops and stops on every path (button_up, pause, death, reset), the press one-shot is a separate, shorter, NON-looping stream that fires on every press, and the press-burst slices to all 5 frames in every mode with a wider-than-tall cell, fires with its head buried inside the character and its tail on screen, stays stuck to it in both axes instead of drifting off with the world, loops its sustain frames for as long as the button is down without touching the ember frame, and ends once released | `_on_boost_pressed`/`_on_boost_released`, the hidden-mid-press reset in `_process`, `_reset_game`, `_enable_stream_loop`, the `BOOST_BURST_*` block, or the burst art change |

Most of them instantiate the real `Main.tscn` and call its own functions
rather than re-deriving the maths, so they cannot drift from the game. Keep
it that way — if a checker needs a calculation, extract it from the draw
code and call it (see `_boost_pop_layout`). `check_boost_bar_range.gd` and
`check_sparkle_pools.gd` still re-derive; a copy of a table is exactly what
passes while the game itself loads nothing.

`check_gate_reach.gd` is the deliberate exception, and the reason is worth
keeping straight: it checks a claim about **physics**, not about drawing.
Calling `_spawn_gate`'s own reach formula would make it assert that the
formula equals itself. So it integrates the real `gravity`/`flap_velocity`/
`max_fall_speed` at 1/60s and compares that against where gates actually get
placed. Both bugs it was written for — `available_time` ignoring
`BOOST_BUTTON_MULTIPLIER`, and `up_reach` using the flap impulse as if it
were a sustained climb rate — were live in the shipped code for months and
show up on screen only as "a gate you sometimes just can't make", which no
player can tell apart from their own bad play.

It also fails when the margin gets too *large*: if placement never uses more
than a quarter of the available climb, then something else is binding and
the check is guarding nothing.

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

Use this for anything where the question is "does it look right", and reach
for it before mocking a composite up separately. A hand-built preview of the
BOOST popup looked fine for two rounds while the real game was drawing
`TURBO!+600` with the space swallowed; one real capture found it.

## Architecture

`scripts/Main.gd` is ~6000 lines and deliberately monolithic: gameplay is
**custom-drawn** in one `_draw()`, not built from nodes. Gates, character,
background and FX are all `draw_texture_rect` calls over plain Dictionaries
in Arrays. There is no physics engine and no per-entity scene.

Consequences worth knowing before editing:

- Anything visual is a `_draw_*` function plus a `_update_*` and a state
  Array. Features are self-contained in that trio and are documented as
  such in block comments ("Whole feature = these consts + ... Delete those
  to remove it").
- Per-mode variation is **parallel arrays indexed by `Mode`**, e.g.
  `MODE_PARTICLE_DIR`, `MODE_FX_DIR`, `TRAIL_COLORS_PER_MODE`. Adding a mode
  means extending every one of them. A count of `0` (see
  `MODE_PARTICLE_COUNT[SKY]`) disables a feature for one mode while keeping
  the arrays index-aligned.
- `_apply_mode(mode)` loads all per-mode art. It runs at `_ready` and on
  every mode switch.
- `_boot_load()` does the heavy loading *after* the logo fades in, not in
  `_ready`. A headless run that only survives a few frames will not have
  reached it.

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

The source is the in-game motion sheet, so `-Pose fly -Frame N` picks a cell
of that grid (`-Pose happy|sad` takes the single-frame faces instead).
Default is the bird's frame 2, the wings-up pose — chosen by rendering all
four as finished icons and looking at them at 48px, where the other three
read as a ball with a beak. Enlarging goes through an **integer
nearest-neighbour step before the final resample**: these are pixel art, and
a straight 1.7x bicubic turns every hard pixel edge into a gradient. Pass
`-Character dragon|shark|unicorn` to rebuild from a different mode's sprite,
and `-OutRoot <dir>` to write candidates somewhere other than the repo.

The exception is an **animation strip** — the character sheets and the boost
burst. Those stay whole and are cut at load time by `_slice_spritesheet`,
which takes a cell grid, drops fully transparent cells and rebuilds each
cell's mipmaps. A regular grid needs no detection, so there is nothing for a
tool to measure and nothing to commit twice.

The boost burst runs the pipeline **backwards**: that art arrived as loose
per-frame PNGs, so `tools/build_boost_burst_strips.ps1` assembles them into
the strips instead of cutting one up. The sources live in
`assets/fx/boost_burst/frames/` behind a `.gdignore`, so Godot never imports
twenty PNGs the game does not open. Frames are copied at their **full canvas
size**, never trimmed — the frames are registered against each other (the
flame's head holds still while its tail grows backward out of it), and
trimming each to its own bounds makes the head jitter.

**Effects are baked into the files, not applied at runtime.** This project
has no blur shader in its custom-draw setup, so:

- Background softness is baked by `tools/blur_background.ps1`.
- Ambient particle blur is baked by `slice_ambient_sheet.ps1 -Sigma`.
- The boost burst's soft edge is baked by `build_boost_burst_strips.ps1 -Sigma`.
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
JUNGLE (1.45) kept it; SKY and DREAM needed more blur than the metric
allowed and OCEAN much less (2.64). Two pairs — SKY and DREAM — are
therefore knowingly inverted, with the near layer softer than the far, and
get their depth from occlusion and the 2.5x speed split instead. They are
listed in `$DepthInversionExpected` with a reason each; `-SelfTest` prints
those as notes and still warns for any other mode that inverts.

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
| Launcher icons | `assets/ui_assets/icon/` — legacy 192, adaptive fore/back 432 |
| Export filter | `all_resources` |
| Excluded | `assets/references/*`, `tools/*` |
| Gradle build | off (no plugins yet) |

The game answers to three different names and they are not meant to match.
The **launcher label** is the one under the icon on the home screen, where
roughly ten characters survive before truncation — hence `QuizRun` rather
than the full title. The **Play Store title** is `QuizRun: Dual Gate`, set in
the Play Console and not in this repo at all. The **in-game title art** is
its own painted asset. Left empty, `package/name` falls back to
`application/config/name`, which is `QuizRunDualGate` — the Godot project
folder name leaking out as a product name.

**The package name is permanent once published.** It keys the Play Console
listing, every OAuth client, the GPGS configuration and the AdMob app
record; changing it later means recreating all four. It was
`com.kimmc1358.quizrundualgate` until the studio identity settled on
`janiju` — everything else already said JANIJU STUDIO.

`export_filter` must stay `all_resources`. The game builds asset paths at
runtime — flags, particles, tap sparkles — so nothing links them from a
scene, and the scene-following export modes drop them silently.

## Ad policy

The agreed strategy, and what of it exists in code. **No ads SDK is in the
project** — this is the decision layer only, and it is testable without one.

| | Rule | Built? |
|---|---|---|
| Rewarded | Opt-in on the revive popup, once per run. The run's leaderboard entry is frozen at the pre-revive score; the personal best still takes the full score | Yes — `revive_offered`, and `leaderboard_score` captured on the first death only |
| Interstitial | Every 5 runs left behind, skipping runs that used a rewarded ad, with the first 3 runs after install exempt | Yes — `_ad_*`, no ad shown |
| Banner | Mode-select bottom only, never in gameplay | Slot only — see below |
| App-open | Not used | n/a |

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

`run_revived` doubles as "this run used a rewarded ad". It is not a second
flag, because two flags for one fact drift.

## The bottom banner slot

An AdMob banner is an Android View laid **over** the Godot surface, not
something drawn inside the viewport. It does not push anything; it covers
whatever is under it. So the game reserves the space and the banner sits in
the hole.

`ModeSelectScreen.set_banner_reserve(px)` takes that height **in game
pixels** and returns what it actually reserved. Two things follow from that
signature:

- **The caller must convert.** A plugin reports the banner in device pixels;
  the viewport is pinned to 480 wide whatever the device is, so the value has
  to be scaled by `480 / real screen width` before being passed in. Handing
  over raw device pixels reserves the wrong amount on every phone but one.
- **The return value is the decision.** It is all-or-nothing: reserving half
  a banner is worse than reserving none, because the screen loses the space
  *and* still gets covered. If the reserve would leave less than
  `BANNER_MIN_GAP_PX` between blocks the screen refuses and returns 0, which
  means "do not show a banner on this device" — not an error.

Measured at 480 wide, the space available before blocks collide is 11px at
16:9, 118px at 18:9 and 225px at 20:9. A 50dp banner is roughly 67 game px on
a 1080-wide phone, so everything from 18:9 up takes it and 16:9 has never had
the room. That is why the refusal path exists rather than being a bug.

Nothing here shows a banner — there is no ads SDK in the project (see the
audit in the git log). This is only the hole it will sit in.

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
    feature tag. Do not "fix" this by changing the base viewport — that is
    where `_gate_field_height_cap` gets the play field's ceiling, so it moves
    the difficulty.
  - `rendering/textures/vram_compression/import_etc2_astc` exists only
    because the Android export refuses without it. Nothing is actually
    re-encoded: all 473 textures import lossless.
- `assets/backgrounds/<mode>_world/` has no `sky_world/particles/` — SKY
  intentionally has no ambient layer.
- The score box art (`assets/gates/flag_panel/panel_*.png`) is shared
  between the HUD and the gate's flag panel. Changing it affects both.
- `_load_trimmed()` builds an `ImageTexture` at runtime and calls
  `generate_mipmaps()` itself, so its inputs ignore the `.import` setting.
- **`GATE_SPEED` and `base_gate_spacing` move together, or difficulty moves
  with them.** Everything the player has to react to is priced in
  `base_gate_spacing / GATE_SPEED` — the seconds between one hole and the
  next. Raising the speed alone shortens that and quietly tightens gate
  placement; raising both in proportion buys the *sensation* of speed for
  free, because the whole world scrolls faster while the rhythm and the
  reachable range stay exactly where they were (130/600 and 200/900 are the
  same 4.5-second gate).
- **The device's screen height is not the play field.** The stretch mode is
  `canvas_items` + `expand`, so width is pinned at 480 and only height grows
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
- **Phones are covered; tablets are not, and that is a decision, not an
  oversight.** `expand` treats the base size as a minimum on *both* axes, so
  a screen wider than 16:9 does not lose height — it gains width, and the
  viewport comes out 640x854 on 4:3 rather than 480x640. Gameplay survives
  that (the field lands at 650px, near the 690 cap) but the mode-select
  screen does not: at 4:3 the START button overlaps the bottom row of cards
  and covers their BEST scores. Left alone deliberately while the game is
  being tested on phones. Reproduce with
  `DisplayServer.window_set_size(Vector2i(480, 640))` before the scene loads.
- **Only `check_gate_reach.gd` sweeps aspect ratios.** Every other checker
  reads the one resolution out of `ProjectSettings` and therefore only ever
  sees 16:9. The START overlap above was found by taking a screenshot, not
  by a checker. Before trusting a green suite about anything layout-shaped,
  check whether the thing in question is actually measured at more than one
  ratio.
- Anything set against the world's scroll rate is set against `GATE_SPEED`
  **in the same breath**, and stops being true when it changes. The one that
  bites is `PARTICLE_DRIFT_X_RATIO`: DREAM's petals are only perceived as
  diagonal relative to the background sliding under them, so speeding the
  background from 130 to 200 turned a 45-degree drift into exactly 0 — dead
  vertical — with the ratio untouched. Its comment carries the table.
