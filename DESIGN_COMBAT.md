# Attributes, stances, and parry/riposte for melee combat

Design doc for a planned combat-system addition. Not yet implemented — no `.odin` files
or `content.json` reflect this yet. Written up here so the design isn't lost between
sessions.

## Context

The game currently has no attribute system: combat is `damage = max(1, roll(damage_dice) -
armor)`, attacks always land (no accuracy/evasion roll at all), and there's no way to
avoid a hit except armor absorbing some of it. The player asked for Strength/Dexterity/
Constitution-style attributes that creatures have too (not just the player), and for
parry/riposte — with riposte being a distinct, separately-rolled, and "very effective"
follow-up, plus critical successes/failures, plus an attack/defensive/neutral stance a
character can set. Ranged weapons and magic are explicitly deferred to later.

This is a real combat-system addition, not a refactor: it introduces the game's first
opposed/random-threshold roll (a d20-style check) alongside the existing damage dice.

## Design

**Attributes** (Strength, Dexterity, Constitution) are per-kind data, like `damage_dice`
and `armor` already are — added to `Creature_Definition` (creatures.odin) and
`assets/content.json`, not duplicated onto `Actor` (same reasoning as the last DOD pass:
nothing overrides them per-instance, so they're looked up via `CREATURES[actor.kind]`).
A classic modifier curve: `attribute_modifier(score) = floor((score - 10) / 2)` — e.g.
STR 8 → -1, STR 14 → +2. Roles:
- **Strength** → bonus to melee damage dealt.
- **Dexterity** → parry chance and riposte accuracy.
- **Constitution** → bonus added to `max_hit_points` once, at spawn (`make_creature`).
  Named bosses (Grishnak, Gorluk) keep directly-authored final stats as today — the CON
  bonus only applies to ordinary creatures built straight from `CREATURES[kind]`.

Example spread: Goblin (STR 8, DEX 14, CON 8) is a frail but hard-to-pin-down striker;
Ogre (STR 18, DEX 6, CON 16) hits like a truck but rarely parries and is slow to dodge.

**Weapon weight** gates riposte itself, not just its odds — a `Weapon_Weight ::
enum{Light, Medium, Heavy}` on `Item_Definition` (items.odin, for the player's equipped
weapon) and on `Creature_Definition` (for a monster's innate attack). Light (daggers,
bare hands): riposte fully available, no penalty — this is what gives light weapons a
real niche. Medium (short sword, longsword): riposte available but at a roll penalty.
Heavy (spiked club, an ogre's smash): riposte isn't possible at all — parrying a heavy
blow still negates the damage, there's just no fast counter to throw back. Strength
still nudges the riposte roll (for light/medium wielders), but only at half its normal
modifier — enough to matter, not enough to make a heavy weapon competitive at riposting.

**Armor weight** stacks on top of weapon weight rather than replacing it — a separate
`Armor_Weight :: enum{Light, Medium, Heavy}` on `Item_Definition` (items.odin, for armor
pieces) and on `Creature_Definition` (for a monster's natural hide/scales). Today's two
armors: Leather Armor = Light, Chain Shirt = Medium; a future heavy armor slots in as
Heavy. Armor weight only affects the **riposte** roll, not the parry roll — it's a
straight penalty (`armor_weight_modifier`: Light = 0, Medium = -1, Heavy = -3), since
being encased in heavy armor makes you less nimble no matter how light your weapon is.
Parrying itself stays governed by Dexterity and stance alone, so this is specifically
what makes light-weapon-and-light-armor a distinct, riposte-focused playstyle: a
dagger-wielder in a chain shirt still ripostes, just at a worse roll than the same
dagger-wielder in leather.

**Stance** is real per-instance state (`Stance :: enum{Neutral, Aggressive, Defensive}`
on `Actor`), since it changes turn to turn. Aggressive: +2 damage, -2 to the wearer's own
parry/riposte rolls. Defensive: -2 damage, +2 to parry/riposte rolls. Neutral: no
modifiers. The player switches stance freely (no turn cost — a standing toggle, not an
action). Monsters get a fixed `default_stance` per kind in `Creature_Definition` (e.g.
Ogre = Aggressive, Goblin = Neutral) rather than switching dynamically — a stretch goal,
not this pass.

**Combat resolution**, in `resolve_attack_impact` (rules.odin), before damage is applied:

1. **Parry roll** (defender): `1d20 + dex_modifier(target) + stance_bonus(target) vs
   PARRY_DIFFICULTY`. Natural 1 = critical failure: parry is impossible *and* the
   attacker's hit becomes an automatic critical (bonus damage). Natural 20 = critical
   success: parry auto-succeeds and skips straight to a guaranteed, bonus-damage riposte.
   Otherwise: success if `roll + modifier >= difficulty`.
2. **If parried**, the original damage is fully negated. If the defender's weapon is
   Heavy, that's the end of it — no riposte is even attempted. Otherwise, a **separate
   riposte roll** decides whether the counter lands: `1d20 + dex_modifier(target) +
   stance_bonus(target) + weight_modifier(target's weapon) + armor_weight_modifier(target) +
   strength_modifier(target)/2 vs RIPOSTE_DIFFICULTY` (easier than a fresh attack — the
   opening is already there). On success, the defender immediately strikes back via the
   existing `start_attack` machinery, flagged so this counter-attack (a) cannot itself be
   parried (no infinite parry/riposte chains) and (b) deals bonus damage (`×1.5`, rounded
   up) — this is what makes riposte "very effective." On failure, the parry still avoided
   the hit, but no counter lands this exchange.
3. **If not parried**, damage applies as today, plus the attacker's `strength_modifier`,
   with the critical-failure-triggered auto-crit from step 1 (or a natural-20 on the
   damage side, if we want normal swings to crit too — flagged below as an open call).

All of this is symmetric: it runs the same whether the player or a monster is attacking,
so monsters parry and riposte the player using their own Dexterity, and vice versa.

## Changes (when this gets built)

- **creatures.odin**: add `strength, dexterity, constitution: int`,
  `default_stance: Stance`, `weapon_weight: Weapon_Weight`, and `armor_weight:
  Armor_Weight` to `Creature_Definition` (a monster's innate attack/hide has an implicit
  weight — e.g. goblin dagger = Light weapon + Light hide, ogre smash = Heavy weapon +
  Heavy hide).
- **content.odin**: matching fields on `Content_Creature`, parsed the same way
  `behaviours`/sounds are (`from_name` for the stance and both weight enums).
- **assets/content.json**: attribute + stance + weapon_weight + armor_weight values for
  Adventurer, Goblin, Ogre.
- **items.odin**: add `Weapon_Weight :: enum{Light, Medium, Heavy}` and `Armor_Weight ::
  enum{Light, Medium, Heavy}`; a `weight: Weapon_Weight` field on weapon
  `Item_Definition`s (Goblin_Dagger = Light, Short_Sword/Longsword = Medium, Spiked_Club
  = Heavy, `FIST_DICE`'s implicit unarmed weight = Light) and an `armor_weight:
  Armor_Weight` field on armor `Item_Definition`s (Leather_Armor = Light, Chain_Shirt =
  Medium). The player's effective weapon/armor weight for riposte purposes comes from
  whatever's equipped (`inventory.weapon` / `inventory.armor`), falling back to unarmed
  (Light) / unarmored (Light).
- **actors.odin**: add `Stance` enum and `stance: Stance` field to `Actor` (defaults
  `.Neutral` for the player at spawn, `CREATURES[kind].default_stance` for monsters);
  add a small `is_riposte`-style flag threaded through `start_attack` (extra parameter,
  defaulted so existing call sites in rules.odin:229 and behaviour.odin:48 don't change)
  so `resolve_attack_impact` knows not to let a riposte itself be parried.
- **rules.odin**: `attribute_modifier`, `stance_damage_bonus`/`stance_defense_bonus`, and
  a small `d20_check(modifier, difficulty) -> (success: bool, critical: Critical)`
  helper; rewrite the front of `resolve_attack_impact` per the resolution flow above;
  add `strength_modifier(attacker)` into the existing damage formula.
- **input.odin / ui.odin**: a way for the player to pick their stance (a hotkey or a
  small button row) and a place to see current stance + STR/DEX/CON, near the existing
  "Damage"/"Armor" lines in the inventory panel (ui.odin:315-316).
- **New combat log lines** via the existing `set_message` for parries, riposte hits,
  riposte misses, and crits, so the player can actually feel these outcomes happening.

## Open calls flagged for review (all easy to change later)

1. Stance switching is a free, instant toggle — not a turn-consuming action.
2. A riposte can't itself be parried, to avoid infinite exchanges.
3. Starting numbers — `PARRY_DIFFICULTY = 14`, `RIPOSTE_DIFFICULTY = 12`, stance ±2,
   riposte damage ×1.5, modifier = floor((score-10)/2) — are just a first pass, meant to
   be tuned by feel.
4. Whether an ordinary (non-parried, non-crit-triggered) attack can also crit on a
   natural 20 of its own, or crits only ever come from the parry roll's extremes — the
   design above only wires crits through the parry roll.
5. Monster stance is fixed per kind for now, not chosen dynamically by behaviour.
6. Heavy weapons can't riposte at all (a hard cutoff) rather than just suffering a big
   penalty Strength could claw back from — confirm that's the right feel, versus making
   Heavy merely very hard instead of impossible.
7. Armor weight only penalizes the riposte roll (Light/Medium/Heavy = 0/-1/-3) rather
   than gating it outright the way Heavy weapons do — confirm that asymmetry is right,
   versus a hard block (e.g. can't riposte in heavy armor no matter how light your
   weapon is).

## Verification (once this is actually built)

- `odin run .` — fight goblins and the ogre with the new attributes, confirm parries,
  riposte hits/misses, and both critical outcomes all show distinct messages and correct
  damage; switch player stance and confirm damage/parry rates shift accordingly; confirm
  a riposte can't itself trigger another parry; confirm named bosses' stats are
  unaffected by the Constitution change; confirm the build is clean.

## Future ideas (not this pass)

- **Crit flourish — bleed.** Right now a crit is just bonus damage on the same roll.
  A crit could instead (or additionally) attach a short bleed: the target loses 1-2 HP
  at the start of each of its next few turns. Cheap to build on what already exists —
  reuse the per-creature `blood_color` hit VFX for each tick, and a small turn-counter
  next to the existing `hurt_seconds_left`-style animation state. Start with bleed alone
  before considering other status flourishes (stagger/skipped-turn, extra knockback,
  temporary armor sunder) — those follow the same shape once bleed proves out, but
  bleed is the smallest first step.
