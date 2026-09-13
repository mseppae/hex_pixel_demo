package main

// The settings for each kind of creature, filled from assets/content.json at startup
// (see content.odin). Only the ids live in code, as Creature_Kind; everything else,
// including which behaviours a creature has, is data.

import rl "vendor:raylib"
import "hexgrid"

Creature_Kind :: enum {
	Adventurer,
	Goblin,
	Ogre,
}

Creature_Definition :: struct {
	name:                  string,
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
}

CREATURES: [Creature_Kind]Creature_Definition

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
