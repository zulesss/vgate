# M3 Enemy Assets Research

Research-агент, 2026-04-27. Asset preview gate перед интеграцией.

---

## 1. Pack Overview — Quaternius Sci-Fi Essentials Kit

| Параметр | Значение |
|---|---|
| **URL** | https://quaternius.com/packs/scifiessentialskit.html / https://quaternius.itch.io/sci-fi-essentials-kit |
| **Лицензия** | CC0 confirmed |
| **Состав (free)** | 37 моделей: animated robot enemies, textured guns, animated screens, crates, props |
| **Состав (Source)** | 65 моделей + Godot 4.3+ project, .blend, custom shaders |
| **Форматы** | FBX, OBJ, glTF (.glb) |
| **Godot** | Source-версия включает готовый проект Godot 4.3+ |
| **Анимации** | Confirmed "animated enemies" — но точный список (idle/walk/attack/die) публично не задокументирован |
| **Архетипы** | "Animated robot enemies" — число вариантов публично не указано, предположительно 2-4 типа robot из 37 моделей |
| **Release** | Ноябрь 2024 |

---

## 2. Coherence с Kenney Starter Kit FPS

**Verdict: Needs Work (не фатально)**

- Оба автора — low-poly stylized CC0. Общая «школа» стиля.
- Разница: Kenney — vertex-color / flat (без UV), Quaternius — texture atlas (solid colors per-region). Разница видна при стандартном Godot PBR-освещении.
- Quaternius robots: чуть более mechanical detail, больше edge loops vs Kenney blocky minimalism.
- Митигация: Unshaded / Flat shader на Quaternius models выравнивает разницу.
- Стратегия из `asset_pipeline.md`: один source приоритетом — Quaternius для enemies, Kenney для environment.

---

## 3. Recommended Models для M3

**Без прямого preview — это предположения, не lock:**

- **Стрелок**: искать slim/upright humanoid robot с weapon-holding pose. Silhouette на 20-30u читается через вертикальный силуэт + оружие в руках.
- **Ближнебой**: heavy/compact robot без ranged weapon. Низкий центр тяжести, широкие «плечи» или «клешни».
- Разные модели обязательны — tint одной mesh в два цвета недостаточно для read двух типов врагов через поведение.

**До финального решения**: нужен один скриншот из Godot Source-проекта с обоими robot models на нейтральном фоне.

---

## 4. Fallback Stack

| Кандидат | Плюс | Минус | Приоритет |
|---|---|---|---|
| **Quaternius Cyberpunk Game Kit** | CC0, 71 модель, animated enemies + turrets, GLB | Cyberpunk-darker style, не textured | **Fallback #1** |
| Kenney Animated Characters (Kay Lousberg) | CC0, 17 анимаций, 75 skins | Human-style, не robot | Плохой fit |
| Mixamo | 10000+ анимаций, free для игр, humanoid auto-rig | Не CC0, characters — humans | Для animations только |
| SciFi LowPoly FPS Character (rcorre.itch.io) | Godot AnimationTree pre-built, 29 animations | CC-BY, один персонаж, нет death anim | Анимации-референс |

---

## 5. Integration Risks — Godot 4.6

1. **AnimationLibrary setup**: `.import`-конфиг на skeleton path + animation tracks — 30-60 мин per model, не блокер.
2. **Non-humanoid rig**: robot rigs могут быть механическими (не spine+limb). Universal Animation Library retarget не применим — анимации должны быть embedded в pack.
3. **Free vs Source**: free (37 моделей) может давать недостаточное enemy variety. Source — за Patreon claim credits.
4. **Texture mismatch на арене**: Kenney (vertex-color) + Quaternius (texture atlas) → разница в Godot PBR. Митигация: Flat/Unshaded material на enemies.

---

## Recommendation

Использовать Sci-Fi Essentials Kit, но **перед интеграцией** открыть Godot Source-проект и сделать скриншот robot models на арене рядом с Kenney-текстурой пола. Если два robot archetype визуально читаются как «slim shooter» и «heavy melee» — интегрировать их. Если variety недостаточна или Source недоступен — переключиться на **Quaternius Cyberpunk Game Kit** (Fallback #1, CC0, confirmed animated enemies).

**Первые два файла на preview** (если скачан Sci-Fi Essentials Kit Source):
1. Открыть Godot-проект из Source-zip, найти enemy scenes — сделать screenshot всех robot variants
2. Расставить два наиболее разных силуэта рядом на нейтральном сером фоне

---

## Sources

- [Sci-Fi Essentials Kit — quaternius.com](https://quaternius.com/packs/scifiessentialskit.html)
- [Sci-Fi Essentials Kit — itch.io](https://quaternius.itch.io/sci-fi-essentials-kit)
- [Sci-Fi Essentials Kit — OpenGameArt](https://opengameart.org/content/sci-fi-essentials-kit)
- [Quaternius на X — анонс с Godot support](https://x.com/quaternius/status/1857915945148125485)
- [Cyberpunk Game Kit — quaternius.com](https://quaternius.com/packs/cyberpunkgamekit.html)
- [Modular Sci-Fi MegaKit — itch.io](https://quaternius.itch.io/modular-sci-fi-megakit)
- [Universal Animation Library 2 — itch.io](https://quaternius.itch.io/universal-animation-library-2)
- [SciFi LowPoly FPS Character — itch.io](https://rcorre.itch.io/scifi-fps-character)
- [Kenney Animated Characters 3 — itch.io](https://kenney-assets.itch.io/animated-characters-3)
