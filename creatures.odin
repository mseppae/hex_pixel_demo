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
	creature := Actor {
		kind               = kind,
		name               = definition.name,
		damage_dice        = definition.damage_dice,
		armor              = definition.armor,
		max_hit_points     = definition.max_hit_points,
		knockback_distance = definition.knockback_distance,
		weapon_sound       = definition.weapon_sound,
		tint               = rl.WHITE,
		hex                = hex,
		hit_points         = definition.max_hit_points,
		facing             = .South_East,
	}
	return creature
}
