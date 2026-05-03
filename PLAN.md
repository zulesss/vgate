# vgate — План полного слайса

Документ фиксирует скоуп, майлстоуны и распределение работы. Изменения обсуждаются до кода.

Источники:
- `docs/concept/M0_concept.md` — core fantasy + hook (Velocity Gate) от game-designer + market-analyst
- `docs/feel/feel_spec.md` — must-стек feel-engineer'а на 10 дней + nice-to-have backlog
- `docs/research/asset_pipeline.md` — ассет-стек CC0 + Kenney Starter Kit FPS как foundation

---

## 1. Концепт (lock)

**Core fantasy** *(game-designer, locked)*:
Ты — единственный подвижный элемент в мире, который хочет тебя остановить. Скорость — не преимущество, она обязательна. Стоять = смерть. Эмоция — **управляемая паника**. Не zen flow ULTRAKILL и не пазл Neon White — ты не контролируешь ситуацию, ты только чуть опережаешь её.

**Hook — Velocity Gate**: HP в классике нет. Есть `velocity_cap` (0–100, старт 80). Хиты от врагов снижают cap. Когда `current_speed < threshold` дольше 2.5 сек — drain → смерть. **Убийство = velocity burst** (кап восстанавливается частично). Враги одновременно угроза и топливо.

**Setting**: sci-fi / cyberpunk-минимализм (выбран по покрытию CC0-ассетов, см. `docs/research/asset_pipeline.md`). Финальный тон — после feel pass M2.

**Player verbs (4)**: Move / Shoot / Dash / Kill (Kill — conscious verb-транзакция, не side-effect).

---

## 2. Скоуп — IN / OUT

Скоуп расширен 2026-04-28 (после M4 экзит'а — каденс позволяет). M5+ покрывает полный полиш + 7 дополнительных майлстоунов.

| ✅ IN (полный слайс + расширения) | ❌ OUT (вырезано окончательно) |
|---|---|
| 3 арены single-tier flat (B Плац 50×50 / A Камера 26×26 / C Cathedral 44×44, M9) | 4+ арен; multi-tier (Шахта abandoned 2026-05-03) |
| 1 оружие: blaster (M9 cut 2026-05-01) | 2+ оружий, кастомизация |
| 3 типа врагов: melee, shooter + 1 доп (M8) | 4+ типов |
| Velocity Gate полностью реализован (cap, drain, kill burst, dash burst) | **HP в классике, regen, armor** — конфликт с хуком |
| Feel must (FOV double-axis, heartbeat, low-pass, bob fade, kill burst, dash feel) + nice-to-have (дыхание, motion blur, kill chain, dash relief — M7) | — |
| 1 mode: continuous spawn ramp (3 arenas, M9) | Onslaught wave mode (M11 cut 2026-05-03 — 3 уровней достаточно) |
| Adaptive music 2 layers + полный SFX bus | BPM-sync music, custom score (затратно для 1-2 дней) |
| Score / timer / death / restart loop (2.8 сек cycle) | Online leaderboard, replay system |
| Main menu, Pause, Settings menu (M6: mouse sens, volume, motion blur toggle) | Run-state save (между сессиями только high-score) |
| Quaternius модели для player + 2 типов врагов (M5, был deferred из M3) | Анимированные риги с lip sync (static Quaternius rigs OK) |
| Controller support через Godot InputMap (M6) | — |
| Light нарратив pass (M12: имя, tagline, environmental tone) | — |
| Settings persist в user:// (M6) | Cloud sync |

---

## 3. Exit criteria полного слайса

Слайс готов когда:
1. Один run играется от старта до смерти 10-15 минут без ошибок консоли
2. Velocity Gate **читается**: игрок в danger-зоне понимает что замедляется ДО смерти (FOV + audio + bob)
3. Kill ощущается как выдох — главный feel-чек (см. `docs/feel/feel_spec.md` §5)
4. Spawn ramp создаёт ощущение нарастающего давления
5. Death → restart < 3 сек, цикл играть-снова работает без friction
6. Performance: 60 FPS на средней машине (стабильно при 30+ врагах на арене)

---

## 4. Майлстоуны

Каждый майлстоун заканчивается плейтестом + code-review pass на изменённых файлах (`feedback_code_review_periodic.md`). Следующий не стартует без thumbs-up. После принятия — `git tag v0.MX`.

### M0 — Foundation: Kenney Starter Kit FPS + 3D-арена placeholder
**Цель**: импортировать Kenney Starter Kit FPS, адаптировать controller под Godot 4.6 если нужно, поднять placeholder-арену 40×40 с CSG-стенами.
- [ ] Скачать https://github.com/KenneyNL/Starter-Kit-FPS, скопировать scripts + assets в проект
- [ ] PlayerController работает: WASD + mouse-look + jump (стандартный)
- [ ] Placeholder-арена: пол 40×40 (CSG-Box), 4 стены (CSG-Box), spawn-point игрока
- [ ] Один dummy-враг (CharacterBody3D + capsule visual), стоит на месте
- [ ] Headless smoke + import работают чисто

**Owners**: godot-engineer (импорт + адаптация Starter Kit)
**Exit**: можно бегать по арене, видеть dummy. Плейтест: управление как у обычного FPS, ничего не сломано.

### M1 — Velocity Gate core
**Цель**: hook реализован минимально читаемым способом (без feel-полировки, голые числа на UI debug).
- [ ] Autoload `VelocityGate`: state (current_speed, velocity_cap, drain_timer, threshold)
- [ ] Autoload `Events`: signals (player_hit, enemy_killed, dash_started, drain_started, player_died)
- [ ] Damage on hit от dummy: cap −15, instant feedback на debug-UI
- [ ] Drain logic: speed < threshold > 2.5 сек → tick-урон до 0
- [ ] Kill restore: убил dummy (выстрелом из Starter Kit gun) → cap +N
- [ ] Dash: 2.5 сек cooldown, velocity burst в направлении взгляда, instant
- [ ] Restart loop: смерть → 2 сек → arena reset → spawn

**Owners**: systems-designer (числа cap math: penalty, kill restore, drain rate, threshold) → godot-engineer
**Exit**: hook играется. Можно умереть от drain, можно убить и не умереть. Числа сырые но петля замкнута.

### M2 — Feel pass (главный полировочный майлстоун)
**Цель**: Velocity Gate **ощущается**, не только работает в коде. Реализуем must-стек из `docs/feel/feel_spec.md`. Главный feel-чек — kill читается как выдох (см. §5 feel_spec).
- [ ] FOV double-axis mapping (speed_ratio + cap_ratio, min из обоих, ease-in кривые)
- [ ] Heartbeat audio: 60→110 BPM по cap, lub-DUB
- [ ] Low-pass filter на ambient bus (8kHz→1.2kHz при низком speed_ratio)
- [ ] Camera bob amplitude → 0 при low ratio
- [ ] Kill burst: FOV +15° punch (ease-out 180 мс) + hit-stop 65 мс + time-dilation 0.08 сек snap + audio crack frame 0
- [ ] Dash feel: FOV +12° stretch + camera push 0.15 units + whoosh +200 cents (или +300 если из удушения)
- [ ] Death → restart 2.8 сек: 1.8 сек смерть + 0.6 сек чёрный + score + 0.4 сек fade-in

**Owners**: feel-engineer (специфика тайминга/кривых) → godot-engineer (имп) → user playtest на главный feel-чек
**Exit**: Главный вопрос: войти в danger-зону, убить врага. Если выдохнул — exit OK. Если нет — итерация feel-стека (+ hit-stop, потом + time-dilation).

### M3 — Enemy variety: стрелок + ближнебой
**Цель**: 2 типа врагов с различимым поведением + базовый AI.
- [ ] Стрелок: range-attack, держит дистанцию, penalty к cap −10 на hit
- [ ] Ближнебой: бежит на игрока, melee на ~1.5 units, penalty к cap −20 на hit
- [ ] AI: NavigationAgent3D для пути, простые states (Idle / Chase / Attack)
- [ ] Импорт моделей из Quaternius Sci-Fi Essentials Kit (анимированные роботы)
- [ ] Telegraph атак: визуальный + звуковой (стрелок поднимает оружие, ближний издаёт звук перед ударом)

**Owners**: game-designer (различимость поведения) → systems-designer (числа damage/HP/speed) → godot-engineer
**Exit**: 2 типа в арене ведут себя различимо. Плейтест: "я отличаю поведение типов через 30 сек".

### M4 — Spawn ramp + score/timer + run loop
**Цель**: continuous spawn ramp работает, run длится 10-15 минут, прогрессия через сложность.
- [ ] Spawn-controller: формула `interval = 4 / (1 + time*0.015)` (Devil Daggers форма)
- [ ] Spawn-points distribution на арене (минимум 4 точки по периметру)
- [ ] Score: убийства × множитель за время выживания
- [ ] Timer на HUD: текущее время run'а
- [ ] Local high score persisted в `user://vgate_progress.cfg`
- [ ] Death screen: score + best + restart

**Owners**: level-designer (spawn-point layout + safe-zones отсутствие) → systems-designer (calibrate ramp formula) → godot-engineer
**Exit**: 10-15 минут run проигрывается с нарастающим давлением. Плейтест: ощущение "вот-вот сломаюсь".

### M5 — Polish + audio + main menu + ассеты
**Цель**: shippable feel. Bridge от placeholder-look к legit-look.
- [ ] Adaptive music: 2 layers (base + intensity), intensity на 120 сек, volume tween
- [ ] SFX bus: gun-fire, hit-impact, kill-confirm, dash-whoosh, heartbeat, drain-warning, ambient
- [ ] HUD финальный стиль: sci-fi minimal вместо дефолтных Godot Label'ов
- [ ] Main menu: VGate title + [НАЧАТЬ] / [ВЫХОД] (Mode select добавится в M11)
- [ ] Pause на Esc (resume / restart / main menu)
- [ ] Background variety: skybox через Polyhaven HDRI
- [ ] Quaternius модели: player + Melee + Shooter (deferred из M3, заменить капсулы)

**Owners**: research (asset scouting: audio packs + Quaternius варианты) → feel-engineer (audio-mix спека) → godot-engineer
**Exit**: игра выглядит и звучит как продакт, не как prototype. Asset preview gate соблюдён.

### M6 — Settings + Controller + Save settings
**Цель**: QoL, отдача в input/audio контроль.
- [ ] Settings menu: mouse sensitivity slider, volume (master/music/SFX), motion blur toggle, controller bindings
- [ ] Controller support через Godot InputMap (Xbox/PS layout), parity с keyboard+mouse
- [ ] Settings persist в `user://vgate_settings.cfg` (отдельно от high-score persistence)
- [ ] Pause menu integration: Settings доступны из Pause

**Owners**: godot-engineer
**Exit**: settings сохраняются между сессиями, controller играется параллельно клавиатуре.

### M7 — Nice-to-have feel layer
**Цель**: добивка чувств после M5 audio. См. feel-spec backlog.
- [ ] Дыхание: heavy breath audio под heartbeat при low cap
- [ ] Motion blur: radial blur при высокой скорости (toggle через Settings из M6)
- [ ] Kill chain: 3+ kills в окне 3 сек → visual flair / camera flair
- [ ] Dash relief: post-dash exhale visual (particle trail или briefcase-glow)

**Owners**: feel-engineer → godot-engineer
**Exit**: каждый эффект включается/выключается через Settings (M6). На плейтесте «дрожит лучше».

### M8 — 3-й тип врага
**Цель**: вариативность AI без подрыва Velocity Gate.
- [ ] game-designer определяет identity (snipe-camper, juggernaut, swarmling — выбрать одного)
- [ ] systems-designer задаёт HP/speed/damage/range/spawn-cap
- [ ] godot-engineer импл AI поверх EnemyBase
- [ ] Quaternius визуал (отдельный robot-archetype от melee/shooter)
- [ ] Spawn integration в M4 ramp: type curve расширяется до 3 типов
- [ ] Identity readable за 5 сек на плейтесте

**Owners**: game-designer → systems-designer → godot-engineer
**Exit**: 3 типа на арене, identity мгновенно различима, hook не сломан.

### M9 — Time-based Conquest + 3 arenas + boss redesign ✅ DONE (2026-05-01 → 2026-05-03)

**История**: M9 originally "Weapon variety", cut 2026-05-01 (`43fa3d8`). Re-scoped 2026-05-01 в comprehensive finale milestone:
- Time-based conquest core (120с timer + drain + objective)
- 3 distinct arenas с 3 distinct objectives (replace M10 vertical arena)
- Multi-pivot Arena C (Шахта multi-tier abandoned → Дорога journey abandoned → Cathedral altar capture **locked**)
- Boss redesign (3-phase + dash-time charge + AOE)
- ~~Wall-run MVP~~ **CUT** — пользователь решил skip 2026-05-03 (focus на close vs further scope)

#### Готово
- [x] Time-based core: 120с timer, win/loss conditions, score formula `kills × avg_cap × time_norm`, anti-camping spike, threshold step-up
- [x] Arena B "Плац" (open 50×50, 4 low walls cross) — sphere capture objective (15/25 + survive 120s), per-arena PlayerStart
- [x] Arena A "Камера" (claustrophobic hub-and-spoke 26×26, closed dead-end alcoves) — marked enemy hunt (10 marks + survive)
- [x] Arena C "Собор" (Cathedral 44×44 closed ceiling 12u, 4 altar clusters + center boss spawn) — altar capture (4 altars + boss kill, drain-driven, no timer). Spec: `docs/levels/M9_cathedral.md`
- [x] Multi-arena routing via group (objective_sphere / objective_marked_hunt / objective_cathedral)
- [x] Per-arena objective directors: SphereDirector / MarkDirector / AltarDirector
- [x] Boss redesign 3-phase + charge (P1+ access, per-phase telegraph 0.6/0.5/0.4) + AOE swing + forced anti-kite charge (3s timer) + ChargeBeam visual aim indicator + kill polish + HP bar HUD. Spec: `docs/systems/M9_boss_redesign.md`
- [x] Engine-level NavMesh fixes (CSG visibility — detach-from-tree pattern, MESH_INSTANCES parsed_geometry_type)
- [x] Restart re-instantiate arena (pre-placed enemies respawn)
- [x] Cathedral 120s win race fix (subscribe-after-emit) + timer UI hidden
- [x] "CAPTURED" 2s toast on altar capture
- [x] Drain tolerance bump 0.5→0.2 (harsh feel — no jitter forgiveness)

**Tagged**: M9-final commit `ead8b1f` (2026-05-03)
**Owners**: game-designer + level-designer (specs) → godot-engineer (impl) → playtest-analyst (balance cycle, 6+ rounds)
**Exit (met)**: 3 arenas с distinct objectives shipped, boss feels climactic с per-phase escalation, wall-run dropped per user scope decision.

### M10 — ❌ FOLDED INTO M9 (2026-05-03)
**Original**: Vertical/multi-tier additional arena.
**Outcome**: Multi-tier nav abandoned (Godot 4 engine bugs prohibitive cost для solo-dev). 3 arenas now part of M9 scope (Plats / Камера / Cathedral — all single-tier flat).

### M11 — ❌ CUT (2026-05-03)
**Original**: Onslaught wave mode (10 предзаданных волн как альтернатива continuous ramp).
**Outcome**: Cut по решению пользователя — 3 уровня (Плац/Камера/Cathedral) достаточно для slice'а. Onslaught добавил бы balancing overhead + WaveController + mode select UI без proportional payoff. Brainstorm от 2026-05-03 (game/level/systems-designer) сохранён в conversation, не дамплен в docs/ (не approved).

### M12 — Narrative pass ✅ DONE (2026-05-03 → 2026-05-04)

**Direction A "Испытание/Экзекуция" locked** — машинное правосудие проверяет приговор движением. 3 арены = 3 стадии исполнения приговора. Boss = «Исполнитель». Drain justification = «Модуль Кинетического Контроля».

#### Готово
- [x] Имя проекта: **VGate → КИНЕТИКА** (`project.godot config/name`)
- [x] Tagline: «Двигайся или умри. Это приговор.»
- [x] Capsule copy (Steam/itch ready) — в `docs/systems/M12_narrative.md`
- [x] Полная русская локализация: main menu / pause / settings / credits / death / win / run HUD / intro_text / boss labels — 60+ строк переведено
- [x] Intro splash terminal-style 2-3s перед ареной (МОДУЛЬ КИНЕТИЧЕСКОГО КОНТРОЛЯ — АКТИВЕН / ЗАПУСК ПРОЦЕДУРЫ ИСПЫТАНИЯ → fade в первую арену), skippable
- [x] Per-arena narrative intro framing (СТАДИЯ ПЕРВАЯ/ВТОРАЯ/ТРЕТЬЯ — public demo / solitary / ritual execution)
- [x] Drain death header «СКОРОСТЬ ИСЧЕРПАНА» (single fixed после iteration на RNG variants)
- [x] Death screen tutorial hint (capsule text как подсказка-tutorial для нового игрока)
- [x] Sequential level loading: Плац → Камера → Собор campaign + final "ВСЕ ПРИГОВОРЫ ИСПОЛНЕНЫ" complete screen
- [x] Pickup audio cue на sphere/altar capture
- [x] Drain/heartbeat audio stops on win (mirror death cleanup)
- [x] Double jump CD 1.25s (=DASH_COOLDOWN/2) + HUD bar mirror dash pattern

**Spec**: `docs/systems/M12_narrative.md` (LOCKED 2026-05-03)
**Owners**: narrative-designer (theme) → godot-engineer (impl, multi-round polish)
**Exit (met)**: имя финализировано, tagline locked, capsule shippable, environmental tone (terminal-style death/intro/per-arena framing) присутствует, sequential campaign + tutorial hint shipped.

#### Открытое (deferred)
- Ambient audio motifs per arena (Плац drum-march / Камера silence-with-hum / Собор choral drone) — flagged for M13 polish bandwidth
- Cyrillic font verification — Windows playtest gates rendering quality (default font может потребовать fallback asset)
- Dedicated pickup .ogg asset (currently reuse kill_confirm.ogg pitch-shifted) — flag for M13 audio polish если tonal confusion

### M13 — Final balance + shippable
**Цель**: финальная балансировка после всего контента + capsule art если идём в Next Fest.
- [ ] Полный playthrough — playtest-analyst на ≥2 наблюдений (правило `feedback_playtest_first.md`)
- [ ] Финальная балансировка через systems-designer на основе плейтеста (после M8/M9 расширения врагов и оружий)
- [ ] Capsule art / store description если идём в Next Fest
- [ ] Final tag `v1.0`

**Owners**: playtest-analyst → systems-designer → narrative-designer
**Exit**: shippable demo. Тег `v1.0`.

---

## 5. Locked решения

### Концепт
Полностью в `docs/concept/M0_concept.md`. Velocity Gate, 4 verbs, scope cuts — locked.

### Feel must-стек
Полностью в `docs/feel/feel_spec.md`. На 10 дней — только `must`-слои. Nice-to-have в backlog для post-shippable.

### Числа (TBD — systems-designer в M1)
Стартовые ориентиры (изменимы после первого playtest):
- velocity_cap: старт 80, max 100
- threshold: 30 (speed_ratio < 0.3 → начинается drain timer)
- drain_timer: 2.5 сек tolerance + drain rate
- penalty: стрелок −10, ближнебой −20
- kill restore: +25 (одно убийство ≈ один-два хита компенсирует)
- dash cooldown: 2.5-3 сек
- spawn ramp formula: `interval = 4 / (1 + time*0.015)` — Devil Daggers форма

Финальные числа задаст systems-designer в M1 / М4 / M6.

### Layout арены (TBD — level-designer в M0/M1)
- Размер: ~40×40 units
- Геометрия: открытая центральная зона + 2-3 cover-блока (boxing пространства), без вертикали в M0 (vertical может прийти в M3 если работает)
- Spawn-points: 4 по периферии
- Sightlines: должны быть открытые на 70-80% арены, чтобы стрелок имел смысл, но cover читаем

Финальный layout — level-designer pass с учётом FPS-перспективы.

### Asset stack
Полностью в `docs/research/asset_pipeline.md`. Краткое:
- **Foundation**: Kenney Starter Kit FPS (https://github.com/KenneyNL/Starter-Kit-FPS) — character controller + weapon + base AI, MIT/CC0
- **Environment**: Quaternius Modular Sci-Fi MegaKit (270+ моделей, CC0)
- **Enemies**: Quaternius Sci-Fi Essentials Kit (анимированные роботы, CC0)
- **Weapons**: Kenney Blaster Kit (40 моделей, CC0)
- **Skybox**: Polyhaven HDRI (CC0)
- **VFX**: Synty SIMPLE FX (free) или CSG-particles

---

## 6. Роли агентов

| Агент | Зона | Активен в |
|---|---|---|
| **game-designer** | Concept arbiter, конфликты, новые механики | M0 (locked), M3 enemy identity, M8, M9, M11 |
| **level-designer** | Layout арены, spawn-points, sightlines, доп уровни | M0/M1, M4, M10, M11 |
| **systems-designer** | Числа cap math, dash cooldown, enemy stats, spawn ramp, weapon TTK | M1, M3, M4, M8, M9, M13 |
| **narrative-designer** | Имя проекта, tagline, capsule copy, env tone | M12 |
| **feel-engineer** | Feel-стек спека, audio mix, nice-to-have feel | M2 (главный), M5 (audio), M7 |
| **playtest-analyst** | Фидбэк-цикл по `feedback_playtest_first.md` | После каждого M, обязательно M10, M13 |
| **code-reviewer** | Ревью после групп коммитов | После M2, M4, M8/M9, M13 |
| **godot-engineer** | Вся имплементация | Все майлстоуны |
| **market-analyst** | Positioning / Next Fest подача | M13 / post-shippable |
| **research** | Asset scouting (audio, Quaternius, Polyhaven), Godot 4.6 best practice | M5 (asset gate), по запросу |
| **Пользователь** | Финальный арбитр + плейтестер | Все |

---

## 7. Риски и митигация

| Риск | Митигация |
|---|---|
| Kenney Starter Kit FPS не подойдёт под Godot 4.6 (старая версия) | M0: godot-engineer проверяет первым шагом, если не работает — backup-план писать controller с нуля (1-2 дня) |
| 3D headless smoke падает на сервере (`libfontconfig`) | См. context.md — это известный issue с veldrath. Если падает — флагнуть юзеру, тестировать только на Windows |
| Главный feel-чек (kill = выдох) не сработает с базовым стеком | feel-engineer §5: итеративная проверка, начинай с FOV punch + audio crack, добавляй hit-stop потом time-dilation. Не строй полный стек сразу. |
| FOV double-axis = motion sickness у части игроков | Min FOV 58° — нижний предел до тошноты. Plus: option в settings уменьшить эффект (post-shippable) |
| Spawn ramp формула буксует (слишком медленно/быстро) | Числа в config-файле, systems-designer калибрует через playtest M4 |
| Single-arena run без replay-motivation | Local high score + run-time + score-multiplier дают минимум retention; для shippable demo это honest |
| 10 дней — рамка условная, скоуп вылезет | M3 enemy variety первая жертва (1 тип вместо 2). M5 polish — вторая (audio минимальный, без adaptive music) |
| FPS-arena поджанр насыщен (market-analyst) | Hook (Velocity Gate) — оригинальный, в одно предложение. Это compensates за насыщенность |

---

## 8. Git workflow

- Ветка `main` — стабильное играбельное (или в milestone, но компилится)
- Каждый майлстоун: `git tag v0.MX`
- Commit + push по дефолту (`feedback_commit_and_push.md`)
- Коммит = логическая единица, не 1 line = 1 commit (`feedback_parallel_briefs.md`)
- Code-reviewer после групп коммитов одного модуля
- PLAN.md — единственный источник правды по скоупу. Изменения обсуждаются.
- GitHub remote — создаётся юзером после M0 на `github.com/zulesss/vgate`

---

## 9. Готовность к разработке

**Залочено**:
- Core fantasy + hook + verbs + scope IN/OUT
- Feel must-стек с конкретными числами/мс/кривыми
- Asset pipeline (CC0 + Kenney Starter Kit FPS как foundation)
- Майлстоуны M0–M6 с owner-агентами

**TBD при старте M0/M1**:
- Числа баланса (systems-designer)
- Layout арены (level-designer)
- Имя проекта (narrative-designer в M6)

**После `/clear`**:
1. Открыть `/home/azukki/vgate/`
2. Прочитать `.claude/context.md` + `PLAN.md` + `docs/concept/M0_concept.md` + `docs/feel/feel_spec.md`
3. Стартовать M0 через godot-engineer (импорт Kenney Starter Kit FPS + placeholder-арена)
4. Параллельно подключить level-designer + systems-designer на M1 (числа + layout)

Память `~/.claude/projects/-home-azukki/memory/` — все feedback-правила активны (включая новые: iteration_threshold, design_artifact_dump, godot_brief_template, hook на блок Edit `.gd` в parent-контексте).
