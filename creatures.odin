package main

// The settings for each kind of creature. This table is a good candidate for a
// JSON file later, so balance can be tweaked without recompiling.

import rl "vendor:raylib"
import "hexgrid"

Creature_Kind :: enum {
	Adventurer,
	Goblin,
	Ogre,
}

make_creature :: proc(scene: ^Scene, kind: Creature_Kind, hex: hexgrid.Hex) -> Actor {
	creature: Actor
	switch kind {
	case .Adventurer:
		creature = Actor {
			name                  = "adventurer",
			frame_size            = {16, 24},
			footprint             = SINGLE_HEX_FOOTPRINT[:],
			shadow_radius         = 6,
			blood_color           = {200, 30, 30, 255},
			damage_dice           = {count = 1, sides = 6, bonus = 1},
			max_hit_points        = 20,
			walk_seconds          = 0.3,
			attack_seconds        = 0.5,
			knockback_distance    = 4,
			turns_between_actions = 1,
			hurt_sound            = .Hurt_Player,
			death_sound           = .Death_Player,
		}
	case .Goblin:
		creature = Actor {
			name                  = "goblin",
			attack_verb           = "stabs",
			frame_size            = {16, 24},
			footprint             = SINGLE_HEX_FOOTPRINT[:],
			shadow_radius         = 6,
			blood_color           = {150, 20, 20, 255}, // try {60, 140, 30, 255} for green goblin blood
			damage_dice           = {count = 1, sides = 4},
			max_hit_points        = 10,
			walk_seconds          = 0.3,
			attack_seconds        = 0.5,
			knockback_distance    = 4,
			turns_between_actions = 1,
			weapon_sound          = .Light,
			hurt_sound            = .Hurt_Goblin,
			death_sound           = .Death_Goblin,
		}
	case .Ogre:
		creature = Actor {
			name                  = "ogre",
			attack_verb           = "smashes",
			frame_size            = {40, 48},
			footprint             = TRIANGLE_FOOTPRINT[:],
			shadow_radius         = 15,
			blood_color           = {120, 25, 15, 255},
			damage_dice           = {count = 2, sides = 4},
			max_hit_points        = 18,
			walk_seconds          = 0.45, // heavy and slow...
			attack_seconds        = 0.8,  // ...with a long, readable wind-up
			knockback_distance    = 1.5,
			turns_between_actions = 2,    // acts every other turn
			shakes_screen_on_hit  = true,
			weapon_sound          = .Heavy,
			hurt_sound            = .Hurt_Ogre,
			death_sound           = .Death_Ogre,
		}
	}
	creature.kind = kind
	creature.tint = rl.WHITE
	creature.sprite_sheet = scene.creature_sprites[kind]
	creature.hex = hex
	creature.hit_points = creature.max_hit_points
	creature.facing = .South_East
	return creature
}
