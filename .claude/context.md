# vgate — context for implementation agents

Auto-prepended preamble for godot-engineer briefs. Keep under ~40 lines.

## Project
- **Display name**: "VGate" (working title — переименовать после narrative-designer pass)
- **Engine**: Godot 4.6, GDScript only, Forward+ renderer (3D)
- **Genre**: 3D FPS arena, single-arena survival с hook'ом Velocity Gate
- **Repo**: `/home/azukki/vgate/` — git remote TBD (юзер создаёт на GitHub после первого M0), branch `main`, solo
- **Source of truth**: `PLAN.md` + `docs/concept/M0_concept.md` + `docs/feel/feel_spec.md` + `docs/research/asset_pipeline.md`

## Foundation — Kenney Starter Kit FPS
Базовый FPS-controller, weapon system и enemy AI берём из готового CC0/MIT проекта:
- Repo: https://github.com/KenneyNL/Starter-Kit-FPS
- Импорт делает godot-engineer в M0: scripts + assets копируются в `vgate/`, адаптируются под Velocity Gate state
- Это экономит 1-3 дня бойлерплейта — НЕ переписывай controller с нуля без необходимости

## Autoloads (планируются по майлстоунам)
- `Events` — signal bus (M1)
- `VelocityGate` — main state (current_speed, velocity_cap, drain_timer) (M1)
- `HitStop` — freeze enemies + camera (M2)
- `Sfx` — audio pool с динамическим low-pass filter (M2)
- `MusicDirector` — adaptive music 2 layers (M5)

## Conventions
- Каждый script имеет `class_name`
- 3D placeholder visuals: CSG-shapes / стандартные mesh primitives до импорта Kenney/Quaternius. Не ждать ассетов чтобы тестировать механику.
- Враги — CharacterBody3D + NavigationAgent3D (NavMesh для арены baked один раз)
- Velocity Gate state живёт в autoload `VelocityGate`, юнит-классы (Player, Enemy) только читают/мутируют через сигналы Events
- Палитра/тон выбран — sci-fi (Kenney Starter Kit base + Quaternius Sci-Fi MegaKit). Финальный визуал — после M2 feel pass.

## Git workflow
- Commit + push to `main` by default (юзер тестирует на Windows после push)
- Single-task commits batched into logical units
- Security warning on push allowed via `.claude/settings.local.json`
- Remote setup — юзер создаёт `github.com/zulesss/vgate`, потом локально `git remote add origin git@github.com:zulesss/vgate.git && git push -u origin main`

## Validation
- Before push: `cd /home/azukki/vgate && timeout 20 /home/azukki/tools/godot/godot --headless --import 2>&1 | tail -5` — must be clean
- Smoke: `timeout 15 /home/azukki/tools/godot/godot --headless --quit-after 5 2>&1 | tail -10`
- Headless 3D на сервере — может падать на `libfontconfig.so.1` или GPU-driver (см. log сессий veldrath). Если smoke падает на системной либе, не повторять — флагнуть parent'у.
