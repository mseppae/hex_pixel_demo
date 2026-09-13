package main

// Saving and loading.
//
// A save file is JSON, so you can open it in a text editor and read it. It doesn't
// store the game's own structs directly, because those hold things that only make
// sense while the program runs: textures on the graphics card, pointers to other
// creatures, animation timers. Instead the game is copied into the plain "Saved_"
// structs below, and rebuilt from them when loading.
//
// Enums are written as numbers. So new kinds (items, creatures, tiles, ...) must be
// added at the END of their enum, or old saves will read them as the wrong thing.
// If a change can't be done that way, raise SAVE_FORMAT_VERSION: older saves are
// then shown as unreadable instead of loading wrong.

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:time"
import "core:time/timezone"
import rl "vendor:raylib"
import "hexgrid"

SAVE_FORMAT_VERSION :: 2 // 2: the village became depth 0, and quests were added
SAVE_SLOT_COUNT     :: 3

Saved_Creature :: struct {
	kind:         Creature_Kind,
	named:        Named_Creature,
	hex:          hexgrid.Hex,
	facing:       hexgrid.Direction,
	hit_points:   int,
	is_dead:      bool,
	is_awake:     bool,
	turns_waited: int,
	stance:       Stance,
}

Saved_Container :: struct {
	kind:            Container_Kind,
	anchor_hex:      hexgrid.Hex,
	items:           []Item_Stack,
	has_been_opened: bool,
}

Saved_Level :: struct {
	depth:              int,
	size:               hexgrid.Grid_Size,
	tiles:              []Tile,
	monsters:           []Saved_Creature,
	containers:         []Saved_Container,
	blood_stains:       []Blood_Stain,
	oldest_stain_index: int,
	has_stairs_up:      bool,
	stairs_up_hex:      hexgrid.Hex,
	stairs_down_hex:    hexgrid.Hex,
}

Saved_Inventory :: struct {
	gold:           int,
	gold_collected: int,
	backpack: []Item_Stack,
	weapon:   Maybe(Item_Kind),
	armor:    Maybe(Item_Kind),
}

Save_Game :: struct {
	version: int,

	// Shown in the list of slots. (Save_Summary reads just these.)
	saved_at:       string,
	depth:          int,
	hit_points:     int,
	max_hit_points: int,
	gold:           int,

	// The adventure itself
	adventure_id:  u64, // the same in every save of this adventure; death deletes them all
	game_seed:     u64,
	current_depth: int,
	deepest_depth: int,
	player:        Saved_Creature,
	inventory:     Saved_Inventory,
	levels:        []Saved_Level,  // levels[0] is the village
	quest_states:  []Quest_State,  // one per Quest_Id, in enum order
	named_slain:   []bool,         // one per Named_Creature, in enum order
}

// A few fields of Save_Game: reading only these is enough for the slot list.
Save_Summary :: struct {
	version:        int,
	adventure_id:   u64,
	saved_at:       string,
	depth:          int,
	hit_points:     int,
	max_hit_points: int,
	gold:           int,
}

// What the slot list shows for one slot, kept between frames (so no temporary strings).
Slot_Info :: struct {
	exists:          bool, // there is a file
	readable:        bool, // and it could be read with this version of the game
	depth:           int,
	hit_points:      int,
	max_hit_points:  int,
	gold:            int,
	saved_at_buffer: [32]u8,
	saved_at_length: int,
}

slot_saved_at :: proc(info: ^Slot_Info) -> string {
	return string(info.saved_at_buffer[:info.saved_at_length])
}

// Saves live in a "saves" folder next to the game's program file, so they're found
// no matter which folder the game is started from.
saves_folder :: proc() -> string {
	return fmt.tprintf("%ssaves", rl.GetApplicationDirectory())
}

slot_path :: proc(slot: int) -> string {
	return fmt.tprintf("%s/slot_%d.json", saves_folder(), slot + 1)
}

// ---------------------------------------------------------------------------
// Saving
// ---------------------------------------------------------------------------

can_save_now :: proc(scene: ^Scene) -> bool {
	return scene.turn_phase == .Player_Choosing && !scene.player.is_dead
}

save_to_slot :: proc(scene: ^Scene, slot: int) -> (ok: bool) {
	save := build_save_game(scene)
	data, marshal_error := json.marshal(save, {pretty = true, use_spaces = true, spaces = 1}, context.temp_allocator)
	if marshal_error != nil do return false

	if !os.exists(saves_folder()) {
		if os.make_directory(saves_folder()) != nil do return false
	}
	// Write to a temporary file first, then swap it in: if the game crashed halfway
	// through writing, the old save would still be intact.
	temporary_path := fmt.tprintf("%s.writing", slot_path(slot))
	if os.write_entire_file(temporary_path, data) != nil do return false
	return os.rename(temporary_path, slot_path(slot)) == nil
}

// Everything here is allocated with the temporary allocator: it only needs to live
// until it has been written to the file.
build_save_game :: proc(scene: ^Scene) -> Save_Game {
	context.allocator = context.temp_allocator
	inventory := &scene.inventory

	save := Save_Game {
		version        = SAVE_FORMAT_VERSION,
		saved_at       = local_time_text(),
		depth          = scene.current_depth,
		hit_points     = scene.player.hit_points,
		max_hit_points = scene.player.max_hit_points,
		gold           = inventory.gold,
		adventure_id   = scene.adventure_id,
		game_seed      = scene.game_seed,
		current_depth  = scene.current_depth,
		deepest_depth  = scene.deepest_depth,
		player         = save_creature(&scene.player),
		inventory      = Saved_Inventory {
			gold           = inventory.gold,
			gold_collected = inventory.gold_collected,
			backpack       = inventory.backpack[:],
			weapon         = inventory.weapon,
			armor          = inventory.armor,
		},
	}

	levels := make([]Saved_Level, len(scene.levels))
	for level, level_index in scene.levels {
		monsters := make([]Saved_Creature, len(level.monsters))
		for &monster, index in level.monsters do monsters[index] = save_creature(&monster)
		containers := make([]Saved_Container, len(level.containers))
		for container, index in level.containers {
			containers[index] = Saved_Container {
				kind            = container.kind,
				anchor_hex      = container.anchor_hex,
				items           = container.items[:],
				has_been_opened = container.has_been_opened,
			}
		}
		levels[level_index] = Saved_Level {
			depth              = level.depth,
			size               = level.size,
			tiles              = level.tiles,
			monsters           = monsters,
			containers         = containers,
			blood_stains       = level.blood_stains[:],
			oldest_stain_index = level.oldest_stain_index,
			has_stairs_up      = level.has_stairs_up,
			stairs_up_hex      = level.stairs_up_hex,
			stairs_down_hex    = level.stairs_down_hex,
		}
	}
	save.levels = levels
	save.quest_states = make([]Quest_State, len(Quest_Id))
	for state, id in scene.quest_states do save.quest_states[id] = state
	save.named_slain = make([]bool, len(Named_Creature))
	for slain, named in scene.named_slain do save.named_slain[named] = slain
	return save
}

save_creature :: proc(creature: ^Actor) -> Saved_Creature {
	return Saved_Creature {
		kind         = creature.kind,
		named        = creature.named,
		hex          = creature.hex,
		facing       = creature.facing,
		hit_points   = creature.hit_points,
		is_dead      = creature.is_dead,
		is_awake     = creature.is_awake,
		turns_waited = creature.turns_waited,
		stance       = creature.stance,
	}
}

// Like "2026-09-11 18:48", in the player's own time zone when it can be found.
local_time_text :: proc() -> string {
	moment, _ := time.time_to_datetime(time.now())
	if region, found := timezone.region_load("local", context.temp_allocator); found {
		moment = timezone.datetime_to_tz(moment, region)
	}
	return fmt.tprintf("%4d-%02d-%02d %02d:%02d", moment.year, moment.month, moment.day, moment.hour, moment.minute)
}

// ---------------------------------------------------------------------------
// Loading
// ---------------------------------------------------------------------------

load_from_slot :: proc(scene: ^Scene, slot: int) -> (ok: bool) {
	data, read_error := os.read_entire_file(slot_path(slot), context.temp_allocator)
	if read_error != nil do return false
	save: Save_Game
	if json.unmarshal(data, &save, allocator = context.temp_allocator) != nil do return false
	if save.version != SAVE_FORMAT_VERSION || len(save.levels) == 0 do return false
	restore_game(scene, &save)

	// Saves made before adventures had an ID: give it one and write it back, so that
	// dying in this adventure deletes this save too.
	if save.adventure_id == 0 {
		scene.adventure_id = new_adventure_id()
		save_to_slot(scene, slot)
	}
	return true
}

// Rebuilds the running game from a save. The save's own data is temporary, so
// everything is copied into memory the game keeps.
restore_game :: proc(scene: ^Scene, save: ^Save_Game) {
	for level in scene.levels do destroy_level(level)
	clear(&scene.levels)
	clear_effects(&scene.effects)

	scene.game_seed = save.game_seed
	scene.adventure_id = save.adventure_id
	scene.player = restore_creature(save.player)

	inventory := &scene.inventory
	clear(&inventory.backpack)
	append(&inventory.backpack, ..save.inventory.backpack)
	inventory.gold = save.inventory.gold
	inventory.gold_collected = max(save.inventory.gold_collected, save.inventory.gold) // older saves lack it
	inventory.weapon = save.inventory.weapon
	inventory.armor = save.inventory.armor
	apply_equipment(scene)

	for saved in save.levels {
		level := new(Level)
		level.depth = saved.depth
		level.size = saved.size
		level.tiles = make([]Tile, len(saved.tiles))
		copy(level.tiles, saved.tiles)
		for saved_monster in saved.monsters {
			append(&level.monsters, restore_creature(saved_monster))
		}
		for saved_container in saved.containers {
			container := Container {
				kind            = saved_container.kind,
				anchor_hex      = saved_container.anchor_hex,
				footprint       = footprint_for_container(saved_container.kind),
				has_been_opened = saved_container.has_been_opened,
			}
			append(&container.items, ..saved_container.items)
			append(&level.containers, container)
		}
		append(&level.blood_stains, ..saved.blood_stains)
		level.oldest_stain_index = saved.oldest_stain_index
		level.has_stairs_up = saved.has_stairs_up
		level.stairs_up_hex = saved.stairs_up_hex
		level.stairs_down_hex = saved.stairs_down_hex
		if level.depth == 0 do add_village_npcs(level)
		add_trees(level)
		append(&scene.levels, level)
	}
	scene.current_depth = clamp(save.current_depth, 0, len(scene.levels) - 1)
	scene.quest_states = {}
	for state, index in save.quest_states do if index < len(Quest_Id) do scene.quest_states[Quest_Id(index)] = state
	scene.named_slain = {}
	for slain, index in save.named_slain do if index < len(Named_Creature) do scene.named_slain[Named_Creature(index)] = slain
	scene.deepest_depth = max(save.deepest_depth, len(scene.levels) - 1)
	scene.turn_phase = .Player_Choosing
	scene.open_panel = .None
}

restore_creature :: proc(saved: Saved_Creature) -> Actor {
	creature := make_named_creature(saved.named, saved.hex) if saved.named != .None else make_creature(saved.kind, saved.hex)
	creature.facing = saved.facing
	creature.hit_points = saved.hit_points
	creature.is_dead = saved.is_dead
	creature.is_awake = saved.is_awake
	creature.turns_waited = saved.turns_waited
	creature.stance = saved.stance
	if creature.is_dead do creature.death_seconds = DEATH_SECONDS // long gone, not dying right now
	return creature
}

// Reads just the summary of each slot, for the slot list.
refresh_slot_infos :: proc(scene: ^Scene) {
	for &info, slot in scene.slot_infos {
		info = {}
		data, read_error := os.read_entire_file(slot_path(slot), context.temp_allocator)
		if read_error != nil do continue
		info.exists = true
		summary: Save_Summary
		if json.unmarshal(data, &summary, allocator = context.temp_allocator) != nil do continue
		if summary.version != SAVE_FORMAT_VERSION do continue
		info.readable = true
		info.depth = summary.depth
		info.hit_points = summary.hit_points
		info.max_hit_points = summary.max_hit_points
		info.gold = summary.gold
		info.saved_at_length = copy(info.saved_at_buffer[:], summary.saved_at)
	}
}

// Deletes every slot holding the given adventure. Returns how many were deleted.
delete_saves_of_adventure :: proc(adventure_id: u64) -> (deleted: int) {
	if adventure_id == 0 do return 0
	for slot in 0 ..< SAVE_SLOT_COUNT {
		data, read_error := os.read_entire_file(slot_path(slot), context.temp_allocator)
		if read_error != nil do continue
		summary: Save_Summary
		if json.unmarshal(data, &summary, allocator = context.temp_allocator) != nil do continue
		if summary.adventure_id == adventure_id && os.remove(slot_path(slot)) == nil {
			deleted += 1
		}
	}
	return deleted
}
