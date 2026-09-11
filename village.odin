package main

// The village (depth 0), its people, their quests, and the named creatures the quests are about.

import "core:fmt"
import "core:math/rand"
import rl "vendor:raylib"
import "hexgrid"

// ---------------------------------------------------------------------------
// Named creatures: tougher versions of goblins and ogres, each living on one depth only
// ---------------------------------------------------------------------------

Named_Creature :: enum u8 {
	None,
	Grishnak,
	Gorluk,
}

Named_Creature_Definition :: struct {
	name:           string,
	title:          string,
	kind:           Creature_Kind,
	depth:          int, // the only level it appears on
	max_hit_points: int,
	damage_dice:    Dice,
	armor:          int,
	tint:           rl.Color, // multiplied with the normal sprite's colors
	trophy:         [2]Item_Stack, // extra loot on its body
}

// Filled from assets/content.json at startup (see content.odin).
NAMED_CREATURES: [Named_Creature]Named_Creature_Definition

make_named_creature :: proc(scene: ^Scene, named: Named_Creature, hex: hexgrid.Hex) -> Actor {
	definition := NAMED_CREATURES[named]
	creature := make_creature(scene, definition.kind, hex)
	creature.named = named
	creature.name = definition.name
	creature.max_hit_points = definition.max_hit_points
	creature.hit_points = definition.max_hit_points
	creature.damage_dice = definition.damage_dice
	creature.armor = definition.armor
	creature.tint = definition.tint
	creature.knockback_distance *= 0.5
	return creature
}

// "the goblin" or "Grishnak", and the same at the start of a sentence.
display_name :: proc(creature: ^Actor, start_of_sentence := false) -> string {
	if creature.named != .None do return creature.name
	return fmt.tprintf("%s %s", "The" if start_of_sentence else "the", creature.name)
}

// ---------------------------------------------------------------------------
// Villagers
// ---------------------------------------------------------------------------

Npc_Role :: enum u8 {
	Elder,
	Smith,
}

Npc_Definition :: struct {
	name:      string,
	tint:      rl.Color, // they wear the adventurer's sprite in other colors
	offset:    hexgrid.Hex, // where they stand, from the village center
	idle_line: string,
}

NPCS: [Npc_Role]Npc_Definition

Npc :: struct {
	role:   Npc_Role,
	hex:    hexgrid.Hex,
	facing: hexgrid.Direction,
}

npc_index_at :: proc(level: ^Level, hex: hexgrid.Hex) -> int {
	for npc, index in level.npcs {
		if npc.hex == hex do return index
	}
	return -1
}

// ---------------------------------------------------------------------------
// The village map
// ---------------------------------------------------------------------------

VILLAGE_CENTER :: hexgrid.Hex{q = 8, r = 9}
VILLAGE_RADIUS :: 7
// Small houses: three wall hexes each, placed from the village center.
VILLAGE_HOUSES := [?]hexgrid.Hex{{q = -5, r = -1}, {q = 2, r = -5}, {q = -2, r = 4}, {q = 3, r = 2}}

generate_village :: proc(scene: ^Scene) -> ^Level {
	level := new(Level)
	level.depth = 0
	level.size = {LEVEL_WIDTH, LEVEL_HEIGHT}
	level.tiles = make([]Tile, hexgrid.grid_cell_count(level.size))
	random_state := rand.create_u64(scene.game_seed ~ 0x5EED_0000_0000)
	generator := rand.default_random_generator(&random_state)

	for &tile, index in level.tiles {
		hex := hexgrid.grid_hex_at(level.size, index)
		is_open := hexgrid.hex_distance(hex, VILLAGE_CENTER) <= VILLAGE_RADIUS && !is_border_index(level, index)
		tile.kind = .Floor if is_open else .Wall
	}
	for house in VILLAGE_HOUSES {
		for offset in TRIANGLE_FOOTPRINT {
			set_tile_kind(level, hexgrid.hex_add(hexgrid.hex_add(VILLAGE_CENTER, house), offset), .Wall)
		}
	}
	level.has_stairs_up = false
	level.stairs_up_hex = hexgrid.hex_add(VILLAGE_CENTER, {q = -1, r = 2}) // where a new adventure begins
	level.stairs_down_hex = hexgrid.hex_add(VILLAGE_CENTER, {q = 6, r = 0})
	set_tile_kind(level, level.stairs_down_hex, .Stairs_Down)
	choose_tile_variants(level, generator)
	add_village_npcs(level)
	return level
}

// Villagers aren't saved: they're put back whenever the village is built or loaded.
add_village_npcs :: proc(level: ^Level) {
	for role in Npc_Role {
		append(&level.npcs, Npc{role = role, hex = hexgrid.hex_add(VILLAGE_CENTER, NPCS[role].offset), facing = .South_East})
	}
}

// ---------------------------------------------------------------------------
// Quests
// ---------------------------------------------------------------------------

Quest_Id :: enum u8 {
	Slay_Grishnak,
	Smiths_Club,
	Slay_Gorluk,
}

Quest_State :: enum u8 {
	Not_Offered,
	Active,
	Done,
}

Quest_Definition :: struct {
	giver:       Npc_Role,
	title:       string,    // shown on screen while active
	offer:       [4]string, // what the giver says when offering it
	reminder:    string,
	thanks:      [2]string,
	target:      Named_Creature,   // slay quests
	wanted_item: Maybe(Item_Kind), // fetch quests: taken from your backpack
	reward_gold: int,
	reward_item: Maybe(Item_Kind),
	requires:    Maybe(Quest_Id),  // only offered once this one is done
}

QUESTS: [Quest_Id]Quest_Definition

// The quest this villager has for you now, if any.
current_quest_of :: proc(scene: ^Scene, role: Npc_Role) -> (id: Quest_Id, has_one: bool) {
	for quest_id in Quest_Id {
		quest := QUESTS[quest_id]
		if quest.giver != role || scene.quest_states[quest_id] == .Done do continue
		if required, has_requirement := quest.requires.?; has_requirement && scene.quest_states[required] != .Done do continue
		return quest_id, true
	}
	return {}, false
}

quest_is_ready :: proc(scene: ^Scene, id: Quest_Id) -> bool {
	quest := QUESTS[id]
	if quest.target != .None do return scene.named_slain[quest.target]
	if wanted, wants_item := quest.wanted_item.?; wants_item {
		for stack in scene.inventory.backpack do if stack.kind == wanted do return true
	}
	return false
}

complete_quest :: proc(scene: ^Scene, id: Quest_Id) {
	quest := QUESTS[id]
	inventory := &scene.inventory
	wanted_index := -1
	if wanted, wants_item := quest.wanted_item.?; wants_item {
		for stack, index in inventory.backpack do if stack.kind == wanted { wanted_index = index; break }
		ordered_remove(&inventory.backpack, wanted_index) // hand it over first: that frees a slot
	}
	if reward, has_reward := quest.reward_item.?; has_reward {
		if !add_to_inventory(inventory, Item_Stack{reward, 1}) {
			if wanted, wants_item := quest.wanted_item.?; wants_item do add_to_inventory(inventory, Item_Stack{wanted, 1})
			set_message(scene, "Make room in your backpack first.")
			return
		}
	}
	add_to_inventory(inventory, Item_Stack{.Gold, quest.reward_gold})
	scene.quest_states[id] = .Done
	set_message(scene, "Quest complete: %s.", quest.title)
}

// "Quests: Slay Grishnak (depth 2)   Bring Tomas a spiked club"
active_quests_text :: proc(scene: ^Scene) -> string {
	text := ""
	for id in Quest_Id {
		if scene.quest_states[id] != .Active do continue
		done := " (done: return to the village)" if quest_is_ready(scene, id) else ""
		text = fmt.tprintf("%s%s%s%s", text, "   " if text != "" else "Quests: ", QUESTS[id].title, done)
	}
	return text
}

// Called when a creature dies, to keep track of the named ones.
note_named_death :: proc(scene: ^Scene, creature: ^Actor) {
	if creature.named == .None do return
	scene.named_slain[creature.named] = true
	definition := NAMED_CREATURES[creature.named]
	set_message(scene, "%s %s is dead!", definition.name, definition.title)
}

// ---------------------------------------------------------------------------
// The dialogue panel
// ---------------------------------------------------------------------------

DIALOGUE_PANEL         :: rl.Rectangle{63, 52, 300, 132}
DIALOGUE_ACTION_BUTTON :: rl.Rectangle{DIALOGUE_PANEL.x + 8, DIALOGUE_PANEL.y + DIALOGUE_PANEL.height - 22, 110, 16}
DIALOGUE_CLOSE_BUTTON  :: rl.Rectangle{DIALOGUE_PANEL.x + DIALOGUE_PANEL.width - 66, DIALOGUE_PANEL.y + DIALOGUE_PANEL.height - 22, 58, 16}

open_dialogue :: proc(scene: ^Scene, npc_index: int) {
	level := current_level(scene)
	npc := &level.npcs[npc_index]
	npc.facing = direction_toward_position(hex_floor_position(npc.hex), hex_floor_position(scene.player.hex))
	scene.player.facing = direction_toward_position(hex_floor_position(scene.player.hex), hex_floor_position(npc.hex))
	scene.dialogue_npc_index = npc_index
	scene.open_panel = .Dialogue
}

// What the panel shows right now: the lines, and the label of the action button ("" = none).
dialogue_content :: proc(scene: ^Scene) -> (lines: [4]string, action: string, reward: string) {
	npc := current_level(scene).npcs[scene.dialogue_npc_index]
	quest_id, has_quest := current_quest_of(scene, npc.role)
	if !has_quest {
		lines[0] = NPCS[npc.role].idle_line
		return
	}
	quest := QUESTS[quest_id]
	switch scene.quest_states[quest_id] {
	case .Not_Offered:
		lines = quest.offer
		action = "Accept"
		reward = fmt.tprintf("Reward: %d gold", quest.reward_gold)
		if item, has_item := quest.reward_item.?; has_item do reward = fmt.tprintf("%s and a %s", reward, ITEMS[item].name)
	case .Active:
		if quest_is_ready(scene, quest_id) {
			lines[0], lines[1] = quest.thanks[0], quest.thanks[1]
			action = "Claim reward"
		} else {
			lines[0] = quest.reminder
		}
	case .Done:
	}
	return
}

draw_dialogue_panel :: proc(scene: ^Scene) {
	npc := current_level(scene).npcs[scene.dialogue_npc_index]
	panel := DIALOGUE_PANEL
	draw_panel(panel, NPCS[npc.role].name)
	lines, action, reward := dialogue_content(scene)
	for line, index in lines {
		draw_text(line, i32(panel.x) + 8, i32(panel.y) + 22 + i32(index) * 12, TEXT_COLOR)
	}
	if reward != "" do draw_text(reward, i32(panel.x) + 8, i32(panel.y) + 76, GOLD_TEXT_COLOR)
	if action != "" do draw_button(scene, DIALOGUE_ACTION_BUTTON, action)
	draw_button(scene, DIALOGUE_CLOSE_BUTTON, "Close")
}

handle_dialogue_click :: proc(scene: ^Scene) {
	if !mouse_is_over(scene, DIALOGUE_PANEL) || mouse_is_over(scene, DIALOGUE_CLOSE_BUTTON) {
		scene.open_panel = .None
		return
	}
	_, action, _ := dialogue_content(scene)
	if action == "" || !mouse_is_over(scene, DIALOGUE_ACTION_BUTTON) do return
	npc := current_level(scene).npcs[scene.dialogue_npc_index]
	quest_id, _ := current_quest_of(scene, npc.role)
	if scene.quest_states[quest_id] == .Not_Offered {
		scene.quest_states[quest_id] = .Active
		set_message(scene, "New quest: %s.", QUESTS[quest_id].title)
		scene.open_panel = .None
	} else {
		complete_quest(scene, quest_id)
	}
}

// A villager standing on the map: the adventurer's sprite, recolored.
draw_npc :: proc(scene: ^Scene, npc: ^Npc, camera: rl.Camera3D, light: f32) {
	feet := hex_floor_position(npc.hex)
	rl.DrawCylinder({feet.x, FLOOR_HEIGHT + 0.1, feet.z}, 6, 6, 0.1, 16, rl.Fade(rl.BLACK, 0.35))
	frame_size := rl.Vector2{16, 24}
	column := sprite_frame_for(npc.facing, camera)
	source := rl.Rectangle{f32(column) * frame_size.x, 0, frame_size.x, frame_size.y}
	size := rl.Vector2{frame_size.x, frame_size.y * upright_stretch(camera)}
	rl.DrawBillboardPro(camera, scene.creature_sprites[.Adventurer], source, feet, {0, 1, 0}, size, {size.x / 2, 0}, 0, shade(NPCS[npc.role].tint, light))
}
