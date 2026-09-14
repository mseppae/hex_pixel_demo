package main

// The settings for each kind of creature, filled from assets/content.json at startup
// (see content.odin). Everything about a creature is data, including which sprite
// sheet draws it, what it's called when something dies to it, and what it drops.
// See DESIGN_DATA_DRIVEN.md.

import rl "vendor:raylib"
import "hexgrid"

// An index into CREATURES, resolved once (at spawn, or at content load for a fixed
// reference like Adventurer/Goblin/Ogre below) and cheap to carry around after that.
// It is only meaningful for the run that resolved it: nothing outside this process
// should ever see the number. Anything that outlives the process (a save file, the
// ranking list) stores the creature's `id` string instead — see save.odin.
Creature_Kind :: int

Creature_Definition :: struct {
	id:                    string, // matches content.json and what level tables, quests etc. refer to it by
	name:                  string,
	article:               string, // "a goblin", "another adventurer": for death messages and the ranking list
	sprite_sheet:          string, // a file name in assets/ (see load_creature_sprite_sheet)
	corpse:                Container_Kind, // which existing corpse silhouette it leaves (see items.odin)
	attack_verb:           string,
	frame_size:            rl.Vector2,
	footprint:             []hexgrid.Hex,
	shadow_radius:         f32,
	blood_color:           rl.Color,
	damage_dice:           Dice,
	armor:                 int,
	max_hit_points:        int,
	// Attributes and combat posture: per-kind, never overridden per-instance (unlike
	// damage_dice/armor, which the player's equipment resolves onto Actor instead).
	// See DESIGN_COMBAT.md.
	strength:              int,
	dexterity:             int,
	constitution:          int,
	default_stance:        Stance,
	weapon_weight:         Weapon_Weight, // a monster's innate attack (a player's comes from its weapon)
	armor_weight:          Armor_Weight,  // a monster's natural hide (a player's comes from its armor)
	walk_seconds:          f32,
	attack_seconds:        f32,
	knockback_distance:    f32,
	turns_between_actions: int,
	shakes_screen_on_hit:  bool,
	weapon_sound:          Weapon_Sound,
	hurt_sound:            Sound_Id,
	death_sound:           Sound_Id,
	behaviours:            []Behaviour,
	loot:                  []Loot_Table_Entry,
}

// Filled from assets/content.json at startup (see content.odin). Index order matches
// the file, and is otherwise meaningless: nothing should assume, say, that index 0 is
// the adventurer. Use creature_kind_named for that.
CREATURES: [dynamic]Creature_Definition
creature_index_by_id: map[string]Creature_Kind

// The handful of creatures the game itself refers to by name, resolved once right
// after content loads (see resolve_known_content in content.odin). A missing one means
// the built-in content.json itself is broken, which load_content already warns about.
// (The depth-based spawn counts in level.odin are the reason the newer kinds are here
// too — not because anything about them is special.)
ADVENTURER, GOBLIN, OGRE: Creature_Kind
RAT, BAT, SPIDER, SLIME, MUSHROOM, SKELETON, TROLL, GOLEM: Creature_Kind

// Looks up a creature by its content.json id. Used both for the few kinds the code
// itself needs to name (see above) and, at content-load time, for anything that
// refers to a creature by name (a level table, a named creature, ...).
creature_kind_named :: proc(id: string) -> (kind: Creature_Kind, found: bool) {
	kind, found = creature_index_by_id[id]
	return
}

make_creature :: proc(kind: Creature_Kind, hex: hexgrid.Hex) -> Actor {
	definition := CREATURES[kind]
	// Constitution adds to max HP once, at spawn. Named bosses override max_hit_points
	// with a directly-authored final number afterward (see village.odin), so this bonus
	// only ever applies to ordinary creatures.
	max_hit_points := definition.max_hit_points + attribute_modifier(definition.constitution)
	creature := Actor {
		kind               = kind,
		name               = definition.name,
		damage_dice        = definition.damage_dice,
		weapon_weight      = definition.weapon_weight,
		armor              = definition.armor,
		armor_weight       = definition.armor_weight,
		max_hit_points     = max_hit_points,
		knockback_distance = definition.knockback_distance,
		weapon_sound       = definition.weapon_sound,
		tint               = rl.WHITE,
		hex                = hex,
		hit_points         = max_hit_points,
		facing             = .South_East,
		stance             = definition.default_stance,
	}
	return creature
}
