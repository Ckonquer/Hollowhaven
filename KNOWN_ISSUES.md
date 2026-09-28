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

## Chapter Two — open items after integration pass 2 (2026-09-28)
Chapter Two ("The Lanterns of Hallowmere") is fully built: every area, the three Chapter Two bosses (Count Velour, the Matron at
Weaver's Crossing, the Borrowed Choir), Echo Trials for all three trial bosses (the Weaver Matron, Count Velour, the Borrowed Choir),
the Lanternwake Expeditions, the Music Box and the onboarding tips. Decisions: `docs/ch2/INTEGRATION_WAVE_BC.md` (pass 1) and
`docs/ch2/INTEGRATION_WAVE_D.md` (pass 2). Everything below was verified only by headless automated tests: **no Chapter Two screen,
model or fight has been looked at on screen or played with real input yet, and nobody has listened to it.**

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
* `.uid` files for the scripts added since Wave B come from one editor import at the very end of pass 2 (D09); scripts added later
  need another import.
* Onboarding tip pacing (2.5 s calm, 25 s between tips, 30 s after a horror moment) is untuned: a Chapter One save can see about
  five tips in its first minutes (P50, kept until a real play session).
* The Bell Throat echo stone stands at (153.6, -28, 27.6), next to the checkpoint; if the wall rocks touch it on screen it moves to
  about (153.4, -28, 24.75) (one data line, L10).

### Visual checks still to do (windowed debug build + screenshots; commands in AGENTS.md)
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
  Bellcaps; the Quarry Warden (fight length, estimated 1.5-3 min with copper gear; a charge baited near the upper edge now stops or
  bonks there; pulses vs knockback and rolls); the Velvet Wing's punish window and the drain rule (a raised lantern inside the mark
  breaks it, Lumi's glow does not, Glimmerstep does); the wisp's dazzle cooldown and proximity hint; Matron timing vs camera latency.
* Bosses: Count Velour's pacing (target 2-4 min), damage taken without dodging, the light-stagger reach, `--velour-phase=2|3`; the
  Crossing Matron (camera after a side change, long far-anchor pounces, pounce knockback vs kindling, fight length ~2-3 min, two Brood
  Skitters leaping 0.85 s apart); the Borrowed Choir (4-6 min target pace, the 60 % sweep lock, the Intense feint).
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
