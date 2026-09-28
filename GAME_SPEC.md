# Hollowhaven — For Krystal · Game Spec (Chapter One: "The Dimming Ward")

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
