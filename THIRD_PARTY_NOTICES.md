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
| Sound effects, ambience, music | Synthesised from scratch with Python (numpy/scipy); deterministic seeds. The Chapter Two music (22 compositions + 4 layers, `game/assets/audio/music/m*.ogg`) is written as OGG Vorbis with `soundfile` / libsndfile (build time only, see below) | `tools/audio/` and `tools/audio/music2/` → `game/assets/audio/`; per-cue provenance: `docs/ch2/MUSIC_MANIFEST.md` |
| Application icon | Drawn with Pillow | `tools/art/make_icon.py`, `game/icon.svg` |

No image, sound, model or music files were downloaded from the internet. No commercial or unclear-licence
assets are used. The player character is an original stylised explorer and does not depict a real person.

## Development-only tools (not shipped)
Python 3.12 + numpy (BSD-3), scipy (BSD-3), Pillow (MIT-CMU / HPND) - used only to generate audio and the icon.

Build-time audio encoding (Chapter Two music), installed in the project venv `.tools/pyenv/`; nothing from these packages is
copied into the game or the release ZIP:

| Package | Version | Licence | Use |
|---|---|---|---|
| python-soundfile (`soundfile`) | 0.14.0 | BSD-3-Clause | Python binding used by `tools/audio/music2/group_*.py` to write the OGG Vorbis files |
| libsndfile | 1.2.2 (bundled in the soundfile wheel as `_soundfile_data/libsndfile_x64.dll`; licence text `_soundfile_data/COPYING`) | GNU LGPL 2.1 | the OGG Vorbis encoder behind `soundfile` (its Ogg / Vorbis support comes from Xiph.Org's libogg / libvorbis) |
| cffi | 2.1.1 | MIT-0 | dependency of soundfile |
| pycparser | 3.0 | BSD-3-Clause | dependency of cffi |

The music reviewers also re-measured loudness with ffmpeg's `ebur128` filter (ffmpeg on the development PC's PATH, not part of the
project toolchain); it wrote no shipped file.

The release ZIP `dist/Hollowhaven-2.0.0-Windows.zip` carries the copy of this file made before this section was added
(`Licenses/THIRD_PARTY_NOTICES.txt`); the next `tools/build_release.ps1` run ships the updated text.
