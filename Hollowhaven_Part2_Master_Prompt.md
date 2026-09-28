# HOLLOWHAVEN: FOR KRYSTAL
# Chapter Two — The Lanterns of Hallowmere
## Integrated Chapter One upgrade: Home, Style, Companions & Music

**Document type:** complete design and implementation assignment for the coding agent working in the existing Hollowhaven repository. This document specifies proposed work; it does not claim that the expansion already exists or has been tested.

**Owner's priorities, in order:** preserve Krystal's real world and save; make progression and home-building worth continuing indefinitely; add beautiful character customization; make companions visibly useful in combat; substantially enrich Chapter One; create a creative Halloween-themed Chapter Two; give BOTH chapters much more musical variety; test the packaged continuation.

---

## 0. Your assignment — implement, do not just plan

You are the developer, game designer, technical artist, audio designer, and QA lead for the EXISTING Hollowhaven game. Implement this specification in the actual repository. Do not create a replacement game, port engines, reset the world, or deliver only a design document.

The project documentation reports Godot 4.7.2-stable, GDScript, Forward+, Jolt, and a Windows x86_64 release. Preserve the project's verified local toolchain unless inspection establishes a specific blocker. Read the actual repository before changing it. Do not reinstall Unity, start an Unreal project, or blindly upgrade Godot. Verify the executable's version locally; a version written in a handoff is not itself proof about the current installation.

Make ordinary creative and technical decisions yourself. Work through integration, real execution, testing, fixes, and packaging without asking whether to continue after every milestone. Do not buy assets, incur external API charges, enable online dependencies, publish the repository, or modify unrelated computer settings. Respect necessary installation, licensing, and desktop-control permissions. Keep work bounded, stop only processes you own, and leave an exact continuation checkpoint if a session ends. Do not promise unattended background work after the session stops.

The old documents describe the Chapter One baseline; their original short-chapter scope is not a reason to stop after Chapter One again. This specification intentionally extends that scope while preserving ownership, technical compatibility and completed story facts.

The delivery is ONE updated game containing the improved Chapter One, Chapter Two, and ongoing free play. The existing Continue button must load Krystal's existing journey. A Chapter Two subtitle or new main-menu artwork must NOT change the app's save-directory identity.

### Source basis and limitations

Read these supplied documents, then compare them with current source:
- `Hollowhaven_Chapter1_Bible.md`: existing story, world, systems, items, and continuity baseline.
- `Hollowhaven_Technical_Handoff.md`: source/report baseline at commit `9512a0d`, version `0.9.0`; save schema and extension constraints.
- `AGENTS.md`, `GAME_SPEC.md`, `PROJECT_STATE.md`, `QA_REPORT.md`, `KNOWN_ISSUES.md`, `THIRD_PARTY_NOTICES.md`, and `README.md`.
- In the actual repository, also read `docs/ARCHITECTURE.md` and inspect the save, quest, world, player, companion, combat, and UI code.

The design author received documentation, not the source project or an actual player save. Therefore, paths and current-state descriptions below are handoff-derived, while all proposed new mechanics, numbers, story, and content are design decisions. Do not mistake documentation review for source verification.

The handoff warns that later bug fixes may exist after its recorded commit. Preserve those fixes and any owner changes. Never reset the checkout to the documented commit merely to match this specification.

If only these documents exist in your environment, do not invent a repository or build. Locate the actual project within the authorized workspace; otherwise report that implementation is blocked on access to it, preserving this design.

### Definition of success

Krystal presses Continue, finds her own home and possessions intact, optionally changes her appearance, discovers new tools and companion abilities, travels into a new region, repeatedly returns to improve the SAME home, completes an emotionally satisfying new adventure, and still has enjoyable resource, building, outfit, equipment, and companion goals afterward.

A fresh player receives character creation near the beginning and the enriched Chapter One before naturally reaching the same expansion. Nobody must start over to receive the new systems.

---

## 1. The core idea

### Pitch

Restoring the Heartseed did not replace the Haven. It made its light strong enough to reveal an old path into **Hallowmere Reach**, an autumn woodland of pumpkin gardens, haunted orchards, bell towers, mineral terraces, and an eccentric vampire's manor. This is the homeland of an old Lanternwake festival: Halloween whimsy above, unsettling things below. Other lamps once guided travelers safely through these woods. They have fallen silent.

Below the Reach lie **the Hushed Works**, where the miners' warning comes true: something has learned familiar voices. The escaped Weaver uses the passages above it, but the deeper threat is not merely a larger spider. **The Borrowed Choir** is an echo-born presence that imitates comfort without understanding it.

Krystal grows pumpkins, restores the festival's garden, quarry and manor lanterns, improves her own house, and equips herself and her friends. She breaks a vampire's borrowed enchantment, follows the miners' trail, confronts the escaped Weaver on a dangerous crossing, and releases the stolen echoes from the Choir. Her original Heartseed stays in its stone throughout. Her previous victory is real and permanent.

### Three connected loops

**Home loop:** gather and grow → craft tools, equipment, clothing, and furnishings → expand/decorate the existing house → improve storage and gardens → enjoy companion life.

**Adventure loop:** discover a landmark → learn its environmental or combat rule → obtain a new material or recipe → choose a meaningful upgrade → open a new route → come home.

**Long-term loop:** renewable resources → better equipment and optional specializations → richer builds and outfit collections → companion bonds and repeatable expeditions → more creative freedom. Quests introduce these systems; they are not the only reason to play.

Halloween belongs mainly in the new region: carved pumpkins, warm windows, playful bats, fancy gothic outfits, abandoned celebrations, shambling garden zombies, and a vampire manor. It is permanent playable content, not a real-calendar event that expires after October. Offer a player-controlled seasonal-decor preference; never automatically repaint the original house or force Halloween clothing.

Keep approximately the existing cozy/adventure/horror balance. Bigger content does not mean constant attacks. The Haven remains mechanically safe, and most surface time should be pleasant.

### Length and scope

Design for approximately **3–5 hours of new first-time exploration and main progression**, with substantial optional building, outfits, side activities, and post-story play. This is a pacing target, not measured playtime or a guarantee. A route-aware bot will be faster. Record actual test durations and what they include.

Meet the target through distinct activities and encounters, not inflated health, resource taxes, forced crop waits, mandatory maximum bonds, repeated errands, or long empty paths. If measured content is short, add meaningful interactions and route choices—not a misleading playtime label.

Scope: retain the original world and dungeon; add one substantial surface region, one substantial main dungeon, compact optional annexes, meaningful systemic upgrades, and a finite, replayable postgame. “Ongoing” means meaningful renewable systems and creative building, not a promise of infinite authored content. Do not attempt an infinite generated open world or multiplayer.

---

## 2. Non-negotiable continuity and save engineering

### 2.1 Preserve the original game state

The handoff describes `%APPDATA%\Hollowhaven\saves\slot1.json`, a backup, and separate `settings.cfg`; JSON format `hollowhaven-save`, schema version 1. Verify these against the actual code and runtime. Tests already support a separate `--save-dir`.

Preserve, without substitutions:
- Original `surface` and `below` area identities, terrain beneath existing builds, spawn identities, and world coordinates.
- Every placed structure's UID, item ID, area, position, rotation, storage binding, and instance data.
- Chest contents and ordering, crops and growth state, the chosen bed/respawn, and dropped items.
- Inventory quantities and slot positions, hotbar selection, key pouch, tools, lantern, and existing equipment ownership.
- Krystal's identity, unlocked recipes, discovered lore, world time, counters, and relevant settings.
- Mochi, Pebble, and Lumi: identity, befriending, bond XP, assignments, waiting locations, and daily interaction state.
- Existing completion flags, cleared quest enemies, lit checkpoints, working lift, restored Ward Stone, and Chapter One rewards.

Do not move her house into a new map. Hallowmere Reach is an additional registered area with a return route to the original `surface`. Optional outposts are additional possessions, not replacements for her home.

### 2.2 Protect the REAL save, not just the sample

The handoff explicitly says `save_chapter1_complete/slot1.json` is a QA/bot-produced fixture, NOT Krystal's personal save. Never replace the user's save with it or call it hers.

Before any migration test:
1. Determine the actual save location used by the player's build and launch arguments. Do not assume the default folder is the only possible location.
2. Wait for the game to be closed before taking a consistent snapshot. Do not terminate unrelated/user gameplay without permission.
3. Copy relevant saves, settings, and required metadata into a timestamped, immutable pre-expansion backup outside the ordinary rotating backup files.
4. Record source path, build identity, byte hashes, and what was copied. Back up the current playable build/source checkpoint too.
5. Test on COPIES in explicit isolated directories. Do not use the live profile for QA, automated New Game, or destructive recovery tests.
6. Provide an integrity comparison and rollback instructions. The final updated game should migrate its own live save only when the player actually launches it, not during development experiments.

Do not alter, delete, or normalize the immutable original backup. Do not upload personal saves publicly. If the actual save is unavailable, use the sample and synthetic fixtures but label real-save verification as not run.

### 2.3 Versioned, idempotent migration

Use the existing `SaveSystem.migrate()` extension point. If the actual source still uses version 1, implement a documented v1→v2 migration for the new persistent fields. If later migrations already exist, extend them rather than overwriting them or downgrading the schema.

Migration must be deterministic, idempotent, validated before write, and recoverable. Repeat loading must not duplicate items, grant rewards again, reset daily pet interactions, or reapply numerical bonuses cumulatively.

Add sensible defaults for missing customization, equipment, optional quests, mastery, and Chapter Two state. Preserve legacy values and stable IDs. Do not replace the inventory with a new default array. Do not initialize empty world containers over populated ones.

Retain existing item, structure, creature, flag, checkpoint, and area IDs. The documented loader skips unknown item IDs, so renaming/deleting old IDs can destroy possessions. Add new IDs or explicitly migrate aliases; never silently discard unresolved player-owned content. Reject unsupported newer save versions without overwriting them or quietly rolling back to an older backup as though that were a normal continuation.

Any stat changes must recompute from base values + equipment + current companion + active buffs, not modify the saved maximum repeatedly on load. Preserve existing absolute HP when adding maximum HP, except documented resting/healing behavior; never kill or fully heal someone just because a cosmetic or support option changed. Clamp safely when maximum values decrease.

### 2.4 The indexed-quest trap

The legacy quest list has indices 0–15, with `free_play` at index 15. Its goals are described as optional but can block linear advancement. **Never insert customization, new Chapter One quests, or new progression steps into that existing indexed list. Never reorder it.**

Keep all legacy main-quest identities stable. Append Chapter Two content after the legacy section or add a compatible stable-ID chapter layer with an explicit tested index-to-ID migration. Prefer the smallest reliable extension.

Move the legacy free-play goals into a persistent OPTIONAL tracker. Their existing progress must survive, and already completed goals stay completed. A new chapter must not require five-heart bond or a Heartbloom Lamp just because `free_play` happened to list them.

Add parallel optional tasks without making them new legacy main steps. New Chapter One activities attach to world triggers and that optional tracker.

A completed legacy save normally has `ward_restored`, `chapter_one_complete`, completed quest `return`, and index 15. Verify actual source semantics. An interrupted completion may have only some evidence. Reconcile it using the actual completion code and saved facts—do not broadly set every Chapter One flag or replay all rewards. Ensure the existing reward-once logic covers the banner and Heartbloom recipe.

Chapter Two becomes AVAILABLE after legitimate Chapter One completion. It starts when Krystal accepts the new Ward Stone inscription. It does not auto-teleport her, advance on load, or steal her current building session. New systems such as wardrobe and companion combat become usable in existing saves without accepting Chapter Two.

Chapter Two ending uses its own scoped flow, flags, and reward ledger. It must not rerun `Game.complete_chapter()` as though restoring Chapter One again.

### 2.5 Spatial integrity

Do not rebuild the original Haven at a new origin, flatten its terrain, regenerate its existing resource layout in a different order, rescale legacy pieces, or randomly relocate props. New resources use namespaced stable IDs; new areas get stable scene/spawn registrations.

Treat the saved home as authoritative. New developer-placed props must avoid occupied structure bounds, player paths, crop plots, and storage access. Put necessary interaction options on the existing Ward Stone or select validated empty locations. Nothing critical may depend on a new object occupying the center of her house.

Grandfather valid legacy placements when improving building rules. Do not delete or auto-dismantle old pieces because a stricter validator now dislikes them. Report unusual collisions with non-destructive repair options.

---

## 3. Krystal's Haven grows; it never gets replaced

### Expanded building

Keep the original clearing and all player construction. Extend buildable ground into adjacent usable space, aiming for a materially larger connected footprint where actual terrain/landmarks permit. Do not blindly increase a radius into the stream, paths, Old Oak, or critical interactables.

The safe zone expands with the authored/validated home-build boundary, including a buffer; arbitrary player-placed lights do not create an invulnerability field across the whole map. No enemy attacks, projectiles, horror spawns, or scheduled events may damage Krystal or companions inside it. Do not add raiding or structural damage.

Implement reliable two-storey construction: stairs, upper floors, appropriate roof connections, railings, and reachable landings. Prefer deterministic snap points and simple ramp collision under steps. Do not claim multi-storey support because a floor can merely float in the air.

Add porches, stairs, half-walls, arched windows, alternate roof shapes, flower boxes, curtains, bookshelves, wardrobes, kitchen furnishings, planters, companion beds, and coherent new material styles. Include optional Halloween decorations: carved pumpkins with selectable faces, pumpkin string lights, a candy bowl, bat bunting, crescent windows, a gothic porch, ghost lanterns, and a harmless decorative scarecrow. No decoration secretly becomes hostile at home. Permit recoloring selected new/old pieces without changing their UID or storage contents. Do not recolor her entire existing house automatically.

Support validation prevents new floating construction and blocked access, but never causes cascading collapses or destroys existing pieces. Provide undo for placement and reversible, clearly previewed upgrades. Dismantling with full refunds must not become a mastery-XP exploit.

### Furniture should do things

- **Vanity Mirror / Wardrobe:** reopen character styling and save favorite looks.
- **Furnace:** process new metal recipes; finite batches, clear progress, short active timers, saved queue.
- **Loom & Dye Bench:** unlock craftable outfit patterns, cloth, dye palettes, and furnishing variants.
- **Improved Kitchen:** new useful meals; do not invalidate the existing campfire.
- **Companion Nook:** select a pet's home spot, home task, favorite interactions, and cosmetic ribbon.
- **Expedition Board:** shows optional discoveries, trials, and crafting possibilities without imposing a daily checklist.
- **Storage upgrade:** enlarge the selected chest in place, preserving its UID and all contents.

Allow optional crafting from eligible nearby home chests. Clearly show where materials will come from. Withdraw across inventory/chests as one validated transaction, using stable chest ordering. No remote extraction from unrelated outposts or another area. Never consume ingredients when the result cannot be safely created or persistently dropped.

The restored Haven's existing crop blessing stays intact. New bonuses need clear caps and multiplicative/additive rules; avoid accidentally multiplying growth once per load.

---

## 4. Character creation, clothing, and expression

### Placement in the journey

**New Game:** after the overwrite confirmation and comfort options but BEFORE the first playable arrival, show “Meet Krystal.” Provide a rotating 3D preview, readable categories, confirm, reset, and back/cancel. Cancel must not erase the old save or start autosaving a new one. Customization is a UI prelude, not an inserted legacy quest.

**Existing save:** preserve the original auburn-braid explorer appearance as the migration default. At the first safe opportunity, show a dismissible message: “Your wardrobe is ready. You can change your look without starting over.” Let Krystal style herself from a safe pause-menu entry or the Ward Stone's wardrobe option immediately. Also unlock a craftable mirror/wardrobe for the house. Do not spawn furniture inside an occupied build or require late-game currency just to choose her hair.

**Later:** mirrors and wardrobes reopen the same system for free. Hair, eyes, skin tone, and already-unlocked clothes can be changed freely. New patterns are collectible/craftable progression.

### Minimum meaningful selection

Build original, tasteful, cute stylized clothing appropriate for exploring:
- Eight recognizable hairstyles: original side braid, bob, long waves, high ponytail, twin braids, space buns, braided crown, and half-up ribbon style.
- At least twelve hair-color swatches; six skin-tone options; eight eye-color options.
- Separate hair accessory, upper garment, lower garment or dress, footwear, and visible-back accessory controls where the current avatar permits.
- Six complete starter looks with genuine mesh/silhouette differences, not six recolors of trousers: original Cozy Explorer; Strawberry Picnic pinafore; Ribboned Adventurer with pleated skirt and leggings; Cloud Cardigan ensemble; Moonflower day dress; Mushroom Dungarees.
- Earnable additional themes: Pumpkin Patch cardigan with skirt, Ribbon Witch (dress/skirt, pointed hat, boots), Velvet Vampire (ruffled dress and little cape), Ghostlight party dress, Moon Moth shawl, and Lanternwake festival dress. These need distinct silhouettes and outfit parts, not just different color swatches. Include matching hair ribbons and non-obstructive hats. Keep starter clothes attractive: do not withhold all cute options until the end.
- Palette choices including rose, lavender, cream, mint, sky, plum, and warm neutrals. Color is not the only differentiator.
- At least three saved appearance presets with descriptive names.

Keep customization respectful: an original stylized character, not an inferred reconstruction of the real Krystal. No body-measurement system or sexualized framing is needed. Skirts/dresses must behave sensibly during running, rolling, stairs, and camera movement; use simple procedural sway rather than expensive cloth simulation if appropriate.

### Appearance must not cost combat power

Separate **appearance** from **equipment stats**. Krystal can wear a cute skirt visually while benefiting from crafted armor. Provide “show equipped armor” as an option, not a forced downgrade or paid transmog system. Clearly label cosmetic clothing as cosmetic.

Do not change the collision capsule, movement tuning, or interaction reach with hairstyle/outfit choice. Prevent shared-material bugs where changing her hair recolors every companion or another saved preset. Preserve selections through travel, death, save/load, screenshots, ending scenes, and future content.

Unknown cosmetic IDs in a later-compatible save should retain their underlying data while falling back to a safe visible default and reporting the missing option. Do not erase ownership.

## 5. Progression beyond objectives

Implement persistent progression along four complementary axes: tools/equipment, home/workstations, companion bonds, and exploration/mastery. Quest completion should reveal possibilities; it must not be the only source of rewards.

### 5.1 Equipment tiers

Keep every legacy item and recipe working, including the 18-damage Copper Sword and 9-damage stone tools. Add new items; do not rename legacy copper into iron or erase old resources.

| Tier | Access | Weapons/tools | Defensive identity | New freedom |
|---|---|---|---|---|
| Familiar foundations | Start / early Chapter One | Existing stone tools and Copper Sword | Optional padded clothing armor | Learn, build, explore without forced grinding |
| Copperwood | Optional Chapter One crafting | Copper harvesting tools, existing Copper Sword | Copperwood hood/body/boots | Faster gathering, first armor choices, tailoring and a better home |
| Ironwood | Early/mid Hallowmere Reach | Ironwood sword, axe and pick | Stronger armor, purposeful charm slot | Efficient new resources, improved construction, reliable new-region combat |
| Moonsteel | Upper quarry / late Chapter Two | Moonsteel blade and tools | Best general-purpose set, alternate support charms | Late encounters, distinctive building materials and postgame specialization |

Initial sword targets: Copper 18, Ironwood 25, Moonsteel 34 base damage. Add a simple craftable Sparkseed Wand as an optional ranged alternative: readable projectile, finite range, shared stamina cost, no rare ammunition requirement, lower sustained damage than equivalent melee. Never make it required for existing enemies or puzzles; all required targets remain melee-reachable or interactable. Preserve legacy attack/tool auto-selection without silently forcing the wand when mining. New harvesting tools should improve harvesting efficiency without automatically becoming superior combat weapons. Actual swing timings and encounter health must be verified before tuning.

Use three armor slots (head, body, boots) and one charm slot. Starting FULL-set physical reduction targets: padded 6%, Copperwood 12%, Ironwood 20%, Moonsteel 26%. Split these transparently across pieces. Charms offer choices rather than another required universal damage tier: gathering, stamina, healing support, or darkness comfort. Avoid random affixes, durability decay, and inventory-full loot fountains in this update.

Physical reduction combines multiplicatively across independent sources, with a documented final cap of 45%. Example: 20% armor and Pebble's 10% support produce 28% combined reduction, not an unchecked additive stack. Apply shield absorption after mitigation. Define whether any special damage bypasses armor; never silently bypass it to cancel the player's upgrade. Check invulnerability before damage. Never process a single hit twice.

Show actual equipped damage, protection, speed, and companion effects in a readable stats panel. Equipment ownership and equip/unequip must be transactional and persistent; it must not duplicate stackable items or lose them into an invisible slot. Respect existing weapon/hotbar selection behavior. Merely opening a menu must not unequip the lantern or change the selected tool.

### 5.2 Resources and recipes must form a complete dependency graph

Add a small, coherent set of resources: Sunflax, Roseberries, Resin, Iron Ore, Woven Cloth, Copper Bar, Iron Bar, Moon Crystal, and Moonsteel Bar. Add Pumpkin, Sugarcap, Moonpetal, and Lantern Wax for Halloween farming, meals, dyes, and decor. Keep the list bounded; sources and initial recipes are in section 16. Keep wood, stone, fiber, copper_ore, glowcap, silk/Pale Thread, and echo_shard useful.

Example acquisition chain:
- Sunflax and Roseberries have renewable plants/crops and discoverable starter seeds.
- Resin comes from designated renewable resource nodes, not compulsory harm to pets or wildlife.
- Copper bars use the existing copper ore; legacy raw-copper recipes stay valid.
- Reach iron is reachable with existing tools at reduced efficiency; an early upgrade makes it faster.
- Moon Crystal is mined with the Ironwood pick after repairing access to the upper quarry.
- Moonsteel uses ordinary iron plus Moon Crystal and existing Echo Shards.

Provide sufficient guaranteed nodes on accessible routes to craft required tools and repair quest machinery before any higher-tier gate. Main progression never depends on a rare random drop. Important upgrade materials have renewable sources after their discovery.

### 5.3 Small masteries, not another grind

Add three persistent five-rank tracks, earned through genuine play:
- **Gathering:** harvesting different nodes, discovering material types, and normal continued gathering. Rewards include small efficiency/yield benefits and later material highlighting nearby.
- **Hearthcraft:** first-time recipes, distinct useful structures, real crop harvests, and workshop development. Rewards emphasize recipes, furnishing variants, and modest conveniences.
- **Wayfinding:** discovering landmarks, opening shortcuts, reading new lore, and completing varied encounters. Rewards include modest sprint-stamina efficiency and map clarity.

No mastery rank is a mandatory main-story gate. Do not award repeated full XP for dismantling/rebuilding the same object, moving items between chests, loading a save, re-equipping clothing, or healing self-inflicted test damage. Natural resource respawning and farming are allowed; do not punish ordinary sandbox play.

Where existing saved counters prove earlier activity, award conservative one-time legacy credit. Record that it was applied. Do not pretend to know unrecorded actions or reset everyone to a brand-new profile.

Keep combined non-combat yield bonuses modest and visible. No compounded daily exponential growth. Exact thresholds can be tuned after route testing and must be recorded in data, not hidden in unrelated scripts.

### 5.4 Inventory and storage progression

Retain the first eight hotbar slots and legacy item ordering. Add craftable backpack expansions from 32→40→48 slots and a selected-chest capacity upgrade from 20→40. These are optional conveniences, not artificial pain required to finish the story.

Serialize capacity and validate it before loading slot arrays. Never truncate occupied extra slots during a fallback or downgrade. Full inventories must route rewards to safe persistent overflow, and quest objects stay in the key pouch.

---

## 6. Companions are real combat partners

The current handoff describes bond hearts without perks and Pebble's charge as mostly comic. The player specifically wants Mochi to heal, Pebble to provide toughness, Lumi to improve movement, and all three to attack real enemies. Keep their personalities and existing gathering/home behaviors, but implement visible combat contribution, meaningful support stats, and bond development.

### 6.1 Shared rules

Retain one active following companion initially. Others stay home; do not silently add a three-pet army or stack all their passives. Every befriended follower gains a useful passive, a real basic attack, and a signature ability immediately. Bond enhances these instead of making low-bond pets useless.

Use an “Assist / Stay close / Wait” behavior choice. Default Assist attacks enemies Krystal is fighting or enemies already attacking her. Do not aggro peaceful groups, attack through walls, or chase the stalker into inaccessible geometry. A setting can disable automatic attacks while retaining support.

Provide a rebindable **Companion Skill** action, default T if actually unbound. Autocast may be enabled by default with sensible conditions; the manual action requests the same ability, not a second independent cooldown. Show the cooldown, range/failure reason, passive, bond perks, and attack purpose in the Friends panel. Prevent UI focus from leaking the skill key into gameplay.

Companions remain immortal friends, not disposable tanks. Avoid taunting bosses permanently onto an invulnerable pet. Threats target Krystal and their own authored objectives; Pebble's support protects her. Attack animation and hit timing must agree. Projectiles require valid line of sight and cannot damage through rooms or scenery.

Calculate companion damage from a stable, modest gear-tier bonus rather than copying the currently selected tool damage every frame. Do not award permanent XP for hitting invulnerable bosses, the practice dummy, or friendly objects.

The handoff reports direct steering/breadcrumbs rather than a navmesh. Inspect navigation and add obstacle-aware path planning or a small tested navigation graph where needed; combat must not be a visible pet endlessly running into a wall. Authored ceiling routes remain appropriate for spiders.

Support requires the active companion to be present in the same area and within a sensible following range. A pet waiting at home does not fire invisible attacks into the dungeon. Use reliable recovery when the follower is stuck, but do not teleport offensive pets into closed boss rooms.

Pause suspends combat timers. Save/load retains cooldowns/buffs consistently; switching pets, loading, and area transitions cannot repeatedly refresh a powerful skill. Sleeping advances world resources normally but must not apply pet passives twice.

### 6.2 Initial balance specification

These are starting values, not substitutes for playtesting. Aim for companion basic damage around 10–25% of a similarly equipped player's ordinary sustained damage. All three must remain viable on the main route.

| Companion | Passive while present | Basic attack | Signature ability |
|---|---|---|---|
| **Mochi — gentle healer** | +8% healing received; existing foraging stays | Visible soft spore projectile, 4 damage, approximately every 2.4 s, medium range | **Bloomguard:** restore 18 HP over 6 s; 25 s cooldown. Autocast when Krystal is meaningfully wounded; no overheal spam |
| **Pebble — brave protector** | 10% physical damage reduction; existing mining help stays | A readable headbutt/stone punch, 8 damage, approximately every 2.4 s | **Stoneheart:** 25-point shield lasting up to 6 s; 26 s cooldown. Briefly staggers eligible ordinary enemies, never stun-locks a boss |
| **Lumi — swift lightbearer** | +8% movement speed and existing illumination/warnings | Small light bolt, 6 damage, approximately every 2.2 s | **Glimmerstep:** an additional +12% movement for 4 s and a short nearby light pulse that exposes eligible shadow enemies; 24 s cooldown |

Global movement buff cap: +30% over the chosen base movement state. Do not increase jump distance or dodge invulnerability unpredictably. Lantern puzzles and all required light counters remain usable without Lumi; companionship is an advantage, not a mandatory key.

### 6.3 Bond perks, preserving existing XP

Keep the established 0–5-heart thresholds unless source inspection requires a documented correction. Existing bonds unlock corresponding perks immediately; no rebefriending.

- **At two hearts:** Mochi healing bonus becomes 10%; Pebble gains a modest shield increase; Lumi passive speed becomes 10%.
- **At three hearts:** Mochi's skill clears one eligible web/root slow; Pebble's shield also resists one knockback; Lumi's skill briefly reduces sprint-stamina cost. No perk trivializes boss positioning.
- **At five hearts:** modest signature enhancement, a special affectionate animation, and a cosmetic companion ribbon. For example, Mochi heals 22 rather than 18; Pebble's shield reaches 32; Lumi's active lasts 6 s. Record final values in one place.

Bond progress comes from varied companionship, working together, discoveries, and existing daily care. Never require repeatedly feeding a pet hundreds of items. Display the next practical perk, not only hearts.

### 6.4 Mochi's courage — solve the healer/threshold conflict

Preserve the original refusal until a new OPTIONAL early task, **Brave Little Steps**, is completed. Krystal crafts a Comfort Ribbon, equips it on Mochi, and patiently walks to a lit, safe lantern at the OUTSIDE mine threshold, still in the original surface area. Completing that surface interaction sets the permanent courage flag; an optional follow-up walk into the safe landing demonstrates it. Do not require Mochi to enter the mine to earn the flag that permits entering the mine: that would be a circular gate. No forced terror or maximum bond requirement.

Afterward, Mochi can accompany Krystal underground. It still trembles or shelters behind her during horror cues, but these brief personality reactions must not disable healing indefinitely or break follower navigation. Players who prefer Pebble or Lumi need not complete the task. Original refusal tests continue to apply when the courage flag is false.

### 6.5 Life at home

Give home behavior visible purpose: Mochi tends assigned crops and occasionally naps; Pebble inspects its cairn or carries a small stone; Lumi visits its perch and reacts to the house lights. They notice new furnishings with restrained lines and animations.

Home tasks cannot generate rare, undiscovered quest materials or infinite items every frame. Use bounded yields, saved timers/daily ledgers, optional designated storage, and safe overflow. Do not steal food from chests unless an explicit assignment allows it. Preserve favorite foods and existing care rules.

---

## 7. Enrich Chapter One without replaying it

Add depth around the existing 15-step story, not new mandatory steps inserted into its indexed quest list. Keep all original victory and restoration facts intact.

### Optional Chapter One content

| Activity | Location / start | What Krystal does | Reward / ongoing value |
|---|---|---|---|
| **A Look of Your Own** | New Game creation; existing safe wardrobe access | Choose a real outfit and hairstyle; optionally make a mirror | Free starter looks and home styling access |
| **Brave Little Steps** | Mochi interaction once befriended | Craft Comfort Ribbon; accompany Mochi to a lit safe landing | Mochi can help underground |
| **Copper, Not Just Courage** | Workbench recipe discovery | Create furnace and first armor piece; learn equipment vs appearance | Copperwood equipment and useful processing |
| **The Tailor's Cache** | A new unobtrusive cache near Old Oak | Find a pattern through a short environmental clue | Loom recipe and Ribboned furnishing/clothing pattern |
| **Bramblewatch** | Thornthicket outskirts | Read charging-enemy tells; challenge an optional Knotted Elder | Resin source, sturdy planter and a cosmetic pattern |
| **A Gardener's Afternoon** | Sunny Meadow / crop plot | Discover Sunflax/Roseberries; plant and harvest either naturally | Renewable tailoring/food materials |
| **Tobin's Lost Shift** | A NEW side door off the mine, not a changed legacy room | Explore three compact annex spaces; fight a Hollow Drudge, find a service note, open a shortcut | Echo materials, miner lamp furnishing, an early clue to Chapter Two |
| **A House With an Upstairs** | Optional building notebook | Add stairs and a reachable upper-floor landing in a testable player build | Stair/roof variants; no mandatory house layout |

Existing players can do these after the ending. Do not mark everything complete just because Chapter One is complete. Conversely, never require them to replay the original gathering tutorial, rescue already-owned pets, or return the Heartseed again.

Add the four new ordinary Chapter One enemy archetypes in section 12, in authored optional combat pockets. Avoid the Haven, primary tutorial pickup areas, and peaceful Berry Glade. Preserve the original three ruin enemies' cleared state. Use new namespaced spawners, not reused flags that resurrect a cleared quest.

Keep the Nursery's purposeful silence. Extra combat belongs in annexes or other eligible pockets, not every formerly quiet room. Existing authored scares should remain once-per-save unless the player deliberately starts an optional replay trial.

---

## 8. The Weaver Matron — a real encounter, not just more HP

The documented Chapter One ending has the Weaver flee into a ceiling crack. Preserve that outcome. The new design strengthens the encounter for players who have not completed it and provides an OPTIONAL memory-trial version for those who already have.

Do not reset `weaver_defeated`, respawn the main quest boss on a completed save, reissue the Heartseed, close the working lift, or make the restored Ward Stone dim again.

### Three escalating phases

**Phase 1 — Something overhead.** Keep the braziers as the core rule. The Matron visibly tracks between valid ceiling anchors, telegraphs a drop with a ground mark plus rattle, and becomes vulnerable when a missed drop or lit brazier brings it down. Teach the rule before combining attacks.

**Phase 2 — The floor becomes a web.** Add a narrow telegraphed web fan that slows rather than permanently roots. A later attack stretches visible trip-lines between fixed anchors, leaving at least one clearly reachable route. Krystal can cut a line or burn it with her lantern. Limit active hazards and expire old ones.

**Phase 3 — Desperate weaving.** Make previously lit braziers reusable at a readable cooldown so three one-use scorches cannot exhaust every reliable damage window. The Matron attempts to darken one brazier with a clearly visible channel. Interrupt by striking the hanging thread or approaching with light. Combine ONE ground hazard with a delayed descending pounce, not an unreadable stack of attacks. Preserve a recovery window after each major action.

Initial timing targets: at least 1.0–1.4 s warning for major attacks; approximately 2.5 s recovery after a missed committed pounce; longer vulnerability after a brazier scorch. Tune against actual movement/camera visibility and input latency.

Add a capped two-minion release late in Phase 2 on Standard/Intense: visible shaking sacs release small Brood Skitters after a generous warning; they never spawn underfoot. On Gentle use one slower minion. Do not overlap minion release with the main pounce; extinguish remaining hazards during a phase transition. Arachnophobia swaps sacs/minions for pale pods and floating seeds.

Do not turn this into a health sponge. Start near the existing 240 HP baseline, assess the new player/pet damage, and prioritize phases and decisions over health inflation. Aim for roughly a few minutes of engaged first-encounter combat, not repeated stationary swinging.

### Companion interaction

Mochi can help recover from mistakes and later cleanse a slow. Pebble absorbs a dangerous hit. Lumi helps reposition and exposes the correct target. All companion attacks respect the Matron's vulnerability state; they cannot hit through ceiling invulnerability or finish the encounter from outside the arena.

### Failure, replay, comfort

Decide one consistent boss reset policy: preserve won progression, reset active encounter state cleanly on defeat/quit, and never leave mismatched braziers/phases that make the next attempt unwinnable. Explain checkpoint behavior. Consumable recovery should be generous enough not to force repeated surface grinding.

For completed saves, an optional **Echo Trial** at an appropriate dungeon checkpoint runs a separate encounter instance with its own flags/reward ledger and no Heartseed. Explain that it is a remembered challenge, not undone history. Leaving restores ordinary exploration. Main-world boss flags never change.

Arachnophobia mode replaces the Matron with the **Hollow Mother**, web fans with drifting root/veil hazards, and all associated animations, names, sounds, shadows, icons, and lore wording. Gentle lowers overlap and aggression. Intense raises deliberate stalking and anticipation without removing telegraphs, making darkness unreadable, or adding extreme audio spikes.

---

## 9. Hallowmere Reach — Halloween as a place, not a temporary skin

Create a new registered area, proposed ID `hallowmere_reach`, approximately 280 × 220 m of compact, authored terrain. Treat dimensions as a layout guide, not permission for empty walking. Use looping paths, visible landmarks, secrets, harvest pockets, return shortcuts, and contrasting neighborhoods.

The new region is permanently autumnal: amber leaves, plum twilight, round pumpkins, ribbons, crooked fences, friendly-looking festival architecture, and just enough abandoned celebration to feel mysterious. It does NOT spread a destructive curse over the original Haven. Existing woods keep their identity; new seasonal content there is optional and additive.

### Connection and return

The restored Ward Stone reveals a dormant trail near the OUTER Moonlit Ruin route, away from occupied construction. A repaired waygate connects to Hallowmere through the existing area-transition system. Validate both arrival spawns and provide an immediate two-way route. Never trap an under-equipped player across the boundary.

Later, lit lantern arches provide travel between discovered SAFE points, including the ORIGINAL Haven. Travel preserves both areas, all outpost structures, dropped items, crops, chest contents, companions, and clock. It does not copy or relocate the house. No fast travel during a chase or active boss fight.

Keep the old mine lift's original function. Add a clearly labeled service connection only after unlocking it; do not replace “back to the mine landing” with an unexpected trip into Chapter Two.

### Main landmarks

| Place | Look and feeling | Playable purpose and return value |
|---|---|---|
| **Lanternwake Commons** | Empty festival stalls, copper leaves, a small cottage foundation, pumpkin arch, warm string lights | Safe arrival, map board, checkpoint, wardrobe access, return arch, optional small outpost. It becomes a charming festival destination, not a replacement home. |
| **Pumpkintide Orchard** | Oversized pumpkins, roseberry rows, crooked fences, amber puddles, little scarecrows | Redirect a short irrigation channel, plant a guaranteed festival seed, restore the garden lantern. Introduce Pumpkin Mimics and Patchwalkers in separate, clearly marked pockets. Renewable pumpkins, seeds, dye plants, and recipes. |
| **Thimblebrook Pools** | Reeds, stepping stones, moonpetals, shallow sparkling water | Quiet gathering and a visual chime trail; an optional reed creature encounter. No swimming or drowning system required. |
| **Ashbell Quarry** | Copper-red terraces, bell-shaped ore markers, pale crystal seams | Iron access, Quarry Warden encounter, repairable winch, upper Moon Crystal deposits, tool progression. Resource routes stay useful after the story. |
| **The Candleyard** | Whimsical leaning stones, moonflowers, old groundskeepers' tools, very readable violet night | Small optional loops with Hollow Drudges, Patchwalkers and a memory-note puzzle. A hidden dress pattern, candle decor and a calm bench at the edge. Keep it atmospheric rather than graphic. |
| **Moonveil Manor** | Small gothic manor: crescent windows, velvet colors, many candles, an extravagant bat-shaped crest | Compact five-space interior, readable vampire rules, Count Velour encounter, Manor lantern, tailoring knowledge, and an optional bat rescue. Not a huge human-NPC simulation. |
| **Ward-Keeper's Conservatory** | Overgrown greenhouse silhouettes, planters, patterned amber light, worn festival symbols | Link the three regional lanterns, explain the true-light rule, discover workshop recipes, and read what Lanternwake originally protected. Safe corner. |
| **Sunken Bellhouse** | Half-sunken masonry, still water, one reassuring upper window over an ominous stair | Entrance to the Hushed Works, Foreman's Key connection, equipment/comfort reminder, reliable way home. |

Moonveil Manor's spaces: Entrance Cloakroom (safe return); Looking-Glass Hall (teach reflection/light clues); Ballroom (short candle-routing puzzle); Count's Gallery (vampire encounter); Conservatory Balcony (restored lantern, reward, shortcut). It can be a compact separate area or safely segmented interior; choose after inspecting rendering/loading conventions. Give it stable IDs and saved state either way.

Make garden, quarry and manor routes simultaneously visible after arrival. Each supplies one guaranteed lantern seal, and their progress is recorded independently. Completing one must not erase another. The main tracker may recommend a route but cannot require a secret fixed order.

Essential resources have multiple reachable nodes. Put late materials in recognizable pockets, not uniformly everywhere. Preserve discovered map landmarks, resource pins and shortcuts. Do not cover the map in identical exclamation marks.

### Halloween activities that also serve the sandbox

Grow ordinary pumpkins; carve harvested ones at a workbench into friendly, sleepy, toothy, cat, moon, or ghost faces. Choosing the face is cosmetic and reversible before placement. Lantern colors and patterns can be adjusted without destroying the object.

A small **Lanternwake collection** rewards discovering patterns, growing crops, completing side mysteries, and decorating voluntarily. It is not a mandatory checklist or real-date login reward. Candy is a modest food/cosmetic crafting reward, not currency from microtransactions. Never require changing the computer's date.

The final celebration should add useful lights, recipes and pleasant interactions to Commons. At home, grant decorations to Krystal's inventory/unlock list; do not automatically place a festival stage through her house.

---

## 10. The Hushed Works — Chapter Two's main dungeon

Proposed area ID `hushed_works`. Reuse reliable checkpoint, interaction, room-building and horror-director contracts. Do not rewrite the existing `below` scene into this dungeon.

The Foreman's Key still fits an old service route linking the Bellhouse and mine network. The Weaver's crack connects through an accessible service gallery; no impossible jump into the original ceiling is required. The entry story gate is Chapter One completion plus the linked regional lanterns. Merely acquiring the key early cannot skip the original ending.

Build a connected room graph with two meaningful loops and shortcuts to safety. Three ward-line mechanisms can be approached in a flexible order from the refuge hub. All essential puzzles work with the ordinary lantern, no particular companion, and sound muted.

| # | Room | Playable content | Pacing and safety |
|---|---|---|---|
| 1 | **Service Landing** | Unlock with the Foreman's Key; show a real lantern illuminating its surroundings | Safe checkpoint, permanent exit |
| 2 | **Tool Lockers** | Hollow Drudge encounter, fixed service diagram, optional note | One taught fight, no director ambush layered on it |
| 3 | **Humming Rails** | Rail sounds continue after Krystal stops; the wrong signal has no corresponding light | Suspense and a clue, not instant damage |
| 4 | **Sluice Gallery** | Two visible valves redirect shallow water and restore a ward line | Short route choice, no drowning or irreversible valve state |
| 5 | **Bellmaker's Floor** | Bellcap Sentries; sequence mechanism using large symbols and matching captions | Restore another line; no pitch discrimination required |
| 6 | **Hall of Closed Eyes** | Carved faces and a misplaced lantern reveal an optional route | Quiet after combat; no forced camera control |
| 7 | **Pocket Conservatory** | A shaft-lit underground garden; miners' refuge record; hub for three branches | Safe checkpoint, preparation, reliable return-home shortcut |
| 8 | **Light Well** | Rotate two reflectors to restore the last line; discover an outfit/decor alcove | Calm light puzzle with reset button and readable goals |
| 9 | **Threaded Winch** | Recent Weaver trail; introduce temporary cuttable/burnable threads | Teach before testing; retreat allowed |
| 10 | **Weaver's Crossing** | Focused rematch with the escaped Matron on a secure service bridge | Checkpoint BEFORE arena; horror director suppressed |
| 11 | **The Wrong Landing** | A false lift has a readable lighting flaw; real lift remains discoverable | Wrong choice gives a short recoverable detour, not death |
| 12 | **The Borrowed Porch** | A generic cottage facade in an impossible place; no true illumination | Dungeon-contained illusion, never copies or changes the real house |
| 13 | **Bell Throat** | Final supplies, a miners' note, learn the Choir's exposure rule | Safe checkpoint; explicit return/continue choice |
| 14 | **Choir Vault** | Three-phase Borrowed Choir climax | Reliable victory exit, committed progression and rewards |

Use different room silhouettes, ceiling heights, traversal decisions, sound identities, temperatures and materials. Fourteen renamed copies of one corridor do not satisfy the design.

The Pocket Conservatory shortcut opens persistently. Krystal can return home between excursions, craft, restyle, swap companions and improve equipment. Do not require one long uninterrupted dungeon run.

---

## 11. Chapter Two main story and objectives

All identifiers below are PROPOSED additions. Namespace new quest, encounter, reward and once-event IDs, for example `ch2_*`. Keep existing source IDs unchanged.

Use existing flag/item/placed/counter objectives where appropriate. Add explicit persistent optional/parallel quest support rather than abusing a linear index to represent simultaneous branches. Main progression reads world state; completing an action before reading its objective still counts.

| Step / proposed ID | Objective and story beat | Hint / reward |
|---|---|---|
| 1. **A Light Beyond** `ch2_light_beyond` | After Chapter One, read and ACCEPT the Ward Stone's new inscription | Reveals the old Lanternwake trail; existing victory stays true |
| 2. **The Hallowmere Way** `ch2_waygate` | Repair the boundary waygate with familiar materials | Suggested cost 8 wood, 4 stone, 2 copper ore; permanent two-way access |
| 3. **A Festival Waiting** `ch2_commons` | Reach Commons, light the arrival arch, read its map | Safe checkpoint, home-return route, crop seeds, three visible branches |
| 4. **Three Lamps, Three Roads** `ch2_outer_lamps` | Discover the orchard, quarry and manor lamp locations | Parallel objectives; choose their order |
| 5. **Pumpkins With Opinions** `ch2_orchard` | Repair irrigation, clear the taught mimic encounter, light the garden lamp | Guaranteed Garden Seal, pumpkin seeds, carving and cooking recipes |
| 6. **The Quarry's Pulse** `ch2_quarry` | Defeat Quarry Warden, repair the mineral winch, light its lamp | Guaranteed Quarry Seal, upper route and Ironwood knowledge |
| 7. **A Most Peculiar Invitation** `ch2_manor` | Enter Moonveil Manor, learn candle/reflection rules, break Count Velour's enchantment | Guaranteed Manor Seal; vampire/witch tailoring patterns; safe manor balcony |
| 8. **Made for the Journey** `ch2_prepare` | Read preparations and inspect a practice seam beside the Conservatory | Recommend an armor/tool upgrade, never demand a whole expensive set or mastery level |
| 9. **A Thread of True Light** `ch2_lamps_linked` | Link all three restored lanterns at the Conservatory | Persistent safe-light routes; reveals the Bellhouse stair |
| 10. **The Key Still Fits** `ch2_service_gate` | Use the EXISTING Foreman's Key | Key remains in pouch; no second rescue or key farming |
| 11. **Hask's Rail** `ch2_true_signal` | Follow the real lantern signal to the rail junction | Visual/caption teaching of the false-light rule |
| 12. **A Pocket of Day** `ch2_refuge` | Reach the underground garden; unlock return shortcut | Safe rest and independent route home |
| 13. **What They Left** `ch2_miners` | Recover the fixed refuge record | Confirms Hask, Tobin and Foreman reached the refuge and left by the drainage route |
| 14. **Wake the Lines** `ch2_three_lines` | Restore water, bell and light circuits in any supported order | Different mechanics, independent saved flags |
| 15. **Weaver's Crossing** `ch2_weaver_crossing` | Clear the Matron's bridge ambush using taught counters | Route clears; thread/veil furnishing pattern, NOT another Heartseed |
| 16. **The House That Isn't** `ch2_false_home` | Recognize the imitation porch and reveal the true stair | Harmless retreat possible; real Haven unchanged |
| 17. **No Welcome in That Voice** `ch2_choir` | Banish the Borrowed Choir and free the stolen echoes | Outer ward restored; reward ledger committed before cinematic |
| 18. **Lanterns on Every Road** `ch2_routes_restored` | Return through the brightened festival routes | More pleasant regional exploration and optional trials |
| 19. **Bring the Celebration Home** `ch2_homecoming` | Return to original Haven and speak to its Ward Stone | Earn home decoration patterns and complete-journey recognition |
| 20. **The Lanternwake** `ch2_feast` | Choose “Celebrate” at home or Commons | Small celebration, Chapter Two ending, continued playable world |

Steps 5–7 are branch completion records, not forced ordered prerequisites. When one is completed early, later quest evaluation must accept it. The player can pause the main journey to build, craft, dress up, care for pets, explore old areas, or finish side activities.

Important objects are guaranteed, persistently owned, and recoverable if legitimately missing. If an old save has inconsistent key state, repair only from verified acquisition evidence; do not globally grant keys to unfinished games.

Emotional arc: pride in her home → delight in an autumn festival and new possibilities → theatrical vampire adventure → genuine unease below → frightening but learnable Weaver/Choir encounters → relief and a celebration in the SAME cherished home.

---

## 12. Enemies: different decisions, not bigger health bars

Initial numbers below are tuning starting points. Measure actual player swing rates, old/new gear, no-companion play, every pet, and comfort settings. Never claim balance because the table exists.

Use a faction/target filter, line-of-sight checks, clear wind-up/active/recovery states, and safe arena boundaries. Pets, passive wildlife, decorations and crop pumpkins are not enemies. Cosmetic Halloween decorations never randomly wake up inside the safe home.

### Chapter One additions: four new ordinary types

| Enemy | Where / look | Starting range | Attacks, tells and counterplay |
|---|---|---|---|
| **Brambleback** | Original woodland outskirts; squat bark-backed creature | 55–65 HP, 12–14 damage | Scrapes dirt and lowers its head before a committed charge. Side-step and punish its exposed flank. Front armor reduces damage, never makes early tools completely useless. |
| **Lantern Moth** | Optional dusk pocket or mine annex; round moth with bright wings | 30–40 HP, 8–10 damage | Wings flare before one slow drifting projectile. Use cover/dodge; it rests at melee-reachable height. No projectile through walls. |
| **Hollow Drudge** | Tobin's annex and later Works/Candleyard; shambling mineral-coated miner coat | 55–70 HP, 14–16 damage | Raises a pickaxe for a long, narrow swing. A second distinct tell precedes a ground scrape. Side-step, punish recovery. A zombie-like silhouette without gore. |
| **Brood Skitter** | Optional deeper pockets and capped boss adds; small spider | 24–32 HP, 6–8 damage | Legs draw inward and a small ground mark appears before a short leap. Easy to stagger; max two during a teaching encounter. Arachnophobia: **Pale Sprout**, floating seed with a root lash, fully different silhouette/sound. |

Keep the original Brambling and Gloomling. Add authored encounters using NEW spawner IDs, not resurrected original quest groups. The Nursery stays intentionally quiet. Surface variety does not mean monsters in every berry bush.

### Chapter Two additions: five more ordinary archetypes

| Enemy | Where / look | Starting range | Attacks, tells and counterplay |
|---|---|---|---|
| **Pumpkin Mimic** | Orchard combat plots; squat jack-o'-lantern mouth with stubby vine feet | 65–85 HP, 12–15 damage | Stem twitches twice before waking; interaction announces “Inspect twitching pumpkin,” not an indistinguishable safe crop. Telegraphs a bite; later rolls in a marked lane and gets stuck briefly. Never replace a player's planted crop with a mimic. |
| **Patchwalker** | Orchard/Candleyard; lumbering straw-and-vine garden zombie in a torn coat | 80–100 HP, 15–18 damage | Raised rake sweeps a visible arc. On a separate long tell, throws a mud clod that briefly slows. Dodge outside arc or cut the wind-up; slow is bounded and cannot chain permanently. |
| **Velvet Wing** | Manor approach and galleries; masked vampire bat in a tiny cape | 45–60 HP, 10–13 damage | Hangs still, folds cloak, then dashes along a visible line. Missed dash leaves it at reachable height. A drain mark can be broken with line-of-sight, ward-light, or a hit. No unavoidable lifesteal. |
| **Bellcap Sentry** | Quarry/Works; heavy mushroom-bell guardian | 70–90 HP, 13–17 damage | Bell visibly expands before a radial pulse. Move outside radius or dodge through with normal invulnerability; clear recovery. Symbols and ring graphics communicate everything with audio muted. |
| **Borrowed Wisp** | Deep Works and small late encounters; false warm light in a little mask | 55–75 HP, 14–18 damage | Its light does not illuminate surfaces. Lantern exposure reveals a reachable target before it casts a marked delayed sweep. Do not require randomly choosing among identical lethal clones. |

Do not add every monster to every biome. Distinguish territory, sound, movement and loot identity. Reuse original enemies thoughtfully where mixed encounters teach complementary skills. Regular encounters generally use two or three enemies; cap projectiles and simultaneous committed attacks.

Common enemy materials are renewable but never the only random source for a story-required component. Cleared story groups stay cleared. Repeatable groups have separate IDs and schedules and never respawn in view, directly beside the player, or while a route is still being traversed.

### Optional Chapter One elite — Knotted Elder

A large thorn-root guardian in a NEW Thornthicket pocket. Root sweep and committed charge have different tells. Temporary roots leave a route or can be cut; no enclosure softlock. A Resin reward, planter pattern and outfit detail make it worthwhile. It does not replace the original ruin group or block Lumi's old rescue.

### Ashbell elite — Quarry Warden

A broad stone guardian with a cracked bell in its shell. Teach side-step/punish, then introduce three spaced ground pulses. Bait a committed charge into a fixed mineral pillar to expose the guardian. At least two pillars or a recoverable reset prevent an unwinnable arena. Guaranteed Quarry Seal. Pillars and combat state reset consistently on retry; permanent winch/quest progress does not.

---

## 13. Three distinct major Chapter Two encounters

### 13.1 Count Velour — theatrical vampire, not a copy of the spider

Original visual: a small floating bat-masked figure in an oversized velvet cape, a flamboyant collar and a tiny crown. Express character through silhouette, hovering, cloak motion, emotes and brief text. No realistic face, lip-sync or voice acting required.

He has been repeating a stolen festival invitation under the Choir's enchantment. He is a real antagonist during the encounter; afterward he becomes an eccentric, non-hostile manor resident offering brief lines and unlocked tailoring patterns. Do not add a complex branching dialogue system.

Arena: a compact ballroom with curtains, a central light fixture, three ward candles and visible cover. Teach one candle before combat. “Daylight” here is stored ward-light, so neither real time nor the day/night clock can block victory.

**Phase A — An invitation too close.** Velour bows and his shadow points along the coming cape-dash lane. Sidestep; he recoils at the far end for an attack window. A later drain tether shows its connection and warns before healing him; break line-of-sight, strike him, or enter a lit candle pool. The tether does not heal him before its visible channel succeeds.

**Phase B — The ballroom in flight.** He disperses into bats. A broad marked safe lane remains as bats sweep across two other lanes. The true returning bat carries a recognizable collar/shape; candle-light reveals him early. He reforms at reachable height and cannot remain invulnerable indefinitely. No more than one ordinary Velvet Wing helper at a time.

**Phase C — Drop the borrowed mask.** He tries to darken a candle with a stationary, interruptible channel. Relight an accessible candle using the lantern or attack his exposed form. Light staggers him and creates a generous damage window. Strong equipment helps, but there must be at least one meaningful interaction with the core mechanic.

Starting health about 340–420; tune for approximately 2–4 minutes of engaged first-encounter play, not a guarantee. Defeat disperses the enchantment, not gore. He returns the Manor Seal and remarks: “A dreadful host. I did not even offer you a chair.” Commit completion before dialogue; no reward duplication on reload.

Gentle: slower dash, easier tether break, one sweep pattern. Intense: a taught dash feint with a separate final tell and less idle time, not invisible projectiles or louder volume.

### 13.2 Weaver's Crossing — the escaped Matron returns

Use a NEW encounter ID and separate state. This is not resetting the Chapter One boss. A broad service bridge has guardrails and authored ceiling anchors; no bottomless precision-platforming requirement.

First, the Matron throws cuttable threads across one route while a clearly telegraphed pounce targets another. Krystal lights line-braziers and clears threads to expose anchors. After one exposure the Matron changes sides and introduces a delayed pounce with an audible/visible final preparation. A two-minion release can occur instead of, never simultaneously with, the most demanding pounce.

Require line-of-sight and valid landing points. No attacks through ceilings, knockback into unrecoverable voids, or mandatory rapid 360-degree camera spinning. Limit ongoing environmental hazards to one set plus one committed attack. Pets attack exposed phases normally.

Two or three successful anchor exposures plus tuned damage drive the Matron behind an old service gate. Its deeper route closes; it is no longer this chapter's main threat. Reward a distinctive thread/veil decor pattern, not the Heartseed. Preserve the original `weaver_defeated` and restoration flags.

Arachnophobia: the Hollow Mother floats between stone seals; floating veils and pale roots replace every spider/silk element, including adds, shadows, art, icons and captions. No arachnid close-up is forced on either mode.

### 13.3 The Borrowed Choir — final boss

Original shape: cracked hanging bells, wooden masks, harvest ribbons and dim lights around an empty center. It learned the miners' signals and the festival's welcoming sounds but cannot make genuine light. This explains the echoes and imitation Lumi without retconning the restored Heartseed.

Arena: a large readable circular vault with three fixed lantern anchors, safe walkable perimeter and clear exits after victory. Prepare an accessible practice reveal just before the arena.

**Phase A — False welcome.** Three forms appear. The genuine threat consistently illuminates a marked nearby surface and has the correct silhouette motion; false ones do not. Raising the lantern at a fixed anchor resolves the ambiguity. Correct reveal grants a damage window. Wrong selection produces a survivable, telegraphed sweep rather than instant death. Use at least two cues and an explicit high-visibility option, not color alone.

**Phase B — Stolen rhythm.** It sends visible expanding resonance rings and marks short delayed strike zones. Activate two fixed resonators using the symbol sequence taught earlier. Each weakens a protection layer. Timing assist removes tight timing; sound muted remains fully playable. At most two Borrowed Wisps, not an unlimited add factory. Pets attack the exposed form, not illusory hitboxes.

**Phase C — The kept flame.** False cozy lights compete with a visibly anchored true flame. Move among reachable lit sectors, dodge one readable pattern and reveal the Choir with the lantern. Three successful exposures or an equivalent tested damage threshold ends the fight. Good equipment shortens damage windows but does not bypass all learned interaction; avoid long arbitrary invulnerability waits.

Starting health around 480–620 with low overhead between phases; tune for approximately 4–6 minutes of first-encounter combat. Enforce a generous recovery pattern and checkpoint. This must not be a 15-minute damage sponge.

Victory releases the trapped echoes as gentle chimes. Masks and ribbons fall harmlessly; regional lanterns regain their true signal. Boss completion and one-time rewards commit atomically BEFORE optional ending presentation. A crash during credits must resume into a completed world, not duplicate loot or replay the fight.

---

## 14. Six authored horror moments and their rules

Suppress the random director during authored scenes, boss encounters, puzzles needing concentration, and recovery. Use only one major event at once. Quiet stretches are content, not gaps to fill with enemies.

| Moment | What happens / learnable rule | Gentle / Intense |
|---|---|---|
| **The Pumpkin That Turned** | A clearly non-player-owned roadside pumpkin faces a different direction on return. Later a stem twitch teaches mimic recognition. No unavoidable attack. | Gentle: playful movement and caption. Intense: a distant face quietly turns before looking still; no volume spike. |
| **The Empty Waltz** | In the manor, one pair of hanging cloaks moves after the waltz stops. Candle-light reveals harmless supports; a later room applies the true-shadow rule. | Gentle: longer preview. Intense: delayed final movement, always readable and non-damaging. |
| **Hask's Last Knock** | The rails answer after Krystal stops moving. Correct signals have a nearby source/visible lantern; false ones come from dark sealed corridors. | Gentle: clear source caption. Intense: more patient silence, never a compulsory audio-only decision. |
| **The Companion at the Wrong Door** | A fake Lumi appears where the real companion cannot be. Its light fails to illuminate the ground and its movement/chime is wrong. | Gentle: explicit clue, harmless fold-away. Intense: the illusion waits longer before moving. No pet is replaced or harmed. |
| **Scratching Above the Winch** | Loose dust and a visible overhead route precede the Weaver. Counter is the taught lantern/line-brazier rule; not an instant attack while reading a note. | Gentle: fewer passes and no stalking lunge. Intense: longer anticipation then a clearly marked approach. Non-arachnid variant uses drifting dust/veil sounds. |
| **The Borrowed Porch** | A generic safe-looking cottage facade exists inside the dungeon. The “warm” lamp casts no local light; the true path has an anchored flame. | Gentle: clear interaction description. Intense: a brief familiar musical fragment, then silence. Never reconstruct private home details or alter the real Haven. |

Important lore text/audio never plays simultaneously with loud combat music. Captions name meaningful sounds without spoiling every optional mystery. Do not clone real people's voices or access personal recordings.

The director remains a local rule-based system. Preserve event eligibility, deterministic debug seeds, safe-zone exclusion, cooldowns, no-spawn-in-view rules and major-threat budgets. Add only well-tested new events. On returning home, fully suppress hostility; harmless ambient festival sounds should not simulate an invasion.

---

## 15. Optional stories, continuing goals, and replay

Quests are signposts into systems, not the only source of pleasure. Keep optional objectives separate from the main story and preserve them across chapters.

### Side activities with real payoffs

| Activity | What makes it different | Reward |
|---|---|---|
| **A Pumpkin With a Face** | Grow, harvest and carve a pumpkin; choose its face and light | Carving patterns, own-home decor, useful food remains |
| **The Count's Wardrobe** | Find three guaranteed cloth scraps in the manor's optional rooms; each has a visual clue | Vampire dress/cape pattern, not a random tiny drop chance |
| **A Candle for the Groundskeeper** | Read two short Candleyard notes and place a light at a fixed empty marker | Ghostlight lantern and a calm moonflower nook |
| **A Hat Too Large** | Follow fluttering ribbons along a short visible route to a stranded witch hat | Ribbon Witch accessory; no precision-jump requirement |
| **The Long Way Home** | Open three return shortcuts through exploration | Map pin upgrade and a cottage sign style |
| **The Harvest Table** | Cook two DIFFERENT seasonal recipes and choose a table decoration | Kitchen palette and festival dessert recipe |
| **A Room for Friends** | Assign safe home spots and place any companion furnishing | New affectionate home interactions; no required room shape |
| **The Miner Who Came Back** | Find optional Tobin/Hask notes in old annex and new refuge | Miner lantern furnishing and a story resolution, not another mandatory fetch chain |

Do not force all eight to unlock the ending. Their rewards remain obtainable afterward. Guaranteed collectible sources persist or recover correctly; completion never consumes placed player decorations without consent.

### Optional fourth friend — Pipkin, a pumpkin-hood bat

A bonus only AFTER Mochi, Pebble and Lumi have complete, tested combat/home behavior and the main chapter works. Do not use a new pet to avoid improving the old ones.

Find a tiny fruit bat tangled in a harmless ribbon in the manor balcony. Free it and offer a Pumpkin Biscuit. It has a little pumpkin hood, oversized ears and a polite upside-down sleep. Favorite food: Roseberries.

Role: optional treasure scout. A restrained sparkle points toward nearby undiscovered OPTIONAL caches; it never reveals every horror event or multiplies quest loot. Basic attack is a small 5-damage swoop; signature “Moon Mote” briefly marks one enemy for a modest bonus on Krystal's next hit, with a 25-second cooldown. No extra loot on bosses, no guaranteed superiority to the first three. One-follower rules still apply.

All baseline systems and story must remain completable with no Pipkin. If bonus scope is not implemented, report it plainly as deferred, not completed. It is the only optional extra companion in this release.

### Post-story sandbox

Keep BOTH surface regions and BOTH main dungeons reachable. Offer renewable wood, ore, plants, pumpkins, cloth ingredients and late materials. A fully equipped player can make more ambitious buildings and collect styles without replaying the story.

Support Ironwood/Moonsteel gear goals, optional gathering/support charms, backpack/chest improvements, upstairs/porch/garden projects, outfit presets and companion bonds. Do not auto-scale every old enemy to match upgrades; returning stronger should feel rewarding. Separate optional trials provide challenge instead.

**Lanternwake Expeditions:** an optional board selects from three hand-authored replay templates—Orchard Patrol, Quarry Circuit, and Manor Afterglow—with a small saved random seed for group/reward variation. These are not procedurally infinite dungeons. Show expected difficulty and reward types before starting. No daily login restriction, real-time FOMO, compulsory grind or required rare drops.

**Echo Trials:** optional replay versions of Matron, Velour and Choir encounters, introduced as memories. They use isolated encounter/reward state, never revive the main-world boss or give another quest Heartseed. First clears guarantee unique cosmetic patterns; repeated clears provide modest renewable resources. Leaving a trial returns the player safely with normal progress intact. Do not save fake trial victory flags over story flags.

A cozy player should have things to grow, cook, style and build; an adventurous player should have equipment goals and replayable fights. Neither playstyle is required to exhaust the other.

---

## 16. Materials, crafting and placeables: implement the whole supply chain

Use original IDs unchanged and namespaced new IDs. The display names here are proposed content; choose stable actual IDs after checking the item database. Every named reward, ingredient, station and unlock must exist and be reachable. Add automated dependency/obtainability validation.

### Sources

| New material | Reliable acquisition | Renewable role |
|---|---|---|
| **Sunflax / Seeds** | Sunny Meadow optional patch, Orchard starter packet | Cloth and furnishing materials; normal crop loop |
| **Roseberries / Seeds** | Original-world garden discovery and Hallowmere hedges | Food, dye, optional Pipkin food |
| **Resin** | Marked tappable sap stumps; optional Brambleback/Elder drops | Furniture and processing; no required combat RNG |
| **Pumpkin / Seeds** | Guaranteed Commons starter seeds and Orchard plants | Carving, cooking, decor; harvest grants replantable seeds |
| **Sugarcap** | Thimblebrook fungus patch | Seasonal desserts; renewable |
| **Moonpetal** | Pool/Candleyard edge plants | Lavender/blue dye and tea; renewable without grave combat |
| **Iron Ore** | Lower Ashbell accessible with old stone pick, slower | Bars, equipment and advanced construction |
| **Moon Crystal** | Upper Ashbell after winch repair; Ironwood pick | Moonsteel and late decorative light; renewable |
| **Copper Bar / Iron Bar** | Furnace processing | Do not replace legacy raw-copper recipes |
| **Woven Cloth** | Loom from Sunflax and existing fiber | Outfits, ribbons, decor |
| **Lantern Wax** | Workbench from Resin and existing fiber | Candles and pumpkin lights |
| **Moonsteel Bar** | Furnace from Iron Bar, Moon Crystal, existing Echo Shard | Final gear tier and optional ornate structures |

All original resources remain useful. Add renewable Echo Shard and silk/Pale Thread nodes in safe post-discovery resource pockets, with stable new IDs, if the old supply is finite. Do not accidentally deplete every source of a required material.

### Initial workstations and processing recipes

Quantities are initial balance specifications. Keep resource costs comfortable; tune using actual route/gathering time, not arbitrary scarcity.

| Station / output | Recipe | Availability |
|---|---|---|
| Furnace | 10 stone + 4 wood + 2 copper ore, at workbench | Early Chapter One optional discovery; not an inserted quest |
| Loom & Dye Bench | 8 wood + 6 fiber, at workbench | Old Oak tailor cache; existing saves can find it |
| Vanity Mirror | 4 wood + 2 copper ore + 2 stone, at workbench | Free safe styling exists before this decorative convenience |
| Improved Kitchen | 8 stone + 6 wood + 2 copper bar, at workbench | Early workshop upgrade; old campfire still works |
| Woven Cloth ×2 | 3 Sunflax + 2 fiber, at loom | Starter tailoring |
| Copper Bar ×1 | 2 copper ore, at furnace | Short, saved batch timer |
| Iron Bar ×1 | 2 iron ore, at furnace | First quarry access |
| Moonsteel Bar ×1 | 2 iron bar + 1 moon crystal + 1 echo shard, at furnace | Upper-quarry discovery |
| Lantern Wax ×2 | 1 resin + 1 fiber, at workbench | First Resin discovery |
| Comfort Ribbon | 2 cloth + 2 berries, at loom | Mochi's optional courage task |

Furnaces are cozy devices, not house-fire simulators. No fuel tax is necessary for this release. Use a finite queue, visible completion state and interruption-safe output. Either player inventory or a small station output buffer receives results exactly once. No lost/duplicated batches on save/load.

Dye unlocks a reusable palette at the Loom rather than charging for every character edit. Example palettes: rose (Roseberries), pumpkin (Pumpkin), lavender (Moonpetal), cream (Sunflax), ember (Resin + berry), midnight (Moonpetal + Echo Shard). Physical garment patterns can consume cloth once to become owned; switching owned clothes is free.

### Equipment and storage

| Item / upgrade | Initial recipe | Purpose |
|---|---|---|
| Padded armor pieces | Hood: 1 cloth + 3 fiber; body: 2 cloth + 4 fiber; boots: 1 cloth + 2 fiber | Modest optional early protection |
| Copper Axe / Pick | 3 wood + 3 copper bar + 2 fiber | Faster old-region gathering; stone tools remain usable |
| Copperwood armor pieces | Hood: 2 cloth + 1 copper bar; body: 3 cloth + 2 bars; boots: 2 cloth + 1 bar | First optional defensive set; appearance independent |
| Ironwood Sword | 3 iron bar + 2 wood + 1 cloth | Meaningful melee upgrade |
| Ironwood Axe / Pick | 3 iron bar + 3 wood + 1 resin | Efficient mining/woodcutting, Moon Crystal access |
| Ironwood armor | Hood: 2 iron bars + 2 cloth; body: 4 bars + 3 cloth; boots: 2 bars + 2 cloth | Mid-tier protection |
| Moonsteel Sword | 4 moonsteel bar + 2 wood + 1 echo shard | Late melee tier |
| Moonsteel Axe / Pick | 3 moonsteel bar + 3 wood + 1 resin | Late gathering efficiency; not a unique-story bottleneck |
| Moonsteel armor | Hood: 2 moonsteel bars + 2 cloth; body: 4 bars + 3 cloth; boots: 2 bars + 2 cloth | Late armor; old equipment remains owned |
| Sparkseed Wand | 4 wood + 2 copper bars + 2 glowcaps | Optional ranged combat at accessible tier; no unique required interaction |
| Gatherer's Charm | 2 resin + 2 copper bars + 2 fiber | Modest harvesting convenience; one charm slot |
| Swiftstep Charm | 2 iron bars + 2 moonpetals + 1 cloth | Stamina benefit, movement bonuses obey cap |
| Kindling Charm | 1 moonsteel bar + 2 glowcaps + 2 cloth | Modest healing/lantern utility; no compulsory boss immunity |
| Backpack 32→40 | 4 cloth + 2 copper bars | Preserve original 32 slots and hotbar order |
| Backpack 40→48 | 6 cloth + 2 iron bars | Optional additional capacity |
| Chest 20→40 | 6 wood + 2 iron bars | Upgrade chosen chest in place; preserve UID/content |

Do not consume old swords or tools as hidden ingredients. For an actual in-place upgrade UI, show exactly what changes and keep any unequipped original item safe. Equipment snapshots, capacity changes and crafting transactions need regression tests.

### Food and farming

Add Sunflax, Roseberry and Pumpkin crops using the existing crop framework; all four crop families including Sweetroot remain usable. New crop growth targets 5–10 active minutes before the existing blessing/tending modifiers. This is not forced idle time: she can explore/build, and existing bed/time behavior should remain consistent. One crop harvest should return or permit enough seeds to sustain planting.

Suggested recipes: Pumpkin Soup (1 pumpkin + 1 sweetroot, heals 40); Pumpkin Biscuit (1 pumpkin + 1 Sugarcap, two small snacks); Roseberry Tart (2 Roseberries + 1 Sugarcap, heals 30 plus a short minor stamina benefit); Moonpetal Tea (2 moonpetals + 1 sweetroot, small heal and short slow resistance); Lanternwake Platter (1 pumpkin + 2 Roseberries + 1 sweetroot, strong restorative meal at improved kitchen).

Specify timed-buff stacking rules. A stronger food replaces/refreshes the same buff family rather than stacking dozens. Preserve old foods and recipes. No hunger, ingredient spoilage, equipment durability decay or mandatory gardening schedule.

### Building/decor minimum selection

In addition to every legacy piece, implement at least these coherent functional or visibly distinct additions: stairs, upper-floor support/landing, railing, half-wall, porch post, arched window, gable roof, roof corner, window flower box, curtain, bookshelf, wardrobe, mirror, kitchen unit, companion bed, companion perch, sturdy planter, cottage bench, selectable-face pumpkin lantern, pumpkin string lights, bat bunting, ghost lantern, crescent window, candy bowl, decorative scarecrow, and gothic porch trim.

Group structural pieces into recipes with costs proportional to existing wood pieces, not ten times more expensive. Cloth furnishings use wood/fiber/cloth; Halloween lanterns use pumpkins/Wax/wood; ornate late variants use small amounts of iron/Moonsteel. Bind every listed piece to an explicit recipe/data definition before claiming it exists. Palette swaps are variants, not the entire counted catalogue.

Unlock starter structural essentials such as stairs early. Story rewards may add styles but cannot gate all useful home expansion. Keep late rewards worthwhile without locking basic customization or storage behind the final boss.

---

## 17. Writing, identity and the ending

Use “Krystal” sparingly. Keep the original dedication and authorship: **For Krystal, from Ali**. Do not replace it with the developer/model's branding. Text is short, warm and slightly old-fashioned for inscriptions.

Use or lightly polish these lines while keeping their facts:

**Ward Stone, Chapter Two available:** “A light well kept reaches farther than its keeper knows. There are lanterns beyond these woods. Tonight, one has answered.”

**Acceptance choice:** “Follow the lantern road” / “Stay a little longer.” Declining does not hide new wardrobe or companion systems.

**Ward Stone, reassurance:** “Your hearth is safe. No road you follow shall unmake it.”

**Festival board:** “Lanternwake: a lamp at every gate, a sweet upon every table, a place for every traveler.”

**Garden note:** “Plant the round ones for supper. Carve the crooked ones for company. Do not feed the one that feeds itself.”

**Manor invitation:** “To the bearer of a proper light: you are expected. The house has practiced being welcoming.”

**Count Velour, first bow:** “Do come in. I have been expecting someone for a terribly long time.”

**Count Velour, after the curse:** “A dreadful host. I did not even offer you a chair.”

**Hask's rail note:** “The knock came back a beat too late. I put my lamp beside the rail. A true light stays with what holds it.”

**Tobin's note:** “I dropped the lantern when the passage answered me. Hask found me at the sluice. Tell whoever comes after us: the garden below is real.”

**Foreman's refuge record:** “Three of us made the garden. Tobin, Hask, and me. We left by the drainage stair at dawn. The voices stayed behind.”

**Ward-Keeper's Conservatory:** “We did not build the lanterns to drive out every dark. We built them so a traveler could always find a kindness.”

**Before the Choir:** “It has learned a welcome. It has not learned a home.”

**Mochi after learning courage:** “Mochi checks its ribbon. Then it takes one very brave little step.”

**Pebble guarding:** “Pebble plants its feet. This is apparently a job for a very serious rock.”

**Lumi after restoring a lamp:** “Lumi's light answers the lantern, warm and gold.”

**Pipkin, only if implemented:** “Pipkin offers you half a berry. It seems to have already inspected the other half.”

**Ward Stone, return:** “Light kept. Roads found. Welcome home, Krystal.”

**Chapter Two ending card:** “The lanterns shine beyond the trees. The quiet below is quiet again. There are pumpkins to plant, walls to raise, and friends waiting by the fire. The road will keep. Tonight is yours.”

Ending: original home, original placed furniture, chosen appearance, current companions, warm festival music, a small skippable celebration. No scripted camera inside a wall: validate cinematic viewpoints against player-built geometry and fall back to a simple safe shot. Do not spawn tables or guests inside her house.

Rewards: Lanternwake festival dress, carved-lantern patterns, gothic/cottage furnishing variants, a pleasant Wardlight feature for the home, optional trial access, and continued resources. Existing Chapter One rewards remain owned. Send overflow to safe persistent storage/pickups without losing items. After a clear “Chapter Two complete,” resume FREE PLAY in the same save.

---

## 18. Music overhaul for BOTH chapters — keep the good music, end the repetition

The owner likes the current music. Preserve its best melodies and atmosphere. The problem is insufficient audible variety and location identity, not a request to replace everything with a different style. Inspect the actual audio routing: the handoff lists five music pieces, but that does not prove players regularly hear all five or that their transitions work.

Audit which tracks actually play, where, for how long, and what causes restarts. Fix any dominant-loop or selector bug as well as expanding the library. Do not merely create audio files that never get selected.

### 18.1 Cue catalogue: 27 genuine compositions

Retain and remaster the five existing title/Haven/night/boss/return pieces when they fit, and create the additional compositions below. Proposed cue names are data IDs, not existing assets. A phase stem, pitch shift, percussion mute or tempo change of one piece is not a second composition. Each new piece needs a recognizable melody/motif, arrangement or substantial original ambient structure.

| ID / working title | Location / purpose | Musical direction |
|---|---|---|
| M01 **A Little Light** | Title/menu; retain existing title theme | Preserve the gentle music-box/plucked identity; no abrupt reset between adjacent title panels |
| M02 **Home in the Clearing** | Original Haven day A; retain current Haven theme | The familiar comforting melody she already likes |
| M03 **Wood, Wool & Windows** | Haven day B / building | Soft plucked strings, marimba, warm bass; different tune and phrase length |
| M04 **Berry Tea Afternoon** | Haven day C / crafting and gardening | Gentle piano/celesta, airy woodwind-like synth, sparse percussion |
| M05 **Lanterns After Dark** | Haven night A; retain existing night piece | Quiet familiar nocturnal mood |
| M06 **Firefly Wishes** | Haven night B | Slower harp-like plucks, warm sustained tones, a new lullaby melody |
| M07 **Footpaths & Ferns** | Chapter One woods exploration A | Light wandering rhythm, soft bells and distinct ascending phrases |
| M08 **The Long Way Home** | Chapter One woods exploration B | More spacious melody and instrumentation; not M07 transposed |
| M09 **Ripples at Mirror Pond** | Pond / quiet glade visits | Sparse piano, water-like plucks, long rests; optional appearances, not constant wallpaper |
| M10 **Thorns in the Path** | Ordinary Chapter One combat | Short energetic melodic loop with clear resolution; not the boss theme |
| M11 **The Last Shift** | Old Mine / Tobin annex | Low restrained pulses, isolated metallic notes, long-form ambient variation |
| M12 **Eyes That Stay Shut** | Ruins / portions of Silk approach | Dissonant bell-like fragments, bowed-synth texture and genuine space for silence |
| M13 **The Thread Above** | Chapter One Matron; retain existing boss piece | Preserve identity, add musically compatible phase layers and recovery transitions |
| M14 **The Heart Comes Home** | Original Chapter One restoration; retain ending reprise | Existing emotional payoff stays recognizable and correctly triggers once |
| M15 **Welcome to Lanternwake** | Commons / regional safe areas | Playful autumn melody, celesta, soft pizzicato, gentle theatricality |
| M16 **Copper Leaves at Dusk** | Hallowmere travel alternate / festival outskirts | Warm lilting exploration; different structure from Commons music |
| M17 **Pumpkin Patch Parade** | Orchard / seasonal gardening | Bouncy but not irritating bassoon-like synth, marimba, little clacks, warm strings |
| M18 **Stone Bells, Quiet Hills** | Ashbell Quarry | Measured low plucks, occasional struck-metal tones, broad adventurous phrases |
| M19 **Candles for the Moon** | Candleyard | Gentle eerie lullaby, airy choral-like synth without intelligible voices; no cheap stinger loop |
| M20 **The Empty Waltz** | Moonveil Manor exploration | Original minor-key three-beat waltz, harpsichord-like timbre, celesta and muted low strings |
| M21 **A Midnight Invitation** | Count Velour encounter | Faster theatrical waltz with a contrasting middle section and clear phase transitions |
| M22 **Harvest Trouble** | Ordinary Chapter Two combat | Playful-spooky action, distinct from M10 and major-boss music |
| M23 **Under the Bellhouse** | Hushed Works | Sparse metallic ambience and restrained harmonic movement, room for environmental clues |
| M24 **A Pocket of Day** | Underground refuge | Warm little piano/harp melody; relief after the surrounding soundscape |
| M25 **No Thread Left Unseen** | Weaver's Crossing | More urgent original rematch arrangement with genuinely new material, not only louder M13 |
| M26 **The Borrowed Welcome** | Final Choir encounter | Familiar interval hints become unsettling counterpoint; three coherent intensity layers; accessibility cues remain audible |
| M27 **Every Road Leads Home** | Chapter Two return / celebration / optional later safe-home rotation | Bright original festival reprise combining selected home and Lanternwake motifs with a new ending |

Typical non-stinger pieces should have roughly 90–180 seconds of meaningful musical development; ambience can use evolving layers and silence. Do not loop an eight-second generated arpeggio for three minutes and call it a full track. Use distinct A/B sections, rests, endings and arrangements. Shared thematic motifs provide coherence but must not make every track sound identical.

Target 27 usable base compositions including retained pieces. If practical inspection reveals a source cue does not exist or is unusable, create its replacement rather than claiming it was retained. The catalogue is a production requirement, not a list of pretend completed assets.

### 18.2 A music system that makes the variety audible

Use a data-driven `MusicDirector` or extend the existing audio system cleanly. It must be separate from enemy/horror logic while receiving necessary state/events. Music randomness uses its own seed/state and must not change gameplay random outcomes.

Inputs: area, subregion, day/night, safety, combat state, current boss/phase, authored scene, menus, comfort settings and recent tracks. Example priority: muted/paused policy → authored ending/major cinematic → active boss → authored horror suppression → ordinary combat → safe refuge → regional exploration → ambience. Define exact ownership so two directors cannot fight over volume every frame.

Use a shuffle bag per playlist, prevent immediate repeats, and do not restart a track because the player opens inventory or crosses a boundary for one frame. Haven daytime rotates M02/M03/M04, night rotates M05/M06; exploring the original woods rotates M07/M08 with appropriate location entries for M09. Hallowmere uses M15/M16 plus authored subregion identity cues. No single track should dominate every safe area by accident.

Regional overrides need hysteresis: require approximately 8–12 seconds of stable entry and a minimum dwell/cooldown before switching again. Do not retrigger a dramatic arrival every time the player gathers at a border. A region may play its signature then return to a varied compatible playlist rather than indefinitely repeating one piece.

Where practical, transition on a phrase boundary. Use about 3–6 second gentle exploration crossfades and faster but controlled combat entries; prevent clipping during overlap. On ordinary combat end, release over a few seconds and return to the prior regional mood after threat has genuinely cleared. A distant enemy stuck behind a wall must not pin combat music forever.

For bosses, compatible stems can respond to phase changes without restarting the entire piece. For horror, sometimes fade music OUT so the room, footsteps and silence matter. Do not paste dramatic boss music over every corridor or jump scare. Keep important attack tells, companion cues and UI information audible with sensible ducking rather than huge volume changes.

Preserve track-history state as an optional small part of audio preferences when appropriate; exact sample-position resume is not required. A save must not fail just because an audio cue was renamed. Gameplay state migration takes priority over musical resume.

### 18.3 Production and player control

Use the existing original synthesis workflow where effective, but do actual composition: melody, harmony, register, articulation, phrasing, instrumentation and arrangement. No copyrighted Halloween/movie/game songs and no unlicensed downloads. A more varied instrument palette is welcome, but licensing and reproducibility still apply.

Generated assets must be committed or reproducibly generated, imported correctly, exported with the game and included in provenance. Use streaming/compression appropriate to long tracks rather than keeping every uncompressed music buffer in memory. Verify actual supported import settings for the installed Godot build; do not invent APIs.

Keep separate music, ambience, effects, UI and master controls; add a restrained optional **Music Box** furnishing that previews/unlocks discovered safe-area tracks and favorites. It is a home feature, not a global override that breaks boss/horror cues. Add its actual model, recipe (6 wood + 2 copper bars + 1 echo shard), UI and persistence only after the core selector works. No music-box craft is required to hear soundtrack variety.

Test normalized loudness, peaks, loop seams, starts/stops, crossfade sums, silent gaps and phase changes. Do not flatten every song to maximum loudness. Preserve important dynamic contrast at comfortable levels. Reduce-flashing/shake settings do not get bypassed by music-synchronized VFX.

### 18.4 Honest music verification

Supply a track manifest: source/generator, composition ID, duration, location playlist, instrument/arrangement notes, import format, peak/loudness measurements and observed in-game selection.

A selector unit test and a telemetry log do not establish that music sounds good. With available listening/audio tools, audition distinct sections and transitions and inspect in-game mix recordings. If subjective listening is unavailable, label it NOT VERIFIED; do not claim a human listening pass happened.

Run a bounded real-game route covering original Haven by day/night, original exploration, mine, original boss/trial, Commons, orchard, manor, quarry, Works, new boss and return. Log actual track changes. Separately verify idle safe-home rotation and boundary oscillation. Report audible checks separately from scheduling tests or simulated-time tests.

Do not replace the player's liked original soundtrack wholesale. The update should sound familiar at home and excitingly different across the world.

---

## 19. Implementation architecture and compatibility requirements

Follow the ACTUAL `AGENTS.md` and `docs/ARCHITECTURE.md`. The handoff reports typed GDScript with tabs, no `class_name`, script-built child nodes, persistent state through `GameState`, and inter-module signals through `Events`. Preserve these contracts unless a narrow, necessary change is documented and tested. Do not build a second framework beside the first one.

Use data files for items, recipes, structures/crops, appearances, equipment, enemies, quests, companion skills, music and horror events. Keep new state versioned and owned centrally. Separate visual selection from stat calculation and from inventory transactions.

Likely additive state categories:
- Appearance selections, owned patterns, palette unlocks, presets and cosmetic settings.
- Equipment slot records, capacity upgrades, finite station queues and output buffers.
- Optional objectives, chapter acceptance, independent branch flags and reward-once ledger.
- Companion skill cooldowns, courage flag, home assignments and any new perk state that cannot be derived from existing bond XP.
- New-area discoveries, resource/spawner IDs, crop/world persistence, and trial/exploration ledgers.
- Conservative mastery progress and a one-time legacy-credit marker.
- Music preferences/history if needed; avoid putting unnecessary playback internals in critical saves.

Prefer deriving effective stats and bond perks from authoritative inputs rather than redundantly saving totals. Migrate derived-value fields deliberately if the old state mixed them. Timed effects need one defined clock: paused play stops combat cooldowns; normal sleeping/travel behavior is explicit; app closure does not silently generate days of loot or infinite home work.

Register every new area and spawn through existing `Game.AREAS` / area contracts. Check `get_zone_at`, safe zones, collision validation and spawning for each. Use `Game.change_area` only after confirming the installed code signature. Update autosave logic for new safe areas; the old surface-only manual-save check must not accidentally forbid every new region.

Per-area transient enemy/boss state can reset consistently, but committed victory, keys, opened shortcuts and permanently restored lamps must remain saved. Trial instances need explicit rules for save/quit/rejoin; they cannot overwrite original-world boss flags.

Add a small obstacle-aware navigation solution where current breadcrumbs/direct steering fail. Keep it proportional: navigation regions or an authored waypoint graph with collision checks, local avoidance, leashing and safe recovery. Test actual two-storey player builds, doors, narrow dungeon halls and boss arenas. A pet visibly fighting from behind a wall is not a successful pathfinding workaround.

Use bounded object/audio budgets. Pool frequent projectiles/effects if measurement supports it; prevent thousands of live timers, particles, sounds or enemy nodes. Deactivate unloaded areas' visual/AI work while preserving saved state. Do not run parallel unbounded CPU load tests or leave processes behind.

Provide an authorized non-invasive debug/QA view with read-only state and music/quest/damage events. Keep item-grant, teleport and flag-setting cheats behind the existing debug guard and OUT of the ordinary release experience.

Do not silently accept wrong engine-version syntax or suppress runtime script errors. Run baseline tests first. The handoff's 653 passing tests describe a previous build, not proof about this one. Preserve and extend the suite, adapting a test only when its documented product requirement intentionally changed, never to hide a failure.

---

## 20. Save-continuity and QA release gates

Testing is part of the implementation, not a paragraph saying it should be done later. Distinguish source review, unit/integration tests, graphical inspection, real-input play, profiling and subjective listening/fun. Report each honestly.

### 20.1 The real-save evidence gate

The supplied handoff explicitly labels its Chapter-One-complete sample as a BOT TEST SAVE, not Krystal's personal world. Do not substitute it for hers.

Create isolated QA copies of the actual player save when it is accessible and permission allows. Record file hashes before testing. Never run New Game against the real profile. Back up live saves and the old build before the eventual player-initiated upgrade. Test migration failure before packaging, not on her live house.

Compare canonical pre/post state immediately after migration, BEFORE gameplay advances the clock. Compare all preservation fields from section 2, allowing only documented additive/default changes and deliberate schema normalization. In particular inspect:
- Structure count, every UID/type/area/position/rotation/data record, chest binding and contents.
- Crop identity/growth and resource depletion; no regenerated ID-order mapping.
- Inventory/key quantities and ordering; chosen hotbar and usable legacy tools.
- Companion identity/bond/assignment, original bed/respawn, quests/flags, restored world and unlocked recipes.

Give a machine-readable difference report. Screenshot the actual home from comparable safe views before/after using a COPY, but do not treat screenshots alone as proof that hidden chest/crop data survived. Reading a JSON successfully is not migration verification either.

If the actual personal save is unavailable, use documented bot and synthetic fixtures and mark PERSONAL-SAVE VERIFICATION BLOCKED. You may produce a candidate, but must not label it verified safe for her particular save until that gate is satisfied. Do not erase this caveat at handoff.

### 20.2 Migration fixture matrix

Include at least:
1. Fresh empty profile / New Game canceled at character creation.
2. Early Chapter One before any pet.
3. Mid Chapter One with buildings, full inventory and a waiting companion.
4. Just before the Matron with lower-tier gear.
5. Weaver defeated, Heartseed not yet returned.
6. Interrupted restoration with legitimately partial completion evidence.
7. Chapter One complete at `free_play`, optional lamp/bond goals NOT completed.
8. Chapter One complete with optional goals already satisfied.
9. A dense two-storey home with several filled chests, crops and dropped overflow.
10. A save using a custom `--save-dir` rather than the default location.
11. Current-schema save loaded twice; migration/rewards/perks not duplicated.
12. Malformed main save with a valid backup, plus an unsupported FUTURE-version main save that must not be silently replaced by an older backup.

Also save/quit in new regions, inside trials, at a manor/refuge checkpoint and just after final victory before the ending. Verify compatible retry/resume behavior, companion presence and reachable spawns.

### 20.3 System tests that must exist

**Customization:** new-game cancel safety; old appearance default; unlocked pattern ownership; equip/reset/presets; shared-material isolation; outfit change independent of armor and collision; visible skirt/hair behavior on stairs, sprint, dodge and camera close-up.

**Inventory/crafting/building:** every recipe reachable; no circular material gates; transactions across several chests; full results/overflow; queue completes exactly once; cancel/refund rules; capacity extension without truncation; stairs with reachable upper floor; inherited old placement remains intact; recolor leaves UID/chest data unchanged; no resource respawn through buildings.

**Equipment:** all slot combinations and swaps; no duplicated items; old weapon use still valid; stat calculation recomputes once; reduction cap and order; shield/health accounting; pet changes near low health; food refresh/stacking limits; no exponential perks after reload.

**Companions:** all three actually damage a valid enemy; Mochi heals; Pebble reduces damage/shields; Lumi changes measured movement; cooldowns and manual/autocast share one state; no-pet gameplay works; line of sight; friendly targeting excluded; no aggro stealing/softlock; courage transition; safe-zone/home behavior; obstacle recovery and new-area travel.

**Combat:** one hit per swing/projectile; invulnerability and resist rules; web/root expiration and escape; enemy attack telegraphs; monster limits; minion budgets; ordinary respawn state versus permanent story clear; boss phase resets, braziers usable, exits and rewards; armor tiers feel different on fixed old enemies.

**Quests/world:** legacy indices unchanged or correctly mapped; old free-play optional tasks do not block Chapter Two; accepting later works; quarry/orchard/manor in all meaningful orders; three lines in different orders; no replay of pet rescue/Heartseed restoration; original lift still works; old and new areas saved together; all required return paths available.

**Audio:** every referenced cue exists/imports/exports; playlist anti-repeat; no per-frame restarts; boundary hysteresis; boss/ending priority; combat exit; silence suppression; bus values, crossfade clipping and missing-audio fallback; music randomness independent from game RNG.

**Comfort:** every spider entity, spawn, skin, icon, shadow, effect, text and sound alternative; current preference retained during migration; setting toggle while an enemy is alive; reduce flash/shake; visual puzzle/attack cues with audio muted; alternate puzzles with timing assist. Any stronger horror default remains opt-in rather than overriding her saved settings.

### 20.4 Mandatory graphical and interactive runs

Use the available real desktop/game-control tools. An input bot using read-only telemetry can verify many mechanics, but label its information advantage; it cannot establish what a first-time human notices or whether music is pleasant.

**Run A — Her continuation:** load an isolated COPY of the personal completed save, inspect original home/chests/crops/pets, change hair/outfit, equip one upgrade, enter the new region, return home, save through the UI, quit the process, relaunch via Continue and verify all state. Then complete Chapter Two with normal inputs and revisit both old and new regions. No grant/teleport/flag cheats in the claimed end-to-end route.

**Run B — Fresh integrated game:** new isolated profile, character creation, enriched Chapter One, improved Matron, original restoration, accepted Chapter Two, finale, free play. At least one optional Chapter One activity must be exercised through real inputs. Record real route duration; do not turn a route-aware bot's minutes into a human-hour claim.

**Run C — Combat/companion regression:** short controlled encounters for Mochi, Pebble, Lumi and no pet with legacy and new gear. Verify actual health, shield, movement and enemy HP effects, not just UI icons. Targeted setup tools may be used here but mark the run as a diagnostic fixture rather than a natural playthrough.

**Run D — Comfort and music:** arachnophobia enabled before loading; inspect original boss/trial, skitters and rematch plus new Halloween enemies, muted-audio puzzles, caption readability, region transitions and playlist rotation. Listen where capability permits; disclose unavailable subjective checks.

**Run E — Persistence/failure:** save–quit–relaunch in every area type; controlled interruption during writes in a disposable test profile; restore backup; retry bosses/trials; finish after reload; verify no reward duplication. This explicitly closes the incomplete packaged persistence test documented in the old QA report.

Protect the user's desktop: clearly indicate when an interactive run needs mouse/keyboard control. Do not secretly fight their inputs or start lengthy desktop use while they are actively working. Ask only when genuinely required by permissions/access. Stop or release control promptly when interrupted.

### 20.5 Presentation and performance

Inspect actual rendered frames: home preservation, diverse hairstyles/outfits, new building pieces, pet ability feedback, all major landmarks, monster tells, original Matron phases, vampire manor, Choir, ending, menus and settings at 1080p and a smaller supported resolution.

Profile a bounded representative route on the available hardware with the packaged build and no editor running. Report hardware, resolution, preset, average and meaningful low-percentile frame rate/frame times, loading stalls and memory. A 4090 result does not establish low-end requirements. Add reasonable quality settings; no new requirement to buy a GPU.

Check music streaming and several region round trips for leaks, ever-growing node/audio counts or active off-screen AI. Terminate only QA processes you started. Screenshots of nice scenery and headless passing tests do not prove good camera/input responsiveness; test those through play.

Release blockers: any lost home/items, incompatible personal save, duplicated/corrupted rewards, original chapter regression, progression lock, required missing asset, persistent broken companion combat, unreadable required telegraph, game crash, or packaged build failure. Fix before calling the expansion ready.

---

## 21. Milestones: implement in this order, maintain a playable build

**M0 — Verify and protect.** Inspect the actual repo and toolchain, preserve later owner/bug-audit changes, identify the live save correctly, create immutable backups, run baseline tests and original packaged continuation. Record limitations instead of inventing access.

**M1 — Continuity foundation.** Add migration, optional quest layer, chapter availability, stable new-area skeleton/return travel, integrity reports and repeat-load tests. No extensive content until the old house survives. Prove a tiny round trip into a new area and home with the same save.

**M2 — Expression and real companions.** Character creation, old-save styling access, outfits/armor separation, each pet's attack/passive/skill, cooldown UI, navigation fixes and Mochi courage. Demonstrate actual combat effects and persistent appearance in a small existing encounter.

**M3 — Sustainable home/progression.** Equipment, workstations, recipe dependencies, crop/material renewal, storage expansion, two-storey building, furnishing choices and conservative mastery credit. Prove a small working end-to-end resource→equipment→combat and resource→clothing→house loop.

**M4 — Chapter One upgrade.** Optional content, four new enemy types in sensible pockets, improved original Matron and separate completed-save trial. Preserve silence in the Nursery and legacy quest state. Integrate original-region music variety here, not at the end.

**M5 — Hallowmere surface.** Commons, orchard, quarry, manor/Candleyard, branch quests, Halloween farming/decor, Count Velour and reliable return routes. Introduce new regional music alongside each area. Side content should reinforce resources/building, not just text notes.

**M6 — The deeper chapter.** Hushed Works, parallel ward lines, authored horror, Weaver rematch, Choir, miners' resolution, celebration and free play. Prove complete route and reward-once handling before adding optional breadth.

**M7 — Variety and replay.** Finish all required soundtrack cues and selection behavior, costumes, decor and optional activities. Add repeatable templates/trials. Pipkin is the only explicitly optional stretch companion after core gates work.

**M8 — Release.** Migration matrix, personal-save continuation, fresh full playthrough, package persistence, comfort, audio/visual checks and performance. Fix, rebuild, rerun relevant regressions, package, and deliver evidence and rollback instructions.

At every milestone compile, run relevant tests, launch, inspect actual frames and interact. Make local version-control checkpoints. Keep `PROJECT_STATE.md` accurate and write `docs/CHAPTER_TWO_SPEC.md` / `docs/SAVE_MIGRATION.md` from the implemented design. Do not pretend every checkbox passed at the start.

Scope discipline: do not replace actual systems with menu mockups, empty areas, named-but-identical monsters, file-only soundtrack tracks, or a “Chapter Two coming soon” card. If session limits interrupt work, preserve a truthful continuation checkpoint including build status, failing tests and next action. A partial build must be labeled partial, not passed off as the requested finished expansion. Never promise work continues after the session stops.

---

## 22. Handoff and acceptance

Deliver ONE updated offline Windows game, the editable existing source project, reproducible build/test/audio-generation commands, complete distributable files, necessary licensed notices and a ZIP. No engine install, account, API key, online model, server or developer command should be required for Krystal to play the packaged game.

Keep the application's save identity `Hollowhaven` and discover the existing profile automatically using verified code. A “Chapter Two” title must not create an empty new user directory. Keep the prior build archived and clearly label migration/rollback compatibility: an older executable may reject the new schema, so rollback restores BOTH the prior build and the immutable prior save, never overwrites a new save casually.

Add a concise player update note explaining:
- Press **Continue**, not New Game, to keep the existing world.
- Where to style Krystal immediately and later at her mirror.
- What companion support/skill controls were added.
- Where the new Ward Stone invitation appears after Chapter One.
- How to return to her original house.
- New gear, building, Halloween and music settings.
- Remaining limitations, only if real and documented.

Provide `QA_REPORT.md`, `KNOWN_ISSUES.md`, a save-integrity report, an executed-test matrix, screenshots/recordings from the real build, a music manifest and actual build paths/checksums. Keep personal save copies out of publicly shareable source/build ZIPs. Include synthetic or clearly labeled bot fixtures only in a separate private QA bundle when appropriate.

Keep the last handoff short: exact executable to launch, full build/source locations, features actually implemented, tests actually run, blockers/unverified points and safe rollback path. Do not claim zero bugs, subjective fear/fun, human listening, personal-save validation or human playtime without evidence.

### Final definition of done

Krystal presses Continue and finds the SAME house she worked on. Her items, crops, pets and completed story remain. She can pick a cute hairstyle and skirt without losing armor protection. Mochi heals and attacks, Pebble protects and attacks, Lumi helps her move and attacks. She can build upstairs, gather new materials, craft stronger equipment, grow pumpkins, collect clothes and decorate her existing home.

Chapter Two begins by choice. It takes her through warm Halloween scenery, distinct resource/monster challenges, a theatrical vampire manor, unsettling underground mysteries, a stronger escaped spider, and a different final threat. She returns to her own home with useful rewards. Familiar good music remains, but homes, woods, gardens, manor, fights, dungeons and celebrations now have real audible variety. After the story, both regions, creative building, renewable crafting and optional adventures still work.

This is a continuation, not a replacement. Protect that above all.

### Start now

Read the actual project instructions and implementation, verify the current environment, protect the existing save and source, establish the baseline, and begin M0/M1. Work through the milestones to a tested packaged release. Make ordinary decisions independently; ask only for genuinely necessary user-only permissions or missing project/save access. Do not return only a plan.

---

## Reference basis for the agent

Existing-game facts in this specification come from the owner's supplied `Hollowhaven_Chapter1_Bible.md`, `Hollowhaven_Technical_Handoff.md`, `AGENTS.md`, `GAME_SPEC.md`, `PROJECT_STATE.md`, `KNOWN_ISSUES.md`, `QA_REPORT.md`, `README.md`, and `THIRD_PARTY_NOTICES.md`. The technical handoff reports source baseline `9512a0d` / game `0.9.0`; verify current source rather than treating that baseline as current truth.

Every new chapter name, region, recipe, stat target, music cue, feature and acceptance gate above is a proposed design/implementation requirement, not a claim of completed development. The design author had documentation, not the runnable source project, actual player save or audio files. No game build, migration, playthrough or listening test was performed by writing this prompt.
