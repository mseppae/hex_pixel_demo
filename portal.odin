package main

// A Scroll of Town Portal (items.odin) opens a two-way link between wherever you read
// it and the village, good for one round trip: stepping into the village leaves it
// open so you can walk back, and stepping back through it to the dungeon closes it.
// There's only ever one open at a time; reading a fresh scroll replaces it.

import "hexgrid"

// Where the village-side portal opens: a few steps from the merchant who sells the
// scrolls, so the "shop" and the "way back down" sit together.
VILLAGE_PORTAL_OFFSET :: hexgrid.Hex{q = 5, r = -1}

Portal :: struct {
	active:      bool,
	depth:       int, // the dungeon depth the other end sits on
	dungeon_hex: hexgrid.Hex,
	village_hex: hexgrid.Hex,
}

// Where the portal shows up on whichever level is currently loaded, if anywhere.
portal_hex_here :: proc(scene: ^Scene) -> (hex: hexgrid.Hex, here: bool) {
	if !scene.portal.active do return {}, false
	if scene.current_depth == 0 do return scene.portal.village_hex, true
	if scene.current_depth == scene.portal.depth do return scene.portal.dungeon_hex, true
	return {}, false
}

// Reading the scroll: opens a link from an open hex next to the player to a fixed
// spot in the village. Replaces any portal already open.
open_portal :: proc(scene: ^Scene) -> bool {
	if scene.current_depth == 0 {
		set_message(scene, "You're already in the village.")
		return false
	}
	dungeon_hex, found := adjacent_open_hex(scene, current_level(scene), scene.player.hex)
	if !found {
		set_message(scene, "There's no room to open a portal here.")
		return false
	}
	scene.portal = Portal {
		active      = true,
		depth       = scene.current_depth,
		dungeon_hex = dungeon_hex,
		village_hex = hexgrid.hex_add(VILLAGE_CENTER, VILLAGE_PORTAL_OFFSET),
	}
	set_message(scene, "A portal to the village shimmers open beside you.")
	return true
}

// The first open, unoccupied neighbor of `from` (the portal never opens under your
// own feet, so stepping onto it is always a deliberate choice).
adjacent_open_hex :: proc(scene: ^Scene, level: ^Level, from: hexgrid.Hex) -> (hex: hexgrid.Hex, found: bool) {
	for direction in hexgrid.Direction {
		candidate := hexgrid.hex_neighbor(from, direction)
		if can_stand_in(level, &scene.player, &scene.player, candidate) do return candidate, true
	}
	return {}, false
}

// Starts the fade-to-black/swap/fade-in transition, the same as taking stairs.
begin_portal_change :: proc(scene: ^Scene) {
	scene.turn_phase = .Changing_Level
	scene.level_change = Level_Change{via_portal = true}
}

// The moment the screen is black: swap depth. Stepping into the village leaves the
// portal open, so you can still walk back through it; only completing the round trip
// back to the dungeon depth closes it.
move_through_portal :: proc(scene: ^Scene) {
	portal := scene.portal
	returning_to_dungeon := scene.current_depth == 0
	if returning_to_dungeon do scene.portal.active = false

	target_depth := 0 if scene.current_depth != 0 else portal.depth
	target_hex := portal.village_hex if scene.current_depth != 0 else portal.dungeon_hex

	scene.current_depth = target_depth
	scene.deepest_depth = max(scene.deepest_depth, target_depth)
	scene.travel_destination = nil
	scene.player.hex = target_hex
	scene.player.action = .None
	clear_effects(&scene.effects)
	set_message(scene, "You step through the portal.")
}
