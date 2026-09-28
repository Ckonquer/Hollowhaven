# Hollowhaven — Chapter One Bible (handoff for designing Chapter Two)

This document describes **everything that exists in Hollowhaven Chapter One** so a designer can write
**Chapter Two** (story, world, quests, creatures, horror, boss, ending). The design will then be implemented
into the existing game. Chapter Two must continue **seamlessly from Krystal's existing save**: everything she
built, collected and befriended carries over.

Section 12 is the template of what the Chapter Two design should contain. Section 11 lists what is easy or
hard to build in this game, so the design stays buildable.

---

## 1. The game at a glance

| | |
|---|---|
| Title | **Hollowhaven** — "For Krystal" (a personal gift; credits read "For Krystal, from Ali") |
| Genre | 3D cozy survival-adventure with creature companions and a restrained horror dungeon |
| Feel (target mix) | ~70% cozy (gathering, building, farming, companions), ~20% adventure & friendly combat, ~10% concentrated horror |
| Player character | **Krystal**, an original stylised chibi explorer: warm auburn hair with a side braid, teal explorer jacket, mustard scarf, plum trousers, brown boots, satchel. (Not modelled on the real person.) |
| Camera / controls | Third person, keyboard + mouse, single player, offline |
| Engine / platform | Godot 4.7.2, Windows PC |
| Art style | Storybook toon shading with soft colour bands, lavender shadows, gentle rim light and outlines on characters. Everything is built from rounded procedural shapes in code (no imported models). Chunky, cute, readable silhouettes. |
| Audio | 154 original synthesised sounds + 5 music pieces (music-box/plucked title theme, cozy Haven theme, night theme, tense boss theme, warm ending reprise), ambience beds per area |
| Length | Chapter One: an optimal bot run took ~12.5 minutes; a first-time human is estimated at 40–60 minutes. **The owner felt it was too short → Chapter Two should be substantially longer (see §12).** |
| Name usage | "Krystal" appears sparingly and naturally: player name, "Krystal's Haven" sign, a few inscriptions and creature lines, the dedication. Never a greeting card. |

### Controls (rebindable)
WASD move · mouse look · Space jump · Shift sprint · Ctrl/V dodge roll · Left mouse attack/chop/mine ·
Right mouse or Q eat/use item · E interact · F raise/lower lantern · Tab/I inventory · C crafting ·
B build mode (R rotate, X dismantle, left mouse place) · J journal · M map · G companion follow/wait ·
1–8 hotbar · wheel zoom · Esc pause · F1 controls · F12 screenshot.

---

## 2. Story so far (Chapter One: "The Dimming Ward")

**Premise.** Long ago a Ward-Keeper set a seed of light — the **Heartseed** — into a mossy standing stone
(the **Ward Stone**) at the heart of a woodland clearing. "The deep went quiet." Something that lives deep
beneath the old mine cannot bear a kept flame "nor a home that is loved". Over time the Heartseed was
carried below by the **Weaver** (in arachnophobia mode, the **Hollow Mother**, a pale drifting shade), and
the ward began to dim.

**Chapter One beats.**
1. Krystal arrives at the overgrown clearing. The Ward Stone flickers. Its inscription: *"Light kept, home
   kept. The seed sleeps below; the stone remembers."* then *"Welcome, Krystal. This haven has waited a long
   time for someone to love it."*
2. She gathers sticks, stones and grass, crafts a stone axe, fells trees and builds a workbench.
3. **Mochi**, a timid mushroom sprite in the Berry Glade, is befriended with 3 berries (and gifts Sweetroot seeds).
4. **Pebble**, a small stone creature, is freed from under a grumbling boulder at the quarry with a pickaxe.
5. She makes the clearing a home (bed + crop plot, plants seeds).
6. At the Moonlit Ruin she drives off grumpy **Bramblings** and befriends **Lumi**, a luminous fox-like creature.
7. The Ward Stone warns: *"Its heart was taken to the deep. What took it still weaves in the dark. Carry
   light. Carry friends. Come home."* She crafts a lantern and food.
8. She clears the rubble sealing the **Hollow Mine** and descends: the Old Mine (abandoned by miners who fled),
   the far older **Ruins** below it (carved faces, a drowned shrine), then the **Silk Hollows**.
9. In the **Heartseed Chamber** she lights three ancient fire-bowls (braziers) to burn the **Weaver Matron**
   off the ceiling and strike it while it is stunned. Defeated, it **shrieks and flees into a deep crack in the
   ceiling** — it is *not* killed. The Heartseed is freed from its cocoon.
10. An old lift carries her back up. She returns the Heartseed to the Ward Stone: light blooms across the
    Haven, flowers and bunting appear, companions celebrate. *"Light kept. Home kept. Thank you, Krystal."*
    Ending card: *"The Ward Stone shines again. The Heartseed is home, and your friends are safe. Something
    still stirs in the deep... but tonight, the lights are on."* Credits, then free play.

**Open threads / hooks for Chapter Two** (none of these are resolved yet):
* The Weaver/Hollow Mother **retreated into the deep crack** above the Heartseed Chamber. Where does it lead?
* "Something down there has **learned our voices**" (Foreman's order). The fake-Lumi "Imitation" hints at a
  mimic intelligence in the deep.
* The miners: **Old Hask** (said the rails hum at night), **Tobin** (went back for his lantern; only the
  lantern was found), the **Foreman** (locked the lower gate, kept the key). Their fate is unknown.
* The **Ward-Keeper** who first set the Heartseed: who were they, where did they go? Are there other ward stones?
* The deep works' **lift winch** was "jammed at the bottom of the deep works". The carved faces in the ruins
  "all with their eyes shut".
* Krystal still carries the **Foreman's Key** in her key pouch (quest items are never lost).
* The ending grants the **Heartbloom Lamp** recipe and the **Haven Banner** — the Haven now "glows".

### Lore notes found in Chapter One (journal entries)
| id | Title | Text |
|---|---|---|
| landing_notice | Notice by the Lift | LIFT OUT OF ORDER. The winch jammed at the bottom of the deep works and nobody is going down to fix it. Use the ladder. And stop singing on shift. The echoes sing back. |
| miner_journal_1 | Miner's Journal, page 11 | Glowcaps are thick past the bend, bright enough to eat lunch by. Old Hask swears the rails hum at night. I told him it's only the wind. There is no wind down here. |
| foreman_order | The Foreman's Order | The lower gate stays LOCKED. Nobody goes below after the bell. Something down there has learned our voices. If you hear a friend calling from the dark, do not answer. Look for your own light. I'm keeping the key. |
| miner_journal_2 | Miner's Journal, torn page | We broke into stonework older than any of us. Carved faces, all with their eyes shut. Tobin laughed at them and went back for his lantern. We found the lantern. |
| ward_keeper | The Ward-Keeper's Carving | Here we set the seed of light into the stone above, and the deep went quiet. Keep it bright. What waits below cannot bear a kept flame, nor a home that is loved. |
| hollows_page | A Page Caught in the Silk (alt: …in the Roots) | It clings high and weaves where it thinks the light can't reach. The old fire-bowls still take a flame. Light them and its threads burn away, and down it comes. |

---

## 3. Characters

### Krystal (player)
Health 100, stamina 100 (sprint, dodge roll with brief invulnerability, swings). Carries a lantern (warm
light, radius ~6–7 m) once crafted. No hunger; food heals. On defeat she "wakes up, a little shaken but
safe" at her bed / the Haven / the last lit dungeon lantern — **no item loss**.

### Companions (one follows at a time; the others stay home at the Haven)
All three have idle/walk/reaction animations, blink, look at Krystal, emote bubbles (!, ?, heart, …, zZ),
short descriptive lines (no voiced dialogue), stuck-recovery (they safely reappear behind Krystal), and
cannot be hurt or lost. **Bond** 0–5 hearts from petting (once/day), feeding the favourite food (once/day),
working together and exploring new zones together. *Bond currently gives hearts + lines only; no perks yet.*

| | **Mochi** (Puffcap) | **Pebble** (Cobblet) | **Lumi** (Glimmerkit) |
|---|---|---|---|
| Look | Round mushroom sprite: big red cap with cream spots, soft cream body, stubby feet, huge shiny eyes | Chunky grey stone body, moss tuft with a sprout, thick stone eyebrows, stubby arms | Small cream-gold glowing fox-like creature, big gold-tipped ears, fluffy tail, soft warm light |
| Personality | Timid, affectionate, loves berries | Overconfident, curious, devoted to rocks | Gentle, observant, sees what others miss |
| Befriend | Offer 3 berries (hides if you sprint near it) | Mine the grumbling boulder pinning it (pickaxe), then help it up | Hides frightened in the ruin until the Bramblings are driven off, then approach |
| Ability | Forager: brings berries/fiber while following; at home tends crops (faster growth) | Miner: headbutts rocks you mine for +1 stone/ore; brings a Shiny Pebble gift daily; comically charges enemies (bounces off, gets dizzy) | Lightbearer: soft light (counts as a light source); notices threats before Krystal (freezes, dims, warns) |
| Horror behaviour | **Refuses to enter the mine**: trembles at the threshold and waits there; reunites happily when Krystal returns | Brave: follows underground | Follows underground; reacts to authored moments (stares down the dark passage; hides and whimpers at the fake Lumi) |
| Favourite food | berries | shiny pebble | sweetroot |
| Home spot | by the crop plots | a rock pile | a lantern perch by the Ward Stone |

Sample lines — Mochi: "Mochi wiggles happily." / "Mochi squeaks and ducks behind Krystal." · Pebble:
"Pebble charges at the enemy! ...and bounces off. It is undeterred." / "Pebble presents you with a Shiny
Pebble. It's clearly the best one." · Lumi: "Lumi's light dims. It has noticed something." / "Lumi sparkles
like a tiny festival of lights!"

### The Ward Stone
A mossy monolith ringed by standing stones, with carved runes. It "speaks" through short, slightly
old-fashioned inscriptions. Dim before the ending; glowing warmly after.

### Threats
| Enemy | Where | Stats | Readable tell & counterplay |
|---|---|---|---|
| **Brambling** | Surface: Moonlit Ruin (quest group of 3, never respawns), Thornthicket, quarry edge | 30 HP, 10 dmg | Grumpy walking thornball; crouches + wiggles (0.7 s) before a pouncing bite, then is dizzy (recovery window). Drops fiber/berries. |
| **Gloomling** | Below: Collapsed Gallery (quest pair), Hall of Faces | 40 HP, 12 dmg | Shadowy imp with glowing eyes; eyes flare (0.8 s) before a claw swipe. **Fears light**: hesitates in lantern light and takes double damage while "exposed". Dissolves into wisps. |
| **The Weaver** (stalker) | Silk Hollows ceiling routes | cannot be killed there | Crawls ceilings in stop-start rhythms, appears briefly; if Krystal lingers in darkness it **rattles** (1 s) then lunges. Counter: raise the lantern (it recoils), dodge, break line of sight. Gentle intensity: never lunges. |
| **The Weaver Matron** (boss) | Heartseed Chamber | 240 HP | Clings to ceiling anchors; telegraphed drop (shadow circle + rattle, 1.2 s) — a miss leaves it stuck (2.5 s window). Lighting each of 3 braziers scorches it off the ceiling (stunned 5 s). Only damageable when stuck/scorched. Flees into the crack at 0 HP. |
| **Arachnophobia alternative** | everywhere spider-like | same stats | "The Hollow Shade" / "The Hollow Mother": a hooded drifting shadow with a pale mask and long wispy arms (no legs); webs become pale roots, silk becomes "Pale Thread", skittering becomes soft drifting sounds, text uses alt versions. |

---

## 4. The surface world — Hollowhaven Woods

About 220 m × 220 m of rolling storybook woodland, bounded by hills, dense tree walls and a cliff. A
day/night cycle (~14 real minutes of day, ~4 of night; nights stay readable in blue moonlight, with fireflies).
Butterflies, falling leaves, wind-swayed foliage, grass and flowers.

| Landmark | Position (x, z; origin = Haven, north = −z) | Content |
|---|---|---|
| **Krystal's Haven** | (0, 0), radius 20, safe | Starting clearing: the Ward Stone (0, −6), campfire cooking station (4, 3), "Krystal's Haven" wooden sign, fences, flowers, loose sticks/stones/grass; the building area (radius 16) |
| **Berry Glade** | (−55, 12) | Berry bushes, fairy mushroom ring where Mochi waits |
| **Pebble Quarry** | (66, −12), east across the stream | Rocky terraces, copper ore veins, boulders, Pebble's boulder |
| **Moonlit Ruin** | (−12, −66), north | Crumbled arches and columns, Lumi's alcove, Bramblings |
| **Hollow Mine** mouth | (54, −74), north-east cliff | Timber frame, old rails, rubble seal (pickaxe), comfort reminder on first entry |
| **Mirror Pond** | (46, 52), south-east | Pond fed by the stream, lily pads, reeds |
| **Sunny Meadow** | (−8, 60), south | Flower fields |
| **The Old Oak** | (−34, −20) | Giant landmark tree |
| **Thornthicket** | (−62, −46), north-west | Brambly bushes, Bramblings |
| Stream | runs north→south at x≈20–30 into the pond | Shallow and wadeable; 3 crossings (stepping stones, two bridges) |

Dirt paths lead from the Haven to the glade, ruin, mine, quarry, pond, meadow, oak and thicket.
Resources respawn: trees ~1 in-game day, bushes ~12 h, grass ~8 h, ground sticks/stones ~10 h.

---

## 5. The Below (Chapter One dungeon: 11 spaces, three moods)

| # | Space | Mood | Content |
|---|---|---|---|
| 1 | **Mine Landing** | warm amber, safe | Lantern checkpoint, "climb back up", the lift (jammed until the boss is beaten), notice board |
| 2 | **Timbered Tunnel** | warm, rails | **THE THRESHOLD**: Lumi stops at a pitch-dark side passage, stares, then moves close behind Krystal. Nothing attacks. |
| 3 | **Collapsed Gallery** | dusty | Two Gloomlings (teach the light rule), rubble to mine through |
| 4 | **Foreman's Office** | cozy-abandoned | Lantern checkpoint, the Foreman's Order, the **Foreman's Key** on a key board |
| 5 | **Lower Gate** | | Locked gate ("The foreman kept the key") → spiral stair down |
| 6 | **Descent Stair** | cold teal begins | Scratching above |
| 7 | **Hall of Faces** | cold teal, pillars, carved shut-eyed faces | **THE DISTANT CROSSING**: a pale shape crosses a far doorway; investigating finds drag marks, a dropped miner's lantern and a silk strand/root. Two Gloomlings. |
| 8 | **Drowned Shrine** | shallow water | **THE IMITATION**: a fake "Lumi" chimes from the wrong exit (cold blue-white light, casts no light, stiff jerky movement, reversed chime). The real Lumi hides and whimpers. Approaching it makes it fold into darkness. Lantern checkpoint after. |
| 9 | **Webbed Passage** | violet-grey, webs thicken | The stalker's ceiling routes; first sighting recoils from the lantern ("It shrinks from your light.") |
| 10 | **The Nursery** (optional) | silent | Egg sacs/root knots, silk + echo shards; deliberately nothing attacks |
| 11 | **Heartseed Chamber** | round cavern, high ceiling, deep crack | Checkpoint before it; the boss fight; the Heartseed cocoon; the lift shortcut back to the landing |

**Local horror director** (offline, rule-based pacing): states calm → unease → anticipation → encounter →
recovery; weighted, cooldown-limited events that often choose to do nothing: distant pickaxe strikes,
creaking timbers, footsteps behind, trickling pebbles, faint whisper, a familiar squeak from the wrong place
("wrong Mochi"), lantern flicker, far glimpse of a silhouette, Lumi noticing, scratching above, web rustle,
sudden silence, a Gloomling ambush (major), a stalker pass overhead (major). It never stacks major scares,
never spawns in view or too close, and stays quiet in safe zones, the boss fight and authored moments.

**Comfort settings** (shown on New Game and before the mine; editable in pause):
Horror intensity **Gentle** (fewer scares, no ambushes, softer sounds, less damage) / **Standard** /
**Intense** (more cues, darker, bolder stalking) · **Arachnophobia mode** · reduce camera shake · reduce
flashing · captions for important sounds · separate master/music/ambience/effects/UI volume.

---

## 6. Systems

* **Gathering**: hand (E) for sticks, stones, grass, berry bushes, glowcaps, silk; **axe** for trees;
  **pickaxe** for rocks, copper veins, rubble, echo crystals. Wobble, particles and sound feedback; auto tool choice.
* **Inventory**: 32 slots (first 8 = hotbar), stacks, tooltips, sort; quest items live in a separate
  **key pouch** (never lost). A full backpack drops extras as persistent pickups (never destroyed).
* **Crafting**: stations = by hand / **workbench** / **campfire** (cooking). Transactional (exact ingredients).
* **Building** (Haven only, grid-snapped): floors, walls, windows, doorways, roof tiles, fences, lantern posts,
  furniture; ghost preview green/red with reasons; rotate, dismantle with full refund; can't wall yourself in.
* **Farming**: crop plots; Sweetroot grows in 4 stages over ~6 real minutes; Mochi at home speeds it; after the
  ending, the Heartseed's blessing makes crops grow 1.5× faster.
* **Survival/combat**: health & stamina; food heals (no hunger); readable enemy tells and recovery windows;
  dodge roll; lantern light matters underground.
* **Save**: autosave on entering/leaving the mine, sleeping in the bed, lighting dungeon lanterns and at the
  chapter end; manual save from the pause menu on the surface (not while chased). Versioned save with backup.
* **UI**: title screen (dusk diorama, "For Krystal"), HUD (health, stamina, hotbar, goal tracker, prompts,
  toasts, dialog lines, captions, hints, boss bar, day dial, companion portrait), inventory, crafting, storage,
  journal (goals / lore / friends & bonds), painted map with landmarks and goal marker, companion menu
  (pet, follow, wait, go home, feed), pause (save, settings, controls, comfort, "return to the Haven / last
  lantern" unstuck, quit), settings (gameplay, key rebinding, video, audio, comfort), F1 controls overlay,
  ending + scrolling credits.

---

## 7. Items (all of Chapter One)

**Resources**: Wood, Stone, Plant Fiber, Berries (food, heals 8), Copper Ore, Sweetroot Seeds, Sweetroot
(food, heals 15), Shiny Pebble (Pebble's gifts), Glowcap (dungeon mushroom), Weaver Silk / Pale Thread
(dungeon), Echo Shard (dungeon crystal "that hums with faraway sounds").
**Tools & weapons**: Stone Axe (9 dmg), Stone Pickaxe (9 dmg), Copper Sword (18 dmg), Lantern (equipment).
**Food**: Berry Snack (heals 30), Glowcap Skewer (heals 45), Hearty Stew (heals 60 + faster stamina recovery).
**Placeables**: Workbench, Storage Chest (20 slots), Cozy Bed (sleep until morning + save + respawn point),
Crop Plot, Wooden Floor, Wooden Wall, Window Wall, Doorway, Roof Tile, Picket Fence, Lantern Post, Flower Pot,
Woven Rug, Table, Stool, Pebble Cairn, Echo Chime, Heartbloom Lamp (post-ending), Haven Banner (ending reward).
**Key items**: Foreman's Key, The Heartseed.

### Recipes
| Station | Recipe (ingredients → result) |
|---|---|
| Hand | Stone Axe (3 wood, 2 stone, 2 fiber) · Stone Pickaxe (3 wood, 3 stone, 2 fiber) · Workbench (8 wood, 2 stone) · Berry Snack (4 berries) · Crop Plot (3 wood, 3 fiber) |
| Workbench | Copper Sword (2 wood, 4 copper, 2 fiber) · Lantern (3 copper, 2 fiber, 2 wood) · Storage Chest (10 wood, 1 copper) · Cozy Bed (8 wood, 6 fiber) · Wooden Floor (2 wood) · Wooden Wall (3 wood) · Window Wall (3 wood, 1 fiber) · Doorway (3 wood) · Roof Tile (2 wood, 2 fiber) · Picket Fence ×2 (2 wood) · Lantern Post (3 wood, 1 copper, 1 fiber) · Flower Pot (3 stone, 1 fiber) · Woven Rug (6 fiber, 2 berries) · Table (5 wood) · Stool (2 wood) · Pebble Cairn (3 shiny pebble, 2 stone) · Echo Chime (3 echo shard, 1 wood, 1 fiber) · Heartbloom Lamp (2 glowcap, 2 silk, 2 wood — unlocked by the ending) |
| Campfire | Hearty Stew (2 sweetroot, 3 berries) · Glowcap Skewer (2 glowcap, 1 wood) |

---

## 8. Chapter One quest chain (shown in the goal tracker; hints teach controls in context)

| # | Step | Objectives | Reward / note |
|---|---|---|---|
| 1 | A Dim Haven | Read the Ward Stone | |
| 2 | Gather Supplies | 3 wood, 2 stone, 2 fiber | |
| 3 | A Proper Tool | Craft a Stone Axe | |
| 4 | Timber! | Fell 2 trees, hold 10 wood | |
| 5 | A Place to Work | Place a Workbench | |
| 6 | A Timid Friend | Befriend Mochi (Berry Glade) | 3 Sweetroot Seeds |
| 7 | Something Stuck | Craft a pickaxe, free Pebble | 2 copper ore |
| 8 | Make It Home | Place a bed and a crop plot, plant seeds | |
| 9 | Lights in the Ruin | Drive the Bramblings from the ruin, befriend Lumi | |
| 10 | The Ward Remembers | Listen to the Ward Stone, craft a Lantern, prepare 2 healing meals | |
| 11 | The Hollow Mine | Clear the entrance, enter the mine | |
| 12 | The Old Mine | Find the Foreman's Key | |
| 13 | Deeper Still | Find a way deeper (reach the Silk Hollows) | |
| 14 | The Silk Hollows (alt: The Pale Hollows) | Reclaim the Heartseed | |
| 15 | Bring Back the Light | Return the Heartseed to the Ward Stone | Haven Banner, Heartbloom Lamp recipe, restoration, credits |
| 16 | Krystal's Haven (free play) | Optional: max bond with a companion; build a Heartbloom Lamp | |

Quest objectives are **state checks**, so they survive saving/loading and completing things early. The
available objective types are: flag set · have N of an item · have N of any of several items · N structures
placed · creature befriended · counter reached (e.g. trees felled, crops planted), optionally counted from
the step's start.

---

## 9. What a finished Chapter One save contains (the continuity baseline)

* Quest log at step 16 (free play), flags `ward_restored` and `chapter_one_complete`, plus every progress flag
  (mine opened, gate open, all 4 dungeon lanterns lit, Weaver defeated, lift working, lore read...).
* All three companions befriended with their bond levels; one of them may be following. Mochi, Pebble and
  Lumi have home spots at the Haven.
* Everything Krystal built (bed, workbench, crop plots, chests with contents, walls/roofs/decor), crops and
  their growth, depleted/respawning resources, dropped items.
* Inventory (tools, sword, lantern, materials, food), the key pouch (**Foreman's Key** is still there), the
  Haven Banner, the Heartbloom Lamp recipe, discovered lore, stats, the day/time.
* The restored Haven look (bunting, glowing Ward Stone, flowers, fireflies at night).
* The Below still exists and can be revisited: lanterns lit, lift working, boss gone, Nursery open.

---

## 10. Tone & content rules to keep

* Cozy first, horror as contrast: the Haven stays **mechanically safe** (no home invasions, no destroyed
  builds, no companion deaths). A rare late-story distant silhouette/sound near home is acceptable.
* Horror by restraint: fading warmth, narrowing spaces, familiar things made strange, movement just out of
  view, a companion noticing first, silence where an encounter seemed likely. Not every cue leads to an
  attack. Fair, learnable rules for every threat; never random unwinnable guesses. No extreme loud spikes,
  no unreadable darkness, no fake system errors.
* Every spider-like element needs a non-arachnid alternative (model, sound, text, icon).
* Friendly survival: no hunger, no punishing death (wake up safe, nothing lost).
* All creatures, names, sounds, visuals and music original — no references to existing games or IP.
* Companions are friends, never disposable or mandatory keys.

---

## 11. What is easy vs. costly to build in this game

**Easy / cheap** (data or small code): new items, recipes, foods, placeables/decor, crops; new quest steps
using the objective types in §8; new lore notes, inscriptions and companion lines; new horror director events
built from the existing kinds; new resource nodes; new structures for the Haven; bond-level perks for
companions; new comfort options.

**Moderate** (new code but proven patterns): a new area (surface region or underground level) built from
rounded procedural shapes, with rooms, lighting moods, fog, props, checkpoints; new enemy types with a clear
tell and counterplay; a new companion (visual + one ability + befriending); authored scripted moments
(triggers, silhouettes, camera-friendly events); a boss with 2–3 readable phases; a mechanic like
rope/lift/bridge repair or light-puzzles; night-only events; fishing or a simple mini-activity.

**Costly / avoid**: human characters with complex animation or lip-sync; branching dialogue trees;
voice acting; cinematic cutscenes beyond camera moves, fades and text; large open worlds; vehicles or mounts;
multiplayer; physics destruction; photorealism; online features.

**Style constraints**: stylised, chunky, readable shapes and colour-coded moods; text-based dialogue
(speech-line boxes and inscriptions); synthesised music/sound (describe moods/instruments, not songs).

---

## 12. Chapter Two — what the design should contain (please fill in every section)

Please return a design document with these sections:

1. **Premise & title** — Chapter Two name, a one-paragraph pitch, how it follows from the open threads (§2).
2. **Continuity & start** — how Chapter Two begins for a save that has finished Chapter One (an in-world
   trigger, e.g. a new inscription, a sound from the deep, a visitor, the lift moving at night) and what a
   player who has *not* finished Chapter One sees (Chapter One must still be completed first). Everything
   in §9 must carry over; state what the Haven gains or how it changes.
3. **Target length** — aim for roughly **2–3× Chapter One's content** (a first-time player ~90–150 minutes)
   *without* grinding or empty walking: more places, more varied goals, optional side content.
4. **Story beats** — 10–20 beats from start to ending, with the emotional arc (cozy → uneasy → frightening →
   triumphant → cozy), and the Chapter Two ending (plus any hook for Chapter Three, if wanted).
5. **Places** — each new area or expansion: name, mood, size, landmarks/rooms (for underground: a room list
   like §5 with 8–15 spaces), what the player does there, lighting/colour mood, checkpoints/safe spots, how it
   connects to the existing world (surface map §4, the mine, the crack in the Heartseed Chamber, the lift).
6. **Quest chain** — ordered steps (title, short description, objectives using the types in §8 or clearly
   described new ones, hints, rewards), including optional side quests.
7. **New companion(s)** (optional, max one recommended) — look, personality, befriending, one clear ability,
   horror behaviour, favourite food, lines. Also: bond-level perks for Mochi, Pebble and Lumi if desired.
8. **Enemies** — each: look, where, tell/telegraph, counterplay, damage level, arachnophobia alternative if
   needed.
9. **Horror moments** — 4–6 authored moments (like THE THRESHOLD / THE IMITATION), each with its rule the
   player can learn, what happens on Gentle vs Intense, and the arachnophobia version. New director events
   if any (sound/glimpse/etc.).
10. **Boss / climax** — arena, phases, telegraphs, how light or companions matter, how failure resets fairly,
    and the resolution (defeat, banishment, reconciliation...).
11. **Items, recipes, structures, crops** — tables like §7 (name, what it does, how it's obtained, recipe).
12. **Rewards & the ending** — what visibly improves at the Haven, new decor/recipes, credits text.
13. **Free play after Chapter Two** — optional goals and repeatable cozy activities.
14. **Writing** — all inscriptions, notes, companion lines, hints and ending text (short, gentle, a little
    old-fashioned for ancient things; "Krystal" used sparingly).
15. **Audio & music moods** — ambience per new area, 1–3 new music moods, key sound cues.
16. **Accessibility & comfort** — anything new that needs a comfort option or caption.

Keep everything original, keep the Haven safe, keep horror fair and restrained, and keep it buildable within
§11.
