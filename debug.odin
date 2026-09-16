package main

// Developer tools are deliberately driven by the same content tables as the game.
// That makes every item and creature testable immediately after adding it to
// assets/content.json, without needing to add another hard-coded cheat entry.

import "core:fmt"
import rl "vendor:raylib"
import "hexgrid"

DEBUG_MAX_DEPTH :: 99
DEBUG_PANEL :: rl.Rectangle{f32(LOW_RES_WIDTH - 360) / 2, f32(LOW_RES_HEIGHT - 178) / 2, 360, 178}

open_debug_panel :: proc(scene: ^Scene) {
	scene.open_panel = .Debug
	scene.debug_depth = scene.current_depth
	set_message(scene, "Developer tools open.")
}

// Returns a nearby legal anchor, preferring an empty hex two steps away so a spawned
// monster does not immediately overlap the player or force an unavoidable attack.
debug_spawn_hex :: proc(scene: ^Scene, creature: ^Actor) -> (hex: hexgrid.Hex, found: bool) {
	level := current_level(scene)
	for distance in 2 ..= 6 {
		for _, index in level.tiles {
			candidate := hexgrid.grid_hex_at(level.size, index)
			if hexgrid.hex_distance(scene.player.hex, candidate) != i32(distance) do continue
			if can_stand(scene, creature, candidate) do return candidate, true
		}
	}
	return {}, false
}

debug_spawn_selected_item :: proc(scene: ^Scene) {
	if len(ITEMS) == 0 do return
	kind := Item_Kind(scene.debug_item_index % len(ITEMS))
	count := 100 if ITEMS[kind].category == .Gold else 1
	if !add_to_inventory(&scene.inventory, Item_Stack{kind = kind, count = count}) {
		set_message(scene, "No backpack room for %s.", ITEMS[kind].name)
		return
	}
	if count > 1 {
		set_message(scene, "Debug: added %d gold.", count)
	} else {
		set_message(scene, "Debug: added %s.", ITEMS[kind].name)
	}
}

debug_spawn_selected_monster :: proc(scene: ^Scene) {
	if len(CREATURES) == 0 do return
	kind := Creature_Kind(scene.debug_creature_index % len(CREATURES))
	monster := make_creature(kind, {})
	spot, found := debug_spawn_hex(scene, &monster)
	if !found {
		set_message(scene, "No open ground nearby for %s.", CREATURES[kind].name)
		return
	}
	monster.hex = spot
	append(&current_level(scene).monsters, monster)
	set_message(scene, "Debug: spawned %s.", CREATURES[kind].name)
}

debug_heal_player :: proc(scene: ^Scene) {
	player := &scene.player
	healed := player.max_hit_points - player.hit_points
	player.hit_points = player.max_hit_points
	set_message(scene, "Debug: restored %d HP.", healed)
}

// A jump generates every intermediate depth, preserving the normal deterministic
// seed sequence and making it possible to walk back through the generated levels.
debug_go_to_depth :: proc(scene: ^Scene) {
	target := max(0, min(scene.debug_depth, DEBUG_MAX_DEPTH))
	for len(scene.levels) <= target do append(&scene.levels, generate_level(scene, len(scene.levels)))
	scene.current_depth = target
	scene.deepest_depth = max(scene.deepest_depth, target)
	scene.player.hex = current_level(scene).stairs_up_hex
	scene.player.action = .None
	scene.turn_phase = .Player_Choosing
	scene.travel_destination = nil
	clear_effects(&scene.effects)
	set_message(scene, "Debug: moved to %s.", depth_name(target))
}

handle_debug_keys :: proc(scene: ^Scene) {
	if scene.open_panel != .Debug || scene.turn_phase != .Player_Choosing do return
	if len(ITEMS) == 0 || len(CREATURES) == 0 do return
	if rl.IsKeyPressed(.UP) do scene.debug_item_index = (scene.debug_item_index + len(ITEMS) - 1) % len(ITEMS)
	if rl.IsKeyPressed(.DOWN) do scene.debug_item_index = (scene.debug_item_index + 1) % len(ITEMS)
	if rl.IsKeyPressed(.ENTER) do debug_spawn_selected_item(scene)
	if rl.IsKeyPressed(.LEFT) do scene.debug_creature_index = (scene.debug_creature_index + len(CREATURES) - 1) % len(CREATURES)
	if rl.IsKeyPressed(.RIGHT) do scene.debug_creature_index = (scene.debug_creature_index + 1) % len(CREATURES)
	if rl.IsKeyPressed(.SPACE) do debug_spawn_selected_monster(scene)
	if rl.IsKeyPressed(.H) do debug_heal_player(scene)
	if rl.IsKeyPressed(.LEFT_BRACKET) do scene.debug_depth = max(0, scene.debug_depth - 1)
	if rl.IsKeyPressed(.RIGHT_BRACKET) do scene.debug_depth = min(DEBUG_MAX_DEPTH, scene.debug_depth + 1)
	if rl.IsKeyPressed(.G) do debug_go_to_depth(scene)
}

draw_debug_panel :: proc(scene: ^Scene) {
	draw_panel(DEBUG_PANEL, "Developer tools (F1 closes)")
	item := ITEMS[scene.debug_item_index % len(ITEMS)]
	creature := CREATURES[scene.debug_creature_index % len(CREATURES)]
	x := i32(DEBUG_PANEL.x) + 10
	y := i32(DEBUG_PANEL.y) + 28
	draw_text("Up/Down + Enter: add item", x, y, DIM_TEXT_COLOR)
	draw_text(fmt.tprintf("  %s [%s]", item.name, item.id), x, y + 12, TEXT_COLOR)
	draw_text("Left/Right + Space: spawn monster", x, y + 36, DIM_TEXT_COLOR)
	draw_text(fmt.tprintf("  %s [%s]", creature.name, creature.id), x, y + 48, TEXT_COLOR)
	draw_text("H: fully heal", x, y + 72, TEXT_COLOR)
	draw_text(fmt.tprintf("[/]: target depth %d     G: go there", scene.debug_depth), x, y + 88, TEXT_COLOR)
	draw_text("Tools work only while it is your turn.", x, y + 120, DIM_TEXT_COLOR)
}
