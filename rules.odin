package main

// The game rules: who stands where, taking turns, stairs, combat, and finding paths.

import "core:fmt"
import "core:math"
import "core:math/rand"
import rl "vendor:raylib"
import "hexgrid"

SCREEN_SHAKE_SECONDS    :: 0.3
LEVEL_FADE_SECONDS      :: 0.35 // fade to black, then the same back in
MONSTER_NOTICE_DISTANCE :: 7    // sleeping monsters wake when you come this close

// Whose turn it is. While someone is "acting", their animation plays and
// clicks are ignored, so each action finishes before the next one starts.
Turn_Phase :: enum {
	Player_Choosing,
	Player_Acting,
	Monsters_Acting,
	Changing_Level,
	Player_Dead,
}

Stairs_Direction :: enum {
	None,
	Down,
	Up,
}

Level_Change :: struct {
	direction:   Stairs_Direction,
	seconds:     f32,  // time since the fade started
	has_swapped: bool, // true once the new level is in place (at full black)
}

// levels[0] is the village (depth 0), levels[1] is depth 1, and so on.
current_level :: proc(scene: ^Scene) -> ^Level {
	return scene.levels[scene.current_depth]
}

depth_name :: proc(depth: int) -> string {
	return "The village" if depth == 0 else fmt.tprintf("Depth %d", depth)
}

// ---------------------------------------------------------------------------
// The map and who stands where
// ---------------------------------------------------------------------------

is_on_map :: proc(level: ^Level, hex: hexgrid.Hex) -> bool {
	_, inside := tile_at(level, hex)
	return inside
}

// Hexes outside the map count as walls.
is_wall :: proc(level: ^Level, hex: hexgrid.Hex) -> bool {
	tile, inside := tile_at(level, hex)
	return !inside || tile.kind == .Wall
}

is_open_ground :: proc(level: ^Level, hex: hexgrid.Hex) -> bool {
	return !is_wall(level, hex)
}

stairs_at :: proc(level: ^Level, hex: hexgrid.Hex) -> Stairs_Direction {
	tile, _ := tile_at(level, hex)
	#partial switch tile.kind {
	case .Stairs_Down: return .Down
	case .Stairs_Up:   return .Up
	}
	return .None
}

// The living creature covering this hex on the current level, or nil.
actor_at :: proc(scene: ^Scene, hex: hexgrid.Hex) -> ^Actor {
	player := &scene.player
	if !player.is_dead && footprint_covers(player, player.hex, hex) do return player
	for &monster in current_level(scene).monsters {
		if !monster.is_dead && footprint_covers(&monster, monster.hex, hex) do return &monster
	}
	return nil
}

// Could `mover` stand with its anchor on `anchor` in `level`? Every hex of its footprint
// must be open ground and not taken by anyone else. (Its own current hexes don't count as
// taken, which matters for the ogre: its next position overlaps its current one.)
// `player` may be nil while a level is still being built.
can_stand_in :: proc(level: ^Level, player: ^Actor, mover: ^Actor, anchor: hexgrid.Hex) -> bool {
	for offset in actor_footprint(mover) {
		hex := hexgrid.hex_add(anchor, offset)
		if !is_open_ground(level, hex) do return false
		if player != nil && player != mover && !player.is_dead && footprint_covers(player, player.hex, hex) do return false
		for &monster in level.monsters {
			if &monster != mover && !monster.is_dead && footprint_covers(&monster, monster.hex, hex) do return false
		}
		for &container in level.containers {
			if container_blocks_movement(&container) && container_covers(&container, hex) do return false
		}
		for npc in level.npcs {
			if npc.hex == hex do return false
		}
	}
	return true
}

can_stand :: proc(scene: ^Scene, mover: ^Actor, anchor: hexgrid.Hex) -> bool {
	return can_stand_in(current_level(scene), &scene.player, mover, anchor)
}

roll_dice :: proc(dice: Dice) -> int {
	total := dice.bonus
	for _ in 0 ..< dice.count {
		total += 1 + rand.int_max(dice.sides)
	}
	return total
}

// ---------------------------------------------------------------------------
// Starting a game
// ---------------------------------------------------------------------------

start_new_game :: proc(scene: ^Scene, game_seed: u64) {
	for level in scene.levels do destroy_level(level)
	clear(&scene.levels)
	clear_effects(&scene.effects)

	scene.game_seed = game_seed
	scene.adventure_id = new_adventure_id()
	scene.deepest_depth = 0
	scene.quest_states = {}
	scene.named_slain = {}
	scene.player = make_creature(.Adventurer, {})
	clear(&scene.inventory.backpack)
	scene.inventory.gold = 0
	scene.inventory.gold_collected = 0
	scene.inventory.weapon = Item_Kind.Short_Sword
	scene.inventory.armor = nil
	add_to_inventory(&scene.inventory, Item_Stack{.Healing_Potion, 1})
	apply_equipment(scene)
	scene.open_panel = .None
	scene.travel_destination = nil
	append(&scene.levels, generate_level(scene, 0))
	scene.current_depth = 0
	scene.player.hex = current_level(scene).stairs_up_hex
	scene.turn_phase = .Player_Choosing
	set_message(scene, "The village. Talk to the elder and the smith. (seed %d)", game_seed)
}

// ---------------------------------------------------------------------------
// Turns
// ---------------------------------------------------------------------------

handle_click :: proc(scene: ^Scene, clicked_hex: hexgrid.Hex) {
	switch scene.turn_phase {
	case .Player_Acting, .Monsters_Acting, .Changing_Level:
		scene.travel_destination = nil // any click, even mid-step, cancels a walk in progress
		return // wait for the current action to finish
	case .Player_Dead:
		return // the ranking screen takes over
	case .Player_Choosing:
	}

	player := &scene.player
	level := current_level(scene)
	scene.travel_destination = nil // a fresh command always overrides any walk in progress

	// Clicking the stairs you're standing on uses them.
	if clicked_hex == player.hex {
		direction := stairs_at(level, clicked_hex)
		if direction != .None do begin_level_change(scene, direction)
		return
	}

	// A villager: talk when next to them, otherwise walk over.
	if npc_index := npc_index_at(level, clicked_hex); npc_index >= 0 {
		if hexgrid.hex_distance(player.hex, clicked_hex) <= 1 {
			open_dialogue(scene, npc_index)
			return
		}
		next_step, path_exists := find_first_step(scene, player, stop_next_to_hex = clicked_hex)
		if path_exists {
			start_walk(player, next_step)
			scene.travel_destination = clicked_hex
			scene.travel_adjacent_only = true
			scene.turn_phase = .Player_Acting
		}
		return
	}

	clicked_creature := actor_at(scene, clicked_hex)
	containers_there := container_indices_at(level, clicked_hex)
	if clicked_creature == nil && len(containers_there) > 0 {
		// Next to that hex (or on it): look through everything lying there.
		if hexgrid.hex_distance(player.hex, clicked_hex) <= 1 {
			open_loot_panel(scene, containers_there[:])
			return
		}

		// A chest can't be walked onto, so approach and stop next to it. Corpses and
		// dropped items don't block movement, so walk straight onto the hex.
		blocks_movement := false
		for index in containers_there {
			if container_blocks_movement(&level.containers[index]) do blocks_movement = true
		}
		if blocks_movement {
			next_step, path_exists := find_first_step(scene, player, stop_next_to_hex = clicked_hex)
			if path_exists {
				start_walk(player, next_step)
				scene.travel_destination = clicked_hex
				scene.travel_adjacent_only = true
				scene.turn_phase = .Player_Acting
			}
			return
		}
		next_step, path_exists := find_first_step(scene, player, destination = clicked_hex)
		if path_exists {
			start_walk(player, next_step)
			scene.travel_destination = clicked_hex
			scene.travel_adjacent_only = false
			scene.turn_phase = .Player_Acting
		}
		return
	}

	if clicked_creature != nil {
		// Next to it: attack. Otherwise: walk toward it.
		if actors_distance(player, clicked_creature) == 1 {
			start_attack(player, clicked_creature)
			scene.turn_phase = .Player_Acting
			return
		}
		next_step, path_exists := find_first_step(scene, player, stop_next_to = clicked_creature)
		if path_exists {
			start_walk(player, next_step)
			scene.turn_phase = .Player_Acting
		}
		return
	}

	next_step, path_exists := find_first_step(scene, player, destination = clicked_hex)
	if !path_exists {
		set_message(scene, "You can't get there.")
		return
	}
	start_walk(player, next_step)
	scene.travel_destination = clicked_hex
	scene.travel_adjacent_only = false
	// Stepping onto the stairs you clicked takes them, once the step has finished.
	if next_step == clicked_hex {
		scene.stairs_after_this_step = stairs_at(level, next_step)
	}
	scene.turn_phase = .Player_Acting
}

// Called every frame: moves to the next turn once all animations have finished.
advance_turns :: proc(scene: ^Scene) {
	if actor_is_animating(&scene.player) do return
	for &monster in current_level(scene).monsters {
		if actor_is_animating(&monster) do return
	}

	#partial switch scene.turn_phase {
	case .Player_Acting:
		if scene.stairs_after_this_step != .None {
			direction := scene.stairs_after_this_step
			scene.stairs_after_this_step = .None
			begin_level_change(scene, direction)
			return
		}
		scene.turn_phase = .Monsters_Acting
		scene.monster_turn_index = 0
		start_next_monster_turn(scene)
	case .Monsters_Acting:
		scene.monster_turn_index += 1
		start_next_monster_turn(scene)
	}
}

// Gives the turn to the next monster that actually does something; a monster that
// only waits (or is dead, or asleep) is skipped at once.
start_next_monster_turn :: proc(scene: ^Scene) {
	monsters := &current_level(scene).monsters
	for scene.monster_turn_index < len(monsters) {
		if scene.player.is_dead {
			player_has_died(scene)
			return
		}
		started_an_action := take_monster_turn(scene, &monsters[scene.monster_turn_index])
		if started_an_action do return // advance_turns continues once its animation ends
		scene.monster_turn_index += 1
	}
	if scene.player.is_dead {
		player_has_died(scene)
	} else {
		continue_travel(scene)
	}
}

any_monster_awake :: proc(level: ^Level) -> bool {
	for &monster in level.monsters {
		if monster.is_awake && !monster.is_dead do return true
	}
	return false
}

// Once the player's step and every monster's turn have finished, either keep walking
// toward a travel destination on autopilot, or hand control back to the player.
continue_travel :: proc(scene: ^Scene) {
	scene.turn_phase = .Player_Choosing
	destination, traveling := scene.travel_destination.?
	if !traveling do return

	player := &scene.player
	arrived := hexgrid.hex_distance(player.hex, destination) <= 1 if scene.travel_adjacent_only else player.hex == destination
	if arrived {
		scene.travel_destination = nil
		return
	}
	if any_monster_awake(current_level(scene)) {
		scene.travel_destination = nil
		set_message(scene, "Something's nearby. You stop.")
		return
	}

	next_step: hexgrid.Hex
	path_exists: bool
	if scene.travel_adjacent_only {
		next_step, path_exists = find_first_step(scene, player, stop_next_to_hex = destination)
	} else {
		next_step, path_exists = find_first_step(scene, player, destination = destination)
	}
	if !path_exists {
		scene.travel_destination = nil
		return
	}
	start_walk(player, next_step)
	scene.turn_phase = .Player_Acting
	if !scene.travel_adjacent_only && next_step == destination {
		scene.stairs_after_this_step = stairs_at(current_level(scene), next_step)
	}
}

// The death animation has finished: the adventure is over.
player_has_died :: proc(scene: ^Scene) {
	scene.turn_phase = .Player_Dead
	end_adventure(scene)
}

// Returns true if the monster started an action. The monster itself decides nothing:
// its behaviours (see behaviour.odin) are tried in order until one acts.
take_monster_turn :: proc(scene: ^Scene, monster: ^Actor) -> bool {
	if monster.is_dead do return false
	definition := CREATURES[monster.kind]

	if !monster.is_awake {
		if actors_distance(monster, &scene.player) > notice_distance_of(monster) do return false
		monster.is_awake = true
	}

	// Slow creatures only act every few turns.
	monster.turns_waited += 1
	if monster.turns_waited < definition.turns_between_actions do return false
	monster.turns_waited = 0

	for behaviour in definition.behaviours {
		if try_behaviour(scene, monster, behaviour) do return true
	}
	return false
}

// ---------------------------------------------------------------------------
// Stairs
// ---------------------------------------------------------------------------

begin_level_change :: proc(scene: ^Scene, direction: Stairs_Direction) {
	scene.turn_phase = .Changing_Level
	scene.level_change = Level_Change{direction = direction}
}

// Fade to black, swap levels while the screen is black, fade back in.
update_level_change :: proc(scene: ^Scene, frame_seconds: f32) {
	if scene.turn_phase != .Changing_Level do return
	change := &scene.level_change
	change.seconds += frame_seconds
	if !change.has_swapped && change.seconds >= LEVEL_FADE_SECONDS {
		move_to_level(scene, change.direction)
		change.has_swapped = true
	}
	if change.seconds >= 2 * LEVEL_FADE_SECONDS {
		scene.turn_phase = .Player_Choosing
	}
}

// How dark the screen is during a level change: 0 = normal, 1 = black.
level_change_darkness :: proc(scene: ^Scene) -> f32 {
	if scene.turn_phase != .Changing_Level do return 0
	progress := scene.level_change.seconds / LEVEL_FADE_SECONDS // 0 to 2
	return progress if progress < 1 else max(0, 2 - progress)
}

move_to_level :: proc(scene: ^Scene, direction: Stairs_Direction) {
	target_depth := scene.current_depth + (1 if direction == .Down else -1)
	first_visit := target_depth >= len(scene.levels)
	if first_visit {
		append(&scene.levels, generate_level(scene, target_depth))
	}
	scene.current_depth = target_depth
	scene.deepest_depth = max(scene.deepest_depth, target_depth)
	scene.travel_destination = nil
	level := current_level(scene)

	// Going down, you arrive on the new level's stairs up, and the other way round.
	scene.player.hex = level.stairs_up_hex if direction == .Down else level.stairs_down_hex
	scene.player.action = .None
	clear_effects(&scene.effects) // drops in mid-air and numbers belong to the old level

	switch {
	case target_depth == 0: set_message(scene, "Back in the village. Fresh air, at last.")
	case first_visit:       set_message(scene, "Depth %d. The air is colder here.", target_depth)
	case:                   set_message(scene, "Back on depth %d. It's just as you left it.", target_depth)
	}
}

// ---------------------------------------------------------------------------
// Combat
// ---------------------------------------------------------------------------

// The moment a weapon connects: roll damage, then trigger the flash, knockback, blood and number.
resolve_attack_impact :: proc(scene: ^Scene, attacker, target: ^Actor) {
	attacker_definition := CREATURES[attacker.kind]
	target_definition := CREATURES[target.kind]

	// Armor takes some of the sting out of every hit, but a hit always does at least 1.
	damage := max(1, roll_dice(attacker.damage_dice) - target.armor)
	target.hit_points = max(0, target.hit_points - damage)
	target.is_awake = true

	target_center := footprint_center(target, target.hex)
	away_from_attacker := rl.Vector3Normalize(target_center - footprint_center(attacker, attacker.hex))
	target.hurt_seconds_left = HURT_SECONDS
	target.knockback_direction = away_from_attacker
	if attacker_definition.shakes_screen_on_hit {
		scene.screen_shake_seconds_left = SCREEN_SHAKE_SECONDS
	}

	// Halfway up the (stretched) upright sprite, so the spray starts at the chest
	// of the drawing rather than at its knees.
	chest_height := target_center + {0, target_definition.frame_size.y * 0.5 / scene.camera_up.y, 0}
	spawn_blood_spray(&scene.effects, chest_height, away_from_attacker, target_definition.blood_color, 10 + damage * 4)

	// The impact, and the victim's cry: a death cry if this blow kills.
	play_sound(&scene.sound, IMPACT_SOUNDS[attacker.weapon_sound])
	play_sound(&scene.sound, target_definition.death_sound if target.hit_points == 0 else target_definition.hurt_sound)

	target_is_player := target == &scene.player
	number_color := rl.RED if target_is_player else rl.WHITE
	add_floating_number(&scene.effects, target_center, target_definition.frame_size.y + 16, damage, number_color) // above the health bar

	if attacker == &scene.player {
		set_message(scene, "You hit %s for %d.", display_name(target), damage)
	} else {
		set_message(scene, "%s %s you for %d.", display_name(attacker, start_of_sentence = true), attacker_definition.attack_verb, damage)
	}

	if target.hit_points == 0 {
		target.is_dead = true
		target.death_seconds = 0
		leave_corpse(scene, target)
		// A last, bigger burst in every direction.
		for _ in 0 ..< 6 {
			angle := rand.float32_range(0, 2 * math.PI)
			spawn_blood_spray(&scene.effects, chest_height, {math.cos(angle), 0, math.sin(angle)}, target_definition.blood_color, len(target_definition.footprint) * 10)
		}
		if target_is_player {
			scene.killed_by = attacker.kind
			set_message(scene, "You have been slain on depth %d.", scene.current_depth)
		} else {
			set_message(scene, "%s dies!", display_name(target, start_of_sentence = true))
			note_named_death(scene, target)
		}
	}
}

// ---------------------------------------------------------------------------
// Directions and paths
// ---------------------------------------------------------------------------

// The hex direction that points most closely from one world position toward another.
direction_toward_position :: proc(from, to: rl.Vector3) -> hexgrid.Direction {
	wanted := rl.Vector2{to.x - from.x, to.z - from.z}
	best_direction := hexgrid.Direction.East
	best_alignment := -math.INF_F32
	for direction in hexgrid.Direction {
		one_step := hexgrid.hex_to_pixel(hexgrid.DIRECTION_OFFSETS[direction], 1)
		alignment := rl.Vector2DotProduct(wanted, one_step)
		if alignment > best_alignment {
			best_alignment = alignment
			best_direction = direction
		}
	}
	return best_direction
}

// Breadth-first search over the places `mover` could put its anchor. It explores
// outward one ring of neighbors at a time, so the first goal it reaches is the
// closest. The goal is either a hex (`destination`) or "standing next to" a creature
// (`stop_next_to`). Every position is checked with can_stand, so the ogre's whole
// triangle has to fit at each step. Returns the first anchor to step onto.
find_first_step :: proc(scene: ^Scene, mover: ^Actor, destination := hexgrid.Hex{}, stop_next_to: ^Actor = nil, stop_next_to_hex: Maybe(hexgrid.Hex) = nil) -> (first_step: hexgrid.Hex, path_exists: bool) {
	is_goal :: proc(mover: ^Actor, anchor, destination: hexgrid.Hex, stop_next_to: ^Actor, stop_next_to_hex: Maybe(hexgrid.Hex)) -> bool {
		if stop_next_to != nil {
			return footprint_distance(mover, anchor, stop_next_to, stop_next_to.hex) == 1
		}
		if hex, has_hex := stop_next_to_hex.?; has_hex {
			return hexgrid.hex_distance(anchor, hex) <= 1
		}
		return anchor == destination
	}

	start := mover.hex
	came_from := make(map[hexgrid.Hex]hexgrid.Hex, allocator = context.temp_allocator)
	frontier := make([dynamic]hexgrid.Hex, context.temp_allocator)
	came_from[start] = start
	append(&frontier, start)

	goal_anchor := start
	goal_found := false
	for next_index := 0; next_index < len(frontier); next_index += 1 {
		current := frontier[next_index]
		if is_goal(mover, current, destination, stop_next_to, stop_next_to_hex) {
			goal_anchor = current
			goal_found = true
			break
		}
		for direction in hexgrid.Direction {
			neighbor := hexgrid.hex_neighbor(current, direction)
			if neighbor in came_from do continue
			if !can_stand(scene, mover, neighbor) do continue
			came_from[neighbor] = current
			append(&frontier, neighbor)
		}
	}

	if !goal_found || goal_anchor == start {
		return start, false
	}
	// Walk the path backwards from the goal until the anchor right after the start.
	first_step = goal_anchor
	for came_from[first_step] != start {
		first_step = came_from[first_step]
	}
	return first_step, true
}

// Seeds are kept below a billion: short enough to read out and share, and safely
// stored as a JSON number.
new_random_seed :: proc() -> u64 {
	return rand.uint64() % 1_000_000_000
}

// A random number that marks every save of one adventure, so dying can find and
// delete them all. Kept below 2^52 so it's stored exactly as a JSON number.
new_adventure_id :: proc() -> u64 {
	return 1 + rand.uint64() % (1 << 52)
}

// Messages are formatted into a small buffer inside the scene, so they stay valid
// between frames without allocating memory.
set_message :: proc(scene: ^Scene, format: string, arguments: ..any) {
	scene.message = fmt.bprintf(scene.message_buffer[:], format, ..arguments)
}
