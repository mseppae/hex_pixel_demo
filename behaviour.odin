package main

// Behaviours: the capabilities a creature can have.
//
// Each entry of Behaviour_Kind is one thing the code knows how to do. A creature's
// definition in content.json lists which ones it has, in priority order, and the turn
// code simply asks each in turn "do you want to act?" until one says yes. So a new
// creature is data, and only a genuinely new capability is code.

import "core:math/rand"
import "hexgrid"

Behaviour_Kind :: enum u8 {
	Flee_When_Hurt, // run from the player once badly wounded
	Melee_Attack,   // strike whatever stands next to it
	Chase_Player,   // walk toward the player
	Wander,         // drift one hex at random
}

// One behaviour of one creature. Only the fields its kind uses are filled in.
Behaviour :: struct {
	kind:            Behaviour_Kind,
	below:           f32,  // Flee_When_Hurt: flee under this share of full health (0.3 = 30%)
	notice_distance: i32,  // Chase_Player: how far away it notices you
	damage_dice:     Dice, // Melee_Attack
	verb:            string,
	chance:          f32,  // Wander: how often it bothers to move
}

MAX_BEHAVIOURS :: 6

// Tries one behaviour. Returns true if the creature used its turn on it.
try_behaviour :: proc(scene: ^Scene, creature: ^Actor, behaviour: Behaviour) -> bool {
	player := &scene.player
	distance_to_player := actors_distance(creature, player)

	switch behaviour.kind {
	case .Flee_When_Hurt:
		badly_hurt := f32(creature.hit_points) <= f32(creature.max_hit_points) * behaviour.below
		if !badly_hurt || distance_to_player > 3 do return false
		retreat, found := step_away_from(scene, creature, player.hex)
		if !found do return false // cornered: let the next behaviour (usually attacking) act
		start_walk(creature, retreat)
		return true

	case .Melee_Attack:
		if distance_to_player != 1 do return false
		start_attack(creature, player)
		return true

	case .Chase_Player:
		if distance_to_player > behaviour.notice_distance do return false
		next_step, path_exists := find_first_step(scene, creature, stop_next_to = player)
		if !path_exists do return false
		start_walk(creature, next_step)
		return true

	case .Wander:
		if rand.float32() > behaviour.chance do return false
		direction := rand.choice_enum(hexgrid.Direction)
		destination := hexgrid.hex_neighbor(creature.hex, direction)
		if !can_stand(scene, creature, destination) do return false
		start_walk(creature, destination)
		return true
	}
	return false
}

// The neighbouring hex that puts the most distance between the creature and `from`.
step_away_from :: proc(scene: ^Scene, creature: ^Actor, from: hexgrid.Hex) -> (step: hexgrid.Hex, found: bool) {
	best_distance := hexgrid.hex_distance(creature.hex, from)
	for direction in hexgrid.Direction {
		candidate := hexgrid.hex_neighbor(creature.hex, direction)
		if !can_stand(scene, creature, candidate) do continue
		distance := hexgrid.hex_distance(candidate, from)
		if distance > best_distance {
			best_distance = distance
			step = candidate
			found = true
		}
	}
	return step, found
}

// How far this creature notices the player, from whichever behaviour cares.
notice_distance_of :: proc(creature: ^Actor) -> i32 {
	furthest: i32 = 1
	for behaviour in creature.behaviours {
		if behaviour.kind == .Chase_Player do furthest = max(furthest, behaviour.notice_distance)
	}
	return furthest
}
