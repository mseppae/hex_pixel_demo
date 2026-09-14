package main

// Creatures, items, villagers, quests and named creatures are content, not code, so
// they live in assets/content.json. The ids in that file ("Goblin", "Elder",
// "Slay_Grishnak", ...) are looked up by name below: creatures and items resolve to an
// index into CREATURES/ITEMS (see creature_kind_named / item_kind_named), while
// villagers, quests and named creatures still match real enums in village.odin. See
// DESIGN_DATA_DRIVEN.md for why the two are treated differently.
//
// A copy of the file is built into the program, so the game always has its content.
// If a file of the same name sits next to the program, that one is used instead: you
// can fix a line of dialogue, reprice a reward, or add a whole new creature or item,
// without recompiling. A broken file falls back to the built-in copy, with a note in
// the console.

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:reflect"
import rl "vendor:raylib"
import "hexgrid"

CONTENT_JSON :: #load("assets/content.json")
CONTENT_FORMAT_VERSION :: 1

// The JSON shapes. Ids and item/creature names are text here, and resolved below.
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
	sells:     string, // an item id, or "" for a villager with no shop
	price:     int,
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

// One entry of Creature_Definition.loot (see Loot_Table_Entry in items.odin).
Content_Loot_Entry :: struct {
	item:          string,
	chance:        f32,
	min:           int,
	max:           int,
	max_per_depth: int,
}

Content_Creature :: struct {
	id:                    string,
	name:                  string,
	article:               string, // "a goblin", "another adventurer"
	sprite_sheet:          string, // a file name (see load_creature_sprite_sheet)
	corpse:                string, // a Container_Kind name: which existing corpse art it leaves
	attack_verb:           string,
	frame_size:            [2]f32,
	footprint:             string, // "single" or "triangle"
	shadow_radius:         f32,
	blood_color:           [4]u8,
	damage_dice:           Dice,
	armor:                 int,
	max_hit_points:        int,
	strength:              int,
	dexterity:             int,
	constitution:          int,
	default_stance:        string,
	weapon_weight:         string, // "Light", "Medium" or "Heavy"
	armor_weight:          string, // "Light", "Medium" or "Heavy"
	walk_seconds:          f32,
	attack_seconds:        f32,
	knockback_distance:    f32,
	turns_between_actions: int,
	shakes_screen_on_hit:  bool,
	weapon_sound:          string,
	hurt_sound:            string,
	death_sound:           string,
	behaviours:            []Content_Behaviour,
	loot:                  []Content_Loot_Entry,
}

Content_Item :: struct {
	id:           string,
	name:         string,
	category:     string, // "Gold", "Potion", "Weapon", "Armor", "Scroll" or "Quest_Item"
	icon_column:  int,    // which 16 x 16 column of assets/item_icons.png is its icon
	flavor:       string,
	damage_dice:  Dice,   // weapons
	weight:       string, // weapons: "Light", "Medium" or "Heavy"
	armor:        int,    // armor
	armor_weight: string, // armor: "Light", "Medium" or "Heavy"
	heal_dice:    Dice,   // potions
	sound:        string, // weapons: "Light", "Blade" or "Heavy"
}

Content_File :: struct {
	version:         int,
	items:           []Content_Item,
	creatures:       []Content_Creature,
	named_creatures: []Content_Named_Creature,
	npcs:            []Content_Npc,
	quests:          []Content_Quest,
}

content_path :: proc() -> string {
	return fmt.tprintf("%sassets/content.json", rl.GetApplicationDirectory())
}

// Reads the content into the tables in creatures.odin, items.odin and village.odin.
// The text is copied into memory the game keeps, since the JSON data itself is temporary.
load_content :: proc() {
	if data, read_error := os.read_entire_file(content_path(), context.temp_allocator); read_error == nil {
		if apply_content(data) do return
		fmt.eprintfln("Couldn't read %s; using the built-in content instead.", content_path())
	}
	if !apply_content(CONTENT_JSON) {
		fmt.eprintln("The built-in content is broken: there will be no creatures, items, villagers or quests.")
	}
}

// Look up an enum value by its id, complaining once if the name is unknown. For the
// genuinely fixed vocabularies (Stance, Weapon_Weight, sounds, ...): see find_creature
// and find_item below for the two tables that are open-ended instead.
from_name :: proc($Enum_Type: typeid, name, what: string) -> (value: Enum_Type, found: bool) {
	if name == "" do return {}, false
	value, found = reflect.enum_from_name(Enum_Type, name)
	if !found do fmt.eprintfln("content.json: unknown %s \"%s\"", what, name)
	return
}

// Same idea, but for creatures and items: an open-ended table looked up by id string
// instead of a fixed enum (see DESIGN_DATA_DRIVEN.md). Every place content.json names
// a creature or item goes through one of these, so a typo is reported once at startup
// instead of read as the wrong thing or crashing mid-game.
find_creature :: proc(id, what: string) -> (kind: Creature_Kind, found: bool) {
	if id == "" do return {}, false
	kind, found = creature_kind_named(id)
	if !found do fmt.eprintfln("content.json: unknown %s \"%s\"", what, id)
	return
}

find_item :: proc(id, what: string) -> (kind: Item_Kind, found: bool) {
	if id == "" do return {}, false
	kind, found = item_kind_named(id)
	if !found do fmt.eprintfln("content.json: unknown %s \"%s\"", what, id)
	return
}

apply_content :: proc(data: []u8) -> (ok: bool) {
	file: Content_File
	if json.unmarshal(data, &file, allocator = context.temp_allocator) != nil do return false
	if file.version != CONTENT_FORMAT_VERSION do return false

	// Items first: creatures' loot tables, and everything below, refer to them by id.
	clear(&ITEMS)
	clear(&item_index_by_id)
	for entry in file.items {
		if entry.id == "" || entry.id in item_index_by_id {
			fmt.eprintfln("content.json: item with empty or duplicate id \"%s\"", entry.id)
			continue
		}
		definition := Item_Definition {
			id          = keep(entry.id),
			name        = keep(entry.name),
			icon_column = entry.icon_column,
			flavor      = keep(entry.flavor),
			damage_dice = entry.damage_dice,
			armor       = entry.armor,
			heal_dice   = entry.heal_dice,
		}
		if category, found := from_name(Item_Category, entry.category, "item category"); found do definition.category = category
		if weight, found := from_name(Weapon_Weight, entry.weight, "weapon weight"); found do definition.weight = weight
		if weight, found := from_name(Armor_Weight, entry.armor_weight, "armor weight"); found do definition.armor_weight = weight
		if sound, found := from_name(Weapon_Sound, entry.sound, "weapon sound"); found do definition.sound = sound
		item_index_by_id[definition.id] = len(ITEMS)
		append(&ITEMS, definition)
	}

	clear(&CREATURES)
	clear(&creature_index_by_id)
	for entry in file.creatures {
		if entry.id == "" || entry.id in creature_index_by_id {
			fmt.eprintfln("content.json: creature with empty or duplicate id \"%s\"", entry.id)
			continue
		}
		definition := Creature_Definition {
			id                    = keep(entry.id),
			name                  = keep(entry.name),
			article               = keep(entry.article),
			sprite_sheet          = keep(entry.sprite_sheet),
			attack_verb           = keep(entry.attack_verb),
			frame_size            = {entry.frame_size[0], entry.frame_size[1]},
			footprint             = TRIANGLE_FOOTPRINT[:] if entry.footprint == "triangle" else SINGLE_HEX_FOOTPRINT[:],
			shadow_radius         = entry.shadow_radius,
			blood_color           = {entry.blood_color[0], entry.blood_color[1], entry.blood_color[2], entry.blood_color[3]},
			damage_dice           = entry.damage_dice,
			armor                 = entry.armor,
			max_hit_points        = entry.max_hit_points,
			strength              = entry.strength,
			dexterity             = entry.dexterity,
			constitution          = entry.constitution,
			walk_seconds          = entry.walk_seconds,
			attack_seconds        = entry.attack_seconds,
			knockback_distance    = entry.knockback_distance,
			turns_between_actions = entry.turns_between_actions,
			shakes_screen_on_hit  = entry.shakes_screen_on_hit,
		}
		if sound, found := from_name(Weapon_Sound, entry.weapon_sound, "weapon sound"); found do definition.weapon_sound = sound
		if sound, found := from_name(Sound_Id, entry.hurt_sound, "sound"); found do definition.hurt_sound = sound
		if sound, found := from_name(Sound_Id, entry.death_sound, "sound"); found do definition.death_sound = sound
		if stance, found := from_name(Stance, entry.default_stance, "stance"); found do definition.default_stance = stance
		if weight, found := from_name(Weapon_Weight, entry.weapon_weight, "weapon weight"); found do definition.weapon_weight = weight
		if weight, found := from_name(Armor_Weight, entry.armor_weight, "armor weight"); found do definition.armor_weight = weight
		if corpse, found := from_name(Container_Kind, entry.corpse, "corpse kind"); found do definition.corpse = corpse

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

		loot := make([dynamic]Loot_Table_Entry)
		for listed in entry.loot {
			item := find_item(listed.item, "loot item") or_continue
			append(&loot, Loot_Table_Entry {
				item          = item,
				chance        = listed.chance,
				min           = listed.min,
				max           = listed.max,
				max_per_depth = listed.max_per_depth,
			})
		}
		definition.loot = loot[:]

		creature_index_by_id[definition.id] = len(CREATURES)
		append(&CREATURES, definition)
	}

	resolve_known_content()

	NAMED_CREATURES = {}
	for entry in file.named_creatures {
		id := from_name(Named_Creature, entry.id, "named creature id") or_continue
		kind := find_creature(entry.kind, "creature kind") or_continue
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
			item := find_item(stack.kind, "item") or_continue
			definition.trophy[index] = {item, stack.count}
		}
		NAMED_CREATURES[id] = definition
	}

	NPCS = {}
	for entry in file.npcs {
		id := from_name(Npc_Role, entry.id, "villager id") or_continue
		definition := Npc_Definition {
			name      = keep(entry.name),
			tint      = {entry.tint[0], entry.tint[1], entry.tint[2], entry.tint[3]},
			offset    = entry.offset,
			idle_line = keep(entry.idle_line),
			price     = entry.price,
		}
		if item, sells := find_item(entry.sells, "item"); sells {
			definition.sells = item
		}
		NPCS[id] = definition
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
		if item, has_item := find_item(entry.wanted_item, "item"); has_item {
			quest.wanted_item = item
		}
		if item, has_item := find_item(entry.reward_item, "item"); has_item {
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

// The handful of creatures and items the game itself refers to by name (see
// creatures.odin and items.odin), resolved once right after CREATURES and ITEMS load.
// Missing one means the built-in content.json itself is broken.
resolve_known_content :: proc() {
	ADVENTURER = find_creature("Adventurer", "creature id") or_else 0
	GOBLIN     = find_creature("Goblin", "creature id") or_else 0
	OGRE       = find_creature("Ogre", "creature id") or_else 0

	GOLD               = find_item("Gold", "item id") or_else 0
	HEALING_POTION     = find_item("Healing_Potion", "item id") or_else 0
	TOWN_PORTAL_SCROLL = find_item("Town_Portal_Scroll", "item id") or_else 0
	SHORT_SWORD        = find_item("Short_Sword", "item id") or_else 0
	LEATHER_ARMOR      = find_item("Leather_Armor", "item id") or_else 0
	LONGSWORD          = find_item("Longsword", "item id") or_else 0
	CHAIN_SHIRT        = find_item("Chain_Shirt", "item id") or_else 0
	GOBLIN_DAGGER      = find_item("Goblin_Dagger", "item id") or_else 0
}

// Copies a string out of the temporary JSON data, so it stays valid for the whole run.
keep :: proc(text: string) -> string {
	if text == "" do return ""
	kept := make([]u8, len(text))
	copy(kept, text)
	return string(kept)
}
