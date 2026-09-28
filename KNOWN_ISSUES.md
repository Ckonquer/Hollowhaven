# Known issues — Hollowhaven (Chapter One; Chapter Two: see the last section)

Honest list of what is imperfect or unverified. Severity: **minor** unless stated. Nothing here is a
known crash, save-corruption or progression blocker (those are release blockers and are fixed).

## Not verifiable by the developer
* **Nobody has listened to the audio yet.** All music and sounds are original, synthesised from code and
  checked by numbers (peak/RMS/weighted loudness, loop seams, spectrograms) and in-engine mix captures,
  but subjective quality (the melodies, Mochi's squeaks, scary cues) needs a human listening pass.
* Performance was measured only on the development PC (RTX 4090). Minimum requirements are unknown;
  Settings → Video → Quality (Low/Medium) reduces shadows, SSAO and grass density for weaker GPUs.

## Gameplay / feel
* Companions and enemies have no navmesh: they follow breadcrumbs / steer directly, with stuck detection
  that safely teleports a companion back beside Krystal. On rare tricky terrain they may briefly bump
  into things before recovering.
* The boss fight's HP and lit braziers reset if you quit to the title mid-fight (dying keeps the lit
  braziers within the same session).
* Lighting a brazier is "press E, then a 1.5 s kindle" rather than a held button; walking away cancels it.
* If the camera is swung hard into a wall or corner, it pulls in close and hides Krystal until you turn.
* Late in the dodge roll Krystal can hover ~10 cm for a few frames.
* Pebble's boulder doesn't remember partial hits across a save/load (a few extra swings at most).
* Feeding a companion that has already eaten today keeps the food ("still full") instead of consuming it.
* The wall-placement rule that prevents shutting Krystal in only considers built pieces, not trees or
  rocks at the edge of the build area. Pause → "Return to the Haven" always gets you out.
* Sleeping in a bed works at any hour and skips to the next morning (which also ripens crops).
* Nothing stops Krystal from running the dungeon early. If the Heartseed goes back before the surface goals
  are done, the dungeon goals are skipped and the Haven Banner arrives once the remaining surface goals
  (e.g. befriending Lumi) are finished.
* Closing the window saves on the surface (like Pause > Save). Underground it doesn't: Continue starts at
  the last underground save (a lantern she rested at, or the mine landing on arrival).

## Interface
* Moving items in the backpack/chest needs the mouse (menus themselves work with the keyboard).
* Toasts already on screen keep their old wording if Arachnophobia mode is toggled while they are visible.
* The title-screen Credits card needs a little scrolling at 1080p (the ending credits scroll automatically).
* Emote bubbles above companions are hidden behind walls (deliberate, to avoid see-through bubbles).
* Keeping a debug/QA run windowed requires the user argument `-- --windowed` (engine flags are not visible
  to the game). Normal players are unaffected (Settings → Video → Fullscreen toggles it).

## Visual
* The Ward Stone's moss blobs look a little flat up close; the sign lettering is soft in bright daylight.
* Grass is hidden under built floors with a soft-edged mask, so a few blades can poke 0.3–0.5 m into the
  edge of a structure.
* The `energy` argument of the shared "glow" material has no visible effect (unshaded materials ignore
  it); affected glows were tuned by eye, so this is cosmetic only.

## Chapter Two — open items after integration pass 3 (2026-09-28)
Chapter Two ("The Lanterns of Hallowmere") is fully built: every area, the three Chapter Two bosses (Count Velour, the Matron at
Weaver's Crossing, the Borrowed Choir), Echo Trials for all three trial bosses (the Weaver Matron, Count Velour, the Borrowed Choir),
the Lanternwake Expeditions, the Music Box and the onboarding tips. Decisions: `docs/ch2/INTEGRATION_WAVE_BC.md` (pass 1),
`docs/ch2/INTEGRATION_WAVE_D.md` (pass 2) and `docs/ch2/INTEGRATION_PASS3.md` (pass 3, after bug-fix round 1 CH2-001..017 and the
visual fixes). Checked so far (`QA_REPORT.md` §10): headless automated tests; the QA bot's five route segments S0-S4, driven through
the game's QA input port (virtual input into a headless engine: no OS-level input, nothing rendered); and still frames rendered on the
second monitor by the visual reviewers (110 findings) and their fixers. **No human has played Chapter Two, no OS-level real-input
run has been done, nothing has been judged in motion on screen, and nobody has listened to it.**

### Open work (decided in pass 2, not done yet)
* **New voices (D10).** Every Chapter Two enemy and boss (and the Chapter One additions) uses existing, test-verified sound names:
  safe, and the arachnophobia swaps work, but many creatures share voices. Planned as ONE dedicated audio pass (the `tools/audio`
  sfx generators + Audio index / aliases, then point each script's / data's "voice" at its names, with arachnophobia variants for the
  Crossing), followed by a human listening check. The requested voices: Brambleback, Lantern Moth, Hollow Drudge, Brood Skitter /
  Pale Sprout, Knotted Elder; Pumpkin Mimic (stem rustle, snap, roll), Patchwalker (straw, rake, splat), Velvet Wing (squeak, cape,
  drain), Bellcap Sentry (swell, toll), Borrowed Wisp (false chime, gutter), Quarry Warden (grind, triple toll, crack); Count Velour
  (`velour_bow`, `velour_laugh`, `bat_flock`, `velour_reform`, `candle_snuff`, `velour_dazzled`, `crown_glint`,
  `enchantment_break`); the Crossing (`matron_final_click` / `mother_final_sigh`, `matron_thread_whip` / `mother_roots_lash`,
  `matron_retreat` / `mother_withdraw`); the Borrowed Choir (`choir_bell_toll`, `choir_ring_hum`, `choir_welcome_chord`,
  `choir_release_chimes`, `choir_mask_fall`, `choir_form_burst`, `choir_flame_settle`).
* **Test hygiene (F04).** The test runner's isolation still repairs leaks on every full run (stray projectiles / particles from the
  enemy, wand and companion suites, `Game._bosses` from the boss suites, zone flags, Reach world items); its `ISOLATION <suite>`
  lines name them. No per-suite cleanup yet: the runner's guard is the safety net, and no test fails because of it. Not a player issue.
* `.uid` files: 398 of the 704 scripts under `game/` have no `.uid` yet (counted in pass 3) - most scripts added since Wave B and
  every pass-3 addition (`src/camera/camera_block.gd`, `src/enemies/creature_fx.gd`, the new unit tests, `tests/fixtures/prefetch/*`).
  The one editor import planned for the end of pass 2 (D09) has not run; it is a release step (`--import` once, alone, after the
  last code change and a green full suite; R3-47). Scripts load by path, so nothing breaks without them.
* Left for their owners after pass 3 (player-visible, small): the lamp-stage tracker card can list up to 8 rows (3 "Find the ...
  lamp" rows + the lamp roads; R3-03, UI); the day dial shows a day sky inside Moonveil Manor, where it is always night (R3-43, the
  HUD half of IN-13, UI). The UI group's own visual findings (UI-00..UI-22) were still being fixed when pass 3 closed (no report
  yet), so they are not counted here.
* Onboarding tip pacing (2.5 s calm, 25 s between tips, 30 s after a horror moment) is untuned: a Chapter One save can see about
  five tips in its first minutes (P50, kept until a real play session).
* The Bell Throat echo stone stands at (153.6, -28, 27.6), next to the checkpoint; if the wall rocks touch it on screen it moves to
  about (153.4, -28, 24.75) (one data line, L10).

### Visual checks still to do (windowed debug build + screenshots; commands in AGENTS.md)
Since pass 3 a first still-frame review has covered much of this list (`qa/tmp/visual/VISUAL_BUGS_MERGED.md`: avatar, building,
creatures, interiors, Reach, UI) and the fixers re-rendered their fixes on the second monitor (`QA_REPORT.md` §10). Pass 3 finished the
fixers' cross-file requests and rendered them as stills too: the outfit palettes AV-13 / 14 / 15 (G6), the trip posts, the Crossing
Matron's scar and mantle and the Choir's paper-lantern false lights CR-03 / 05 / 14 (G4), the Woods waygate and Tobin's side-door
arrival cameras (G2). Still open: the partly fixed AV-11 / AV-12 / AV-19 (see "Known small limitations"), the UI findings (still being
fixed when pass 3 closed), and every item below in motion rather than as stills.
* Avatar: every hairstyle, garment, hat and armor fit; skirt and cape sway; belt lantern / satchel / long-hair clipping; the wand
  model and cast pose; ghost-wing glow; the four trial-pattern parts (masquerade mask worn in the hair - never over the face -, opera
  cloak sway, chime ribbons, chorister capelet) with hair, hats, armor, lantern and satchel, and both patterns in the wardrobe grid.
* Meet Krystal and wardrobe screens (preview lighting, long names, the notice card, the "missing options" line); the new settings rows
  and the controls overlay's Building column.
* Equipment column, stats card, empty-slot icons, HUD shield overlay, build bar window and key caps, underground HUD tint, Friends
  panel, companion cooldown ring.
* Journal (five tabs); Woods and Reach maps (labels, "?" pins, arch pins, festival roads, gold pins, mastery pins / cache hints,
  Bramblewatch label, new map glyphs, expedition pins with the current-stop ring and legend); room lists; the gathering sparkle;
  the tracker's expedition card.
* Building: all new models, pumpkin faces (incl. the festival faces), dyed pieces, two-storey preview modes, expanded Haven, crop
  stages ×4, planter, furnace glow (steady with Reduce flashing), storage panel at 40/48 slots.
* Chapter One extras (Tailor's Cache, stumps, meadow, Bramblewatch roots, sticky tree, moth pocket, seasonal decor) and Tobin's
  side door, hatch and annex rooms.
* Enemies: every Chapter One and Chapter Two silhouette under orchard / Candleyard / manor / quarry / Works lighting, tells and ground
  marks on slopes and terraces, high-visibility outlines; the mimic's mouth, the Wisp veiled vs revealed in the dark Works (the veiled
  wisp at 2.9 m under 3.2-3.4 m corridor ceilings) and the new Hall of Closed Eyes wisp, the Bellcap arrows, the Warden's shell split
  and pulse pips; the Matron's hazards in the dark arena and every arachnophobia variant.
* Bosses: Count Velour (figure and cape, the red dash lane and his shadow on the crimson rug, the gold-ring safe lane and the collared
  true bat at distance, the Intense crown flash, the defeat burst, bats vs pillars, the resident appearing after the dispersal); the
  Crossing Matron / Hollow Mother (rings and the final tell readable with the sound muted, threads blocking one lane, the side change,
  the retreat through the opening and the gate dropping after it, hints, outlines); the Borrowed Choir (plates and forms, genuine vs
  false tells, ring openings, the lit sector and strike marks, masks and ribbons falling).
* Wave D: both trial arenas (the Gallery copy, the rotated vault copy), the echo stones in the Below, the manor ballroom and the Bell
  Throat, the trial menu text; the Expedition panel (cards, difficulty pips, reward types), the ribbon lantern (calm, no pulse with
  Reduce flashing) and the end cache; the Music Box panel (780 px wide, not full-screen) and the dancer.
* Hallowmere Reach (arrival view, Commons day/night, autumn colours, forest edge and brook, Conservatory, Bellhouse, linking
  ceremony, orchard, pools, Candleyard, quarry gangway), Moonveil Manor (facade, mirrors, ballroom, camera under low ceilings), the
  Hushed Works rooms 1-14, both ending screens, chapter cards, celebrations, road lanterns at distance, the Ward Stone keepsake.

### Listening still to do
* A human listening pass over the 22 new compositions (every cue m01-m27 except the five retained Chapter One files) and their
  layers; the Music Box preview start / stop / fade and whether favourites are audible in the Haven rotation; then the D10 voices
  once they exist.

### Real-input checks still to do (keyboard / mouse)
* Wardrobe grid (arrows / Enter, drag to turn, typing a preset name, every Esc path), the O key (also over the pause menu), rebinding
  the build keys Z / P / N and the hints then naming the new key, dragging onto equipment slots, map toggle, Q/E journal tabs, scroll
  wheels, reopening panels with arguments.
* The T companion-skill key (with UI focused, after rebinding, with no follower); companion navigation in real Below / Works corridors,
  on stairs, upper floors, the quarry gangway and the brook; companions changing storey rely on the 4 s stuck recovery.
* Walking stairs to an upper floor, Continue while upstairs, a bed upstairs.
* Fights: Brambleback / Elder charges, moth rest window, Drudge in the narrow hall, mimic pocket, Patchwalker (clod slow caption),
  Bellcaps; the Quarry Warden (the bot now takes 40 s with 2-3 exposures and the owed pulses; a human first attempt with copper gear
  is untested; a charge baited near the upper edge now stops or bonks there; pulses vs knockback and rolls); the Velvet Wing's punish
  window and the drain rule (a raised lantern inside the mark breaks it, Lumi's glow does not, Glimmerstep does); the wisp's dazzle
  cooldown and proximity hint; Matron timing vs camera latency.
* Bug-fix round 1 checks that need real play (R3-49): an ordinary enemy losing Krystal behind a wall (the Looking-Glass Hall Velvet
  Wing, CH2-006: only unit-tested, the bot killed it) and saving right after; a Reach tree respawning after its 1440 in-game minutes
  (unit-tested only); every enemy's ground telegraph with the new dark contrast band on grass, stone and the ballroom floor; the
  Chapter One Hollow Mother's new edge light; the avatar limits below in motion.
* Bosses: Count Velour's pacing (target 2-4 min; the bot takes 78 s with no deaths), damage taken without dodging, the light-stagger
  reach, `--velour-phase=2|3`; the Weaver Matron's first-encounter length after CH2-003 (bot 45-71 s, all phases shown); the Crossing
  Matron (a human first attempt vs the ~2-4 min target: the bot takes ~65 s, the scripted rusher 43 s; the primed-anchor caption and
  hint read in play; camera after a side change, long far-anchor pounces, pounce knockback vs kindling, two Brood Skitters leaping 0.85 s
  apart); the Borrowed Choir (4-6 min target pace, the 60 % sweep lock, the Intense feint).
* Echo Trials: a full Velour and Choir trial each (win, fall, leave by the pale door, Continue from inside), the repeat-clear gift paid
  on arrival at the stone with a full backpack, a first-clear pattern sewn at the Loom and worn.
* Expeditions: one full route of each (Orchard Patrol, Quarry Circuit, Manor Afterglow) incl. the panel's Lantern Road hop, spawns never
  in view, a fall mid-route (only the standing enemies return), save / quit mid-run and resume.
* Onboarding pacing on a Chapter One save and in Chapter Two; tips never during fights, trials or horror moments.
* Bellhouse stair and the Foreman's Key gate, the annex stair, ladders, winch cage and Bell Throat dialogs, the servants' stair,
  Continue from manor / Works checkpoints, celebration and ending skips, the Commons dialog, mouse capture after Continue.
* A second-monitor QA-bot playthrough with the updated bot (it now confirms "Meet Krystal", answers the wardrobe card and reads the
  Chapter Two telemetry).

### Performance still to measure
Cold first loads of the Reach (target under ~1.5 s after the warm-up changes), of the Works and of the manor with Count Velour, each
Echo Trial's entry, release-build load times, the Reach's frame rate and draw calls (~300 tree nodes plus outlines).

### Known small limitations (reviewed and kept)
* Avatar (after the pass-3 visual fixes, `qa/tmp/visual/fix_avatar/sheets/`): late in the dodge roll the tucked body still hovers
  briefly (AV-19: the Chapter One roll motion is pinned by the legacy motion test); the witch hat now folds to 45 % of its height while
  rolling, and the roll pivot lifts 0.457 m with no hat, 0.545 m with the sun hat and 0.481 m with the witch hat, so a tall hat can
  still make her look as if she floats. Skirts open as one piece when running and bunch in a roll (AV-11), but small slits still show
  at full sprint (no underskirt) and the knees show through skirts in the sleep / sit pose; whether a long skirt still dips into the
  ground mid-roll has not been re-measured. Long hair drapes over bulky back items, but long hair with the paper lantern pack still
  touches it slightly (AV-12, drape capped at 0.5 rad), and long hair can pass through the shoulders when she turns her head (as the
  Chapter One braid does). The belt lantern and satchel can cut into flared skirts. Under show-armor body pieces the jacket / cardigan
  buttons, pockets and plain hems are now covered (AV-04), but the Cloud Cardigan's fluffy cloud hem and the Velvet Ruffle Bodice's
  white collar still show round every body armor set (re-rendered in pass 3: `qa/tmp/visual/g1_pass3/armor_hem_recheck.png`). Hair no
  longer shows through helms or hoods (AV-02; braided crown re-rendered: `qa/tmp/visual/g1_pass3/crown_helm_recheck.png`).
* Developer logs only (CH2-011, decision R3-16: accepted as engine-internal): quitting can still print "WARNING: N ObjectDB instances
  were leaked at exit" (N varies between runs, e.g. 3-8). Our own source - background loads never claimed at quit - is fixed
  (`Game.release_prefetches()`, `test_flow_quit_prefetch.gd`); a `--verbose` probe (`qa/tmp/bot/s1/vfix_verbose`) shows only bare
  RefCounted objects with a reference count of 0, from engine background compiles and headless WAV playback. No player-visible
  effect; revisit only if a Godot update changes it. (The full test suite also ends with such a line.)
* A gameplay hotkey pressed in the wardrobe opened over the pause menu opens that panel with pause still underneath (like the
  controls overlay; tested not to softlock).
* The furnace queue does not advance while its (fullscreen) crafting panel is open. Furnace jobs from a newer game version are kept
  but not refunded when the furnace is dismantled.
* A full backpack shows both a panel line and a toast; a velvet scrap shows both "Obtained" and "Velvet scrap found (n of 3)".
* Companions: only Mochi reacts to horror cues; Lumi's night lamp visit only finds lamps that are both light sources and structures;
  the gear-tier damage bonus counts weapons in the backpack, not in chests; a pet that falls during a boss fight and never stood on a
  floor while following is not recovered (very rare); Brave Little Steps needs the Loom (Tailor's Cache) first.
* Map: Krystal's and friends' markers can overlap place names (as on the Chapter One map).
* Legacy sweetroot crops are over the newer per-plot triangle budget (unchanged Chapter One shapes).
* The Intense turning pumpkin turns while watched from 16 m or more (kept: still distant, silent and slow).
* Echo Trials open as soon as their boss is defeated; the story flag `ch2_trials_open` gates nothing (its "Old echoes stir..." line is
  flavour). Count Velour's memory starts with all three candles lit (he was already taught in the story).
* Music Box: with the Music volume muted nothing new is discovered and a started song keeps saying "Now playing" until Stop or leaving
  the house; a preview ended by a fight is not resumed; playing the piece that is already on continues it; favourites can bring any
  heard calm piece (e.g. the mine's "The Last Shift") into the Haven rotation, at most two extra per round.
* Expeditions: setting a run aside mid-fight (only possible from the Commons outpost board) makes the group vanish; a dye keepsake
  unlocks the Loom colour directly, without its crafting cost.
* Fights (kept by design): the Quarry Warden is an elite and gets the ordinary combat music; only the Velvet Wing feints among the
  ordinary enemies (the others rest less on Intense), and some ordinary tells are longer than 1.4 s; a veiled wisp can still make its
  marked, delayed sweep; the Choir can be beaten without striking it (exposures end the fight), and without a lantern its fight cannot
  progress (she can always leave); friends' blows while Count Velour channels also lift his mask floor; the Crossing Matron can release
  two Brood Skitters that leap 0.85 s apart (never together with a pounce); a raised lantern anchor cannot be re-raised to refresh it
  (the Choir works around it; the practice anchor's disabled prompt explains the wait).
* Fight pacing rules from bug-fix round 1 (kept by design, pass 3): the Quarry Warden needs 2-3 pillar exposures with early gear (at
  most 35 % per exposure, and phase 2 always plays its three pulses first); the Crossing Matron takes three exposures, one per phase,
  and a brazier lit before she has attacked only "catches" her anchor (her next pounce exposes her) - without a Lantern her HP floor
  is off so blows alone can still finish her; the Weaver Matron needs at least two openings in each of phases 2 and 3, and a scorch
  before a phase's first action waits for it. Count Velour's last blow is never trimmed by his 16 % window cap (only possible at the
  very end of phase C), while the Weaver Matron and the Quarry Warden trim even a finishing blow to their cap (decision R3-10).
* Ordinary enemies give up a hunt after 5 s without seeing Krystal (sight or a hit resets it) and walk home, so they stop blocking
  saves and travel; elites and bosses never give up this way (decision R3-18). A Continued Chapter One save gets no discovery XP for
  Chapter One landmarks it already proves visited - the one-time legacy credit stands in for them (decision R3-17).
