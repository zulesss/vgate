# M9 Arena Specs — B (Плац) / A (Камера) / C (Шахта)

**Статус**: DRAFT — ожидает approve юзера перед impl-делегацией  
**Порядок unlock**: B → A → C  
**Текущая арена 40×40**: удаляется после того как все три finaliz'ированы  
**Engine constraint**: CSGBox3D / CSGCylinder3D через GDScript или scene-tree, Godot 4.6  

---

## Примечание по SpawnController

Текущий `spawn_controller.gd` hard-код'ит `expected 4 spawn points` и `POINT_WEIGHTS := {"S1":3,"S2":3,"S3":2,"S4":2}`.  
При impl'е арен B/A/C godot-engineer должен:  
1. Убрать размерный assert (заменить warning на flexible)  
2. Вынести `POINT_WEIGHTS` как `@export Dictionary` или сделать uniform weight-1 дефолт для точек без явного веса  
3. Переименовать точки в новых аренах S1–S8 (B), S1–S8 (A), S1–S8 (C) — имена попадут в `POINT_WEIGHTS` автоматически если сделать default weight  

---

## Coordinate system (все 3 арены)

- Origin `(0, 0, 0)` = **геометрический центр пола арены** на уровне поверхности (Y=0)  
- X = запад-восток (положительный → восток)  
- Z = север-юг (положительный → юг)  
- Y = вертикаль (положительный → вверх)  
- Floor CSGBox3D — top surface на Y=0, значит `position.y = -0.5` (высота 1u)  
- **Player spawn**: всегда в центре `(0, 0.9, 0)` — capsule center  
- Враги спавнятся на Y=0.9 (константа `SPAWN_Y` в SpawnController — не трогать)  

---

---

# ARENA B — "Плац"

**Character**: открытость, перекрёстный огонь, давление со всех сторон. Первая арена — учит читать пространство и важность velocity.

## 1. Footprint + Ceiling

| Параметр | Значение |
|---|---|
| Footprint | 50 × 50 units |
| Ceiling height | открытое небо (нет крыши) |
| Effective play area | ~46 × 46 (стены толщиной 1u с каждой стороны) |
| Max sightline diagonal | ~65u — shooter'ы на противоположных углах видят друг друга |

## 2. Origin / Player Spawn

- Origin `(0, 0, 0)` — геометрический центр пола  
- **Player spawn**: `(0, 0.9, 0)`  

## 3. Geometry Pieces

```
# FLOOR
Floor          CSGBox3D   pos=(0, -0.5, 0)         size=(50, 1, 50)   # основной пол

# WALLS — 4u высота (игрок не перепрыгивает, sightline срезается)
WallNorth      CSGBox3D   pos=(0, 2, -25.5)         size=(50, 4, 1)    # северная стена
WallSouth      CSGBox3D   pos=(0, 2, 25.5)          size=(50, 4, 1)    # южная стена
WallEast       CSGBox3D   pos=(25.5, 2, 0)          size=(1, 4, 50)    # восточная стена
WallWest       CSGBox3D   pos=(-25.5, 2, 0)         size=(1, 4, 50)    # западная стена

# LOW WALLS — 4 штуки, 1.2u высота (cover для player, не блокирует shooter sightline полностью)
# Расположены по диагональным осям от центра, образуют крест 45°
LowWallNE      CSGBox3D   pos=(8, 0.6, -8)          size=(6, 1.2, 1.5) # cover СВ-квадранта
LowWallNW      CSGBox3D   pos=(-8, 0.6, -8)         size=(1.5, 1.2, 6) # cover СЗ-квадранта (ротация: вдоль Z)
LowWallSE      CSGBox3D   pos=(8, 0.6, 8)           size=(1.5, 1.2, 6) # cover ЮВ-квадранта
LowWallSW      CSGBox3D   pos=(-8, 0.6, -8)         size=(6, 1.2, 1.5) # cover ЮЗ-квадранта — ИСПРАВЛЕНИЕ ниже

# ИСПРАВЛЕНИЕ SW: pos=(-8, 0.6, 8) size=(6, 1.2, 1.5)
LowWallSW      CSGBox3D   pos=(-8, 0.6, 8)          size=(6, 1.2, 1.5)
```

**Итог low walls — финальные координаты:**

| Имя | Position | Size | Ориентация |
|---|---|---|---|
| LowWallNE | (8, 0.6, -8) | (6, 1.2, 1.5) | вдоль X — горизонтальный барьер |
| LowWallNW | (-8, 0.6, -8) | (1.5, 1.2, 6) | вдоль Z — вертикальный барьер |
| LowWallSE | (8, 0.6, 8) | (1.5, 1.2, 6) | вдоль Z |
| LowWallSW | (-8, 0.6, 8) | (6, 1.2, 1.5) | вдоль X |

Четыре low wall образуют разомкнутый ромб вокруг центра. Между ними — проходы ~2u шириной. Игрок может быстро перебегать из укрытия в укрытие, набирая velocity, что активирует Velocity Gate hook.

**Никаких колонн, никаких высоких преград** — арена должна быть читаема с любой точки.

## 4. Spawn-Points — 8 штук, по периметру

Все на Y=0 (SpawnController добавит SPAWN_Y=0.9).

| Имя | Position | Primary enemy hint | Логика размещения |
|---|---|---|---|
| S1 | (0, 0, -23) | shooter | север, центр — дальний LOS на всю арену |
| S2 | (0, 0, 23) | shooter | юг, центр — зеркало S1 |
| S3 | (-23, 0, 0) | melee | запад, центр — боковая атака |
| S4 | (23, 0, 0) | melee | восток, центр — боковой |
| S5 | (-16, 0, -16) | swarm | СЗ угол — рой с фланга |
| S6 | (16, 0, -16) | swarm | СВ угол |
| S7 | (-16, 0, 16) | any | ЮЗ угол |
| S8 | (16, 0, 16) | any | ЮВ угол |

`POINT_WEIGHTS` рекомендация: S1=3, S2=3, S3=2, S4=2, S5=2, S6=2, S7=1, S8=1 (суммарно 16 — SpawnController не требует сумму=10, это внутренняя нормализация).

**MIN_SPAWN_DISTANCE** = 12.0 остаётся — от центра до периметра ~23u, все точки гарантированно >12u от старта.

## 5. NavMesh

- **Количество NavigationRegion3D**: 1 (flat арена, единое пространство)  
- **agent_radius**: 0.3 (capsule radius врагов — текущая арена использует 0.25, для B можно не менять)  
- **agent_height**: 1.8  
- **agent_max_climb**: 0.3  
- **agent_max_slope**: 45°  
- Source geometry group: `"navigation_geometry"` (Arena-нода + все children) — как в текущей arene  
- Edge cases: проходы между low walls ~2u — при agent_radius=0.3 проход 2.0u passable (2.0 > 2×0.3=0.6). Нет критичных узких мест.

## 6. Sightlines

```
ASCII (вид сверху, 50×50, упрощённо):

S1(N)
 |
 | ← полный LOS через центр → 
LW-NW . . . LW-NE
  .   center  .
LW-SW . . . LW-SE
 |
S2(S)

S3(W) ─────────────── S4(E)
         centre

S5 (NW угол) — частичный LOS на S6, S7, S8 через диагональ
```

**Критичные shooter позиции:**
- S1 и S2 — полный LOS на центр арены и на противоположный спавн. Два shooter'а на S1+S2 создают crossfire через центр. Игрок вынужден использовать low walls.
- S3/S4 — боковой LOS, пересекает center line. Shooter с S4 видит игрока прячущегося за LowWallNW.
- S5-S8 углы — ограниченный LOS из-за угла, хорошо для swarm (им LOS не нужен).

**Blind death risk**: минимальный — арена открытая, игрок из центра видит все 8 точек. Telegraph fade 250мс достаточен.

## 7. Visual Language

- **Цветовая палитра**: светло-серый бетон (`Color(0.72, 0.72, 0.72)`) для пола и стен. Low walls — темнее (`Color(0.45, 0.5, 0.55)`), подчёркивают структуру.
- **Ambient**: открытое небо, текущий skybox `empty_warehouse_01_1k.exr` работает.
- **Character**: военный плац, чистые линии, минимализм. Никаких украшений на этом этапе — placeholder-геометрия.
- Kenney/Quaternius ассеты — после finalize-pass, не блокируют impl.

## 8. Player Visibility / Readability

| Риск | Mitigation |
|---|---|
| Shooter с S1 стреляет пока игрок смотрит на S4 | LOS-based AI (уже реализован) — shooter не стреляет если нет LOS, нет. Риск реальный. | 
| Swarm с углового S5/S6 — игрок может не смотреть туда | Telegraph fade (уже есть) + ambient audio `melee_spawn.ogg` — достаточно для первой арены |
| Два shooter'а одновременно с S1+S2 — перекрёстный огонь | `MAX_LIVE_SHOOTERS = 4` и `SHOOTER_ANTI_CLUSTER_RADIUS = 8u` — S1 и S2 разнесены на 46u, anti-cluster не помешает обоим. Игрок должен двигаться — это core hook, а не blind death |

## 9. Estimated Impl Time

- Geometry (8 CSGBox3D + floor + 4 walls): **1.5–2 часа**
- 8 Marker3D spawn-points + SpawnController POINT_WEIGHTS update: **0.5 часа**
- NavigationRegion3D + NavBaker wiring: **0.5 часа**
- Тест bake + smoke: **0.5 часа**
- **Итого**: 3–3.5 часа impl, 1 час nav-tweak. Самая быстрая из трёх.

## 10. Playtest Checklist

1. **Velocity pressure**: набираешь ли ты velocity постоянно, или стоишь за low wall? Если >30 сек стоишь — арена слишком "безопасная", нужно сдвинуть low walls ближе к центру.
2. **Crossfire читаемость**: понимаешь ли, откуда прилетел урон? Есть ли ощущение "два сразу с разных сторон" (это желаемое)?
3. **Shooter периметр**: держат ли shooter'ы периметр или сразу прут в melee? (Должны держать дистанцию ≥10u если LOS есть.)
4. **Угловые спавны S5-S8**: успеваешь ли среагировать на рой из угла, или первый урон всегда неожиданный?
5. **Открытость vs скука**: на 5-й минуте арена ещё интересная или ощущается как "беги по кругу"?

---

---

# ARENA A — "Камера"

**Character**: клаустрофобия, потеря ориентации, дефицит пространства. Вторая арена — проверяет, умеет ли игрок управлять velocity в стеснённых условиях.

## 1. Footprint + Ceiling

| Параметр | Значение |
|---|---|
| Footprint | 26 × 26 units (внешние стены) |
| Ceiling | закрытый потолок, высота 3.5u (создаёт ощущение давления) |
| Hub (центр) | 8 × 8 units — единственное "открытое" пространство |
| Комнаты | 8 штук, 4×4 каждая, расположены по периметру хаба |
| Коридоры | 2u шириной, 3u длиной, соединяют хаб с каждой комнатой |
| Dead-end corners | 4 штуки — угловые комнаты без выхода (кроме как через хаб) |

**Принципиальная схема**: крест-пространство. Хаб = ядро. 4 "основных" комнаты по осям (N/S/E/W) — по 1 выходу каждая. 4 угловых dead-end — ловушки.

## 2. Origin / Player Spawn

- Origin `(0, 0, 0)` — центр хаба (пола)
- **Player spawn**: `(0, 0.9, 0)` — в хабе

## 3. Geometry Pieces

Полный пол — один большой CSGBox3D минус коридорные проёмы нельзя сделать через CSG вычитанием в ноде (нужен CSGCombiner3D). Вместо этого: пол из 9 отдельных Box'ов (хаб + 8 комнат + 8 коридорных полов).

**Однако**: проще сделать **сплошной пол 26×26** и поставить стены как CSGBox3D-ами сверху. Коридоры образуются за счёт отсутствия стен на нужных сторонах. Потолок — один CSGBox3D 26×26.

```
# СТРУКТУРНЫЕ ЭЛЕМЕНТЫ

# Пол и потолок
Floor          CSGBox3D   pos=(0, -0.5, 0)          size=(26, 1, 26)    # сплошной пол
Ceiling        CSGBox3D   pos=(0, 3.5, 0)            size=(26, 0.5, 26)  # потолок

# Внешние стены (высота 4u — от пола до потолка)
WallNorth      CSGBox3D   pos=(0, 1.75, -13)         size=(26, 3.5, 0.5)
WallSouth      CSGBox3D   pos=(0, 1.75, 13)          size=(26, 3.5, 0.5)
WallEast       CSGBox3D   pos=(13, 1.75, 0)          size=(0.5, 3.5, 26)
WallWest       CSGBox3D   pos=(-13, 1.75, 0)         size=(0.5, 3.5, 26)
```

**Внутренняя геометрия** — стены разделяют пространство на хаб + комнаты + коридоры. Принцип: хаб `(-4..+4, z: -4..+4)`. Внутренние стены — только там, где нет прохода.

```
# Внутренние стены (толщина 0.5u, высота 3.5u)
# Схема: хаб 8×8 центр + 8 комнат 4×4 + 8 коридоров 2×3

# Угловые блоки (мёртвые комнаты) — SOLID прямоугольники внутри, образованы
# пересечением 4 внутренних стен. Проще: объявить внутренние стены секциями.

# Северная секция (между хабом и северными комнатами)
InnerWall_N_W  CSGBox3D   pos=(-7, 1.75, -4)         size=(6, 3.5, 0.5)  # западная часть северной стены хаба
InnerWall_N_E  CSGBox3D   pos=(7, 1.75, -4)          size=(6, 3.5, 0.5)  # восточная часть — проход [-1..+1] Z=-4

# Южная секция
InnerWall_S_W  CSGBox3D   pos=(-7, 1.75, 4)          size=(6, 3.5, 0.5)
InnerWall_S_E  CSGBox3D   pos=(7, 1.75, 4)           size=(6, 3.5, 0.5)

# Западная секция
InnerWall_W_N  CSGBox3D   pos=(-4, 1.75, -7)         size=(0.5, 3.5, 6)
InnerWall_W_S  CSGBox3D   pos=(-4, 1.75, 7)          size=(0.5, 3.5, 6)

# Восточная секция
InnerWall_E_N  CSGBox3D   pos=(4, 1.75, -7)          size=(0.5, 3.5, 6)
InnerWall_E_S  CSGBox3D   pos=(4, 1.75, 7)           size=(0.5, 3.5, 6)

# Угловые заполнения (dead-end стены): 4 corners
# СЗ угол: внутренний прямоугольный блок [-13..-4, z: -13..-4]
# Образован внешними стенами N и W + InnerWall_W_N + InnerWall_N_W
# Вход в dead-end corner = нет. Но нам нужны сами комнаты как пространство (не solid).

# DEAD-END комнаты: 4×4, доступ ТОЛЬКО через узкий проход 2u шириной
# Проход в dead-end ОТСУТСТВУЕТ — это ловушка. Враги могут зайти, игрок тоже,
# но выход один — назад через хаб.

# Дополнительные разделяющие стены для dead-end углов:
CornerWall_NW_E  CSGBox3D  pos=(-5, 1.75, -10)       size=(0.5, 3.5, 6)  # восточная стена СЗ dead-end
CornerWall_NW_S  CSGBox3D  pos=(-10, 1.75, -5)       size=(6, 3.5, 0.5)  # южная стена СЗ dead-end
CornerWall_NE_W  CSGBox3D  pos=(5, 1.75, -10)        size=(0.5, 3.5, 6)  # западная стена СВ dead-end
CornerWall_NE_S  CSGBox3D  pos=(10, 1.75, -5)        size=(6, 3.5, 0.5)  # южная стена СВ dead-end
CornerWall_SW_E  CSGBox3D  pos=(-5, 1.75, 10)        size=(0.5, 3.5, 6)
CornerWall_SW_N  CSGBox3D  pos=(-10, 1.75, 5)        size=(6, 3.5, 0.5)
CornerWall_SE_W  CSGBox3D  pos=(5, 1.75, 10)         size=(0.5, 3.5, 6)
CornerWall_SE_N  CSGBox3D  pos=(10, 1.75, 5)         size=(6, 3.5, 0.5)
```

**Итоговая plan-схема пространства (вид сверху):**
```
  W=-13        W=-4   W=-1  W=+1   W=+4        W=+13
  ┌────────────┬───┬──┬──┬───┬────────────┐  Z=-13
  │  DEAD NW   │   │  │  │   │  DEAD NE  │
  │   (trap)   │   │  │  │   │  (trap)   │
  │            ├───┘  │  └───┤            │  Z=-4
  │            │      │      │            │
  ├────────────┤   HUB 8×8   ├────────────┤  Z= 0
  │            │      │      │            │
  │            ├───┐  │  ┌───┤            │  Z=+4
  │  DEAD SW   │   │  │  │   │  DEAD SE  │
  │   (trap)   │   │  │  │   │  (trap)   │
  └────────────┴───┴──┴──┴───┴────────────┘  Z=+13
```

Коридоры (2u ширина) образуются автоматически — промежутки между парными внутренними стенами по осям N/S/E/W.

**Проход N**: X=[-1..+1], Z=-4 (между InnerWall_N_W и InnerWall_N_E)  
**Проход S**: X=[-1..+1], Z=+4  
**Проход W**: X=-4, Z=[-1..+1]  
**Проход E**: X=+4, Z=[-1..+1]  

Dead-end corners доступны через боковые коридоры вдоль периметра — или НЕТ (если закрыть CornerWall'ами полностью). **Решение**: dead-end комнаты доступны через коридоры от осевых комнат. Иначе это просто unusable space и nav-baker их проигнорирует.

**Финальная корректировка dead-end**: между осевой комнатой и угловой — проход 2u. Добавляем 4 коридорных прохода:

```
# Коридоры в dead-end: от осевой Western room к NW/SW dead-ends
# Western осевая комната: X=[-13..-5], Z=[-1..+1]
# NW dead-end: X=[-13..-5], Z=[-13..-5]
# Проход между ними: X=[-8..-6], Z=[-5..-4] → убрать CornerWall_NW_S на этом участке

# Пересмотр: dead-end corner'ы имеют ОДИН вход с боку осевой комнаты
# Ширина прохода 2u: X=[-8..-6] для NW dead-end южной стены
CornerWall_NW_S_left   CSGBox3D  pos=(-11.5, 1.75, -5)  size=(3, 3.5, 0.5)  # X: -13..-10
CornerWall_NW_S_right  CSGBox3D  pos=(-6.5, 1.75, -5)   size=(1, 3.5, 0.5)  # X: -7..-6 (блокирует кроме прохода -8..-6)
# (CornerWall_NW_S заменяется двумя частями — проход X=[-8..-6])

# Аналогично для SW, NE, SE dead-ends
# SW: проход через CornerWall_SW_N, X=[-8..-6]  
# NE: проход через CornerWall_NE_S, X=[+6..+8]
# SE: проход через CornerWall_SE_N, X=[+6..+8]
```

Это усложняет impl. **Альтернатива**: убрать dead-end entirely (4 угловые "ниши" просто недоступны = пустая геометрия), сделать вместо них **4 open alcove** (ниши 3×3 без закрытых стен). Это проще и сохраняет character клаустрофобии.

**Рекомендация**: dead-end реализовать как **alcove** — открытая ниша без потолочного перекрытия с трёх сторон, один выход в хаб. Так nav-baker покроет их без хирургии.

### Упрощённая финальная геометрия A (версия для impl):

```
# FLOOR + CEILING
Floor     CSGBox3D  pos=(0, -0.5, 0)   size=(26, 1, 26)
Ceiling   CSGBox3D  pos=(0, 3.75, 0)   size=(26, 0.5, 26)

# ВНЕШНИЕ СТЕНЫ
WallN     CSGBox3D  pos=(0, 1.75, -13)   size=(26, 3.5, 0.5)
WallS     CSGBox3D  pos=(0, 1.75, 13)    size=(26, 3.5, 0.5)
WallE     CSGBox3D  pos=(13, 1.75, 0)    size=(0.5, 3.5, 26)
WallW     CSGBox3D  pos=(-13, 1.75, 0)   size=(0.5, 3.5, 26)

# ВНУТРЕННИЕ СТЕНЫ — 8 секций, образуют хаб + оси + alcove углы
# Северная ось — стена хаба Z=-4, с проходом X=[-1..+1]
InWall_N1 CSGBox3D  pos=(-6, 1.75, -4)   size=(8, 3.5, 0.5)   # X: -10..-2
InWall_N2 CSGBox3D  pos=(6, 1.75, -4)    size=(8, 3.5, 0.5)   # X: +2..+10

# Южная ось — Z=+4, проход X=[-1..+1]
InWall_S1 CSGBox3D  pos=(-6, 1.75, 4)    size=(8, 3.5, 0.5)
InWall_S2 CSGBox3D  pos=(6, 1.75, 4)     size=(8, 3.5, 0.5)

# Западная ось — X=-4, проход Z=[-1..+1]
InWall_W1 CSGBox3D  pos=(-4, 1.75, -6)   size=(0.5, 3.5, 8)
InWall_W2 CSGBox3D  pos=(-4, 1.75, 6)    size=(0.5, 3.5, 8)

# Восточная ось — X=+4, проход Z=[-1..+1]
InWall_E1 CSGBox3D  pos=(4, 1.75, -6)    size=(0.5, 3.5, 8)
InWall_E2 CSGBox3D  pos=(4, 1.75, 6)     size=(0.5, 3.5, 8)

# ALCOVE-РАЗДЕЛИТЕЛИ: отсекают углы от осевых комнат
# Образуют 4 угловые ниши: NW/NE/SW/SE, каждая ~4×4
# Доступ из осевых комнат через проём 2u

# NW alcove: вход из Western room, проём Z=[-9..-7]
AlcoveWall_NW CSGBox3D  pos=(-9, 1.75, -9)   size=(8, 3.5, 0.5)  # южная стена NW ниши, X: -13..-5 (без проёма — ниша открыта снизу)

# Проще: вместо 4 отдельных alcove-разделителей —
# поставить только КОРОТКИЕ боковые стены, которые создают тактический "закуток"
# без полного закрытия. Character dead-end сохраняется (1 выход) без хирургии.

AlcWall_NW CSGBox3D  pos=(-8.5, 1.75, -8.5)  size=(0.5, 3.5, 8)  # вертикальная стена алькова NW
AlcWall_NE CSGBox3D  pos=(8.5, 1.75, -8.5)   size=(0.5, 3.5, 8)  # аналог NE
AlcWall_SW CSGBox3D  pos=(-8.5, 1.75, 8.5)   size=(0.5, 3.5, 8)
AlcWall_SE CSGBox3D  pos=(8.5, 1.75, 8.5)    size=(0.5, 3.5, 8)
```

**Итог структуры A**: Хаб 8×8 в центре. 4 осевых коридора 2u×3u. Условные угловые ниши, ограниченные одной внутренней стеной. Пространство тесное, sightlines короткие (max 12u через хаб).

## 4. Spawn-Points — 8 штук

| Имя | Position | Primary enemy hint | Логика |
|---|---|---|---|
| S1 | (0, 0, -11) | shooter | северная осевая комната — дальний конец, LOS через коридор в хаб |
| S2 | (0, 0, 11) | shooter | южная осевая комната |
| S3 | (-11, 0, 0) | melee | западная осевая комната |
| S4 | (11, 0, 0) | melee | восточная осевая комната |
| S5 | (-10, 0, -10) | swarm | NW alcove — ловушка угла |
| S6 | (10, 0, -10) | swarm | NE alcove |
| S7 | (-10, 0, 10) | any | SW alcove |
| S8 | (10, 0, 10) | any | SE alcove |

**Важно**: S5-S8 в alcove'ах — если игрок зашёл в угол и там спавнится рой, это **intended pressure**. Это сознательная ловушка второй арены.

## 5. NavMesh

- **NavigationRegion3D**: 1 единственный  
- **agent_radius**: 0.3  
- **agent_height**: 1.8  
- **agent_max_slope**: 5° (flat)  
- **КРИТИЧНО**: коридоры 2u ширина. Passability check: 2.0u - 2×agent_radius(0.3) = 1.4u clearance. Melee (capsule ~0.5u diameter) — пройдёт. Swarmling (capsule ~0.3u) — пройдёт. Shooter — пройдёт.  
- **Edge case**: потолок 3.5u, agent_height 1.8u — OK. При bake нужно убедиться что ceiling не обрезает nav-mesh сверху (geometry_parsed_geometry_type=0 STATIC_COLLIDERS — потолок CSGBox3D с `use_collision=true` будет в bake как overhead obstacle, это правильно).  
- Source group `"navigation_geometry"` — вся Arena-нода.

## 6. Sightlines

```
Hub = central 8×8. Max sightline внутри хаба: ~11u по диагонали.
Shooter в S1 видит коридорный проём (Z=-4, X=[-1..+1]) — ширина LOS 2u.
Через коридор в хаб: LOS = ~7u (коридор 3u + половина хаба 4u = 7u).
Shooter НЕ видит игрока прячущегося за InWall_N1/N2 — стены хаба блокируют.

Критичные sightlines:
- S1 → коридор N → хаб: 7u, ширина 2u — shooter с S1 держит вход в N-коридор
- S3 → коридор W → хаб: аналогично
- Внутри хаба: диагональный LOS ~11u, нет укрытия — хаб = danger zone
- Alcove'ы: нет LOS наружу (закрыты с 3 сторон) — shooter бесполезен в alcove
```

Shooter'ы эффективны только в осевых комнатах и хабе. Это правильно — дефицит пространства лишает shooter'а дальнобойного преимущества.

## 7. Visual Language

- **Потолок**: `Color(0.3, 0.3, 0.35)` — тёмный, давящий  
- **Стены**: `Color(0.4, 0.42, 0.45)` — темнее чем B (контраст арен читается с первой секунды)  
- **Пол**: `Color(0.5, 0.5, 0.52)` — нейтральный  
- **Хаб vs коридоры**: визуально не разделяются геометрией — только давление от потолка. Это сознательно: игрок должен чувствовать сжатие постоянно.

## 8. Player Visibility / Readability

| Риск | Mitigation |
|---|---|
| Blind death из alcove | Telegraph audio `melee_spawn.ogg` слышно через стену. 250мс fade. Приемлемо — это second arena, игрок уже знает telegraph |
| Shooter стреляет через коридор пока игрок в хабе | LOS check работает. Ширина коридора 2u — shooter должен иметь прямую линию. Это correct behaviour — учит не стоять в хабе |
| Два melee с S3+S4 одновременно — зажимают в хабе | Shooter anti-cluster не покрывает melee. Это нормально — хаб = pressure zone |

## 9. Estimated Impl Time

- Геометрия (4 внешних + 8 внутренних + 4 alcove стен + потолок + пол): **3–4 часа** (больше стен чем в B, требуют точной координации)
- Spawn-points + SpawnController: **0.5 часа**
- NavMesh bake + corridor passability check: **1.5–2 часа** (коридоры 2u — нужно визуально верифицировать что nav покрывает их)
- **Итого**: 5–6.5 часов impl, 2 часа nav-tweak.

## 10. Playtest Checklist

1. **Клаустрофобия**: ощущается ли давление от низкого потолка и тесных коридоров в первые 30 секунд?
2. **Хаб как danger zone**: стараешься ли ты избегать хаба (открытое пространство + shooter LOS со всех 4 осей)?
3. **Alcove-ловушки**: попадаешь ли в dead-end и успеваешь ли выйти? Слишком часто → убери S5-S8 из alcove'ов.
4. **Velocity в коридорах**: успеваешь ли набрать velocity gate в пространстве 2u ширина, или gate рушится каждые 3 секунды?
5. **Читаемость после B**: кажется ли A принципиально другой аренкой, или "просто маленькая B"?

---

---

# ARENA C — "Шахта"

**Character**: вертикальность, асимметрия, позиционная игра. Третья арена — проверяет полное владение hook'ом в 3D-пространстве с tier-transitions.

## 1. Footprint + Ceiling

| Параметр | Значение |
|---|---|
| Footprint | 38 × 38 units (внешние стены) |
| Main tier (Y=0) | основной уровень, ~30×30 playable area |
| Mezzanine tier (Y=+4) | 4u над main, периметральные балки/площадки, ~8u ширина каждая |
| Pit tier (Y=-3) | 4 ямы, каждая 6×6, углублены на 3u |
| Ceiling | открытый на main/mez, шахтный колодец визуально — нет крыши |
| Mezzanine ceiling | нет отдельного — mez открыт сверху |

## 2. Origin / Player Spawn

- Origin `(0, 0, 0)` — centre main tier
- **Player spawn**: `(0, 0.9, 0)` — центр main tier

## 3. Geometry Pieces

```
# ═══════════════ MAIN TIER (Y=0) ═══════════════

# Основной пол — без ям (они вырезаются позиционированием, а не CSG subtract)
# Пол 38×38 с 4 "отверстиями" — реализуем как 5 частей: центр + 4 L-shaped секции
# НО CSG не умеет вычитать без CSGCombiner3D.
# Проще: 9-patch пол (3×3 сетка 38×38, убираем 4 угловые ячейки под ямы)

# Центральная часть пола (без ям)
Floor_Center    CSGBox3D  pos=(0, -0.5, 0)       size=(22, 1, 22)   # 22×22 центр без ям

# Боковые полосы между ямами (E-W)
Floor_N         CSGBox3D  pos=(0, -0.5, -14)      size=(22, 1, 8)    # N полоса между ямами
Floor_S         CSGBox3D  pos=(0, -0.5, 14)       size=(22, 1, 8)    # S полоса
Floor_W         CSGBox3D  pos=(-14, -0.5, 0)      size=(8, 1, 22)    # W полоса
Floor_E         CSGBox3D  pos=(14, -0.5, 0)       size=(8, 1, 22)    # E полоса

# Итого main пол: крест 22+8=30u по осям, углы (8×8) — открыты (ямы)

# ═══════════════ PIT TIER (Y=-3) ═══════════════
# 4 ямы в углах, каждая 8×8 footprint, дно на Y=-3.5 (пол ямы 1u толщина)
# Координаты центров ям: (±14, *, ±14)

PitFloor_NW     CSGBox3D  pos=(-14, -3.5, -14)    size=(8, 1, 8)     # дно NW ямы
PitFloor_NE     CSGBox3D  pos=(14, -3.5, -14)     size=(8, 1, 8)     # дно NE ямы
PitFloor_SW     CSGBox3D  pos=(-14, -3.5, 14)     size=(8, 1, 8)     # дно SW ямы
PitFloor_SE     CSGBox3D  pos=(14, -3.5, 14)      size=(8, 1, 8)     # дно SE ямы

# Стены ям (внутренние — 3u высота от Y=-3 до Y=0)
# Каждая яма окружена 4 стенами. Внешние стены арены уже закрывают 2 грани угловых ям.
# Нужны только ВНУТРЕННИЕ 2 грани (обращённые к centre floor)

PitWall_NW_E    CSGBox3D  pos=(-10, -1.5, -14)    size=(0.5, 3, 8)   # восточная стена NW ямы
PitWall_NW_S    CSGBox3D  pos=(-14, -1.5, -10)    size=(8, 3, 0.5)   # южная стена NW ямы

PitWall_NE_W    CSGBox3D  pos=(10, -1.5, -14)     size=(0.5, 3, 8)
PitWall_NE_S    CSGBox3D  pos=(14, -1.5, -10)     size=(8, 3, 0.5)

PitWall_SW_E    CSGBox3D  pos=(-10, -1.5, 14)     size=(0.5, 3, 8)
PitWall_SW_N    CSGBox3D  pos=(-14, -1.5, 10)     size=(8, 3, 0.5)

PitWall_SE_W    CSGBox3D  pos=(10, -1.5, 14)      size=(0.5, 3, 8)
PitWall_SE_N    CSGBox3D  pos=(14, -1.5, 10)      size=(8, 3, 0.5)

# Ramp'ы в ямы: по одному ramp на яму, наклон ~30° (rise 3u, run 4u)
# Ramp реализуется как CSGBox3D с rotation — наклонный Box перекрывает край ямы
# Ramp NW: соединяет Floor_W (Y=0) с PitFloor_NW (Y=-3), вход со стороны W-полосы
Ramp_NW         CSGBox3D  pos=(-11.5, -1.5, -14)  size=(3, 0.5, 6)   # rotation_degrees.z = -30 (наклон ~30°)
Ramp_NE         CSGBox3D  pos=(11.5, -1.5, -14)   size=(3, 0.5, 6)   # rotation_degrees.z = 30
Ramp_SW         CSGBox3D  pos=(-11.5, -1.5, 14)   size=(3, 0.5, 6)   # rotation.z = -30
Ramp_SE         CSGBox3D  pos=(11.5, -1.5, 14)    size=(3, 0.5, 6)   # rotation.z = 30

# ═══════════════ MEZZANINE TIER (Y=+4) ═══════════════
# 4 площадки по краям арены, каждая 8u длина × 4u глубина × 0.5u толщина
# Висят на высоте +4 от main floor. Доступ — ramp с main tier.

Mez_N           CSGBox3D  pos=(0, 4, -15)          size=(22, 0.5, 8)  # северная мез-площадка
Mez_S           CSGBox3D  pos=(0, 4, 15)            size=(22, 0.5, 8)
Mez_W           CSGBox3D  pos=(-15, 4, 0)           size=(8, 0.5, 22)
Mez_E           CSGBox3D  pos=(15, 4, 0)            size=(8, 0.5, 22)

# Перила мез (low walls 1u высота — не дают упасть случайно, но враги стреляют поверх)
Rail_N_outer    CSGBox3D  pos=(0, 4.75, -19)        size=(22, 1, 0.5)
Rail_S_outer    CSGBox3D  pos=(0, 4.75, 19)         size=(22, 1, 0.5)
Rail_W_outer    CSGBox3D  pos=(-19, 4.75, 0)        size=(0.5, 1, 22)
Rail_E_outer    CSGBox3D  pos=(19, 4.75, 0)         size=(0.5, 1, 22)

# Ramp'ы на мез: 4 штуки, с main tier на мез (rise 4u, run 5u = ~38°)
# Ramp реализуется как CSGBox3D наклонный или ступенчатый
# Для CSG — ступенчатые ramp'ы (3 ступени) проще чем гладкие наклонные
# Ступень: 1.5u подъём × 1.7u пробег × 3u ширина

# N ramp (main → Mez_N): 3 ступени с Y=0 до Y=+4
Ramp_MezN_Step1 CSGBox3D  pos=(-1.5, 0.75, -8)     size=(3, 1.5, 1.7)  # ступень 1
Ramp_MezN_Step2 CSGBox3D  pos=(-1.5, 2.25, -10)    size=(3, 1.5, 1.7)  # ступень 2
Ramp_MezN_Step3 CSGBox3D  pos=(-1.5, 3.75, -12)    size=(3, 1.5, 1.7)  # ступень 3 (выход на мез Y=+4.5)

# S ramp
Ramp_MezS_Step1 CSGBox3D  pos=(-1.5, 0.75, 8)      size=(3, 1.5, 1.7)
Ramp_MezS_Step2 CSGBox3D  pos=(-1.5, 2.25, 10)     size=(3, 1.5, 1.7)
Ramp_MezS_Step3 CSGBox3D  pos=(-1.5, 3.75, 12)     size=(3, 1.5, 1.7)

# W ramp
Ramp_MezW_Step1 CSGBox3D  pos=(-8, 0.75, -1.5)     size=(1.7, 1.5, 3)
Ramp_MezW_Step2 CSGBox3D  pos=(-10, 2.25, -1.5)    size=(1.7, 1.5, 3)
Ramp_MezW_Step3 CSGBox3D  pos=(-12, 3.75, -1.5)    size=(1.7, 1.5, 3)

# E ramp
Ramp_MezE_Step1 CSGBox3D  pos=(8, 0.75, -1.5)      size=(1.7, 1.5, 3)
Ramp_MezE_Step2 CSGBox3D  pos=(10, 2.25, -1.5)     size=(1.7, 1.5, 3)
Ramp_MezE_Step3 CSGBox3D  pos=(12, 3.75, -1.5)     size=(1.7, 1.5, 3)

# ═══════════════ ВНЕШНИЕ СТЕНЫ ═══════════════
WallN           CSGBox3D  pos=(0, 4, -19)            size=(38, 8, 0.5)  # высота 8u: от Y=0 до Y=+8
WallS           CSGBox3D  pos=(0, 4, 19)             size=(38, 8, 0.5)
WallE           CSGBox3D  pos=(19, 4, 0)             size=(0.5, 8, 38)
WallW           CSGBox3D  pos=(-19, 4, 0)            size=(0.5, 8, 38)

# ═══════════════ CENTER PAD ═══════════════
# Центральная приподнятая площадка 4×4, высота 1u — тактическое укрытие + elevation
CenterPad       CSGBox3D  pos=(0, 0.5, 0)            size=(4, 1, 4)     # приподнята на 1u над main tier
```

## 4. Spawn-Points — 8 штук, на всех трёх тирах

| Имя | Position | Primary hint | Тир | Логика |
|---|---|---|---|---|
| S1 | (0, 4.9, -15) | shooter | Mez_N | стреляет вниз на main tier, дальний LOS |
| S2 | (0, 4.9, 15) | shooter | Mez_S | зеркало S1 |
| S3 | (-17, 0.9, 0) | melee | main W | боковой перimetral |
| S4 | (17, 0.9, 0) | melee | main E |  |
| S5 | (-14, -2.1, -14) | swarm | Pit NW | рой из ямы |
| S6 | (14, -2.1, -14) | swarm | Pit NE |  |
| S7 | (-14, -2.1, 14) | any | Pit SW |  |
| S8 | (14, -2.1, 14) | any | Pit SE |  |

Pit spawn Y = -2.1 (SPAWN_Y=0.9 + pit floor Y=-3 → -3+0.9=-2.1 — SpawnController добавляет 0.9 к позиции точки, поэтому Marker3D.position.y = -3 для pit, в итоге инстанциирование будет Y=-3+0.9=-2.1. **Marker3D устанавливается на Y=-3, SpawnController сам добавит SPAWN_Y=0.9**).

**Важная правка**: S5-S8 Marker3D ставятся на `Y=-3` (pit floor surface), SpawnController добавит 0.9.  
S1-S2 на мез: Marker3D `Y=4` (mez surface), SpawnController → Y=4.9.

## 5. NavMesh

- **NavigationRegion3D**: **2 региона** или **1 с multi-level bake**  
  - Godot 4 NavigationServer3D поддерживает multi-level geometry в одном регионе если geometry connected (ramp'ы соединяют тиры).  
  - **Рекомендация**: 1 NavigationRegion3D. Bake покроет main + mez (через ступенчатые ramp'ы) + pit (через pit ramp'ы). Tray-nav test: враг с Mez должен найти путь вниз через ramp.  
- **agent_radius**: 0.3  
- **agent_height**: 1.8  
- **agent_max_climb**: 1.5u (ступени 1.5u подъёма — нужно поднять climb с текущего 0.3u)  
- **agent_max_slope**: 45°  
- **Edge cases**:  
  - Ступенчатые ramp'ы: каждая ступень 1.5u climb. NavMesh с agent_max_climb=1.5 — на границе. Если bake не покрывает, поднять до 1.6u.  
  - Pit рamp'ы: наклонные (rotation), Godot nav bake проецирует на surface норму — slope ~30°, passable при agent_max_slope=45°.  
  - Мез-перила (1u стены): не блокируют nav если враг идёт рядом с ними (agent_radius=0.3, перила толщина 0.5 — clearance с краем мез ≥0.3u).  

**Критично для impl**: после bake — визуально проверить что nav-mesh доходит до каждой pit-точки и каждой мез-точки. NavBaker.gd bake_navigation_mesh(false) — sync, достаточно.

## 6. Sightlines

```
ВЕРТИКАЛЬНЫЕ SIGHTLINES (главная особенность C):
- Shooter на Mez_N (Y=4.9) видит весь main tier (Y=0) через открытый верх
- Угол обзора вниз: ~30° от горизонтали к центру (dist ~15u, drop 4.9u = atan(4.9/15) ≈ 18°)
- LOS от S1 на центр: YES — нет препятствий, прямая линия
- LOS от S1 в pit: YES — яма открыта сверху, shooter простреливает вниз

ГОРИЗОНТАЛЬНЫЕ SIGHTLINES (main tier):
- CenterPad (1u возвышение): даёт shooter'у на паде LOS поверх перил мез
- Pit стены 3u: блокируют LOS из pit на main для melee/swarm. Shooter в pit бесполезен — нет LOS
- Main tier max sightline: ~30u диагональ (открыт, нет внутренних стен)

ПО ОСЯМ:
- S3(W) → center → S4(E): полный горизонтальный LOS 34u
- S1(Mez N) → center pad → S2(Mez S): вертикальный crossfire через всю арену
```

**Тактическое следствие**: мез — позиционное преимущество для shooter'а. Игрок, не занявший мез, получает давление сверху. Это incentive для vertical movement и velocity набора на ramp'ах.

## 7. Visual Language

- **Main tier**: `Color(0.35, 0.32, 0.28)` — тёплый тёмный камень (в отличие от холодного серого B и A)
- **Pit**: `Color(0.2, 0.2, 0.22)` — ещё темнее, визуальная опасность
- **Mez**: `Color(0.5, 0.48, 0.44)` — светлее main, подчёркивает elevation
- **Ramp'ы**: `Color(0.4, 0.38, 0.35)` — промежуточный
- **CenterPad**: `Color(0.6, 0.55, 0.45)` — самый светлый объект в арене, читается как "цель"
- Три арены визуально разные: B = светлый бетон, A = тёмный металл, C = камень+глубина

## 8. Player Visibility / Readability

| Риск | Mitigation |
|---|---|
| Pit spawn — враги невидимы пока не вылезут | Telegraph audio из ямы + fade-in. Стены ямы 3u — player слышит до видит. OK. |
| Shooter на мез стреляет сверху — player не смотрит вверх | Первые 5 секунд на арене C: player видит мез-площадки с ramp'ами. Это читается как "туда можно зайти" = осознанный выбор. Shooter spawn telegraph на мез слышен. |
| Падение в яму — "случайная" смерть? | Ямы = осознанный риск. Pit стены 3u — в яму не упасть случайно, только сознательно зайти через ramp. Если игрок вошёл в яму и там заспавнился рой — это intended pressure. |
| CenterPad как spawn position | Не спавнить врагов на CenterPad — он 4×4, SPAWN_DISTANCE=12u от центра справится. |

## 9. Estimated Impl Time

- Main tier пол (5 секций): **1 час**
- Pit geometry (4 ямы × 3 элемента = 12 CSGBox3D): **2 часа**
- Mez geometry (4 площадки + 4 × 3 ступени + 4 перила): **3 часа**
- Стены + CenterPad: **0.5 часа**
- Spawn-points (8 на трёх уровнях): **0.5 часа**
- NavMesh multi-tier bake + agentMaxClimb adjustment + visual check: **3–4 часа**
- **Итого**: 10–11 часов impl, 3–4 часа nav-tweak. Самая дорогая.

## 10. Playtest Checklist

1. **Вертикальный страх**: избегаешь ли ты открытого main tier когда shooter на мез? Занимаешь ли мез сам (притом что player не может занять — он just FPS)?
2. **Pit как выбор**: заходишь ли ты в яму сознательно или случайно? Если случайно — увеличить визуальный contrast края.
3. **CenterPad utility**: используешь ли CenterPad как укрытие или обходишь? (Должен использоваться — иначе убрать или сделать крупнее.)
4. **Ramp velocity**: удаётся ли набрать velocity пробегом по ступеням мез-ramp'а, или ступени ломают momentum (ощущение "залипания")?
5. **Multi-tier читаемость**: понятна ли вертикальная структура арены сразу, или первые 30 секунд — дезориентация?

---

---

# META — Migration Strategy & Architecture

## Scene Structure

**Рекомендация**: отдельные `.tscn` файлы для каждой арены.

```
scenes/
  main.tscn               ← оркестратор (player, HUD, run logic, camera)
  arenas/
    arena_b_plac.tscn     ← только Arena нода + SpawnPoints + NavigationRegion3D
    arena_a_camera.tscn
    arena_c_shaft.tscn
```

`main.tscn` instance'ит нужную арену через `@export var arena_scene: PackedScene` или через код. При смене арены: `queue_free()` текущую, instance + add_child новую.

**Что остаётся в main.tscn**: Player, HUD (RunHud, DeathScreen, PauseMenu), WorldEnvironment/Sun, VignetteLayer, KillChainFlash, NavBaker (или NavBaker переезжает в arena `.tscn`).

**NavBaker**: лучше перенести в каждый arena `.tscn` — у каждой арены свой NavigationRegion3D.

## Arena Selection Mechanic

Это game-design вопрос, но для architecture: минимальная impl — `@export var arena_scene: PackedScene` на Main.gd, меняется через Inspector или маленький SelectArena-screen. Полноценный unlock flow (B → A → C по прогрессу) — отдельный feature после всех трёх арен finalized.

## Реюзуемые Assets из Текущего Репо

| Asset | Реюзуется в B/A/C |
|---|---|
| `scripts/spawn_controller.gd` | Да — нужна адаптация (убрать hard-coded size assert, сделать POINT_WEIGHTS flexible) |
| `scripts/nav_baker.gd` | Да — переносится в каждый arena `.tscn` |
| `scripts/run_loop.gd` | Да — без изменений |
| `objects/melee.tscn`, `shooter.tscn`, `swarmling.tscn` | Да — без изменений |
| `scenes/run_hud.tscn`, `death_screen.tscn`, `pause_menu.tscn` | Да — остаются в main.tscn |
| `assets/skybox/empty_warehouse_01_1k.exr` | B — да (открытое небо). A — нет (закрытый потолок, ambient only). C — да |
| `shaders/vignette_flash.gdshader` | Да — без изменений |

## Порядок Impl

1. **Arena B** первой — самая простая, валидирует SpawnController adaptation + arena scene structure
2. **Arena A** второй — валидирует closed ceiling + corridor nav
3. **Arena C** последней — multi-tier nav, самый сложный bake

**Текущая арена 40×40 удаляется из main.tscn после того как B finalized и юзер approve'ил.**

---

*Документ готов к review. После approve юзера — impl делегируется godot-engineer, начиная с Arena B.*
