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

make_creature :: proc(scene: ^Scene, kind: Creature_Kind, hex: hexgrid.Hex) -> Actor {
	definition := CREATURES[kind]
	creature := Actor {
		kind                  = kind,
		name                  = definition.name,
		attack_verb           = definition.attack_verb,
		frame_size            = definition.frame_size,
		footprint             = definition.footprint,
		shadow_radius         = definition.shadow_radius,
		blood_color           = definition.blood_color,
		damage_dice           = definition.damage_dice,
		armor                 = definition.armor,
		max_hit_points        = definition.max_hit_points,
		walk_seconds          = definition.walk_seconds,
		attack_seconds        = definition.attack_seconds,
		knockback_distance    = definition.knockback_distance,
		turns_between_actions = definition.turns_between_actions,
		shakes_screen_on_hit  = definition.shakes_screen_on_hit,
		weapon_sound          = definition.weapon_sound,
		hurt_sound            = definition.hurt_sound,
		death_sound           = definition.death_sound,
		behaviours            = definition.behaviours,
		tint                  = rl.WHITE,
		sprite_sheet          = scene.creature_sprites[kind],
		hex                   = hex,
		hit_points            = definition.max_hit_points,
		facing                = .South_East,
	}
	return creature
}
