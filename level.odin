package main

// A level: its tiles, the monsters living on it, and the blood on its floor.
// Every level you visit stays in memory, so going back up the stairs finds
// it exactly as you left it.
//
// Levels are generated from the game seed plus their depth. The same seed always
// builds the same dungeon, which makes bugs reproducible ("seed 4471, depth 3").

import "base:runtime"
import "core:math/rand"
import rl "vendor:raylib"
import "hexgrid"

LEVEL_WIDTH  :: 24
LEVEL_HEIGHT :: 18

// Cave generation: start from random noise, then smooth it a few times.
CAVE_WALL_CHANCE      :: 0.45
CAVE_SMOOTHING_ROUNDS :: 4
MINIMUM_OPEN_TILES    :: 140 // retry if the biggest cave is smaller than this

// Monsters start at least this many steps away from where you arrive.
MONSTER_MINIMUM_START_DISTANCE :: 6

Tile_Kind :: enum u8 {
	Floor,
	Wall,
	Stairs_Down,
	Stairs_Up,
	Forest, // grassy ground you can't walk through: the village is ringed with it
	// New kinds go at the END: saves store these as numbers.
}

FLOOR_VARIANT_COUNT :: 4 // plain, cracked, pebbles, mossy
WALL_VARIANT_COUNT  :: 3 // plain, mossy, cracked

Tile :: struct {
	kind:    Tile_Kind,
	variant: u8, // which drawing of that kind to use
}

Level :: struct {
	depth:              int, // 1 = the first level
	size:               hexgrid.Grid_Size,
	tiles:              []Tile,
	monsters:           [dynamic]Actor,
	containers:         [dynamic]Container, // corpses and chests, with whatever loot is still in them
	props:              [dynamic]Prop,      // trees and bushes; worked out from the tiles, never saved
	npcs:               [dynamic]Npc,       // villagers (only in the village)
	blood_stains:       [dynamic]Blood_Stain,
	oldest_stain_index: int, // once the stain list is full, the oldest one gets replaced
	has_stairs_up:      bool, // the first level has no way up
	stairs_up_hex:      hexgrid.Hex, // where you arrive coming down (also the start of level 1)
	stairs_down_hex:    hexgrid.Hex,
}

tile_at :: proc(level: ^Level, hex: hexgrid.Hex) -> (tile: Tile, inside: bool) {
	index := hexgrid.grid_index(level.size, hex) or_return
	return level.tiles[index], true
}

set_tile_kind :: proc(level: ^Level, hex: hexgrid.Hex, kind: Tile_Kind) {
	index, inside := hexgrid.grid_index(level.size, hex)
	if inside do level.tiles[index].kind = kind
}

destroy_level :: proc(level: ^Level) {
	delete(level.tiles)
	delete(level.monsters)
	for container in level.containers do delete(container.items)
	delete(level.containers)
	delete(level.npcs)
	delete(level.props)
	delete(level.blood_stains)
	free(level)
}

// ---------------------------------------------------------------------------
// Generation
// ---------------------------------------------------------------------------

generate_level :: proc(scene: ^Scene, depth: int) -> ^Level {
	if depth == 0 do return generate_village(scene)
	level := new(Level)
	level.depth = depth
	level.size = {LEVEL_WIDTH, LEVEL_HEIGHT}
	level.tiles = make([]Tile, hexgrid.grid_cell_count(level.size))

	// Each level gets its own random generator, seeded from the game seed and the
	// depth. Combat uses a different generator, so fights never change the map.
	level_seed := scene.game_seed ~ (u64(depth) * 0x9E3779B97F4A7C15)
	random_state := rand.create_u64(level_seed)
	generator := rand.default_random_generator(&random_state)

	for {
		carve_caves(level, generator)
		if keep_largest_cave(level) >= MINIMUM_OPEN_TILES do break
	}
	place_stairs(level, depth, generator)
	choose_tile_variants(level, generator)
	place_chests(level, depth, generator)
	place_monsters(scene, level, depth, generator)
	return level
}

// Random noise, smoothed into caves. A hex surrounded mostly by walls becomes a wall;
// one surrounded mostly by floor becomes floor. After a few rounds, the noise has
// clumped into rounded caverns and winding passages.
carve_caves :: proc(level: ^Level, generator: runtime.Random_Generator) {
	for index in 0 ..< len(level.tiles) {
		is_wall := is_border_index(level, index) || rand.float32(generator) < CAVE_WALL_CHANCE
		level.tiles[index] = Tile{kind = .Wall if is_wall else .Floor}
	}

	for _ in 0 ..< CAVE_SMOOTHING_ROUNDS {
		smoothed := make([]Tile, len(level.tiles), context.temp_allocator)
		for index in 0 ..< len(level.tiles) {
			walls_around := count_wall_neighbors(level, hexgrid.grid_hex_at(level.size, index))
			smoothed[index] = level.tiles[index]
			if is_border_index(level, index) || walls_around >= 4 {
				smoothed[index].kind = .Wall
			} else if walls_around <= 2 {
				smoothed[index].kind = .Floor
			}
		}
		copy(level.tiles, smoothed)
	}
}

// Finds every separate open area, keeps the biggest, and fills in the rest,
// so every floor tile can be reached from every other. Returns the kept area's size.
keep_largest_cave :: proc(level: ^Level) -> int {
	area_of_tile := make([]int, len(level.tiles), context.temp_allocator)
	for &area in area_of_tile do area = -1

	largest_area, largest_size := -1, 0
	area_count := 0
	for index in 0 ..< len(level.tiles) {
		if level.tiles[index].kind == .Wall || area_of_tile[index] != -1 do continue
		size := mark_connected_area(level, index, area_count, area_of_tile)
		if size > largest_size {
			largest_area = area_count
			largest_size = size
		}
		area_count += 1
	}

	for index in 0 ..< len(level.tiles) {
		if level.tiles[index].kind != .Wall && area_of_tile[index] != largest_area {
			level.tiles[index].kind = .Wall
		}
	}
	return largest_size
}

// Flood fill: marks every open tile reachable from start_index with area_number.
mark_connected_area :: proc(level: ^Level, start_index, area_number: int, area_of_tile: []int) -> (size: int) {
	frontier := make([dynamic]int, context.temp_allocator)
	append(&frontier, start_index)
	area_of_tile[start_index] = area_number
	for next := 0; next < len(frontier); next += 1 {
		hex := hexgrid.grid_hex_at(level.size, frontier[next])
		for direction in hexgrid.Direction {
			neighbor_index, inside := hexgrid.grid_index(level.size, hexgrid.hex_neighbor(hex, direction))
			if !inside || level.tiles[neighbor_index].kind == .Wall || area_of_tile[neighbor_index] != -1 do continue
			area_of_tile[neighbor_index] = area_number
			append(&frontier, neighbor_index)
		}
	}
	return len(frontier)
}

// Steps needed to walk from `from` to every tile (-1 where you can't get to).
walking_distances :: proc(level: ^Level, from: hexgrid.Hex) -> []int {
	distances := make([]int, len(level.tiles), context.temp_allocator)
	for &distance in distances do distance = -1
	start_index, inside := hexgrid.grid_index(level.size, from)
	if !inside do return distances

	frontier := make([dynamic]int, context.temp_allocator)
	append(&frontier, start_index)
	distances[start_index] = 0
	for next := 0; next < len(frontier); next += 1 {
		current_index := frontier[next]
		hex := hexgrid.grid_hex_at(level.size, current_index)
		for direction in hexgrid.Direction {
			neighbor_index, neighbor_inside := hexgrid.grid_index(level.size, hexgrid.hex_neighbor(hex, direction))
			if !neighbor_inside || level.tiles[neighbor_index].kind == .Wall || distances[neighbor_index] != -1 do continue
			distances[neighbor_index] = distances[current_index] + 1
			append(&frontier, neighbor_index)
		}
	}
	return distances
}

place_stairs :: proc(level: ^Level, depth: int, generator: runtime.Random_Generator) {
	open_tiles := make([dynamic]int, context.temp_allocator)
	for tile, index in level.tiles {
		if tile.kind == .Floor do append(&open_tiles, index)
	}
	arrival_index := open_tiles[rand.int_max(len(open_tiles), generator)]
	level.stairs_up_hex = hexgrid.grid_hex_at(level.size, arrival_index)
	level.has_stairs_up = depth > 0 // depth 1's stairs lead up to the village
	if level.has_stairs_up {
		level.tiles[arrival_index].kind = .Stairs_Up
	}

	// The way down is as far from the way in as the caves allow.
	distances := walking_distances(level, level.stairs_up_hex)
	farthest_index := arrival_index
	for distance, index in distances {
		if distance > distances[farthest_index] do farthest_index = index
	}
	level.stairs_down_hex = hexgrid.grid_hex_at(level.size, farthest_index)
	level.tiles[farthest_index].kind = .Stairs_Down
}

choose_tile_variants :: proc(level: ^Level, generator: runtime.Random_Generator) {
	for &tile, index in level.tiles {
		roll := rand.float32(generator)
		#partial switch tile.kind {
		case .Floor:
			// Moss grows in damp corners, so floors hemmed in by walls get it more often.
			in_a_corner := count_wall_neighbors(level, hexgrid.grid_hex_at(level.size, index)) >= 3
			switch {
			case in_a_corner && roll < 0.35: tile.variant = 3 // mossy
			case roll < 0.70:                tile.variant = 0 // plain
			case roll < 0.85:                tile.variant = 1 // cracked
			case:                            tile.variant = 2 // pebbles
			}
		case .Wall:
			switch {
			case roll < 0.70: tile.variant = 0 // plain
			case roll < 0.85: tile.variant = 1 // mossy
			case:             tile.variant = 2 // cracked
			}
		}
	}
}

// Chests go in corners: floor tiles mostly surrounded by walls, or at least against
// one. (Deeper nooks rarely exist: the cave smoothing fills them in.) A chest blocks its
// hex, so a spot is only used if the cave stays fully connected around it.
place_chests :: proc(level: ^Level, depth: int, generator: runtime.Random_Generator) {
	chest_count := 1 + rand.int_max(2, generator) // one or two
	distances := walking_distances(level, level.stairs_up_hex)

	// Try snug corners first (3 walls around), then anywhere along a wall (2 walls).
	for minimum_walls_around := 3; minimum_walls_around >= 2; minimum_walls_around -= 1 {
		spots := make([dynamic]int, context.temp_allocator)
		for tile, index in level.tiles {
			hex := hexgrid.grid_hex_at(level.size, index)
			if tile.kind == .Floor && distances[index] >= 4 && count_wall_neighbors(level, hex) >= minimum_walls_around {
				append(&spots, index)
			}
		}
		rand.shuffle(spots[:], generator)

		for index in spots {
			if len(level.containers) >= chest_count do break
			hex := hexgrid.grid_hex_at(level.size, index)
			if len(container_indices_at(level, hex)) > 0 || blocking_would_split_cave(level, hex) do continue
			chest := Container{kind = .Chest, anchor_hex = hex, footprint = SINGLE_HEX_FOOTPRINT[:]}
			roll_chest_loot(depth, generator, &chest.items)
			append(&level.containers, chest)
			level.tiles[index].kind = .Wall // for now, so later chests are checked against this one
		}
	}

	// Chests stand on floor; they block movement through can_stand_in, not by being walls.
	for &chest in level.containers {
		set_tile_kind(level, chest.anchor_hex, .Floor)
	}
}

// Would blocking this hex cut the cave in two? Counts how many open tiles can still
// be reached with the hex blocked.
blocking_would_split_cave :: proc(level: ^Level, hex: hexgrid.Hex) -> bool {
	index, _ := hexgrid.grid_index(level.size, hex)
	original_kind := level.tiles[index].kind
	level.tiles[index].kind = .Wall
	defer level.tiles[index].kind = original_kind

	open_count, reachable_count := 0, 0
	distances := walking_distances(level, level.stairs_up_hex)
	for tile, tile_index in level.tiles {
		if tile.kind == .Wall do continue
		open_count += 1
		if distances[tile_index] >= 0 do reachable_count += 1
	}
	return reachable_count < open_count
}

place_monsters :: proc(scene: ^Scene, level: ^Level, depth: int, generator: runtime.Random_Generator) {
	// Spots far enough from where you arrive, in random order.
	distances := walking_distances(level, level.stairs_up_hex)
	candidate_spots := make([dynamic]hexgrid.Hex, context.temp_allocator)
	for tile, index in level.tiles {
		if tile.kind == .Floor && distances[index] >= MONSTER_MINIMUM_START_DISTANCE {
			append(&candidate_spots, hexgrid.grid_hex_at(level.size, index))
		}
	}
	rand.shuffle(candidate_spots[:], generator)

	// Big creatures first, while there's still room for their footprint.
	ogre_count := (depth + 1) / 2
	goblin_count := min(1 + depth, 6)
	kinds_to_place := make([dynamic]Creature_Kind, context.temp_allocator)
	for _ in 0 ..< ogre_count do append(&kinds_to_place, Creature_Kind.Ogre)
	for _ in 0 ..< goblin_count do append(&kinds_to_place, Creature_Kind.Goblin)

	// A named creature lives on its own depth, unless it has already been slain.
	for named in Named_Creature {
		if named == .None || NAMED_CREATURES[named].depth != depth || scene.named_slain[named] do continue
		creature := make_named_creature(named, {})
		for spot in candidate_spots {
			if can_stand_in(level, nil, &creature, spot) {
				creature.hex = spot
				append(&level.monsters, creature)
				break
			}
		}
	}

	for kind in kinds_to_place {
		monster := make_creature(kind, {})
		monster.facing = rand.choice_enum(hexgrid.Direction, generator)
		for spot in candidate_spots {
			if can_stand_in(level, nil, &monster, spot) {
				monster.hex = spot
				append(&level.monsters, monster)
				break
			}
		}
	}
}

is_border_index :: proc(level: ^Level, index: int) -> bool {
	row := i32(index) / level.size.width
	column := i32(index) % level.size.width
	return row == 0 || row == level.size.height - 1 || column == 0 || column == level.size.width - 1
}

// Hexes outside the map count as walls.
count_wall_neighbors :: proc(level: ^Level, hex: hexgrid.Hex) -> int {
	count := 0
	for direction in hexgrid.Direction {
		if is_wall(level, hexgrid.hex_neighbor(hex, direction)) do count += 1
	}
	return count
}

// ---------------------------------------------------------------------------
// Drawing support: one mesh per kind and variant of tile
// ---------------------------------------------------------------------------

Tile_Meshes :: struct {
	floors:      [FLOOR_VARIANT_COUNT]rl.Mesh,
	walls:       [WALL_VARIANT_COUNT]rl.Mesh,
	stairs_down: rl.Mesh,
	stairs_up:   rl.Mesh,
}

build_tile_meshes :: proc() -> (meshes: Tile_Meshes) {
	for variant in 0 ..< FLOOR_VARIANT_COUNT {
		meshes.floors[variant] = build_hex_prism_mesh(HEX_SIZE, FLOOR_HEIGHT, FLOOR_TOP_REGIONS[variant], FLOOR_SIDE_REGION)
	}
	for variant in 0 ..< WALL_VARIANT_COUNT {
		meshes.walls[variant] = build_hex_prism_mesh(HEX_SIZE, WALL_HEIGHT, WALL_TOP_REGIONS[variant], WALL_SIDE_REGIONS[variant])
	}
	meshes.stairs_down = build_hex_prism_mesh(HEX_SIZE, FLOOR_HEIGHT, STAIRS_DOWN_TOP_REGION, FLOOR_SIDE_REGION)
	meshes.stairs_up = build_hex_prism_mesh(HEX_SIZE, FLOOR_HEIGHT, STAIRS_UP_TOP_REGION, FLOOR_SIDE_REGION)
	return meshes
}

unload_tile_meshes :: proc(meshes: ^Tile_Meshes) {
	for mesh in meshes.floors do rl.UnloadMesh(mesh)
	for mesh in meshes.walls do rl.UnloadMesh(mesh)
	rl.UnloadMesh(meshes.stairs_down)
	rl.UnloadMesh(meshes.stairs_up)
}

mesh_for_tile :: proc(meshes: ^Tile_Meshes, tile: Tile) -> rl.Mesh {
	switch tile.kind {
	case .Floor:       return meshes.floors[tile.variant]
	case .Wall:        return meshes.walls[tile.variant]
	case .Stairs_Down: return meshes.stairs_down
	case .Stairs_Up:   return meshes.stairs_up
	case .Forest:      return meshes.floors[3] // the mossy floor, as woodland ground
	}
	return meshes.floors[0]
}

tile_top_height :: proc(level: ^Level, hex: hexgrid.Hex) -> f32 {
	tile, _ := tile_at(level, hex)
	return WALL_HEIGHT if tile.kind == .Wall else FLOOR_HEIGHT
}
