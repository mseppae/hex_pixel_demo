# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Behaviour components: each creature lists behaviours (`Flee_When_Hurt`,
  `Melee_Attack`, `Chase_Player`, `Wander`) in priority order in
  `assets/content.json`; on its turn each is tried until one acts
  (`behaviour.odin`)
- Wounded goblins now flee, and idle ones wander

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
