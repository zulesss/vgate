# Concept — VGate (working title)

Артефакт первого design-pass: game-designer + market-analyst, синтез + approval-gate юзера.
Locked на старте проекта.

---

## Core fantasy

Ты — единственный подвижный элемент в мире, который хочет тебя остановить. Скорость — не преимущество, она обязательна. Стоять = смерть через ~3 сек.

**Эмоция**: управляемая паника. Не zen flow ULTRAKILL, не пазл Neon White — ты не контролируешь ситуацию, ты только чуть опережаешь её.

---

## Hook — Velocity Gate

HP в классике нет. Есть `velocity_cap` (0–100, старт 80).

- **Hits от врагов** снижают `velocity_cap` (стрелок −10, ближнебой −20).
- **Speed below threshold** дольше 2.5 сек → drain → смерть.
  - Threshold формулируется как `speed_ratio = current_speed / max_speed_at_cap` где `max_speed_at_cap = base_walk_speed * (cap/100)`. Drain стартует при `speed_ratio < 0.3` (см. `docs/systems/M1_numbers.md`).
  - **Важно** (M1 design pass от 2026-04-27, юзер approved): ratio нормирован к `max_speed_at_cap`, а не к голому `velocity_cap`. Голая нормировка к cap была математически degenerate (`current_speed / 80` всегда ≤ 0.1 → drain активен всегда). Текущая формула даёт читаемую зону "движусь медленнее 30% своего текущего потолка" + автоматический эффект "ловушка закрывается" (низкий cap → низкий max_speed → труднее выйти из drain).
- **Kill restore**: убийство врага восстанавливает `velocity_cap` на N (стартовый ориентир +25).
- **Враги становятся одновременно угрозой и топливом**. Это не "стрельба для очистки", это "стрельба для дыхания".

**Почему это hook, а не feel:**
Меняет cognitive layer принятия решений. В Devil Daggers ты решаешь "куда встать". Здесь — "какого врага убить первым чтобы не замедлиться".

**Чем отделяется от референсов:**
- ULTRAKILL: blood-as-HP — стиль поощряется. Здесь скорость = жизнь — трусость наказывается **структурно**, не эстетически.
- Devil Daggers: risk-ramp по времени, но HP обычное. Здесь "ресурс жизни" — это поведение.
- Karlson: instakill — бинарно. Здесь деградация постепенная.
- Neon White: расходники как оружие — другая ось.

---

## Player verbs (4)

1. **Move** — бег в 3D, стрейф, базовый jump (не verb сам по себе). Скорость = главный параметр состояния.
2. **Shoot** — одно оружие, полный боезапас. Не управление ресурсом — стреляй. Aim window важен.
3. **Dash** — кратковременный velocity burst в направлении взгляда. Cooldown 2.5-3 сек. Единственный активный source velocity без kill.
4. **Kill** — конкретно verb-транзакция: враг мёртв + cap restore. Игрок целится в убийство, не просто стреляет.

Четвёртый verb (Use / Reload / Crouch) НЕ добавляется — конфликтует с core fantasy. Игра про движение, не менеджмент.

---

## Scope cuts (locked OUT)

| Вырезано | Почему |
|---|---|
| Несколько арен | Одна, хорошо задизайненная |
| Несколько типов оружия | Velocity Gate работает без variety; +оружие = +balance работа |
| Enemy variety > 2 | 2 (стрелок + ближнебой) достаточно проверить hook |
| Анимированные риги | Capsule + базовые mesh из Kenney/Quaternius. Прототип. |
| Meta-progression | Ноль. One run = one session. Local high score максимум. |
| Narrative / lore | Ноль. Сеттинг через визуальный тон. |
| Online leaderboard | Только local high score |
| Controller support | Кб + мышь. Geympad если Godot InputMap покрывает бесплатно. |
| Кастомная музыка | CC0/royalty-free один трек как base layer + один intensity layer |
| Сложный AI pathfinding | NavigationAgent3D базовый, без тактических обходов |

---

## Прецеденты

### Devil Daggers (Sorath, 2016)
- **Что переиспользую**: single arena + spawn ramp как пространство выживания, не "уровень для прохождения". Минималистичная графика для читаемости.
- **Что избегаю**: пассивная agency игрока ("куда встать"). Velocity Gate добавляет agency через Kill-as-resource.

### ULTRAKILL
- **Что переиспользую**: "трусость наказывается структурно". Та же логика, через velocity_cap а не blood proximity.
- **Что избегаю**: AAA-объём (множество врагов, оружий, арен, механик). Это death prototype'а.

### Karlson (Dani)
- **Что переиспользую**: "хук виден за 10 секунд". Velocity Gate должен быть читаем немедленно — остановился, что-то поменялось.
- **Что избегаю**: parkour-platforming. Dash покрывает mobility без platforming-скоупа.

---

## Конфликты внутри концепта (озвучены до кода)

### 1. Velocity Gate × читаемость в 3D от первого лица
В 2D плоский top-down — тривиально читается. В FPS обзор ограничен. Хиты прилетают из-за угла → игрок не понимает почему замедляется → frustration не challenge.

**Решение** (зафиксировано): враги читаемы ДО выстрела (silhouette + audio cue + telegraph). Подробности в `docs/feel/feel_spec.md`. Главный feel-вопрос — kill читается как выдох.

### 2. Dash × Velocity Gate
Dash даёт burst → если cooldown низкий, dash = "HoT" и hook не давит. Если cooldown высокий — игрок беспомощен без kills.

**Решение** (TBD systems-designer): cooldown 2.5-3 сек ориентир, калибровка по playtest M2.

### 3. Single arena × replay motivation
Без meta-progression и без leaderboard — мотивация только personal score. Для прототипа на 10 дней это OK. Для shippable demo нужен local high score + score-multiplier как минимум compensate.

### 4. 2 типа врагов × velocity cap читаемость
Если penalty одинаковый — игрок не различает критичность. **Зафиксировано**: стрелок −10 (можно разминуться), ближний −20 (критично). systems-designer калибрует точные числа.

---

## B-вариант (если Velocity Gate жмёт при импе)

**Ammo-as-Time**: вместо `velocity_cap` есть таймер. Kill добавляет секунды. Пустой = смерть.

Тот же cognitive layer ("kill = ресурс"), но проще в имп — один counter, один timer, без 3D-feel-сложностей.

Минус: ближе к точному клону тайм-аттак жанра (Superhot derivative). Hook менее оригинален.

**Решение перехода на B-вариант** принимается ТОЛЬКО если на M2 feel-чек "kill = выдох" не сработал после 3-х итераций feel-полировки. До M2 — Velocity Gate.

---

## Market context (от market-analyst, для info)

- 3D FPS arena — насыщенный поджанр в 2026. Boomer shooter официально получил тег Steam в 2024, концентрация успеха у DUSK / ULTRAKILL / Ion Fury.
- Movement shooter / zoomer shooter — окно ещё открытое (SPRAWL, VOID/BREAKER, Mullet MadJack).
- Соло indie без аудитории — медиана продаж 200-500 копий первый месяц. С Next Fest demo + devlog: 2000-5000.
- Цель vgate — **shippable demo для Next Fest**, не commercial release. Hook (Velocity Gate) compensates насыщенность ниши.
- Минимализм визуала > узнаваемые ассет-паки в Discovery Queue. Именно поэтому Kenney/Quaternius **base** + собственная стилизация / цветовой акцент.

---

## Closest references по соло-скоупу
- **Devil Daggers** (соло, ~10 лет, 200-500k владельцев) — образец arena minimalism
- **SPRAWL** (соло MAETH, 2023, 87% positive, ~20-50k владельцев) — cyberpunk + wallrun, реалистичный соло-кейс с хуком
- **VOID/BREAKER** (соло Stubby Games, 2025, Game Pass boost) — movement roguelite FPS, доказательство что ниша жива

---

## Locked statements
1. Hook — Velocity Gate (не Ammo-as-Time как primary)
2. Verbs — ровно 4 (Move/Shoot/Dash/Kill)
3. Scope IN/OUT таблица — locked
4. Setting — sci-fi через CC0 (Kenney Starter Kit + Quaternius)
5. Slow-down feedback каналы — FOV + audio (без vignette / UI как доминирующих)

Любое изменение залоченных statements — обсуждается, не делается тихо.
