package main

// Villagers, quests and named creatures are content, not code, so they live in
// assets/content.json. The ids in that file ("Elder", "Slay_Grishnak", ...) match the
// enums in village.odin, and the tables below are filled from the file at startup.
//
// A copy of the file is built into the program, so the game always has its content.
// If a file of the same name sits next to the program, that one is used instead: you
// can fix a line of dialogue or reprice a reward without recompiling. A broken file
// falls back to the built-in copy, with a note in the console.

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:reflect"
import rl "vendor:raylib"
import "hexgrid"

CONTENT_JSON :: #load("assets/content.json")
CONTENT_FORMAT_VERSION :: 1

// The JSON shapes. Ids and item names are text here, and turned into enum values below.
Content_Item_Stack :: struct {
	kind:  string,
	count: int,
}

Content_Named_Creature :: struct {
	id:             string,
	name:           string,
	title:          string,
	kind:           string,
	depth:          int,
	max_hit_points: int,
	damage_dice:    Dice,
	armor:          int,
	tint:           [4]u8,
	trophy:         []Content_Item_Stack,
}

Content_Npc :: struct {
	id:        string,
	name:      string,
	tint:      [4]u8,
	offset:    hexgrid.Hex,
	idle_line: string,
}

Content_Quest :: struct {
	id:          string,
	giver:       string,
	title:       string,
	target:      string, // a named creature, or "" for a fetch quest
	wanted_item: string, // an item to hand over, or ""
	requires:    string, // a quest that must be done first, or ""
	reward_gold: int,
	reward_item: string,
	offer:       []string,
	reminder:    string,
	thanks:      []string,
}

Content_Behaviour :: struct {
	kind:            string,
	below:           f32,
	notice_distance: i32,
	damage_dice:     Dice,
	verb:            string,
	chance:          f32,
}

Content_Creature :: struct {
	id:                    string,
	name:                  string,
	attack_verb:           string,
	frame_size:            [2]f32,
	footprint:             string, // "single" or "triangle"
	shadow_radius:         f32,
	blood_color:           [4]u8,
	damage_dice:           Dice,
	armor:                 int,
	max_hit_points:        int,
	walk_seconds:          f32,
	attack_seconds:        f32,
	knockback_distance:    f32,
	turns_between_actions: int,
	shakes_screen_on_hit:  bool,
	weapon_sound:          string,
	hurt_sound:            string,
	death_sound:           string,
	behaviours:            []Content_Behaviour,
}

Content_File :: struct {
	version:         int,
	creatures:       []Content_Creature,
	named_creatures: []Content_Named_Creature,
	npcs:            []Content_Npc,
	quests:          []Content_Quest,
}

content_path :: proc() -> string {
	return fmt.tprintf("%sassets/content.json", rl.GetApplicationDirectory())
}

// Reads the content into the tables in village.odin. The text is copied into memory the
// game keeps, since the JSON data itself is temporary.
load_content :: proc() {
	if data, read_error := os.read_entire_file(content_path(), context.temp_allocator); read_error == nil {
		if apply_content(data) do return
		fmt.eprintfln("Couldn't read %s; using the built-in content instead.", content_path())
	}
	if !apply_content(CONTENT_JSON) {
		fmt.eprintln("The built-in content is broken: there will be no villagers or quests.")
	}
}

apply_content :: proc(data: []u8) -> (ok: bool) {
	file: Content_File
	if json.unmarshal(data, &file, allocator = context.temp_allocator) != nil do return false
	if file.version != CONTENT_FORMAT_VERSION do return false

	// Look up an enum value by its id, complaining once if the name is unknown.
	from_name :: proc($Enum_Type: typeid, name, what: string) -> (value: Enum_Type, found: bool) {
		if name == "" do return {}, false
		value, found = reflect.enum_from_name(Enum_Type, name)
		if !found do fmt.eprintfln("content.json: unknown %s \"%s\"", what, name)
		return
	}

	CREATURES = {}
	for entry in file.creatures {
		id := from_name(Creature_Kind, entry.id, "creature id") or_continue
		definition := Creature_Definition {
			name                  = keep(entry.name),
			attack_verb           = keep(entry.attack_verb),
			frame_size            = {entry.frame_size[0], entry.frame_size[1]},
			footprint             = TRIANGLE_FOOTPRINT[:] if entry.footprint == "triangle" else SINGLE_HEX_FOOTPRINT[:],
			shadow_radius         = entry.shadow_radius,
			blood_color           = {entry.blood_color[0], entry.blood_color[1], entry.blood_color[2], entry.blood_color[3]},
			damage_dice           = entry.damage_dice,
			armor                 = entry.armor,
			max_hit_points        = entry.max_hit_points,
			walk_seconds          = entry.walk_seconds,
			attack_seconds        = entry.attack_seconds,
			knockback_distance    = entry.knockback_distance,
			turns_between_actions = entry.turns_between_actions,
			shakes_screen_on_hit  = entry.shakes_screen_on_hit,
		}
		if sound, found := from_name(Weapon_Sound, entry.weapon_sound, "weapon sound"); found do definition.weapon_sound = sound
		if sound, found := from_name(Sound_Id, entry.hurt_sound, "sound"); found do definition.hurt_sound = sound
		if sound, found := from_name(Sound_Id, entry.death_sound, "sound"); found do definition.death_sound = sound

		// The behaviours are kept in the order they are listed: that is their priority.
		behaviours := make([dynamic]Behaviour)
		for listed in entry.behaviours {
			kind := from_name(Behaviour_Kind, listed.kind, "behaviour") or_continue
			append(&behaviours, Behaviour {
				kind            = kind,
				below           = listed.below,
				notice_distance = listed.notice_distance,
				damage_dice     = listed.damage_dice,
				verb            = keep(listed.verb),
				chance          = listed.chance,
			})
			if len(behaviours) >= MAX_BEHAVIOURS do break
		}
		definition.behaviours = behaviours[:]
		CREATURES[id] = definition
	}

	NAMED_CREATURES = {}
	for entry in file.named_creatures {
		id := from_name(Named_Creature, entry.id, "named creature id") or_continue
		kind := from_name(Creature_Kind, entry.kind, "creature kind") or_continue
		definition := Named_Creature_Definition {
			name           = keep(entry.name),
			title          = keep(entry.title),
			kind           = kind,
			depth          = entry.depth,
			max_hit_points = entry.max_hit_points,
			damage_dice    = entry.damage_dice,
			armor          = entry.armor,
			tint           = {entry.tint[0], entry.tint[1], entry.tint[2], entry.tint[3]},
		}
		for stack, index in entry.trophy {
			if index >= len(definition.trophy) do break
			item := from_name(Item_Kind, stack.kind, "item") or_continue
			definition.trophy[index] = {item, stack.count}
		}
		NAMED_CREATURES[id] = definition
	}

	NPCS = {}
	for entry in file.npcs {
		id := from_name(Npc_Role, entry.id, "villager id") or_continue
		NPCS[id] = Npc_Definition {
			name      = keep(entry.name),
			tint      = {entry.tint[0], entry.tint[1], entry.tint[2], entry.tint[3]},
			offset    = entry.offset,
			idle_line = keep(entry.idle_line),
		}
	}

	QUESTS = {}
	for entry in file.quests {
		id := from_name(Quest_Id, entry.id, "quest id") or_continue
		giver := from_name(Npc_Role, entry.giver, "villager id") or_continue
		quest := Quest_Definition {
			giver       = giver,
			title       = keep(entry.title),
			reminder    = keep(entry.reminder),
			reward_gold = entry.reward_gold,
		}
		if target, has_target := from_name(Named_Creature, entry.target, "named creature id"); has_target {
			quest.target = target
		}
		if item, has_item := from_name(Item_Kind, entry.wanted_item, "item"); has_item {
			quest.wanted_item = item
		}
		if item, has_item := from_name(Item_Kind, entry.reward_item, "item"); has_item {
			quest.reward_item = item
		}
		if required, has_requirement := from_name(Quest_Id, entry.requires, "quest id"); has_requirement {
			quest.requires = required
		}
		for line, index in entry.offer {
			if index < len(quest.offer) do quest.offer[index] = keep(line)
		}
		for line, index in entry.thanks {
			if index < len(quest.thanks) do quest.thanks[index] = keep(line)
		}
		QUESTS[id] = quest
	}
	return true
}

// Copies a string out of the temporary JSON data, so it stays valid for the whole run.
keep :: proc(text: string) -> string {
	if text == "" do return ""
	kept := make([]u8, len(text))
	copy(kept, text)
	return string(kept)
}
