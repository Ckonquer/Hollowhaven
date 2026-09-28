# Known issues — Hollowhaven (Chapter One; Chapter Two in development: see the last section)

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

## Chapter Two (in development) — open items after the Wave B/C integration pass (2026-09-28)
Chapter Two ("The Lanterns of Hallowmere") is still being built. This list is the honest state after the Wave B/C integration pass;
the decisions behind it are in `docs/ch2/INTEGRATION_WAVE_BC.md`. Everything below was verified only by headless automated tests:
**no Chapter Two screen, model or fight has been looked at on screen or played with real input yet.**

### Deferred work (files were busy during the pass, or it needs a tool that was not allowed)
* QA bot: New Game must click "Confirm" on "Meet Krystal"; runs continuing an old save must dismiss the one-time wardrobe card
  (or pass `-- --no-wardrobe-notice`); the bot does not read the new telemetry keys yet (D01, D11).
* No wardrobe hotkey yet (open it from the pause menu, the Ward Stone or a wardrobe / vanity mirror) (D02). The build-mode keys
  Undo (Z), Recolour (P) and Face (N) are fixed fallback keys, not rebindable yet (D03).
* Lumi's Glimmerstep light pulse does not "expose" the light-fearing Chapter Two enemies yet (D04).
* One enemy test (`test_enemies_ch2_mimic` dormant twitch) can be timing-flaky until its RNG is seeded (D05). (The former flake
  `test_player_avatar.test_idle_head_height_and_blink` is fixed: the test now pushes the next random blink out of its window.)
* The Quarry Warden's charge is not stopped at its arena edge; a charge baited near the upper ledge can carry it down a level (D06).
* Count Velour, the Crossing Matron and the Borrowed Choir were still being built: their full fights, trial modes and the Echo Trials
  for Velour and the Choir are not integrated or verified (D07, D08). Areas fall back safely when a boss script is missing.
* `.uid` files for the new scripts need one editor import (D09). New enemy voices (Brambleback, Lantern Moth, Hollow Drudge, Brood
  Skitter / Pale Sprout, Knotted Elder) still use existing sounds (D10).

### Visual checks still to do (windowed debug build + screenshots; commands in AGENTS.md)
* Avatar: every hairstyle, garment, hat and armor fit; skirt and cape sway; the wand model and cast pose; ghost-wing glow.
* Meet Krystal and wardrobe screens (preview lighting, long names, the notice card, the "missing options" line); the new settings rows.
* Equipment column, stats card, empty-slot icons, HUD shield overlay, build bar window and key caps, underground HUD tint, Friends
  panel, companion cooldown ring.
* Journal (five tabs); Woods and Reach maps (labels, "?" pins, arch pins, festival roads, gold pins, mastery pins / cache hints,
  Bramblewatch label, new map glyphs); room lists; the gathering sparkle.
* Building: all new models, pumpkin faces (incl. the festival faces), dyed pieces, two-storey preview modes, expanded Haven, crop
  stages ×4, planter, furnace glow (steady with Reduce flashing), storage panel at 40/48 slots.
* Chapter One extras (Tailor's Cache, stumps, meadow, Bramblewatch roots, sticky tree, moth pocket, seasonal decor) and Tobin's
  side door, hatch and annex rooms.
* Enemies: Chapter One and Chapter Two silhouettes, tells and ground marks on slopes, high-visibility outlines, the Matron's hazards
  in the dark arena and every arachnophobia variant, the echo stone and trial room.
* Hallowmere Reach (arrival view, Commons day/night, autumn colours, forest edge and brook, Conservatory, Bellhouse, linking
  ceremony, orchard, pools, Candleyard, quarry gangway), Moonveil Manor (facade, mirrors, ballroom, camera under low ceilings), the
  Hushed Works rooms 1-14, both ending screens, chapter cards, celebrations, road lanterns at distance, the Ward Stone keepsake.

### Real-input checks still to do (keyboard / mouse)
* Wardrobe grid (arrows / Enter, drag to turn, typing a preset name, every Esc path), hotkeys with the wardrobe over the pause menu,
  dragging onto equipment slots, map toggle, Q/E journal tabs, scroll wheels, reopening panels with arguments.
* The T companion-skill key (with UI focused, after rebinding, with no follower); companion navigation in real Below / Works corridors,
  on stairs, upper floors, the quarry gangway and the brook; companions changing storey rely on the 4 s stuck recovery.
* Walking stairs to an upper floor, Continue while upstairs, a bed upstairs.
* Fights: Brambleback / Elder charges, moth rest window, Drudge in the narrow hall, mimic pocket, Patchwalker, Bellcaps vs the
  Warden, Matron timing vs camera latency, and the three Chapter Two bosses once they land.
* Bellhouse stair and the Foreman's Key gate, the annex stair, ladders, winch cage and Bell Throat dialogs, the servants' stair,
  Continue from manor / Works checkpoints, celebration and ending skips, the Commons dialog, mouse capture after Continue.
* A second-monitor QA-bot playthrough once the bot knows "Meet Krystal" and the wardrobe card.

### Performance still to measure
Cold first loads of the Reach (target under ~1.5 s after the warm-up changes) and of the Works, release-build load times, the Reach's
frame rate and draw calls (~300 tree nodes plus outlines).

### Known small limitations (reviewed and kept)
* Avatar: while rolling or sitting (sleep, death) the legs can poke ~3–4 cm through skirt panels and long skirts can dip ~6–7 cm into
  the ground mid-roll; tall hats lift the roll (witch hat +18 cm) so she may look like she floats; the belt lantern and satchel can cut
  into flared skirts; body armor does not fully cover the cloud cardigan hem or the ruffle collar; the braided crown can show through a
  helm; long hair can pass through the shoulders when she turns her head (as the Chapter One braid already does).
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
