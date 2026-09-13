# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.2.0] - 2026-09-13

### Added

- A `Forest` tile kind, and trees and bushes as props standing on them: the
  village is ringed with woodland, several plants to a hex at different sizes
  and offsets, so the crowns overhang the hex edges and the map's outline no
  longer reads as a honeycomb (`art_source/trees.py`, `assets/trees.png`)
- Behaviour components: each creature lists behaviours (`Flee_When_Hurt`,
  `Melee_Attack`, `Chase_Player`, `Wander`) in priority order in
  `assets/content.json`; on its turn each is tried until one acts
  (`behaviour.odin`)
- Wounded goblins now flee, and idle ones wander
- Attributes (Strength/Dexterity/Constitution), a Neutral/Aggressive/Defensive
  stance (`T`), and weight-gated parry/riposte for melee combat: parrying can
  crit or fumble on a natural 20/1, and a successful parry can trigger a
  bonus-damage riposte unless the defender's weapon is Heavy (`rules.odin`,
  `DESIGN_COMBAT.md`)
- A Scroll of Town Portal: opens a two-way link back to the village good for
  one round trip (`portal.odin`), sold by a new Merchant villager
- A dialogue-based shop: a villager can offer an item for gold instead of a
  quest (`NPCS[role].sells`), bought via the existing dialogue action button
- Quest items (`Item_Category.Quest_Item`): trophies with no use besides being
  handed to whoever wants them, dropped by named creatures alongside a slay
  quest's existing target-tracking
- 40 new quests across 3 new quest-giving villagers (Hunter, Priestess, Guard
  Captain) plus more for the Elder and Smith, and 25 new named creatures to go
  with them, spanning depths 3-28 — all in `assets/content.json`, no new game
  logic beyond the quest-item category above
- A Quest Log panel (`L`, or the "Quests" button), listing every quest
  currently active and whether it's ready to turn in, replacing the one-line
  HUD summary that couldn't scale past a couple of quests

### Changed

- Creature stats, sounds and sprite sizes moved from `creatures.odin` into
  `assets/content.json`; the code keeps only the ids

## [0.1.0] - 2026-09-12

### Added

- Hex grid in axial coordinates, with pathfinding, line of sight and mouse
  picking
- Procedurally generated cave levels with tile variants, stairs, and levels
  that persist as you left them
- Creatures with six-direction sprite sheets: walk, attack, hurt and death
  animations, including a three-hex ogre
- Items: inventory, equipment, loot, corpses, chests, dropping
- A village (depth 0) with villagers, quests and named creatures
- Saving to three slots, a ranking list, and sound effects

[Unreleased]: https://github.com/mseppae/hex_pixel_demo/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/mseppae/hex_pixel_demo/releases/tag/v0.1.0
