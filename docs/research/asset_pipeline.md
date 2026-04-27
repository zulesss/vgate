# Asset Pipeline — VGate

Артефакт research-агента от 2026-04-27. Куратирован под FPS-arena solo-скоуп, бюджет ≈ 0 (CC0 / cheap CC-BY).

---

## Foundation: Kenney Starter Kit FPS

**Главная находка research-pass'а.** Не пак, а **готовый Godot 4.x проект** с FPS controller + weapon system + enemy AI + CC0-моделями.

- Repo: https://github.com/KenneyNL/Starter-Kit-FPS
- License: MIT (code) + CC0 (assets)
- Содержимое: PlayerController (WASD + mouse-look + jump), оружие с muzzle flash, базовый враг с pathfinding
- Импорт: M0 — godot-engineer копирует scripts + assets в `/home/azukki/vgate/`, адаптирует под Godot 4.6 если нужно

**Эффект**: −1 до −3 дней на бойлерплейт FPS-controller'а. Никакая другая тематика такого не даёт.

---

## Сеттинг — Sci-Fi / Cyberpunk (выбрано)

Выбрано по покрытию ассетов и code-зависимости (Kenney Starter Kit FPS уже sci-fi).

### Покрытие компонентов

| Компонент | Источник | Размер | License |
|---|---|---|---|
| **FPS-controller / weapon base** | [Kenney Starter Kit FPS](https://github.com/KenneyNL/Starter-Kit-FPS) | проект | MIT + CC0 |
| **Modular environment** | [Quaternius Modular Sci-Fi MegaKit](https://quaternius.itch.io/modular-sci-fi-megakit) | 270+ моделей | CC0 |
| **Enemies (анимированные)** | [Quaternius Sci-Fi Essentials Kit](https://quaternius.itch.io/sci-fi-essentials-kit) | 60+ моделей, роботы | CC0 |
| **Cyberpunk variants** | [Quaternius Cyberpunk Game Kit](https://quaternius.com/packs/cyberpunkgamekit.html) | 71 модель + анимированный персонаж | CC0 |
| **Weapons (FPS first-person)** | [Kenney Blaster Kit](https://kenney.nl/assets/blaster-kit) | 40 моделей | CC0 |
| **Weapons backup** | [Quaternius Ultimate Gun Pack](https://quaternius.com/packs/ultimategun.html) | 40 моделей | CC0 |
| **Skybox / lighting** | [Polyhaven HDRI](https://polyhaven.com/hdris) | бесконечный архив | CC0 |
| **VFX (мазл, hit-particles)** | [Synty SIMPLE FX](https://syntystore.com/collections/free-synty-assets) | minimal | Synty free-tier |
| **Animations (если нужно)** | [Mixamo](https://www.mixamo.com/) + [Godot retargeting plugin](https://forum.godotengine.org/t/mixamo-animations-to-godot-plugin/87630) | бесконечный | Mixamo free |

### Минусы Sci-Fi (озвучены до старта)
- Sci-fi коридоры Quaternius заточены под узкие пространства. Для открытой арены 40×40 нужна нестандартная компоновка.
- Жанр насыщенный (см. market context в `docs/concept/M0_concept.md`). Hook (Velocity Gate) compensates.
- Style-mismatch риск если миксовать Kenney-cubes стиль с Quaternius-detailed. Решение в M0 — выбрать ОДИН source приоритетом, второй как fill-in.

---

## Альтернативные сеттинги (back-pocket если sci-fi жмёт)

### Medieval Dungeon (KayKit)
- [KayKit Dungeon Pack Remastered](https://kaylousberg.itch.io/kaykit-dungeon-remastered) — 200+ env моделей CC0
- [KayKit Skeletons](https://kaylousberg.itch.io/kaykit-skeletons) — 4 ригген. скелета, 90+ анимаций CC0
- **Плюс**: один автор, единая palette atlas → перфектная style coherence
- **Минус**: FPS-вид оружия НЕТ в CC0 (нужно конвертировать из third-person, 2-4 часа в Blender). Cartoon-стиль конфликтует с "управляемой паникой" темой.
- **Когда вернуться**: если Kenney Starter Kit FPS не работает с Godot 4.6 ИЛИ если Velocity Gate переходит на B-вариант (Ammo-as-Time) и cartoon-fantasy fits новой эмоции.

### Post-Apocalyptic Zombie
- [Quaternius Zombie Apocalypse Kit](https://quaternius.com/packs/zombieapocalypsekit.html) — 60 моделей, 4 типа врагов с анимациями, CC0
- **Плюс**: enemies покрыты в одном паке
- **Минус**: env разрозненный (нужно компоновать из City Kit + Zombie Kit), style-mismatch
- **Не используем по умолчанию.**

---

## Tier-2 источники (если sci-fi pack не покрывает)

| Источник | Что | License |
|---|---|---|
| [Kenney 3D assets](https://kenney.nl/assets/category:3D) | разрозненные пакеты по теме | CC0 |
| [itch.io free 3D](https://itch.io/game-assets/free/tag-3d/tag-environment) | случайные находки | разные |
| [Sketchfab CC0](https://sketchfab.com/3d-models/categories) | individual models | CC0 / CC-BY |
| [OpenGameArt](https://opengameart.org/) | старая, но актуальная | разные |

---

## Ниши с НИЗКИМ покрытием (не использовать)

- **Horror / Liminal Space / Backrooms** — env есть (CC0 Backrooms Pack), врагов в CC0 нет
- **Cyberpunk фотореалистичный** — для UE4, в Godot не работает. Low-poly cyberpunk через Quaternius — единственный вариант
- **Brutalist / Soviet / Bunker** — ноль систематических CC0 паков
- **Western / Wasteland** — env есть, FPS-оружия и врагов почти нет
- **Voxel FPS (MagicaVoxel)** — env много, рига врагов с анимациями в CC0 — мало

---

## Practical workflow для godot-engineer

### M0: Foundation setup
```bash
cd /home/azukki/vgate
git clone --depth 1 https://github.com/KenneyNL/Starter-Kit-FPS.git /tmp/starter-fps
# Скопировать relevant scripts/scenes/assets в vgate/, не весь проект
# Проверить совместимость с Godot 4.6 (Starter Kit может быть на 4.0/4.1)
# Если version mismatch — godot-engineer мигрирует script syntax (минимум)
```

### M3: Enemy assets
Download Quaternius Sci-Fi Essentials Kit, импорт `.glb` в `vgate/assets/enemies/`. Настроить два preset'а — стрелок (range gun mesh + idle anim) + ближнебой (мили weapon + walk anim).

### M5: Polish
Polyhaven HDRI для skybox (один файл, 4K максимум — не больше).

---

## License compliance

**CC0** — без attribution, без проблем
**MIT (code)** — Kenney Starter Kit FPS требует включить MIT-лицензию в credits / LICENSE.txt при шипе. Ставится одним файлом.

В `vgate/LICENSE.txt` к моменту M5/M6:
```
Game code © [user]
Assets:
- Kenney.nl Starter Kit FPS (MIT + CC0): https://github.com/KenneyNL/Starter-Kit-FPS
- Quaternius (CC0): https://quaternius.com/
- Polyhaven HDRI (CC0): https://polyhaven.com/
- Synty SIMPLE FX (Synty free-tier): https://syntystore.com/
```

Никаких CC-BY с attribution в текущем стеке — упрощает credits.
