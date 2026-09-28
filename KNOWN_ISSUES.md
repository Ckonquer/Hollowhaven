# Known issues — Hollowhaven (Chapter One)

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
