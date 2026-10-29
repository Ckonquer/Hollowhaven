# Hollowhaven · Game Spec (Chapter One: "The Dimming Ward" · Chapter Two: "The Lanterns of Hallowmere")

A small, complete 3D survival-adventure. Cozy storybook woodland on top (~70%), adventure and friendly
combat (~20%), and a restrained, fair horror dungeon below (~10%). Target: 45–90 min first playthrough,
then cozy free-play. Engine: Godot 4.7.2 (GDScript, Forward+). Platform: Windows PC.

## Fantasy
Krystal makes a home in an adorable wilderness, befriends strange little creatures, gathers resources
and explores. Beneath that comforting world lies something ancient that should have stayed buried.

## Tone rules
* Surface: warm, colourful, playful, alive, rewarding. Nothing punishing.
* Below: quiet, unfamiliar, claustrophobic, occasionally genuinely frightening. Restraint > volume.
* Use "Krystal" sparingly and naturally (title dedication "For Krystal", "Krystal's Haven" sign, a few
  inscriptions/creature lines). Never a greeting card.
* Everything original: names, creatures, sounds, visuals. No copied assets or recognisable IP.

## Story (short)
Long ago the Ward Stone at the heart of the clearing held back something that nests deep beneath the
old mine. Its heart, the **Heartseed**, was carried below by the **Weaver** (arachnophobia mode: the
**Hollow Mother**), and the ward has been dimming ever since. Krystal arrives at the overgrown clearing,
repairs it into a home, befriends Mochi, Pebble and Lumi, prepares, descends through the Old Mine, the
drowned Ruins and the Silk Hollows, drives the Weaver back with light, reclaims the Heartseed and returns
it. The Haven blooms. The creature retreats into the deep crack below (sequel hook) — it is not killed
on screen, no gore.

Ward Stone inscriptions (examples; keep short, a little old-fashioned):
* Intro: "Light kept, home kept. The seed sleeps below; the stone remembers." then "Welcome, Krystal. This haven has waited a long time for someone to love it."
* Warning (step "prepare"): "Its heart was taken to the deep. What took it still weaves in the dark. Carry light. Carry friends. Come home." (arachnophobia mode: "...still waits in the dark...")
* Restored: "Light kept. Home kept. Thank you, Krystal."

## Surface: Hollowhaven Woods (~220 m square, see game/data/world_layout.gd)
Landmarks: Krystal's Haven (clearing, Ward Stone, campfire, start), Berry Glade (W, Mochi), Pebble Quarry
(E across the stream, Pebble, copper), Moonlit Ruin (N, Lumi, Bramblings), Hollow Mine (NE cliff, dungeon
entrance sealed by rubble), Mirror Pond (SE), Sunny Meadow (S, flowers), The Old Oak (giant tree),
Thornthicket (NW, Bramblings). A stream runs N→S into the pond; 3 crossings (bridge / stepping stones).
Soft natural boundary: hills, dense tree walls, cliffs. Day/night cycle (~18 real min/day, short night).

## Core loop
gather → craft → befriend → build → prepare → descend → recover treasure → return and improve the haven.
Quest chain in game/data/quests.gd (state-checked objectives, contextual hints).

## Systems summary
* Movement: third-person, camera-relative, sprint (stamina), jump, dodge roll (i-frames), slopes/stairs
  (stairs have ramp collision), fall recovery.
* Gathering: sticks/stones/grass/berries by hand (E); trees need an axe, rocks/ore need a pickaxe (LMB,
  tool auto-selected). Nodes respawn after ~1 in-game day. Satisfying feedback: wobble, chips, sound, pop.
* Inventory: 32 slots, first 8 = hotbar. Stacks, tooltips, storage chests (20). Full backpack → items
  drop as persistent pickups (never destroyed). Quest items live in a key pouch.
* Crafting: small transactional recipe set (game/data/recipes.gd), stations: hand / workbench / campfire.
* Building: Haven-only, grid-snapped (1 m cells, 2 m floors/walls/roofs), ghost preview green/red,
  rotate R, dismantle X (full refund), never traps the player, never blocks routes (outside Haven).
* Farming: crop plots, Sweetroot seeds → 4 stages → harvest. Mochi at home tends crops (faster growth).
* Survival: health 100, stamina 100. Food heals (+ buffs). No hunger. Death → wake at bed/Haven or last
  lit dungeon lantern, full health, no item loss, companions safe.
* Combat: LMB swing (weapon or best tool), readable telegraphs (wiggle / eye flare / rattle), hit flash,
  knockback, tiny hitstop, fair damage, recovery windows. Surface enemy: Brambling. Below: Gloomling
  (fears lantern light: hesitates, takes double damage when lit). Stalker/boss: the Weaver.
* Companions: Mochi (forager, timid, won't enter the mine — waits at the threshold), Pebble (miner,
  brave, gifts), Lumi (lightbearer, notices threats). One follows at a time; others stay home. Bond 0–5.
* Horror director (local, offline): calm → unease → anticipation → encounter → recovery; cooldowns,
  weighted selection, repetition avoidance, safe spawn validation, threat budget, often does nothing.
* Comfort: horror intensity (Gentle/Standard/Intense), arachnophobia mode (Weaver → Hollow Mother, webs →
  pale roots, silk → pale thread, sounds/icons/names swapped), reduce shake, reduce flashing, captions,
  separate music/ambience/SFX/UI volumes. Shown on New Game and before the mine; editable any time.
* Save: autosave on area change, sleeping, lantern checkpoints, chapter end, New Game, a quiet surface
  autosave every 5 minutes and on window close (surface); manual save from pause on the surface (not while
  chased). Versioned JSON, atomic write, backup.

## The Below (one authored dungeon, 11 spaces, three moods)
Old Mine (amber lantern light, timber, rails):
 1. **Mine Landing** — safe; first lantern checkpoint; exit back up. Mochi never comes past the surface mouth.
 2. **Timbered Tunnel** — rails, carts, glowcaps; distant pickaxe sounds. **THE THRESHOLD**: Lumi stops at a
    dark side passage, watches it, then moves close behind Krystal. Nothing attacks. A quiet beat.
 3. **Collapsed Gallery** — first Gloomlings (teach: lantern makes them flinch; eyes flare before swipes).
    Rubble to mine through.
 4. **Foreman's Office** — lore note, the **Foreman's Key** (guaranteed, never random), checkpoint lantern.
 5. **Lower Gate** — locked gate opened with the key → spiral stair down.
Unsettling Ruins (cold teal light, carved faces, shallow water):
 6. **Descent Stair** — narrow, scratching above.
 7. **Hall of Faces** — pillars. **THE DISTANT CROSSING**: a pale shape crosses a doorway far ahead. The
    doorway reveals drag marks, a dropped miner's lantern and a strand of silk/root — a clue, no attack.
 8. **Drowned Shrine** — **THE IMITATION**: a "Lumi" appears on the far side and chimes. Tells: its light
    is cold blue-white (real Lumi = warm gold), it casts no light on the ground, it moves in stiff jerks,
    and its chime is reversed. If the real Lumi is with you it hides behind Krystal and whimpers. Walking
    toward it makes it fold into darkness with a (intensity-scaled) hiss; the real path is the other way.
    Always survivable, never a random guess. Checkpoint lantern after.
Silk Hollows (violet-grey, webs thicken; arachnophobia: pale roots):
 9. **Webbed Passage** — webs densify; stalker ceiling routes; teach the countermeasure: it rattles before
    lunging; it retreats from lantern light and lit braziers; breaking line of sight works.
10. **The Nursery** — optional side cave with silk and echo shards; silence; nothing attacks (empty space
    where an encounter seemed likely).
11. **Heartseed Chamber** — boss arena: the Weaver Matron clings to the ceiling; three braziers. Lighting
    a brazier (hold E near it, lantern needed) burns away its ceiling anchor and drops it, stunned — the
    damage window. After HP 0 it shrieks and retreats into the deep crack; the Heartseed is freed. A lift
    shortcut opens back to the Mine Landing. Checkpoint before the arena.
THE RETURN: stepping out of the mine at dusk/day, the surface music swells gently; companions reunite
(Mochi bounces over); returning the Heartseed triggers the restoration: ward light blooms, flowers and
fireflies spread across the Haven, lanterns light, companions celebrate, "Chapter One Complete" + credits,
reward: Haven Banner + Heartbloom Lamp recipe. Then free-play continues (optional goals).

## Art direction
Storybook woodland: soft shapes, toon ramp shading with lavender ambient shadows, gentle rim light,
painterly noise, outlines on characters/creatures/key props, warm honey sunlight, inviting foliage with
wind sway, readable materials. Palette: game/src/art/palette.gd. Dungeon keeps the same shapes and
shading; mood comes from lighting, fog, composition, animation and sound. Darkness is atmospheric but
navigable: interactables and exits always readable (emissive accents, lantern pools, glowcaps).

## Audio direction
Soft, organic, synthesised originals (tools/audio). Surface: birds, leaves, stream, gentle music-box /
plucked melody. Below: drones, drips, creaks, distant echoes, very sparse stingers (never ear-splitting;
limiter on master). Companions each have a distinct voice (Mochi squeaks, Pebble clacks, Lumi chimes).

## Controls (defaults, rebindable)
WASD move · Mouse look · Space jump · Shift sprint · Ctrl/V dodge · LMB attack/gather · RMB/Q eat/use ·
E interact · F lantern · Tab/I inventory · C crafting · B build (R rotate, X dismantle) · J journal ·
M map · G companion follow/wait · 1–8 hotbar · Wheel zoom · Esc pause · F1 controls · F12 screenshot.

## Chapter Two: "The Lanterns of Hallowmere" (a continuation of the same save)
Design: `Hollowhaven_Part2_Master_Prompt.md`. Implementation contract (wins where they differ):
`docs/CHAPTER_TWO_SPEC.md`. Save schema v2 and rollback: `docs/SAVE_MIGRATION.md`. Player guide:
`docs/player/How to Play.txt` (both chapters; the returning-player update note was retired in 2.0.3). Everything above stays true; Chapter Two only adds. Status: every
Chapter Two system is built and covered by headless tests; what is still to be checked on screen, by ear or with real
input is the Chapter Two section of `KNOWN_ISSUES.md`.

**Continuity.** Continue loads the Chapter One save unchanged: house, chests, crops, companions, flags, quest
index, lore and clock. Migration only adds sections; the untouched v1 file is copied once to
`saves/pre_v2_backup/`; a save from a newer version is refused, never overwritten. Chapter Two is a separate
stable-id quest layer (`data/quests_ch2.gd`) beside the untouched legacy chain; every reward is granted once
through a reward ledger. The game never builds or places anything inside Krystal's house.

**Start by choice.** After `chapter_one_complete` the tracker says "The Ward Stone has something new to say".
The stone's new inscription offers "Follow the lantern road" / "Stay a little longer" (asked again later).
Declining hides nothing: the wardrobe, gear, building and companion upgrades are available either way.

**Story (short).** A waygate north of the Moonlit Ruin (8 wood, 4 stone, 2 copper ore) opens the way to
**Hallowmere Reach**, an autumn festival town whose Lanternwake never finished. Krystal lights the Commons arch,
wakes three festival lamps in any order (Pumpkintide Orchard, Ashbell Quarry and its Quarry Warden, Moonveil
Manor and the theatrical vampire **Count Velour**), links them at the Ward-Keeper's Conservatory and goes down
the Sunken Bellhouse (the Foreman's Key opens it, and is not used up) into the **Hushed Works**: Hask's rail,
the miners' refuge garden, three ward lines (water, bell, light), **Weaver's Crossing** where the escaped
Matron returns (arachnophobia: The Hollow Crossing / Hollow Mother), a house that isn't, and the final
**Borrowed Choir**. The roads relight, the Ward Stone welcomes her home ("Light kept. Roads found. Welcome
home, Krystal."), the Lanternwake is celebrated, and free play continues in the same save.

**New places.** Hollowhaven Woods gains Tobin's side door and annex by the mine mouth, the Tailor's Cache near
the Old Oak, Bramblewatch (Bramblebacks and the Knotted Elder), wild sunflax and roseberries in the Sunny
Meadow, sap stumps, Mochi's courage lantern, lantern moths near Mirror Pond at dusk and a bigger Haven build
area. New areas: `tobin_annex`, `hallowmere_reach` (Commons, Conservatory, Orchard, Thimblebrook Pools,
Candleyard, Quarry, Manor grounds, Bellhouse), `moonveil_manor` (five rooms), `hushed_works` (14 rooms) and
`echo_trial`. Return is always open: the Reach waygate leads home, lit arches form the **Lantern Road** (fast
travel between arches and to the Haven; also from the Ward Stone), never while chased or in a boss fight.

**Expression.** New Game opens "Meet Krystal" (hair style and colour, skin, eyes, outfits, single pieces,
colours). Existing saves get a one-time "Your wardrobe is ready" card; later the Wardrobe is on the O key, in the
pause menu, at a built Wardrobe or Vanity Mirror, at the Ward Stone and at the Commons festival mirror. Three
presets. Clothes are cosmetic only; armor protects whether or not "Show equipped armor" is ticked.

**Companions fight.** Each friend has a passive, a basic attack and a signature skill on a shared cooldown:
Mochi (Bloomguard, heal over time), Pebble (Stoneheart, shield), Lumi (Glimmerstep, speed and a light pulse
that exposes Gloomlings). Autocast when it helps, or the Companion Skill key (T). Their menu (E) sets Assist /
Stay close, automatic attacks, autocast, a home spot (Companion Bed / Perch) and ribbons; bond perks at 2 / 3 / 5
hearts.
Mochi comes underground after the Comfort Ribbon and a rest by the lit lantern at the mine's mouth.

**Progression.** Furnace (queued bars: copper, iron, moonsteel), Loom & Dye Bench (cloth, clothing patterns,
dyes, backpack 40 / 48), Kitchen Counter (festival food). Tools and weapons in stone, copper, ironwood and
moonsteel tiers; padded, copperwood, ironwood and moonsteel armor; charms; the Sparkseed Wand. Chests upgrade
to 40 slots; crafting can draw on nearby chests. New crops: sunflax, roseberry, pumpkin. Three small masteries
(gathering, hearthcraft, wayfinding) with modest bonuses and conservative credit for old saves; no rank ever
gates the story.

**Building.** Two storeys (stairs, upper floors held up by full walls, windows, doorways or porch posts; nothing
collapses), railings, half walls, arched windows, gable roofs, curtains, bookshelves and more; Halloween decor
(carved pumpkins with selectable faces, pumpkin lights, bat bunting, ghost lanterns, a scarecrow, gothic trim);
recolour with Loom dyes (P), undo the last pieces (Z, press twice, exact refund), pumpkin face (N). A small
cottage plot at the Commons allows building in the Reach (no beds there).

**Enemies.** Chapter One additions: Brambleback, Lantern Moth, Hollow Drudge, Brood Skitter (arachnophobia:
Pale Sprout), elite Knotted Elder; the Weaver Matron fight has three phases. Chapter Two: Pumpkin Mimic,
Patchwalker, Velvet Wing, Bellcap Sentry, Borrowed Wisp, elite Quarry Warden; bosses Count Velour, the
Matron at Weaver's Crossing and the Borrowed Choir. Design rule for all: readable tells, fair recovery windows.

**Replay & optional.** Optional goals for both chapters (Journal > Optional). **Echo Trials** (`data/trials.gd`,
area `echo_trial`) replay a won boss fight as a memory: the Weaver Matron (echo stone by the lantern before the
Heartseed Chamber), Count Velour (the manor ballroom's rest candles) and the Borrowed Choir (the Bell Throat). Each
opens right after its boss is defeated (no other gate), never touches story flags, and always returns to its stone;
the first clear sews a unique Loom pattern (Moon Moth Shawl, Moonlit Masquerade, Chime Chorister), later clears pay
modest renewable resources on the way back at the stone. **Lanternwake Expeditions** (`data/expeditions.gd`): the
Expedition Board, a Workbench recipe after the Choir, offers three hand-authored routes through the Reach (Orchard
Patrol, Quarry Circuit, Manor Afterglow; a seed only picks which authored group waits at each stop), ending in a
cache of renewable materials, candy and sometimes a keepsake (a dye colour or a festival decoration); no timers, no
daily limits, never a story item or flag. The optional fourth friend Pipkin is not implemented.

**Music & comfort.** 27 cues (`data/music.gd`, m01-m27) chosen by area, zone, time of day, combat and bosses,
keeping the Chapter One favourites. The **Music Box** (Workbench) plays the songs Krystal has heard in calm places at
home and keeps favourites (a little extra weight in the Haven rotation); any fight, boss, horror or authored music
ends a preview. New comfort options: high-visibility cues, timing assist; gameplay options:
friends join fights, friends use skills on their own, seasonal decorations (off by default, never indoors).
Onboarding tips for the new systems appear once per save (`src/world/story_ch2/onboarding_hints.gd`), one at a
time, never in cutscenes, boss fights, Echo Trials, ordinary fights or horror moments, and respect "Show hints".

**Chapter Two controls (defaults, all rebindable in Settings > Controls).** T companion skill · O wardrobe ·
E on a friend: their menu · Build mode: Z undo (press twice), P recolour, N pumpkin face.
