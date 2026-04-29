# M5 Audio Mix Spec — VGate

Артефакт feel-engineer pass, 2026-04-28. Спека независима от конкретных ассет-файлов — числа
задают контракт для godot-engineer, research-agent подбирает файлы под эти параметры.

Базовый стек feel из M2 уже реализован: FOV single-axis cap, heartbeat loop базовый, low-pass
на ambient, kill burst (FOV punch + hit-stop + time-dilation + audio crack frame 0), dash feel
(FOV stretch + camera push + whoosh). M5 строит поверх — добавляет полный SFX bus, адаптивную
музыку, ducking и настройки.

---

## §1. SFX Bus — per-sound design

### Bus-топология

```
AudioServer buses:
  Master
  ├── Music       (для base + intensity layers, можно duck отдельно)
  ├── SFX         (gun-fire, hit-impact, kill-confirm, dash-whoosh, spawns)
  ├── Heartbeat   (отдельная шина — игрок регулирует независимо от gun-fire)
  └── Ambient     (sci-fi hum + low-pass effect уже сидит здесь с M2)
```

Heartbeat и Ambient выделены в отдельные шины не для эффектов, а для Settings слайдеров
(см. §4) — игрок может глушить тревожные каналы отдельно от sfx-экшена.

---

### Таблица SFX

| # | Sound | Bus | Player2D / 3D | Unit size (3D) | Volume (dB) | Attack / Decay | Pitch variance | Тайминг |
|---|---|---|---|---|---|---|---|---|
| 1 | gun-fire | SFX | 2D | — | −4 dB | attack 0 мс / decay 80 мс | ±6% | on_shoot(), каждый выстрел |
| 2 | hit-impact | SFX | 3D | 8.0 | −6 dB | attack 0 мс / decay 60 мс | ±10% | enemy.apply_damage() frame 0, origin = enemy.global_pos |
| 3 | kill-confirm | SFX | 2D | — | 0 dB (лидер микса) | attack < 5 мс / decay 120 мс | ±4% | Events.enemy_killed, frame 0 |
| 4 | dash-whoosh | SFX | 2D | — | −3 dB | attack 0 мс / decay 200 мс | base pitch, контекстный сдвиг | Events.dash_started |
| 5 | heartbeat | Heartbeat | 2D | — | −18→−8 dB | attack 200 мс / decay 400 мс | 0% (не рандомить ритмику) | loop, pitch_scale управляет BPM |
| 6 | drain-warning | Heartbeat | 2D | — | −14 dB | attack 300 мс / decay 600 мс | 0% | Events.drain_started → loop, stop on drain_stopped |
| 7 | ambient | Ambient | 2D | — | −12 dB | attack 1000 мс / decay — | 0% | run_started → постоянный loop |
| 8 | melee-spawn | SFX | 3D | 16.0 | −2 dB | attack 0 мс / decay 200 мс | ±5% | Events.enemy_spawned (type=melee), frame 0 |
| 9 | shooter-spawn | SFX | 3D | 14.0 | −10 dB | attack 0 мс / decay 150 мс | ±8% | Events.enemy_spawned (type=shooter), frame 0 |

---

### Детальное обоснование по каждому звуку

**1. gun-fire**

Pitch variance ±6% — достаточно чтобы серия выстрелов не ощущалась как machine-gun click
(Nuclear Throne делает ±8%, у нас blaster потише, ±6 хватит). Не делать variance больше ±10%
— у blaster'а должен быть character, не рандомная каша. Volume −4 dB: gun-fire не главная
история в этой игре, главная — kill-confirm и heartbeat. Пусть gun будет "рабочим" звуком,
а не доминирующим. AudioStreamPlayer2D: стрельба идёт от позиции игрока (1st person), 3D не
нужен.

**2. hit-impact**

3D с unit_size 8.0: враг попадает по игроку с позиции врага — нужна пространственная
информация "откуда пришло". Unit_size 8.0 = звук слышен отчётливо в радиусе ~8 units, fade
к 0 к ~32 units. Pitch variance ±10%: удар по игроку повторяется часто, variance убирает
монотонность. Короткий decay 60 мс — snappy, не "болезненный эхо". Volume −6 dB: чуть тише
gun-fire, чтобы не создавал панику звуком отдельно от визуала.

**3. kill-confirm**

0 dB — это лидер микса намеренно. Kill — главная транзакция Velocity Gate. Звук должен
"пробить" через всё остальное. Frame 0 = синхронно с hit-stop (65 мс из M2) — они стартуют
вместе, звук читается как причина стопа. Pitch variance ±4% только: kill должен
ощущаться "правильным", чуть рандом убирает mechanical feel без размытия character'а.
Формат — hi-freq crack (≥2 kHz peak), attack < 5 мс (popcorn, Nuclear Throne стиль).

*Опционально поверх, через 30 мс:* атмосферный "выдох" whoosh −8 dB, decay 300 мс. Это
"nice" из feel_spec §2 — добавляется после первого playtest если crack'а не хватает.

**4. dash-whoosh**

> **2026-04-29:** dash audio rolled back to legacy jump_b.ogg + pitch +200 cents — M5 dash_whoosh.ogg asset звучал артефактом.

Длительность ≤ 200 мс — иначе dash кажется "вязким". Два контекстных варианта через
pitch_scale в коде, не два файла:
- Normal dash: pitch_scale 1.0 → +200 cents (+200 cents = умножить pitch_scale на ~1.122)
- Dash из drain-зоны (speed_ratio < 0.3 на moment dash_started): pitch_scale → +300 cents
  (~1.189x). Вырывание из удушения звучит выше и острее.

Определение контекста: sfx.gd слушает dash_started, в обработчике проверяет
VelocityGate.speed_ratio() на момент сигнала и выбирает pitch_scale.

**5. heartbeat**

> **Updated 2026-04-29:** heartbeat slowed 3x per user feedback (HIGH=0.5, LOW≈0.333, ≈30 BPM peak / ≈20 BPM low). Side-effect: семпл звучит на октаву ниже — гулкое "глубокое" сердце.
> **Updated 2026-04-29 (iter 4):** /9 (≈10 BPM peak), pause = stream_paused via PAUSABLE process_mode (flip earlier decision).
> **Updated 2026-04-29 (iter 5):** /18 (≈5 BPM peak, sub-bass rumble), linear ease вместо quadratic, in-range volume floor −36 dB → heartbeat audible через весь cap 50→10 (плато t² делало звук неслышимым на cap 30-50).

> **Updated 2026-04-28:** mapping переключён со `speed_ratio` на `cap_ratio = velocity_cap / 100`.
> Speed_ratio mapping выдавал max BPM/volume при старте игры (player stationary, current_speed=0
> даёт speed_ratio=0) — даже при cap=80 (полное здоровье) heartbeat бил в максимум. Cap-based
> mapping корректно представляет danger как эрозию cap'а, не как моментальную неподвижность.

BPM-to-pitch_scale: AudioStreamPlayer не умеет в tempo, используем pitch_scale.
Если исходный файл записан при BPM_base = 60:
```
pitch_scale = target_bpm / bpm_base
```
- cap_ratio = 1.0 (cap=100, выше respawn cap 80) → нет heartbeat (mute)
- cap_ratio = 0.80 (respawn cap, "полное здоровье") → mute (≥ 0.45)
- cap_ratio = 0.45 (cap=45) → BPM 60, vol −18 dB (едва слышно, подпороговая тревога)
- cap_ratio = 0.15 (cap=15) → BPM 110, vol −8 dB (явно слышно, паника)
- cap_ratio ≤ 0.0 (cap=0, смерть) → BPM 110, vol −8 dB (максимум)

Кривая pitch_scale по cap_ratio: линейный lerp между (0.45, 1.0) и (0.15, 1.833).
При cap_ratio ≥ 0.45 — volume_db = −80 dB (за порогом слышимости).
Плавный tween volume: 0.4 сек при изменении cap_ratio.

Pitch variance = 0%: ритм — единственный parameter, рандомить нельзя или потеряем
физиологическую реакцию на ускорение/замедление BPM.

**6. drain-warning**

Spectrally под heartbeat'ом: целевая частота 80–200 Hz (sub-bass пульс). Heartbeat сидит
в 300–1500 Hz (lub-DUB). Drain-warning должен проходить через headphones как физическое
давление в грудь, не конкурировать с heartbeat по полосе. Volume −14 dB: тихий, угрожающий
фон — не alarm, а "земля уходит из-под ног". Loop от drain_started до drain_stopped.
Attack 300 мс: постепенный вход, не резкий страт (это подчёркивает что drain — нарастающая
угроза, не мгновенная смерть). Pitch variance 0%: пульс должен быть постоянным.

**7. ambient**

Sci-fi hum −12 dB постоянный loop. Low-pass filter уже висит на Ambient bus с M2
(cutoff 8kHz → 1.2kHz при низком speed_ratio). M5 только добавляет файл и start при
run_started. Volume −12 dB: фоновый ковёр, не должен забивать SFX. При death →
fade out за 1.8 сек (совпадает с death animation, §3).

**8. melee-spawn**

3D с unit_size 16.0 (больше чем hit-impact) — low-freq thud должен "пробивать через стены".
Физически: низкие частоты распространяются дальше, это mimics реальность. Volume −2 dB:
громкий, почти наравне с kill-confirm — melee враг опасен в ближнем бою, его появление
должно читаться через cover. Частотный характер: основная энергия 50–200 Hz, это "thud земли".
Unit_size 16.0 означает что spawn за стеной на 12 units будет слышен — это информация для
игрока ("ближний враг появился за cover").

**9. shooter-spawn**

3D unit_size 14.0, тихий −10 dB. High whine (2–6 kHz): spectrally противоположен
melee-spawn. Игрок со временем разделяет два звука без UI (thud = melee, whine = shooter).
Pitch variance ±8%: shooter может спавниться группами, variance убирает machine-gun
feel множественных спавнов. Звук идентичен pre-attack windup шутера но −4..−6 dB тише —
это создаёт auditory continuity: "я уже слышал этот звук, теперь он громче = атакует".

---

## §2. Adaptive music spec

### Pressure metric

Рекомендация: **composite max из двух** источников.

```
pressure = max(
    1.0 - VelocityGate.speed_ratio(),        # momentary: замедлился — давление
    clampf(live_enemy_count / 20.0, 0.0, 1.0) # arena density
)
```

Почему не одиночные метрики:

- `1.0 - speed_ratio()` реагирует быстро но volatile: player сделал dash → pressure
  упала на кадр. Intensity layer скачет → раздражает.
- `live_enemy_count / 20` стабильна но инертна: на t=0 с 1 врагом intensity = 0.05
  даже если игрок умирает.
- `run_time / 600` — линейный рост без связи с действием, нарушает "управляемую панику"
  (тема игры — реактивность, не inevitable crescendo). Исключить как primary driver.

Composite max берёт лучшее из обоих: density даёт стабильный baseline, speed_ratio добавляет
reactivity на опасные моменты.

Окно сглаживания: tween pressure за 2.5 сек ease-in-out (не linear). Это предотвращает
jumpy музыку при кратких dash/kill-burst изменениях speed_ratio. 2.5 сек — минимум
для "не раздражающего" перехода в music mixing (DJ rule of thumb: <2 сек = jarring).

### Volume mapping

| Слой | Volume при pressure=0 | Volume при pressure=1 | Кривая |
|---|---|---|---|
| Base loop | 0 dB (всегда) | 0 dB (не меняется) | — |
| Intensity layer | −INF (silent, StreamPlayer.volume_db = −80) | 0 dB | ease-in (квадратичная) |

Intensity layer использует ease-in (квадратичная): при низком pressure он почти не слышен
(long plateau у нуля), нарастает резче в верхней части. Это соответствует gameplay-кривой —
бОльшую часть времени игрок держит среднее давление, intensity приходит в экстремальных
ситуациях.

Первый вход intensity: feel_spec §4 говорит "time_elapsed > 120 сек → tween-in за 30 сек".
Это остаётся как safety-gate: даже при нулевом давлении intensity включается после 2 минут
(игрок не может быть "расслаблен" бесконечно — это жанровый сигнал).

### Технически: AudioStreamPlayer, не шина

Base и Intensity — два отдельных AudioStreamPlayer (оба на Music bus). MusicDirector autoload
тикает `_process`, пересчитывает pressure, твинит `intensity_player.volume_db`. Нет сложных
AudioServer effects, нет BPM-sync в M5.

---

## §3. Ducking / Sidechain

### Kill-confirm duck

**Да, нужен.** Когда kill-confirm (0 dB, hi-freq crack) бьёт по ушам, music/ambient
создают "кашу" в этот момент. Classical mix trick: brief duck.

| Bus | Duck amount | Duration | Curve |
|---|---|---|---|
| Music | −6 dB | 180 мс | attack 0 мс, decay ease-out 180 мс |
| Ambient | −4 dB | 120 мс | attack 0 мс, decay ease-out 120 мс |
| Heartbeat | нет duck | — | kill = облегчение, heartbeat должен упасть органически через speed_ratio |

Реализация: в sfx.gd на Events.enemy_killed — одновременно с play kill-confirm запускается
tween на AudioServer.set_bus_volume_db() для Music и Ambient bus. Нет плагина sidechan,
просто ручной tween — достаточно для M5.

180 мс = длительность hit-stop (65 мс) + FOV punch decay (180 мс) совпадают по порядку
величины. Kill-confirm duck синхронизирован с визуальным "выдохом" — это усиливает единство
стека.

### Player death

На Events.player_died:

| Bus | Действие | Duration |
|---|---|---|
| Music | fade out −80 dB | 1.8 сек (= death animation) |
| Ambient | fade out −80 дб | 1.8 сек |
| SFX | немедленный stop всех playing streams | 0 мс |
| Heartbeat | fade out −80 dB | 0.6 сек (быстрее — сердце "останавливается") |
| Drain-warning | немедленный stop | 0 мс |

SFX bus глушится немедленно: после смерти gun-fire и hit-impact не должны заканчивать
свой decay — это создаёт "мусор" поверх death state. Музыка fade-out'ится медленно —
1.8 сек совпадает с death animation, игрок слышит как мир угасает.

На run_started (новый run): все bus'ы возвращаются к своим base volume мгновенно
(не нужен fade-in — арена уже активна, звук должен быть с первого кадра).

---

## §4. Settings hooks (M6)

### Рекомендованные слайдеры

| Слайдер | Bus | Диапазон | Default |
|---|---|---|---|
| Master | Master | 0–100% (−∞..0 dB) | 100% |
| Music | Music | 0–100% | 80% |
| SFX | SFX | 0–100% | 100% |
| Ambience | Ambient | 0–100% | 70% |
| Heartbeat / Warning | Heartbeat | 0–100% | 100% |

Heartbeat bus (содержит heartbeat + drain-warning) — отдельный слайдер обязателен. Есть
категория игроков с anxiety disorders / sensory sensitivity для которых постоянный
нарастающий heartbeat невыносим. Отдельный слайдер — accessibility win без архитектурного
оверхеда (шина уже выделена). Default 100% потому что эти звуки критичны для read'а
Velocity Gate — но игрок должен иметь выход.

Ambient отдельно от SFX: игрок может хотеть тихий фоновый hum (−12 dB и так, но если на
наушниках может мешать) не трогая громкость выстрелов.

Music отдельно от SFX: стандарт жанра. Default 80% а не 100% — adaptive intensity layer при
pressure=1 выходит на 0 dB относительно своего bus, но Music bus при 80% = −2 dB физически,
оставляет SFX headroom.

### Технически в M6

Все bus volume persist'ятся в `user://vgate_settings.cfg`. При старте: читаем cfg, применяем
через `AudioServer.set_bus_volume_db()`. Слайдеры в Settings menu напрямую маппятся на bus
index через `AudioServer.get_bus_index("Music")` и т.д. — нет промежуточных нормировок.

---

## Главный следующий шаг

**Первым делать: kill-confirm + duck.**

Логика: kill-burst — главный feel-чек игры (feel_spec §5). Audio слой этого события уже
размечен в M2 как "audio crack frame 0" но файла нет. Взять любой синтетический hi-freq
crack (sfxr / Chiptone), засунуть в kill-confirm slot, проверить синхрон с hit-stop.

Критерий "работает": войти в danger-зону (heartbeat слышен, FOV сужен) → убить врага →
crack бьёт одновременно с freeze → music/ambient на 180 мс проваливаются. Если в этот
момент физически выдыхаешь — стек работает. Если нет — добавляй "выдох" whoosh +30 мс поверх.

Всё остальное (adaptive music, spawn sounds, settings) вторично относительно этого
единственного feel-чека.
