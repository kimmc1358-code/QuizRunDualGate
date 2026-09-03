# CLAUDE.md

Guidance for Claude Code working in this repository.

See [README.md](README.md) for the tuning defaults table and the design docs
(`듀얼게이트_퀴즈러너_기획서_*.md`). This file covers how to *work* here.

## What this is

A Godot 4.7 mobile prototype: 480x854 portrait, `mobile` renderer, one main
scene. Tap anywhere to flap; fly through the gate whose answer matches the
quiz prompt. Four visual concepts share the mechanic — `SKY`, `JUNGLE`,
`OCEAN`, `DREAM` — picked on the mode-select screen.

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
| `check_boost_bar_range.gd` | all three boost bonus tiers are reachable | `BOOST_BUTTON_MULTIPLIER`, `GATE_SPEED`, `base_gate_spacing`, or the `boost_bonus_*` thresholds change |
| `check_popup_overlap.gd` | the BOOST popup never touches the combo readout or leaves the gate zone | popup sizes/anchors, combo tier fonts, or `_gate_zone_top` change |
| `check_ambient_density.gd` | the fixed-size ambient particle pool stays on screen with the boost held | particle speeds, `PARTICLE_BOOST_WIND_X`, or the spawn-edge logic change |
| `check_sparkle_pools.gd` | every sparkle sprite loads and the per-mode colour mix is right | `TRAIL_COLORS_PER_MODE` or `FX_BURST_COLOR_WEIGHTS_PER_MODE` change |
| `check_bg_layers.gd` | every mode's background layers load, a near layer is a real cut-out, and it outruns its far layer | `MODE_BG_TEXTURE_PATH`, `MODE_BG_NEAR_TEXTURE_PATH`, `bg_speed_ratio`, `bg_near_speed_ratio`, or a background is re-cut/re-blurred |
| `check_boost_hold.gd` | the looping hold sound really loops, and both it and the character glow release on every path (button_up, pause, death, reset) | `_on_boost_pressed`/`_on_boost_released`, the hidden-mid-press reset in `_process`, `_reset_game`, `_enable_stream_loop`, or the `BOOST_GLOW_*` block change |

Most of them instantiate the real `Main.tscn` and call its own functions
rather than re-deriving the maths, so they cannot drift from the game. Keep
it that way — if a checker needs a calculation, extract it from the draw
code and call it (see `_boost_pop_layout`). `check_boost_bar_range.gd` and
`check_sparkle_pools.gd` still re-derive; a copy of a table is exactly what
passes while the game itself loads nothing.

Note: a headless viewport reports a **square** size, not 480x854. Read the
resolution from `ProjectSettings` instead, or a layout check passes by
being given far more room than the game has.

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

**Effects are baked into the files, not applied at runtime.** This project
has no blur shader in its custom-draw setup, so:

- Background softness is baked by `tools/blur_background.ps1`.
- Ambient particle blur is baked by `slice_ambient_sheet.ps1 -Sigma`.
- The boost glow's radial halo is generated by `tools/bake_character_glow.ps1`
  — a pure falloff with nothing to paint, so it is computed rather than
  authored. Its RGB is white even where alpha is zero, so linear filtering
  has no dark pixels to drag into the halo.

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
telling the eye which layer is further away. Every near layer shares
`$NearSigma` (0.5) so each painting keeps its own crispness; only the far
layers are matched onto a common softness. 0.5 is also the floor — the
kernel runs to `ceil(3*sigma)`, so at 0.3 it collapses to a near-delta and
does nothing at all.

Far-layer strength is **measured, not eyeballed**. `blur_background.ps1
-Sharpness` reports the mean |Laplacian| over opaque RGB for every committed
blur, **measured after resampling to the 854px height the game draws it at**
— not on the source pixels. That distinction is load-bearing: SKY's far
layer is 1472x704 and gets magnified 1.21x, while every other layer is
1056 tall and minified to 0.81x, so the same sigma spreads 1.5x further on
one than the other. `-SelfTest` re-derives every file from its source and
diffs it against what is committed — anything but a residual around 1/255
means the sigma table and the PNGs have drifted apart. The table is the only
record of how each file was made, so keep it in step.

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

## Gotchas

- `.tscn` is **not XML**. Writing `&gt;` in a `text =` field stores those
  five characters literally.
- `assets/backgrounds/<mode>_world/` has no `sky_world/particles/` — SKY
  intentionally has no ambient layer.
- The score box art (`assets/gates/flag_panel/panel_*.png`) is shared
  between the HUD and the gate's flag panel. Changing it affects both.
- `_load_trimmed()` builds an `ImageTexture` at runtime and calls
  `generate_mipmaps()` itself, so its inputs ignore the `.import` setting.
