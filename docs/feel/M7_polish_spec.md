# M7 Polish Feel Spec — VGate

Артефакт feel-engineer pass, 2026-04-30. Четыре nice-to-have эффекта из PLAN.md M7.
Статус: гипотеза-на-итерацию. Sub-параметры пивотируются после первого playtest'а
(per rule `feedback_feel_spec_pivot.md`). Pivot-точки явно размечены тегом **[PIVOT]**.

Зависимости:
- `docs/feel/feel_spec.md` — базовый must-стек (kill burst §2, dash §3)
- `docs/feel/M5_audio_spec.md` — audio bus топология, heartbeat BPM mapping, ducking

---

## Эффект 1 — Heavy Breath Audio

### Концепция

Тяжёлое дыхание — физиологический слой поверх heartbeat'а. Heartbeat работает от
`cap_ratio < 0.45` (M5_audio_spec §1.5). Дыхание добавляется глубже в danger-зоне —
cap < 0.25 — когда игрок реально умирает. Это не дублирование heartbeat'а, это
"второй голос тела": сердце бьётся быстро, а лёгкие уже не справляются.

Прецедент: Alien: Isolation — хрипящее дыхание Аманды при proximity AI, только когда
угроза максимальная; Hunt: Showdown — stamina-breath sync, physicality без annoying loop.

### Триггер

```
активация:  cap_ratio < 0.25  (velocity_cap < 25)
деактивация: cap_ratio > 0.30  (гистерезис +0.05 во избежание дёргания)
```

Гистерезис обязателен — без него на пороге 25 дыхание будет включаться/выключаться
по несколько раз в секунду при дрейфующем cap'е. Порог 0.25 ниже heartbeat-пика
(0.15 дальше усиливает) — зона "последние 25 единиц жизни".

### Числа

| Параметр | Значение | Rationale |
|---|---|---|
| Bus | Heartbeat | тот же bus что heartbeat — один слайдер для игрока выключает оба |
| Volume вход | −22 dB | тихий старт, не пугает |
| Volume пик | −10 dB | **[PIVOT]** слышен но не забивает heartbeat (heartbeat peak −6 dB) |
| Fade-in | 1.2 сек ease-in-quad | постепенное нарастание, не внезапное |
| Fade-out при kill | 0.8 сек ease-out | kill = выдох облегчения, дыхание уходит медленно, физиологично |
| Fade-out при death | 0.3 сек | быстрый fizzle при смерти |
| Loop | да | 3 варианта семпла, рандомно чередуются |
| Pitch variance между семплами | ±5% | **[PIVOT]** разнообразие без потери character'а |

Volume рамп по cap_ratio в зоне [0.25 → 0.00]:

```
t = (0.25 - cap_ratio) / 0.25        # 0.0 при cap=25, 1.0 при cap=0
breath_vol_db = lerp(-22, -10, t)    # [PIVOT] числа
```

Нет quadratic на этом лерпе — линейная кривая: breath нарастает плавно,
без "взрыва" в критической зоне (heartbeat уже создаёт urgency нелинейно).

### Частотный профиль — coexistence с heartbeat

Heartbeat (M5_audio_spec §1.5): основная энергия 300–1500 Hz (lub-DUB).
Drain-warning (§1.6): 80–200 Hz (sub-bass).
Breath: целевой диапазон **800–4000 Hz** — шипящий, воздушный характер.
Важно: breath-семпл не должен иметь низкочастотных гудений ниже 400 Hz —
иначе смажется с drain-warning. Asset gate: нужен семпл с выраженным
верхним шипением (aspirated, не guttural).

### Реализация-стратегия (Godot 4.6)

Ownership: расширение существующего audio-менеджера (тот же autoload/node что
управляет heartbeat). Не новый autoload — heartbeat и breath управляются из одного
места, потому что они шарят cap_ratio как входной сигнал и один bus.

Механизм:
- `AudioStreamPlayer2D` на Heartbeat bus, `process_mode = PROCESS_MODE_PAUSABLE`
  (по аналогии с heartbeat — pausable, per M5_audio_spec §1.5)
- Три семпла в `AudioStreamRandomizer` (Godot 4 встроенный) — случайный pick при
  каждом loop. Это убирает mechanical feel без кода.
- `_process` тикает: если cap_ratio пересёк 0.25 вниз — запустить fade-in tween;
  если поднялся выше 0.30 — fade-out tween. Tween пишет `volume_db` напрямую.
- Kill event (`Events.enemy_killed`): если breath активен — запустить 0.8 сек
  fade-out независимо от текущего cap (kill = выдох, даже если cap ещё низкий).
  Breath возобновится сам если cap не поднялся выше 0.30.

### Edge Cases

| Ситуация | Поведение |
|---|---|
| Пауза | `PROCESS_MODE_PAUSABLE` — стримы паузятся автоматически (как heartbeat) |
| Death | fade-out 0.3 сек → stop; на run_started — reset состояния |
| Kill при активном breath | 0.8 сек fade-out независимо от cap; возобновится если cap < 0.25 |
| Dash из danger-zone | breath не меняется в момент dash (dash не восстанавливает cap напрямую) |
| Kill chain активна (§3) | breath fade-out при каждом kill в chain; может быстро включаться обратно — это OK, это правильная tension |
| Kill burst ducking | M5_audio_spec §3: Music и Ambient duck'ятся на 180 мс при kill; Heartbeat bus (и breath) — не duck'ятся. Это корректно: breath/heartbeat должны быть слышны в момент облегчения |

### Asset Gate

Нужен аудио-семпл (3 варианта): aspirated тяжёлое дыхание, 1-3 сек лупабельный,
без музыкальных тонов, без эха. Источники: freesound.org (CC0 breath loops),
Sonniss GDC audio bundle (публичный). Синтез через Bfxr/sfxr не подходит —
дыхание должно быть органическим. **Флаг: требует ручного скаутинга.**

---

## Эффект 2 — Motion Blur

### Концепция

Radial/directional blur при высокой скорости — усиление feel'а velocity когда
игрок разогнан. В feel_spec §1 обозначен: "high ratio = легкий blur 2-4 px".
Но важно инвертировать базовую логику из feel_spec: blur здесь — это награда
за скорость, а не угроза. При низком cap уже работают FOV сужение + heartbeat.
Blur добавляется в HIGH-speed зоне, где игрок чувствует себя быстрым.

Прецедент: Doom Eternal — speed-based motion trail при dash; Ghostrunner —
directional blur в movement; Severed Steel — FOV + blur combo при wallrun.
Все три: blur короткий, не persistent, подчёркивает момент а не стоит постоянно.

### Триггер

```
активация blur:   speed_ratio > 0.75
деактивация blur: speed_ratio < 0.60   (гистерезис)

intensity = clamp((speed_ratio - 0.75) / 0.25, 0.0, 1.0)   # 0 при 0.75, 1 при 1.0
```

**[PIVOT]** Порог 0.75 выбран так чтобы blur не торчал постоянно (нормальный run
держит speed_ratio 0.4-0.7). Blur появляется только при спринте или сразу после dash.

### Числа

| Параметр | Значение | Rationale |
|---|---|---|
| Blur strength max | 0.8 (normalized 0..1 шейдер-параметр) | **[PIVOT]** легкий, не агрессивный |
| Blur strength при speed_ratio=0.75 | 0.0 |  |
| Blur strength при speed_ratio=1.0 | 0.8 | **[PIVOT]** |
| Ramp speed | tween 0.12 сек ease-out при нарастании | быстрый старт, не "включатель" |
| Fade speed | tween 0.20 сек ease-in при угасании | медленнее чем нарастание — момент скорости "задерживается" |
| Samples (если screen-space) | 8 | **[PIVOT]** баланс quality/performance |
| Тип blur | radial от center экрана | tunneling effect; directional blur (motion vector) — сложнее, radial достаточно |

### Реализация-стратегия (Godot 4.6)

**Вариант A (рекомендуемый) — CompositorEffect + GLSL шейдер:**

Godot 4.3+ имеет `CompositorEffect` — screen-space post-process без GDNative.
Radial blur через шейдер: для каждого пикселя сэмплируем несколько точек по
вектору от пикселя к центру экрана, усредняем. Параметр `blur_strength` пишется
из GDScript через `ShaderMaterial.set_shader_parameter()`.

Структура:
- `WorldEnvironment` или `Camera3D` добавляется `Compositor` с кастомным
  `CompositorEffect` ресурсом
- Шейдер-параметр `blur_strength: float` (uniform)
- Autoload `SpeedEffectsManager` (или добавить в существующий feel-manager)
  тикает в `_process`, читает `VelocityGate.speed_ratio()`, вычисляет target
  intensity, пишет в шейдер через tween

**Вариант B — SubViewport + screenspace texture overlay:**
Более простой но с overhead SubViewport. Не рекомендуется если Compositor доступен.

**Вариант C — встроенный MotionVector + TAA:**
Godot 4.x TAA имеет motion blur как side-effect при быстром движении, но
контролируется слабо и не параметризуем из GDScript. Не подходит.

Вариант A — правильный путь. **Флаг: нужна проверка что CompositorEffect доступен
в Godot 4.6 (не только 4.3+). godot-engineer проверяет при старте имплементации.**

### Toggle Support (см. Meta §)

Motion blur — единственный из 4 эффектов который ОБЯЗАТЕЛЬНО имеет toggle в Settings.
Причина: у части игроков вызывает дискомфорт / motion sickness. PLAN.md M6 явно
упоминает "motion blur toggle" в settings. Реализуется через `blur_strength` = 0.0
при toggle off (шейдер работает но strength=0 = no-op).

### Edge Cases

| Ситуация | Поведение |
|---|---|
| Пауза | `Compositor` работает в pause? Нужна проверка. Fallback: писать strength=0 на pause-entered signal |
| Death | на `Events.player_died` — strength → 0.0 немедленно (без tween); смерть не должна размываться |
| Dash | dash резко поднимает speed_ratio → blur вспыхивает после dash одновременно с FOV stretch. Это желательно: визуальное подтверждение скорости burst'а |
| Kill burst + time_scale | time_scale=0.3 во время time-dilation (feel_spec §2): blur в этот момент не меняется (он про скорость, не про kill). При snap обратно — speed_ratio поднимается если kill дал momentum → blur может появиться. Это OK |
| Settings toggle mid-run | немедленное применение (strength=0.0 без tween) |
| Performance | 8 samples на 1080p: ~0.3 мс overhead. При 60 FPS цели — приемлемо. **[PIVOT]** если frame time критичен — reduce samples до 4 |

---

## Эффект 3 — Kill Chain

### Концепция

3+ kills за 3 сек — визуальный/камерный flair, награда за combo-momentum. Kill chain
убирается из feel_spec §2 ("kill chain — nice-to-have post-M2"), теперь реализуется.

Важно: kill chain НЕ должна конкурировать с kill burst (feel_spec §2 — главная
транзакция игры). Kill burst — per-kill, всегда. Kill chain — метауровень поверх,
добавочный слой. Если chain случается, kill burst отрабатывает как обычно,
потом chain flair накладывается сверху.

Прецедент: ULTRAKILL style-meter (S/SS/SSS rank flash), Hades — kill-streak
voice line + visual flash, Devil Daggers — нет explicit chain но momentum музыка.

### Триггер

```
chain_window = 3.0 сек
chain_threshold = 3 убийства в chain_window

chain_counter инкрементируется при каждом kill
chain_timer сбрасывается (рестартует 3 сек) при каждом kill
если chain_timer истёк — chain_counter = 0

flair активируется при: chain_counter == 3 (первый раз)
                        chain_counter == 5 (эскалация)
                        chain_counter == 7+ (максимальная эскалация)
```

Три ступени: 3-kill trigger, 5-kill escalation, 7+ maximum. Не бесконечная
линейная шкала — три уровня проще читать и балансировать.

### Числа

#### Ступень 1 — Chain Start (3 kills)

| Слой | Параметры | Rationale |
|---|---|---|
| FOV punch | +8° мгновенно → возврат 250 мс ease-out-cubic | половина kill burst punch (+15°) — добавочный, не замена |
| Camera roll | ±1.5° за 100 мс → возврат 200 мс ease-out | **[PIVOT]** лёгкое "вскидывание", не тряска |
| Screen flash | белый overlay, opacity 0.12, duration 80 мс, ease-out | **[PIVOT]** едва заметный, подтверждение момента |
| Audio | pitch_scale kill-confirm +5% (чуть выше обычного) | тонкий "звон", не отдельный файл |

#### Ступень 2 — Chain Escalation (5 kills)

| Слой | Параметры |
|---|---|
| FOV punch | +12° → возврат 300 мс ease-out-cubic |
| Camera roll | ±2.5° за 120 мс → возврат 250 мс ease-out |
| Screen flash | opacity 0.20, duration 100 мс |
| Audio | kill-confirm pitch_scale +10% + отдельный synth chord stab −12 dB, 150 мс |
| **[PIVOT]** Particle burst | 8-12 частиц от hit-point, направление — от центра, lifetime 0.3 сек |

#### Ступень 3 — Chain Maximum (7+ kills)

| Слой | Параметры |
|---|---|
| FOV punch | +15° (наравне с kill burst, суммируется) → возврат 350 мс |
| Camera shake | amplitude 4 px, decay 0.25 сек (лёгкий, не агрессивный) |
| Screen flash | opacity 0.28, duration 120 мс, тёплый оттенок (золотистый) |
| Adaptive music | music pressure boost: принудительно поднять intensity_vol +3 dB на 2 сек |
| Audio | chord stab −8 dB + subtle reverb tail |

**[PIVOT]** Все визуальные числа (opacity flash, camera roll, particle count) — итерируются
после первого playtest. Базовые значения взяты от "едва заметно но читаемо".

### Взаимодействие с kill burst

Временная последовательность при kill в chain:

```
frame 0:   Events.enemy_killed
           → kill burst стартует (FOV +15°, hit-stop 65 мс, audio crack)
           → chain_counter++, chain_timer.restart()
frame 0:   если chain_counter достиг порога → chain flair запускается
           chain FOV punch добавляется ПОВЕРХ kill burst FOV punch
           итого FOV: +15° (burst) + +8°/+12°/+15° (chain) = +23°/+27°/+30°
           общий cap FOV: базовый + 30° максимум — далеко от motion sickness
           возврат chain punch начинается с 50 мс задержки (после hit-stop)
```

Hit-stop (65 мс freeze) применяется к enemy physics — chain flair идёт параллельно.
Нет конфликта с time_scale: chain flair — это camera/UI операции, не physics.

### Реализация-стратегия (Godot 4.6)

Ownership: новый lightweight autoload `KillChainManager` или метод в существующем
kill-event handler'е (зависит от текущей архитектуры sfx.gd / feel manager).

Механизм:
- Слушает `Events.enemy_killed`
- Внутренний counter + `Timer` (one-shot, 3 сек, restarts on each kill)
- При достижении пороговых значений — emit chain signal или напрямую вызвать
  camera/FOV methods
- FOV punch: через тот же механизм что kill burst FOV offset (аддитивный offset поверх base FOV)
- Camera roll: `Camera3D.rotation.z` tween — если камера уже обрабатывает roll
  из другого источника, нужна аддитивная система offsets (не перезапись)
- Screen flash: ColorRect overlay в CanvasLayer с tween opacity
- Audio chord: `AudioStreamPlayer2D` на SFX bus, отдельный файл или synth

### Edge Cases

| Ситуация | Поведение |
|---|---|
| Death во время chain | chain_counter = 0, timer stop; никакой chain flair на death |
| Пауза во время chain | Timer паузится (`process_mode = PAUSABLE`); при resume продолжает отсчёт |
| Chain при heartbeat активном | heartbeat продолжает (cap может быть низким даже при kill chain); это правильное tension |
| Breath audio при chain | каждый kill в chain triggering breath fade-out (0.8 сек); при быстрых kills chain дыхание будет быстро fade-out/fade-in — это OK, показывает rhythm kills |
| Kill burst + chain ступень 3 | FOV суммируется до +30°; приемлемо, возврат за 350 мс — не останется надолго |
| Toggle | если добавляется toggle — через Settings flag отключает chain flair полностью, counter продолжает работать (чтобы не ломать другую логику если она появится) |

### Asset Gate

Синтетический chord stab (ступени 2-3): sfxr / Chiptone достаточно. Это hi-freq
synth-bell, 100-200 мс, без decay tail. Можно сгенерировать на месте. Не требует
скаутинга живых записей.

---

## Эффект 4 — Dash Relief

### Концепция

Post-dash "выдох" — визуальный cue что dash отдан. Сейчас dash имеет FOV stretch
и camera push (feel_spec §3) — это forward momentum feel. Dash relief — другое:
это момент ПОСЛЕ burst'а, когда игрок "выдохнул" и dash уходит в cooldown.

Особенно значимо в контексте "dash спас" (feel_spec §3 — дыхание при выходе из
удушения): если dash поднял speed_ratio выше 0.4 из danger-зоны, relief должен
быть физиологически ощутим — облегчение симметричное угрозе heartbeat'а.

Прецедент: Celeste — каждый dash имеет чёткий audio+visual confirm; Titanfall 2 —
movement-as-relief через audio texture; Apex Legends — Octane stim exhale.

### Два режима (контекстный)

**Режим A — Normal dash (speed_ratio ≥ 0.4 на момент dash):**
Лёгкий trail + subtle glow. Подтверждение что dash произошёл, reward без drama.

**Режим B — Relief dash (speed_ratio < 0.4 на момент dash — выход из удушения):**
Более выраженный эффект. Dash из danger-зоны — это полноценный "спасительный
глоток воздуха". Аналог kill burst но через движение.

### Триггер

```
on Events.dash_started:
    if VelocityGate.speed_ratio() < 0.40:
        → Режим B (Relief)
    else:
        → Режим A (Normal)

post-dash check (через 0.5 сек после dash_started):
    if speed_ratio > 0.40 AND был Режим B:
        → дополнительный "exhale" audio подтверждение (see §audio)
```

### Числа — Режим A (Normal)

| Слой | Параметры | Rationale |
|---|---|---|
| Particle trail | 6-8 частиц, spawn в точке start dash, lifetime 0.35 сек, ease-out velocity | **[PIVOT]** лёгкий след движения |
| Trail color | синий/голубой, alpha 0.6 → 0 за lifetime | sci-fi эстетика |
| Particle size | 0.08–0.12 units | едва заметные точки, не "взрыв" |
| Audio | dash-whoosh уже реализован (M5_audio_spec §1.4) — Normal режим без изменений | — |
| Duration | particle system: 0.35 сек, потом stop | — |

### Числа — Режим B (Relief / из danger-зоны)

| Слой | Параметры | Rationale |
|---|---|---|
| Particle trail | 14-18 частиц, lifetime 0.5 сек | **[PIVOT]** заметнее, это событие |
| Trail glow intensity | emission energy 1.8 (vs 1.0 normal) | **[PIVOT]** светится |
| Trail color | яркий белый → голубой градиент | "вырвался из темноты" |
| FOV exhale | −3° от current FOV → возврат 0.4 сек ease-out | **[PIVOT]** лёгкое "сжатие → выдох" контраст к FOV stretch во время dash |
| Audio exhale | если через 0.5 сек speed_ratio > 0.40: shorter whoosh variant −6 dB, pitch −100 cents (ниже = расслабление), decay 300 мс | это "выдох" в отличие от dash "вдоха" |
| Heartbeat response | heartbeat.volume_db tween → −30 dB за 0.6 сек если cap_ratio улучшился | heartbeat уже реагирует на cap change; только accelerate fade если speed улучшился |
| Breath audio response | если breath активен (cap < 0.25): начать fade-out 1.2 сек | dash — потенциальный выход из danger |

**[PIVOT]** FOV exhale (−3°) — самое неочевидное число. Логика: dash даёт +12° stretch,
потом возврат. Если после возврата FOV ещё раз слегка "выдыхает" вниз на −3° и
возвращается — это создаёт двухтактный "вдох-выдох" ритм. Может быть лишним —
первый pivot-кандидат если ощущается как noise.

### Реализация-стратегия (Godot 4.6)

Ownership: расширение существующего dash-handler'а (тот же node/script что сейчас
обрабатывает FOV stretch + camera push при dash). Это минимальный overhead.

Механизм:
- На `Events.dash_started`: определить режим (A/B), запустить particle system
- Particles: `GPUParticles3D` прикреплён к player (или отдельный spawned node в
  world-space для trailing effect). `one_shot = true`, emit из player position,
  direction — инвертированный dash direction (след остаётся позади)
- `AudioStreamPlayer2D` для exhale audio (отдельный от dash-whoosh, чтобы не
  конфликтовал)
- Post-dash check: `Timer` 0.5 сек после dash_started → check speed_ratio →
  если Режим B и threshold пройден → play exhale audio

Частицы в Режиме A простые: `CPUParticles3D` достаточен (6-8 частиц дёшево).
Режим B: `GPUParticles3D` для glow/emission (MeshInstance3D с emission material).

### Edge Cases

| Ситуация | Поведение |
|---|---|
| Death во время dash | particle system stop немедленно; exhale audio не играть |
| Dash в стену (collision) | trail появляется в точке start, не destination — это корректно (trail от откуда, не куда) |
| Cooldown визуал | PLAN.md/feel_spec §3: cooldown viz через "recharge" click + bob amplitude restore — это остаётся отдельным слоем, не часть relief |
| Kill burst + relief dash параллельно | возможно при быстрой последовательности kill→dash. FOV offsets суммируются (kill +15°, dash +12°). Relief exhale добавит −3° после dash decay. Нет критического конфликта |
| Режим B → speed не поднялся выше 0.4 | exhale audio НЕ играет (post-dash check провален); trail уже отработал. Это правильно: dash не помог → нет облегчения |
| Пауза | exhale Timer паузится (PAUSABLE); при resume продолжает отсчёт |

### Asset Gate

Audio exhale — short whoosh variant на пониженном pitch. Если текущий dash-whoosh
(M5: legacy jump_b.ogg + pitch shift) пригоден — использовать его же с pitch −100 cents
и volume −6 dB. Не требует нового файла. Проверить звучание — если не подходит
как "выдох", нужен отдельный breathy-swoosh. **Низкий риск, не блокер.**

Particles: процедурные (GPUParticles3D материал), не спрайты. Никаких внешних assets.

---

## Meta-блок

### Приоритизация для Iter 1

Если из 4 нужно выбирать 1-2 первыми:

**Tier 1 (делать в iter 1):**

1. **Heavy Breath** — напрямую усиливает главный feel-чек игры (danger-zone → kill = выдох).
   Breath — это предпоследний слой перед смертью, усиливает urgency. Риск низкий
   (audio только), рефлекторная реакция у игрока физиологически мгновенная.
   Измеримо: войти в cap < 25 → слышишь дыхание поверх heartbeat → убил → выдохнул.

2. **Dash Relief** — усиливает второй по значимости verb (dash). "Dash спас" feedback
   из feel_spec §3 — уже отмеченный nice-to-have. Даёт closure dash'у которого
   сейчас нет (dash стартовал с whoosh, но нет подтверждения "я в безопасности").
   Риск низкий (particles + audio, ничего сложного).

**Tier 2 (iter 2, после плейтеста Tier 1):**

3. **Kill Chain** — высокая ценность для momentum feel, но требует отдельного manager'а
   и точной калибровки порогов. Если 3-kill порог слишком лёгкий — flair станет шумом.
   Если слишком редкий — не читается. Playtest нужен чтобы понять нужна ли эскалация
   вообще или достаточно одной ступени.

4. **Motion Blur** — самый технически сложный (CompositorEffect + GLSL). Toggle обязателен.
   Польза: feel скорости в high-speed зоне. Риск: performance, motion sickness у части
   аудитории. Делать последним — падение качества (убрать toggle off) не ломает игру.

### Toggle Recommendations

**Рекомендация: не добавлять индивидуальные toggles для всех 4 эффектов до playtest'а.**

Ратionale: PLAN.md M7 говорит "каждый эффект включается/выключается через Settings (M6)".
Это написано как желаемое, не как контракт. На данном этапе:

- **Motion Blur: обязательный toggle** — accessibility, motion sickness риск, уже
  упомянут в PLAN.md M6 settings. Реализовать сразу.
- **Heavy Breath: toggle через существующий Heartbeat bus slider** — если игрок
  опускает Heartbeat volume → breath тоже тихий. Отдельного toggle не нужно.
- **Kill Chain: нет toggle** до playtest'а. Если по фидбэку "раздражает" — добавить.
- **Dash Relief: нет toggle** — эффект скромный, не агрессивный. Нет accessibility concern.

Итого добавляемых toggles в Settings: **1 (Motion Blur — уже запланирован в M6)**.
Остальные 3 — по необходимости после playtest'а.

### Asset Gates Summary

| Эффект | Asset | Статус | Блокер? |
|---|---|---|---|
| Heavy Breath | 3× aspirated breath loop (CC0) | Требует скаутинга freesound.org / Sonniss | Да — без файла нельзя |
| Motion Blur | GLSL шейдер для CompositorEffect | Custom write (не внешний asset); Godot 4.6 compat проверить | Умеренный — нужна проверка API |
| Kill Chain | Synth chord stab | Генерировать через sfxr/Chiptone | Нет, 5 мин |
| Dash Relief | Exhale audio variant | Переиспользовать jump_b.ogg с pitch −100 cents | Нет |
| Dash Relief | Particle material (GPUParticles3D) | Процедурный, без внешних ассетов | Нет |

**Единственный блокирующий asset gate: breath audio samples.**
Motion Blur может быть заскейлирован до простого screen-space overlay если CompositorEffect
окажется несовместим с Godot 4.6 — не блокер, деградирует gracefully.

### Согласованность со стеком M5

| M5 элемент | Взаимодействие с M7 |
|---|---|
| Heartbeat Heartbeat bus (M5_audio_spec §1.5) | Breath добавляется на тот же bus — один volume slider |
| Kill-confirm duck (M5_audio_spec §3) | Duck'ит Music + Ambient, не Heartbeat bus — breath остаётся слышимым при kill. Корректно |
| Adaptive music pressure (M5_audio_spec §2) | Kill chain ступень 3 принудительно буст +3 dB intensity — временный override поверх pressure calc |
| Dash-whoosh audio (M5_audio_spec §1.4) | Dash Relief exhale использует тот же файл (jump_b.ogg) с другими параметрами — нет дублирования |
| FOV punch system (feel_spec §2) | Kill chain FOV punch аддитивен к kill burst FOV punch — нужна аддитивная система, не overwrite |
