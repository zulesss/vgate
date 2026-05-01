# M8 Swarmling Numbers — VGate

Артефакт systems-designer pass от 2026-04-30.
Источники: PLAN.md §M8, docs/systems/M3_enemy_numbers.md, locked identity (game-designer approved).

---

## 1. LOCKED Numbers

| Параметр | Значение | Источник / обоснование |
|---|---|---|
| **max_hp** | 3 | Один выстрел центральной пулей (10 dmg) убивает instantly — reward за aim. Full spread (30 dmg) избыточен — не нужен. Bloodless в Hades: 1-shot fragile = читается как "cannon fodder" |
| **move_speed** | 8.5 u/s | Always faster than player walk даже при cap=100 (player walk maxes at 8.0). Was 8.0 (parity at cap=100 — perfect-cap safe zone) — playtest 2026-05-01 показал что safe-zone "ровно cap=100" слишком тонкий: игрок выходит ниже 100 hit-by-hit и одновременно outrun'ит swarm любым decent cap'ом. Buff +0.5 делает identity жёстче: swarm нельзя outrun'ить вообще, kill loop обязателен. Earlier was 7.7 (safe-zone cap > 96, too wide). Аналог: DOOM 2016 Imp (быстрый, но не hitscan-стремительный) |
| **attack_range (contact)** | 1.2 u | Чуть меньше melee 1.5 u — swarmling мельче физически (SCALE 0.55). Contact = физическое столкновение, не windup-based. Совпадает с capsule radius игрока ≈ 0.5u × 2 + 0.2 margin |
| **attack_windup** | 0 мс | Нет windup. Contact-damage срабатывает мгновенно при пересечении range=1.2u. Telegraph — сам факт сближения. Это противоположность melee/shooter и делает рой читаемым: "не подпускай близко, а не жди анимации" |
| **attack_cooldown** | 1.8 с | Micro-penalty −5 при cooldown=1.8с = 2.78 cap/sec per swarmling при sustained contact. Рой из 3: 8.33 cap/sec — существенно, но не instant kill. Hades Bloodless swarms: частые маленькие хиты хуже одного большого психологически |
| **penalty (cap loss on hit)** | −5 | LOCKED by game-designer. Identity: "один-два ничего не значат, рой опасен". Расчёт: 4 swarmling × −5 × sustained contact ≈ −20 cap/sec = быстрый drain только при полном окружении |
| **detection_radius** | 35 u | Идентично melee/shooter. Арена 40×40 — практически "всегда Chase" при spawn |
| **score per kill** | 50 | Melee=100, Shooter=150. Swarmling = half melee — дёшев поштучно, ценен группой. 4 kills = 200 score = > одного melee. Incentivises clear через цепочку |
| **GROUP_SIZE_MIN** | 3 | Identity locked |
| **GROUP_SIZE_MAX** | 4 | Identity locked |
| **MAX_LIVE_SWARMLINGS** | 8 | **Отдельный sub-cap**, НЕ общий с melee. Логика: при ENEMY_CAP=20 без sub-cap один group-spawn 4 + wave через 2с + wave через 2с = 12 swarmlings без ни одного melee/shooter = identity ломается (рой заполняет всё). Sub-cap=8 = max 2 полных группы одновременно. Выше — новый spawn блокируется до смерти существующих |
| **SCALE_MULTIPLIER** | 0.55 | 0.5–0.7 диапазон из задания. 0.55 = читаемо "явно мельче melee" но не микроскопически. Меньше 0.5 — теряется в 3D-пространстве при > 3 штук. Больше 0.65 — перестаёт читаться как "другой тип", похоже на melee |
| **CHAIN_COUNTER_WEIGHT** | 0.25 | LOCKED по playtest M8 — group=4 spawn, 4 swarm kills = +1 chain (floor); ранее было 0.5 — давал inflation +2/wipe |

---

## 2. Spawn Integration

### Базовая формула (не меняется)

```
interval = max(0.8, 4.0 / (1 + t * 0.005))
```

### Type weights по времени

Swarmling не нужен в первые 60-90 секунд — игрок ещё не освоил movement hook. Мягкий ramp:

| Время (сек) | Melee % | Shooter % | Swarm-group % | Rationale |
|---|---|---|---|---|
| 0–60 | 60 | 40 | 0 | Tutorial pressure — только знакомые типы |
| 60–120 | 45 | 35 | 20 | Первый рой появляется как surprise |
| 120–300 | 35 | 30 | 35 | Swarmling = паритет с другими типами |
| 300+ | 25 | 25 | 50 | Поздний game — рои доминируют, держат constant presence |

"Swarm-group spawn" = один spawn event на весь group (3–4 одновременно), интервал применяется к событиям, не к отдельным единицам.

### Sub-cap enforcement

При spawn event типа swarm-group: `count = min(GROUP_SIZE_MAX, MAX_LIVE_SWARMLINGS - current_live_swarmlings)`. Если `count < GROUP_SIZE_MIN` — spawn откладывается, не отменяется (retry через 1 интервал).

---

## 3. Risk Callouts

**[HIGH] Cap overflow при поздней игре (t > 300с).**
При weight=50% swarm-events + interval=0.8с (минимум): теоретически каждые 0.8с попытка spawn group. Sub-cap=8 ограничивает, но при быстром kill rate (игрок убивает по 1 swarmling/сек) они могут respawn быстрее melee/shooter → arena заполняется только swarmlings. Mitigation: sub-cap=8 жёсткий. Дополнительно отслеживать `swarm_events_in_last_5s ≤ 2` (cooldown на сам тип события).

**[RESOLVED] Kill chain inflation.** 
Изначально CHAIN_WEIGHT=0.5 давал +2 chain на каждое clearance группы 4 swarmlings — инфляция reward signal'а до tier 1 каждые 4с. Решено снижением weight до 0.25 (2026-04-30): 4 swarm kills = +1 chain. Mixed kills (свармы + melee/shooter) теперь честно балансируются: 4 swarm + 1 melee = 2.0 chain (ниже tier 1=3 порога), что соответствует феел-весу.

**[MEDIUM] Contact без windup = invisible threat при лаге / frame drop.**
При 60fps контакт обнаруживается раз в 16мс — нормально. При spike до 20fps — контакт может срабатывать с задержкой 50мс × 2 = пропущен, потом двойной. Cooldown=1.8с защищает от double-hit, но нужна проверка: `last_hit_time[swarmling_id]` per-enemy, не global.

**[LOW] SCALE=0.55 vs hitbox.**
Если visual scale применяется к CollisionShape без отдельного resize — hitbox тоже уменьшится до ~60% melee. attack_range=1.2u может не достигать player capsule если их capsule не масштабируется. Godot-engineer должен явно задать CollisionShape независимо от MeshInstance scale.

---

## 4. Pivot Points

Если playtest показывает проблему — в этом порядке:

| Проблема | Первый pivot | Почему именно он |
|---|---|---|
| Рой **слишком лёгкий** (игрок игнорирует) | `attack_cooldown 1.8с → 1.2с` | Penalty-rate растёт без изменения identity. Не трогать penalty=-5 (locked) |
| Рой **слишком опасный** (3 контакта = death spiral) | `MAX_LIVE_SWARMLINGS 8 → 6` | Уменьшает максимальное давление, не меняет feel одиночной группы |
| Рой **не читается** как отдельный тип | `SCALE_MULTIPLIER 0.55 → 0.45` | Сильнее визуальный контраст с melee. Проверить hitbox отдельно |
