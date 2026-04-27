# Feel spec — VGate

Артефакт feel-engineer pass от 2026-04-27. Базовый стек на 10-дневный shippable demo.

Принцип: на 10 дней — только `MUST`. Nice-to-have отмечено и идёт в backlog. Главный feel-чек в §5 — критическая проверка hook'а.

---

## 1. Slow-down feedback (FOV + audio)

Юзер выбрал каналы: **FOV-сжатие + audio**. Без vignette / UI как доминирующих.

### FOV mapping — двойная ось

FOV маппится не от `velocity_cap` напрямую, а от двух параллельных параметров. Финальный FOV = **min** обоих.

**Ось 1 — speed_ratio = current_speed / velocity_cap** (мгновенная реакция):

| speed_ratio | FOV | Зона |
|---|---|---|
| > 0.6 | 90° | "живой" — никаких сигналов |
| 0.3 – 0.6 | 90° → 72° | "тревога" — ease-in (квадратичная t²), периферия сужается |
| < 0.3 | 72° → 58° за 1.8 сек | "удушение" — ease-in-out, ускоряется к концу |

Ниже 58° **не идти** — motion sickness.

**Ось 2 — cap_ratio = velocity_cap / 80** (медленный drift):

| cap_ratio | FOV cap | Эффект |
|---|---|---|
| > 0.75 | 90° | норма |
| 0.5 – 0.75 | lock 85° | "что-то не так" — едва заметно |
| < 0.5 | дальнейшее снижение | усиливает эффект speed-ratio |

**Финальный FOV = min(fov_from_speed_ratio, fov_from_cap_ratio)** — мир сужается двумя способами одновременно. **MUST.**

### Audio layers

| Layer | Триггер | Параметры | Приоритет |
|---|---|---|---|
| **Heartbeat** | speed_ratio < 0.45 | 60 BPM (тихо, −18 dB) → 110 BPM (−8 dB) при ratio 0.15. Реалистичный lub-DUB, не синусоида. | **MUST** |
| **Low-pass filter на ambient** | speed_ratio < 0.4 | cutoff 8 kHz → 1.2 kHz линейно за 2 сек. Один AudioEffectLowPassFilter + tween. | **MUST** — **сильнейший канал** |
| **Дыхание** | speed_ratio < 0.3 | 3 варианта хрипловатого лупа, ±3 dB рандом | nice-to-have (skip M2, low-pass даёт 80%) |

### Дополнительные visual hints

| Hint | Эффект | Приоритет |
|---|---|---|
| **Camera bob amplitude → 0** | при low ratio за 0.5 сек. "Тело отказывает". Простая имп. | **MUST** |
| **Motion blur** | high ratio = легкий directional blur 2-4 px; low ratio = blur уходит, изображение неестественно чётко | nice-to-have |
| **Screen tilt** | NOT — конфликтует с readability в FPS | **NO** |

### Прецеденты
- **Hunt: Showdown** — ambient low-pass на низкой stamina, эталон
- **Alien: Isolation** — heartbeat sync с proximity AI
- **Soma** — audio-tunnel опасной зоны, без vignette

---

## 2. Kill burst feedback

Kill — глоток воздуха. Ключевое слово: **контраст**. Чем сильнее удушение до — тем слаще выдох.

### Слои стека

| Слой | Параметры | Приоритет |
|---|---|---|
| **FOV punch** | currentFOV + 15° за 1 кадр → возврат за 180 мс ease-out-cubic. Если был 58° → скачок до 73° → возврат | **MUST** |
| **Hit-stop** | 65 мс. Не 5 (не читается), не 80+ (пауза как баг). Замораживает enemy physics+animations, не игрока и не камеру → "скольжение сквозь заморозку" | **MUST** |
| **Time-dilation** | 0.08 сек при `Engine.time_scale = 0.3`, потом **snap** обратно (НЕ плавно). Контраст slow→normal создаёт pop. ULTRAKILL/Doom стиль. Реализация: `Engine.time_scale` + таймер на real-time (`process_mode = PROCESS_MODE_ALWAYS`) | **MUST** |
| **Audio confirm** | Hi-freq "crack" в frame 0 hit-stop'а (не после), attack < 5 мс, fast decay. Popcorn-style как Nuclear Throne. Поверх через 30 мс — атмосферный "whoosh" как выдох. | **MUST** crack, **nice** whoosh |
| **Kill chain** | 2-й kill за 1.5 сек: FOV +20°, hit-stop 80 мс, BPM сердца сбрасывается. 3-й: pitch-up на ambient music | **nice-to-have** post-M2 |

### Порядок выполнения
Hit-stop → snap → time-dilation → snap. **НЕ параллельно** — конфликтует с time_scale.

### Прецеденты
- **Hades** — hit-stop + audio layering на каждом оружии, лучший учебник
- **Dead Cells** — kill burst через camera + particles одновременно
- **ULTRAKILL** — time-dilation + style meter как velocity restore

---

## 3. Dash feedback

Dash = explosion в направление. Единственный активный source velocity без kill.

| Слой | Параметры | Приоритет |
|---|---|---|
| **FOV stretch** | +12° мгновенно → возврат за 250 мс ease-out-quart | **MUST** |
| **Camera push** | смещение 0.15 units forward за 1 кадр → возврат за 200 мс ease-out. "Тело бросило вперёд" | **MUST** |
| **Audio whoosh** | pitch shift +200 cents (выше = быстрее). Если dash из low-speed-ratio → +300 cents (вырывание из удушения слышно) | **MUST** |
| **Cooldown viz** | без UI — тихий "recharge" click + walking bob возвращается к полной amplitude если был снижен | **MUST** |
| **"Dash спас" feedback** | если speed_ratio поднялся выше 0.4 за 0.5 сек после dash — "relief" вариант whoosh (чуть длиннее, реверб) | **nice-to-have** post-playtest |

### Прецеденты
- **Apex Legends** — лучший FOV-stretch на dash/stim
- **Titanfall 2** — весь movement-feedback через audio+FOV без UI
- **Celeste** — timing-based dash с чётким audio-confirm

---

## 4. Run pacing

10-15 минут run. Continuous pressure, не дискретные волны.

### Spawn ramp (форма, не числа)

```
interval = 4 / (1 + time_elapsed * 0.015)
```

| Время | Интервал спавна |
|---|---|
| t=0 | 4 сек |
| t=3 мин | ~2 сек |
| t=7 мин | ~1 сек |
| t=10 мин | ~0.6 сек |

Это **форма кривой**, не точные числа. systems-designer калибрует через playtest M4.

### Паузы (вдохи)
- **НЕ scripted gaps** — разрушает "управляемую панику"
- Вдохи **органические**: kill-chain → cap restored → speed_ratio высокий → brief момент "я в порядке"
- Тишину не дари — пусть зарабатывается

### Adaptive music

Минимально работающее в 10-дневном скоупе — **2 layers**:

| Layer | Триггер | Поведение |
|---|---|---|
| Base loop | всегда | volume 0 dB |
| Intensity layer | time_elapsed > 120 сек | volume 0 за 30 сек tween-in |

**MUST: 2 layers**. **Nice-to-have**: BPM sync, drum tempo как Devil Daggers.

### Death → restart cycle

| Фаза | Длительность |
|---|---|
| Death animation | 1.8 сек (НЕ slow-mo death cam — это zen, не паника) |
| Score display на чёрном | 0.6 сек |
| Fade-in арены | 0.4 сек |
| **Total** | **~2.8 сек** |

**MUST: скорость рестарта критична для replayability петли.**

---

## 5. Главный feel-вопрос на первый playtest

> **Читается ли kill как выдох, а не просто "враг умер"?**

Всё в Velocity Gate держится на этой транзакции. Игрок в панике → Kill verb → буквальное физиологическое облегчение. Если не ощущается — петля рассыпается, игрок начинает кемперить и упирается в death без понимания.

### Что проверять руками первым

1. Войди в danger-зону: speed_ratio < 0.3, слышишь heartbeat, FOV сузился до 58°.
2. Убей врага.
3. **Если выдохнул** — стек работает. Дальше полировка.
4. **Если нет** — стек НЕ работает. Останови, не строй M3 поверх рассыпанного.

### Итеративная имп-стратегия

НЕ строй полный стек kill-burst сразу — итерируй:

**Итерация 1**: только FOV punch + audio crack (минимум). Войди в danger → убей. Проверь.
**Итерация 2** (если 1 не сработала): + hit-stop 65 мс.
**Итерация 3** (если 2 не сработала): + time-dilation 0.08 сек snap.
**Итерация 4**: только если 1-3 не сработали — переходим на B-вариант (Ammo-as-Time, см. concept §B).

---

## 6. Backlog (nice-to-have, post-shippable)

- Дыхание audio loop
- Motion blur (high speed = blur, low speed = unnaturally crisp)
- Kill chain feel (escalation на 2-3 kill подряд)
- Dash "relief" feedback при выходе из удушения
- BPM-sync adaptive music (drum tempo growth)
- Screen-shake calibration (TBD после M2 — может быть нужен на explosions если они появятся)

---

## 7. Что НЕ обсуждается в этом spec'e
- Числа баланса cap math — это systems-designer (M1)
- Layout арены — level-designer (M0/M1)
- Сеттинг и цветовая палитра — выбран sci-fi через ассеты, тон — после M2 feel pass
