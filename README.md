# 三國殺 Roguelike (Prototype)

A short **Godot 4.x** GDScript prototype inspired by 三國殺 card combat, framed as a tiny roguelike.

> Inspired by, not a commercial clone. Basic generation deck only — **no character specialties / unique abilities**. Player and enemies use the **same rules**.

## Requirements

- **Godot 4.2+** (project `config_version=5`, features include `4.2`)
- Forward Plus renderer (default)

## How to open & run

1. Install [Godot 4.x](https://godotengine.org/download).
2. In the Project Manager: **Import** → select `project.godot` in this folder.
3. Press **F5** (or Play) — main scene is `scenes/main_menu.tscn`.

## Controls

| Action | How |
|--------|-----|
| Start run | Main Menu → **Start Run** |
| Enter fight | Map → **Enter Combat** on the current node |
| Play a card | Click an enabled card in your hand |
| End turn | **End Turn** (then discard if over hand limit 5) |
| Discard | In discard phase, click cards until hand ≤ 5 |
| Respond to 殺 | **Play 閃 (Dodge)** or **Take the Hit** |
| Pick reward | Click one of three reward buttons after a win |

## Cards (basic deck)

| ID | ZH / EN | Effect |
|----|---------|--------|
| `sha` | 殺 / Attack | Deal 1 damage; target may cancel with 閃 |
| `shan` | 閃 / Dodge | Reactive only — cancels 殺 |
| `tao` | 桃 / Heal | Restore 1 HP (cap at max HP) |
| `guohe` | 过河拆桥 / Dismantle | Discard 1 random card from opponent hand |
| `wuzhong` | 无中生有 / Draw Two | Draw 2 cards |

Card data lives in `resources/cards/*.tres` backed by `scripts/card_data.gd`.

## Flow

**Main Menu → Map → Combat → Reward → (Map …) → Boss → Reward → Win / Lose**

- Map: 3 normal fights + 1 boss
- Between fights: reward choice (**not** character abilities) — max HP, heal, extra opening draw, or add a card to your deck
- Simple AI enemy using the same card rules

## What’s implemented

- Valid Godot 4 project with autoload `RunManager`
- Data-driven `CardData` resources
- Turn-based combat: draw 2 → play → discard to hand limit
- Shared combatant logic for player & enemy
- Short roguelike loop with win/lose screens
- Placeholder UI (`ColorRect` / `Label` / `Button`)

## Card art

Portrait card textures live in `assets/cards/` and are referenced from `resources/cards/*.tres` via `CardData.art`.
Combat hand UI (`scripts/combat_view.gd`) shows `TextureButton` portraits when art is present.

| ID | English | Art |
|----|---------|-----|
| sha | ATK | `atk.png` |
| shan | DODGE | `dodge.png` |
| tao | HEAL | `heal.png` |
| guohe | BREAK | `break.png` |
| wuzhong | DRAW | `steal.png` (temporary stand-in) |

Extra portraits ready for later cards: `buff.png`, `deny.png`, `duel.png`, `stasis.png`.

## Suggested next steps

- Card art / better hand layout and animations
- Suit/number (花色点数) if you want closer table feel
- Equipment or distance rules (still without character 技能)
- More trick cards and multi-enemy encounters
- Seeded runs, meta unlocks for *basic* cards only
- Audio / juice / accessibility (colorblind-safe card icons)

## Project layout

```
scenes/           main_menu, map, combat, reward, result
scripts/          run_manager, card_data, combatant, combat_*, *_view
resources/cards/  .tres card definitions
assets/           placeholders
```

## License note

Fan prototype for education/fun. 三國殺 is a trademark of its respective owners; this project is an original rules-light homage.
