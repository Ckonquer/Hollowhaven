# Third-party notices and asset provenance

Hollowhaven ("For Krystal") is an original game. This file lists everything in it that was not
written specifically for it, and where each generated asset comes from.

## Engine
| Component | Version | Licence | Source | Notes |
|---|---|---|---|---|
| Godot Engine | 4.7.2-stable (official build) | MIT (Expat) | https://godotengine.org · github.com/godotengine/godot | Engine and export template. The engine bundles third-party libraries (FreeType, HarfBuzz, Jolt Physics, mbedTLS, etc.) under their own permissive licences; their full texts ship with the game in `Licenses/Godot_Engine_Licenses.txt` (generated from `Engine.get_copyright_info()` / `get_license_info()`). |

## Fonts
| Font | Author | Licence | Source | Used for |
|---|---|---|---|---|
| Fredoka (variable) | The Fredoka Project Authors (Milena Brandão, Hafontia) | SIL Open Font License 1.1 | github.com/google/fonts/tree/main/ofl/fredoka | Headings, logo |
| Nunito (variable) | The Nunito Project Authors (Vernon Adams, Cyreal, Jacques Le Bailly) | SIL Open Font License 1.1 | github.com/google/fonts/tree/main/ofl/nunito | Body text |

Licence texts: `game/assets/fonts/OFL-Fredoka.txt`, `game/assets/fonts/OFL-Nunito.txt` (also copied into
the release's `Licenses/` folder). The fonts are embedded unmodified; OFL permits bundling with software.

## Original generated assets (no third-party material)
| Asset type | How it is made | Source files |
|---|---|---|
| 3D models (Krystal, companions, enemies, props, terrain, dungeon) | Procedural geometry built at runtime from primitives and noise-displaced meshes | `game/src/**` (e.g. `src/art/mesh_kit.gd`, `src/player/krystal_avatar.gd`) |
| Materials / shaders | Hand-written Godot shaders (toon ramp, outlines, water, grass, fog) | `game/shaders/*.gdshader`, `game/src/art/mat.gd` |
| Item icons | Drawn procedurally at runtime | `game/src/ui/icon_factory.gd` |
| Sound effects, ambience, music | Synthesised from scratch with Python (numpy/scipy); deterministic seeds | `tools/audio/` → `game/assets/audio/` |
| Application icon | Drawn with Pillow | `tools/art/make_icon.py`, `game/icon.svg` |

No image, sound, model or music files were downloaded from the internet. No commercial or unclear-licence
assets are used. The player character is an original stylised explorer and does not depict a real person.

## Development-only tools (not shipped)
Python 3.12 + numpy (BSD-3), scipy (BSD-3), Pillow (MIT-CMU / HPND) - used only to generate audio and the icon.
