# M1 Numbers — Velocity Gate

Артефакт systems-designer pass от 2026-04-27.
Источники: PLAN.md §5, docs/concept/M0_concept.md, docs/feel/feel_spec.md.
Все числа — стартовые. Финальная калибровка после playtest M2/M4/M6.

---

## Movement

```
base_walk_speed     = 8.0       # units/sec при velocity_cap = 100 (ratio = 1.0)
max_speed_at_cap    = base_walk_speed * (velocity_cap / 100)
                    # при cap=80 → 6.4 u/s; при cap=50 → 4.0 u/s; при cap=20 → 1.6 u/s

current_speed       = velocity.length() по XZ-плоскости только (Y — прыжок — исключён)
speed_ratio         = current_speed / max_speed_at_cap   # нормализовано к текущему потолку
threshold           = 0.3                                 # speed_ratio < 0.3 → стартует drain_timer
```

**Почему XZ-only:** если считать Y, спам прыжком на месте создаёт `speed_ratio > 0` и блокирует drain.
Это degenerate strategy — убирается исключением вертикали из расчёта.

**Почему speed зависит от cap (не константа):** при cap=20 игрок двигается максимум 1.6 u/s —
это "ловушка закрывается". Чем больше получил урона, тем труднее убежать от следующего хита.
Создаёт нарастающее давление без дополнительной механики.

**Почему 8.0 u/s:** арена 40×40. При base_walk_speed=8.0 и cap=80 (max=6.4), пересечь арену по диагонали
≈ 9 сек. Достаточно агрессивно для arena shooter, не teleport-скорость. Калибровать под Kenney
Starter Kit walk feel — если их дефолт сильно расходится, подтянуть к их значению и сохранить
формулу масштабирования.

**threshold 0.3 подтверждён:** при cap=80 → trigger когда speed < 1.92 u/s (почти стоишь).
Совместимо с feel_spec §1: audio heartbeat начинается при ratio < 0.45, low-pass при < 0.4,
drain timer только при < 0.3. Три зоны дают игроку нарастающие сигналы ДО начала drain.

---

## Damage to cap

```
shooter_penalty     = 10        # locked (M0_concept)
melee_penalty       = 20        # locked (M0_concept)
i_frames_after_hit  = 0.3       # сек. Защита от очереди снарядов одного залпа
cap_floor           = 0         # нет нижней границы; drain при cap≈0 убивает быстро
cap_ceiling         = 100       # нельзя превысить через kill restore
```

**i-frames 0.3 сек (не 0.5):** стрелок в M1 — dummy с упрощённым AI. RoF залпа > 0.5 сек,
поэтому 0.3 сек i-frame достаточно защищает от "двойного счёта" одного залпа.
0.5 сек — слишком долго, при ближнебое создаёт ощущение "призрачности" контакта.
TBD-after-playtest: если в M3 стрелок стреляет быстрее — поднять до 0.4.

**cap_floor = 0:** смерти от единственного хита нет. При cap=5, drain=15/сек:
tolerance 2.5 сек + 0.33 сек drain = 2.83 сек на реакцию. Жёстко, но не instant.
Игрок видит cap в debug UI и понимает критичность.

**cap_ceiling = 100:** стартуем с 80, можно добрать до 100 через kills (20 "бонусных" единиц).
Это создаёт mini-reward за kill-chain без дополнительной механики.

---

## Drain

```
tolerance_below_threshold   = 2.5      # сек (locked — concept §1)
drain_rate                  = 15       # cap -= 15 * delta (units/sec) во время drain phase
drain_target                = 0        # drain бьёт в velocity_cap, не в отдельный health bar
drain_auto_stop             = true     # если speed_ratio поднялся выше threshold — drain сбрасывается
```

**Почему drain бьёт в cap, а не отдельный bar:** один параметр = один источник смерти = читаемо.
Игрок видит один индикатор. Если бы был отдельный bar — два параметра, confusion.

**drain_rate = 15/сек:** от cap=80 → смерть за ~5.3 сек (80/15). От cap=40 → 2.7 сек.
Total time от "остановился" до смерти при cap=80: 2.5 + 5.3 = 7.8 сек.
Total при cap=40: 2.5 + 2.7 = 5.2 сек. Нарастающая жёсткость — правильно.

**Почему не константный tick (cap -= X каждые N сек):** плавный drain через delta даёт
корректную работу с i-frames и восстановлением. Tick-урон создаёт момент "несправедливости"
если kill пришёл на 0.1 сек позже тика.

**drain_auto_stop:** если игрок дашнул или убил врага и ratio > 0.3 — drain_timer сбрасывается в 0.
Не только drain_rate паузируется, а весь countdown. Следующая остановка = новые 2.5 сек tolerance.

---

## Kill restore

```
kill_cap_restore    = 25        # instant, cap += 25 при kill confirm (capped at 100)
restore_mode        = instant   # не ramp, не lerp — мгновенно в frame 0 kill-confirm
```

**Почему +25:** strelok_penalty=10 → 1 kill компенсирует 2.5 shooter hit'а. Melee_penalty=20 →
1 kill компенсирует 1.25 melee hit'а. Игра поощряет убийства, не требует идеального уклонения.

**Почему instant (не ramp за 0.3 сек):** feel_spec §2 — FOV punch в frame 0 kill-confirm.
Если cap растёт рампой, speed_ratio поднимается медленно, FOV не открывается вместе с "выдохом".
Instant restore → мгновенный speed_ratio скачок → FOV punch = kill выдох читается телесно.
Если сделать ramp — feel-engineer потеряет синхронизацию стека.

**kill_cap_restore TBD-after-playtest:** +25 — стартовый ориентир. Если playtest M2 показывает
что kill-loop слишком прощающий (игрок стабильно держит cap 80+), снизить до +15.
Если петля слишком рваная — поднять до +30.

---

## Dash

```
dash_velocity_burst     = 20.0      # units/sec, мгновенно в направлении взгляда (XZ-проекция)
dash_duration           = 0.2       # сек, velocity применяется, потом friction гасит до walk
dash_cooldown           = 2.5       # сек
dash_affects_cap        = false     # dash не изменяет velocity_cap
```

**dash_velocity_burst = 20 u/s:** при cap=80, walk_max=6.4. Dash = 3.1x walk max.
Читается как рывок, не телепорт. Полное пересечение арены (40 u) за 2.0 сек невозможно —
velocity гасится за 0.2 сек, фактическое смещение ≈ 20*0.2 = 4 units за burst.
Это правильная величина: уходишь из-под удара, не перемещаешься через всю арену.

**dash_duration = 0.2 сек:** velocity = 20 u/s применяется 0.2 сек, потом стандартный friction
гасит до walk. Фактическое смещение ~4 units (20 * 0.2). Скорее читаемо как "рывок"
чем как "полёт". Если Kenney Starter Kit использует CharacterBody3D — velocity напрямую,
гашение через friction в _physics_process уже есть.

**dash_cooldown = 2.5 сек:** нижняя граница из концепта. Достаточно между dash и следующим dash
убить одного врага или получить хит. Dash не заменяет Kill как recovery.
Если playtest M2 показывает что 2.5 сек слишком коротко (dash спамится) — поднять до 3.0.

**dash_affects_cap = false:** dash = velocity burst, не health action. Это verb для mobility,
не ресурс восстановления. Сохраняет читаемость: cap меняется только через hits (−) и kills (+).

---

## Restart

```
respawn_cap                 = 80    # velocity_cap сбрасывается в стартовое значение
respawn_dash_cooldown_reset = true  # dash cooldown обнуляется при respawn
total_restart_cycle         = 2.8   # сек (matches feel_spec §4)
```

**Разбивка 2.8 сек (из feel_spec §4):**
- Death animation: 1.8 сек
- Score display на чёрном: 0.6 сек
- Fade-in арены: 0.4 сек

**respawn_cap = 80:** не 100 (max). 80 = стандартный старт с буфером к смерти.
Если бы respawn давал 100 — kill-chain перед смертью не имел бы смысла (reset anyway).
80 создаёт ощущение "чистого листа с ограниченным временем".

**respawn_dash_cooldown_reset = true:** игрок стартует с возможностью сразу дашнуть.
Если не сбрасывать — может начать run с cooldown из прошлого run, что несправедливо.

---

## TBD-after-playtest (M2/M4)

1. **i_frames_after_hit**: 0.3 → возможно 0.4 если в M3 стрелок получает RoF < 0.5 сек.
2. **kill_cap_restore**: 25 → калибровать по feel M2. Главный вопрос: слишком ли "легко" держать cap?
3. **dash_cooldown**: 2.5 → 3.0 если dash спамится как основной recovery вместо kills.
4. **base_walk_speed**: 8.0 → синхронизировать с Kenney Starter Kit дефолтом при импорте M0.
   Если у них значительно другой масштаб — пересмотреть всю цепочку формул.
5. **drain_rate**: 15/сек → если playtest M2 показывает "я умираю не понимая почему" —
   снизить до 10/сек (cap=80 → 8 сек drain phase). Если "слишком легко избежать" — поднять до 20.

---

## Быстрая шпаргалка для godot-engineer

| Параметр | Значение |
|---|---|
| base_walk_speed | 8.0 u/s |
| max_speed_at_cap | base * (cap/100) |
| current_speed | XZ velocity.length() |
| speed_ratio | current_speed / max_speed_at_cap |
| threshold | 0.3 |
| shooter_penalty | 10 |
| melee_penalty | 20 |
| i_frames_after_hit | 0.3 сек |
| cap_floor | 0 |
| cap_ceiling | 100 |
| respawn_cap | 80 |
| tolerance_below_threshold | 2.5 сек |
| drain_rate | 15 u/sec (бьёт в velocity_cap) |
| kill_cap_restore | 25 (instant, capped at 100) |
| dash_velocity_burst | 20.0 u/s |
| dash_duration | 0.2 сек |
| dash_cooldown | 2.5 сек |
| dash_affects_cap | false |
| respawn_dash_cooldown_reset | true |
| total_restart_cycle | 2.8 сек |
