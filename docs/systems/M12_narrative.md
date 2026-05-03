# M12 Narrative Pass — design artifact

**Status**: LOCKED 2026-05-03 (Direction A "Испытание/Экзекуция" + название КИНЕТИКА + полная русская локализация)
**Identity**: Машинное правосудие проверяет приговор движением. Стой = виновен.

## Анкоры

- **Core fantasy**: управляемая паника. Игрок осуждён, имплант проверяет приговор движением. Velocity drain = приговор в реальном времени.
- **Унифицирующий мотив**: 3 арены = 3 стадии исполнения приговора (публичная демонстрация → одиночное заключение → ритуальная казнь).
- **Diegetic justification drain'а**: «Модуль Кинетического Контроля» (МКК) — нейронный имплант смертника. Если кинетическая сигнатура падает ниже порога → имплант интерпретирует это как отказ от испытания → завершает приговор.
- **Протагонист**: безымянный осуждённый. Игрок узнаёт правила через смерть, как протагонист — через движение.
- **Босс (Cathedral)**: «Исполнитель». Не злодей — исполняет работу. 3 фазы = 3 степени приговора (предупреждение / суд / исполнение). Золотой HDR emissive = инсигния системы.

## Arena framing

| Арена | Стадия приговора | Нарратив |
|---|---|---|
| **Плац** | Публичная демонстрация | Sphere в центре = маяк судьи. Удержи на виду у всех, или умри прилюдно. |
| **Камера** | Одиночное заключение | Тесный лабиринт проверок. Список меченых = список улик против тебя. |
| **Собор** | Ритуальная финальная казнь | Сакральное пространство, построенное логикой. 4 алтаря = 4 печати приговора. Босс = Исполнитель. |

## Lock'нутые тексты

### Название
**КИНЕТИКА** — read-on-shelf hook на mechanic + thematic resonance.

### Tagline
**«Двигайся или умри. Это приговор.»**

### Capsule (Steam / itch)
> КИНЕТИКА — 3D-арена, где остановка убивает.
>
> Твой запас скорости — единственная нить жизни. Получаешь урон — он сжимается. Стоишь слишком долго — он опускается до нуля. Убивай, чтобы восполнить. Угроза — не враги. Угроза — неподвижность.
>
> Три арены. Три приговора. Одно правило: не останавливайся.

### Death-screen варианты (terminal-style)

Per контекст смерти (RNG или per-arena weighted):

```
ПРЕВЫШЕН ПОРОГ СКОРОСТИ
ПРИГОВОР ПРИВЕДЁН В ИСПОЛНЕНИЕ — %TIME%
ЗАПИСЬ СООТВЕТСТВИЯ: ПРОВАЛЕНО
```

```
ДВИЖЕНИЕ НЕДОСТАТОЧНО
ВЕРДИКТ: ПОДТВЕРЖДЁН
```

```
КИНЕТИЧЕСКАЯ СИГНАТУРА ПОТЕРЯНА
ИНИЦИАЛИЗАЦИЯ ПРОТОКОЛА ЗАВЕРШЕНИЯ
ВРЕМЯ СМЕРТИ: %TIME%
```

```
ВЫ ОСТАНОВИЛИСЬ.
ИМ И НЕ ПОНАДОБИЛОСЬ.
```
(для быстрой смерти, t_alive < 30s — самоиронично)

### Intro splash (2-3 sec, fade-in)

Чёрный экран → курсор-каретка терминала мигает 0.5s → проявляется текст:

```
МОДУЛЬ КИНЕТИЧЕСКОГО КОНТРОЛЯ — АКТИВЕН
ЗАПУСК ПРОЦЕДУРЫ ИСПЫТАНИЯ
```

→ fade to arena (1s).

### Existing UI translation (полный перевод)

**Main menu** (`scenes/main_menu.tscn`):
- VGATE → КИНЕТИКА
- MOVEMENT IS LIFE → ДВИЖЕНИЕ — ЖИЗНЬ
- START → НАЧАТЬ
- SETTINGS → НАСТРОЙКИ
- CREDITS → АВТОРЫ
- QUIT → ВЫХОД

**Pause menu** (`scenes/pause_menu.tscn`):
- PAUSED → ПАУЗА
- RESUME → ПРОДОЛЖИТЬ
- RESTART → ЗАНОВО
- SETTINGS → НАСТРОЙКИ
- MAIN MENU → ГЛАВНОЕ МЕНЮ
- QUIT → ВЫХОД

**Settings menu** (`scenes/settings_menu.tscn`):
- SETTINGS → НАСТРОЙКИ
- MASTER → ОБЩАЯ
- MUSIC → МУЗЫКА
- SFX → ЗВУКИ
- AMBIENT → ФОН
- MOUSE SENS → ЧУВСТВ. МЫШИ

**Credits** (`scenes/credits.tscn`):
- CREDITS → АВТОРЫ
- Music → Музыка
- BACK → НАЗАД

**Death screen** (`scenes/death_screen.tscn`, `scripts/death_screen.gd`):
- VELOCITY DRAINED → terminal-style variant (rotated per spec выше). Default: «ПРЕВЫШЕН ПОРОГ СКОРОСТИ» line 1 + «ПРИГОВОР ПРИВЕДЁН В ИСПОЛНЕНИЕ» line 2.
- Score: 0 → Счёт: 0
- Spheres: 0 / 20 → Сферы: 0 / 20 (per arena: Алтари / Метки / Сферы)
- Best: 0 → Рекорд: 0
- RESTART → ЗАНОВО

**Win screen** (`scripts/win_screen.gd`, `scenes/win_screen.tscn`):
- CATHEDRAL CLEANSED → СОБОР ОЧИЩЕН
- AREA CLEARED → ЗОНА ЗАЧИЩЕНА
- ARENA COMPLETE → АРЕНА ПРОЙДЕНА
- Kills → Убийства
- Avg Cap → Средний КАП
- Time → Время
- Altars → Алтари
- Marked Kills → Метки
- Spheres → Сферы
- SCORE → СЧЁТ
- BEST → РЕКОРД
- RESTART → ЗАНОВО

**Run HUD** (`scripts/run_hud.gd`, `scenes/run_hud.tscn`):
- ENEMIES → ВРАГИ
- HUNT → ОХОТА (✓ ОХОТА %d на done)
- ✓ CLEAR → ✓ ЗАЧИЩЕНО
- KILL THE BOSS → УБЕЙ ИСПОЛНИТЕЛЯ (lore-driven из narrative spec)
- ALTARS → АЛТАРИ
- BOSS → ИСПОЛНИТЕЛЬ (lore-driven)
- CAPTURING → ЗАХВАТ
- CAPTURED → ЗАХВАЧЕНО (toast text)
- CAP → КАП (CSGCylinder3D bar label)

**Intro text** (`scripts/intro_text.gd`):
- CLEAR ENEMIES AND ESCAPE\nIN 2 MINUTES → ЗАЧИСТИ ВРАГОВ И ПОКИНЬ ЗОНУ\nЗА 2 МИНУТЫ (Journey, deprecated arena — но строка в коде)
- CAPTURE %d ALTARS\nAND SLAY THE BOSS → ЗАХВАТИ %d АЛТАРЕЙ\nИ УБЕЙ ИСПОЛНИТЕЛЯ
- HUNT %d MARKED ENEMIES\nAND SURVIVE 2 MINUTES → УСТРАНИ %d МЕЧЕНЫХ\nИ ВЫЖИВИ 2 МИНУТЫ
- CAPTURE %d SPHERES\nAND SURVIVE 2 MINUTES → ЗАХВАТИ %d СФЕР\nИ ВЫЖИВИ 2 МИНУТЫ

**Project metadata** (`project.godot`):
- config/name = "VGate" → "КИНЕТИКА"

## Ambient audio motifs (nice-to-have)

Per arena environmental tone. Не in scope текущего impl pkg'а — flag для M13 polish если останется бюджет.

- **Плац**: drum-march 2/4 на низких частотах, металлический резонанс. Снаружи — ветер, гул турбин. (Как Apocalyptica без струн)
- **Камера**: интермиттирующее гудение флуоресцентного света + далёкие шаги, эхо. **Без музыки** — только звуки пространства. Тишина давит сильнее хора.
- **Собор**: низкий хоровой дрон на одной ноте (sustained, не мелодия). При захвате алтаря дрон смещает высоту (как орган переключает регистр). На spawn'е босса — дрон обрывается, остаётся механика.

Принцип: Плац = звук снаружи, Камера = звук стен, Собор = звук системы.

## Реализация — пакеты

### Pkg A — UI text translation
Полный перевод всех existing English strings (см. список выше). Затрагивает 7 .tscn / 4 .gd файла. Нет logic changes — pure text swap.

### Pkg B — Project name
- `project.godot` → config/name = "КИНЕТИКА"

### Pkg C — Intro splash
Новая сцена `scenes/intro_splash.tscn` + `scripts/intro_splash.gd`. CanvasLayer + Label + Tween. Триггер из main menu START button: вместо direct scene switch — instance intro splash → 2.5s fade → switch to arena. Skippable on input (любая клавиша).

### Pkg D — Death screen variants
`scripts/death_screen.gd` — заменить hardcoded "VELOCITY DRAINED" на random-pick из массива variants. Special case: t_alive < 30s → fixed variant «ВЫ ОСТАНОВИЛИСЬ. ИМ И НЕ ПОНАДОБИЛОСЬ.» (самоирония быстрой смерти).

## Anti-patterns avoided

- ❌ Лор-вики (объяснения через текст, который игрок не прочитает)
- ❌ NPC / диалоги (out of scope solo-dev)
- ❌ Cutscenes (выше)
- ❌ Generic "evil corporation" / "alien invasion" (vgate themes уже навигают)
- ❌ Кнопочные explanations механики ("press SPACE to dash" UI hints) — мы оставляем игрока без обучения, чтобы соответствовать narrative протагониста («ты не выбирал быть здесь»)

## Open questions / followups

- Ambient audio motifs — bandwidth для M13 (низкочастотные drone'ы / drum loop'ы — Kenney audio pack или procedural).
- "ИСПОЛНИТЕЛЬ" vs "БОСС" в HUD — narrative-driven choice. Если playtest покажет confusion ("это про что") — fallback на нейтральное "БОСС". Tracked.
- Localization architecture — сейчас все strings hardcoded inline. Если international Steam release — потребуется TranslationServer. Skip для M12 (Russian-only first).
- Death screen variant frequency — RNG vs deterministic? Пока RNG, weighted (default 60% / variant-2 25% / variant-3 10% / fast-death special trigger).
