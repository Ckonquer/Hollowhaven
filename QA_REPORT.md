# QA report — Hollowhaven

Every entry says what KIND of check it was:
**[code]** source review · **[auto]** automated logic tests · **[visual]** launched and inspected
rendered frames · **[interactive]** played through real OS-level keyboard/mouse input (SendInput) ·
**[subjective]** human-judgement items (e.g. listening) — marked *not verifiable* where applicable.

Environment (all tests unless stated): Windows 11 Pro 10.0.26200 x64 · AMD Ryzen 9 9950X (16C/32T) ·
125.6 GB RAM · NVIDIA GeForce RTX 4090 (driver 32.0.15.9571) + AMD Radeon iGPU · two 1920×1080
displays · Godot 4.7.2-stable official (Forward+, Vulkan). This is the owner's actual PC, not a sandbox.

## 1. Toolchain gate (Milestone A) — 2026-09-27 15:31
| # | Check | Kind | Steps | Expected | Observed | Result | Evidence |
|---|---|---|---|---|---|---|---|
| A1 | Create/open project | auto | `godot --headless --path game --import` | imports without errors | imported | PASS | console |
| A2 | Compile minimal playable scene | auto | gate scene (`tests/gate/gate.gd`) | parses, runs | ran | PASS | gate_log.txt |
| A3 | Standalone build | auto | `--export-release "Windows Desktop"` | Hollowhaven.exe produced | 109 MB exe (PCK embedded) | PASS | builds/gate |
| A4 | Launch in a graphical environment | visual | ran exported exe on the desktop | window opens, Vulkan Forward+ on RTX 4090 | `READY renderer=forward_plus adapter=NVIDIA GeForce RTX 4090` | PASS | qa/evidence/gate/gate_log.txt |
| A5 | Capture a real rendered frame | visual | OS screen capture of the client area (GDI CopyFromScreen) + in-engine viewport capture | real frame | both captured; first OS capture caught the boot splash, second the scene | PASS | qa/evidence/gate/os_before.png, os_after_D.png, ingame_t2.png |
| A6 | Real input changes game state | interactive | `tools/winctl.ps1 -Action key -Key D -Ms 1500` (SendInput scancode) | cube moves +X ≈ 6 m | log `POS 0.67 → 6.07` while `keyD=true`; screenshot shows the cube moved right | PASS | gate_log.txt, os_after_D.png |

(Sections for automated tests, visual checks, interactive playthroughs, persistence, regression and
performance are filled in as they are executed.)
