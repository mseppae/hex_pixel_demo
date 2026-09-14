# Fully data-defined creatures

**Implemented** (steps 1-3 below: sprite sheets by name, `Creature_Kind` and `Item_Kind`
as ids, both save-safe). Step 4, the content pass itself, is still to come — this was a
prerequisite for it, and a natural companion to `DESIGN_RANGED.md`.

Notes from the implementation, for whoever does step 4 next:

- Both `Creature_Kind` and `Item_Kind` ended up as `int` (an index resolved once, not a
  string carried around at runtime) — the "or an index" alternative this doc floated in
  step 1, chosen for the same reason: no repeated map lookups in the turn loop. The
  id string only appears in `content.json`, in save files, and in the handful of
  `find_creature`/`find_item`/`creature_kind_named`/`item_kind_named` calls that resolve
  one to the other.
- Every corner this doc didn't cover ended up data too, once `Creature_Kind` stopped
  being a fixed enum whose cases a `switch` could exhaustively name:
  `Creature_Definition.article` replaces `creature_with_article`'s switch,
  `Creature_Definition.corpse` (a `Container_Kind` by name) replaces `corpse_kind_for`'s,
  and `Creature_Definition.loot` (a list of `Loot_Table_Entry`, independently-rolled
  chances) replaces `roll_creature_loot`'s. A new creature now needs none of the three.
- `Item_Definition` gained `icon_column`: which 16 x 16 column of `item_icons.png` is its
  icon, as an explicit field rather than "whatever position it happens to be in the
  JSON array" (which used to be implicitly the enum's ordinal). Adding an item is still
  an art step (a new column in the sheet, or a new sheet) plus a JSON entry, same as a
  creature needing a `sprite_sheet` — the point of this refactor was never "no art
  needed," just "no recompile needed."
- `Ranking_Entry.killed_by` became the already-resolved article text ("a goblin"), not a
  creature reference — simpler than a second save-safe id, and old ranking entries keep
  their original text even if that creature is later renamed or removed.
- `Container_Kind` (corpses and chests) stayed a real enum on purpose: its cardinality is
  bounded by hand-drawn art in `objects.png`, unlike creatures and items, which can grow
  forever. A creature just names which existing corpse it leaves.

## Where it stands today

Creature *properties* are already data: `assets/content.json` holds each creature's name,
stats, attributes, sounds, weights, default stance and behaviour list, loaded into
`CREATURES` by `content.odin`. That was the earlier data pass.

What is still code:

- **`Creature_Kind` is an enum** of three values (creatures.odin). Every creature in the
  game must be one of them, so a new monster means editing the enum and recompiling.
- **Sprite sheets are hardcoded.** `main.odin` holds `creature_sprites:
  [Creature_Kind]rl.Texture2D`, filled from three `#load`ed PNGs by name. A creature
  cannot choose its own art in data.
- The enum is also **stored in save files as a number**, which is why new kinds have had
  to be appended at the end.

Named creatures (Grishnak, Gorluk) already show the shape of the fix: they are data
entries that reuse an existing kind's sheet with a different tint and different stats. The
change below generalises that to all creatures.

## The change

**1. `Creature_Kind` becomes a string id.** `CREATURES` becomes a
`map[string]Creature_Definition`, and an `Actor` stores its kind as a small fixed-size id
string (or an index into the loaded table, resolved once at spawn). Adding a "cave
goblin" is then one JSON entry.

**2. A creature names its own art.** The definition gains `sprite_sheet` (a file name) and
the existing `tint`. Sheets are loaded into a `map[string]rl.Texture2D` at startup: each
name is loaded once and shared, so ten creatures using `goblin_sheet.png` cost one
texture. Built-in sheets stay `#load`ed by name; a sheet that isn't built in is read from
`assets/` next to the program, which is what lets you add a monster without recompiling.

**3. Saves store the id as text.** `Saved_Creature.kind` becomes a string. This is
strictly safer than the enum number: reordering or removing entries no longer silently
turns one creature into another, and a save naming a creature that no longer exists can be
reported instead of misread. Requires a `SAVE_FORMAT_VERSION` bump.

**4. The same treatment for the remaining hardcoded table.** `ITEMS` in items.odin is the
last one. Items are referenced by name from quests, loot tables and loadouts already, so
this is the same change applied twice.

## What it unlocks

- **A content pass without code.** New creatures, recolours, and whole families
  (cave goblin, goblin brute, young ogre, troll) become JSON entries.
- **Depth character.** Which creatures appear at which depth is already data; with
  data-defined kinds it becomes a real difficulty curve rather than "more goblins".
- **Modding, eventually.** Someone can drop a PNG and a JSON entry beside the program.

## Costs and cautions

- **Lookup cost.** A map lookup per creature per turn instead of an array index. At this
  scale it is irrelevant, but resolving the id to an index once at spawn keeps it exact.
- **Typos become runtime errors, not compile errors.** This is the real price of leaving
  the enum. Mitigate with validation at load: every creature id referenced by a level
  table, quest, or named creature must exist, reported once at startup rather than
  crashing mid-game.
- **Do items and creatures in separate steps**, each with the save bump, so a broken load
  is easy to trace to one of them.

## Suggested order

1. Sprite sheets by name in data (small, immediately useful, no save change).
2. `Creature_Kind` to string ids, with load-time validation and the save bump.
3. `ITEMS` to data the same way.
4. The content pass: more weapons and monsters, purely as data.
