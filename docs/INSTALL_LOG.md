# Installation / change log (machine-level)

All tools are project-local under `Hollowhaven/.tools/` (git-ignored). Nothing was installed system-wide,
no system settings, drivers or security settings were changed, no accounts were created.

| When (local) | What | Source | Verification |
|---|---|---|---|
| 2026-09-27 15:28 | Godot 4.7.2-stable Windows editor (`Godot_v4.7.2-stable_win64.exe.zip`, 86 MB) | github.com/godotengine/godot/releases/tag/4.7.2-stable | SHA-512 matched official SHA512-SUMS.txt |
| 2026-09-27 15:30 | Godot 4.7.2 export templates (`.tpz`, 1.28 GB; only the Windows x86_64 templates were extracted) | same release | SHA-512 matched |
| 2026-09-27 15:30 | Self-contained mode marker `.tools/godot/_sc_` (editor data stays inside the project folder) | — | — |
| 2026-09-27 15:32 | Fonts Fredoka & Nunito (SIL OFL 1.1) → `game/assets/fonts/` | github.com/google/fonts (ofl/) | licence files copied alongside |
| 2026-09-27 15:33 | Python venv `.tools/pyenv` (Python 3.12.10 already present) + numpy 2.5.3, scipy 1.18.1, pillow 12.3.0 | PyPI via pip | import check |
| 2026-09-27 15:33 | Local git repository initialised in `Hollowhaven/` (local user.name "Hollowhaven Dev") | — | — |

Unity was not installed: Unity 6 Personal requires signing in to Unity Hub to activate a licence
("The manual activation method doesn't work with floating license subscriptions or Unity Personal. To
activate a license for Unity Personal, log in to the Unity Hub." — Unity 6000.4 manual). The owner was
unavailable to sign in, so the project uses Godot 4.7.2 (MIT licence, no account).
