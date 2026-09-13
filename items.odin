package main

// Items, the inventory, loot tables, and the things loot lies in (corpses and chests).

import "base:runtime"
import "core:fmt"
import "core:math/rand"
import rl "vendor:raylib"
import "hexgrid"

// ---------------------------------------------------------------------------
// Item definitions
// ---------------------------------------------------------------------------

// The icon for each item is at (kind * 16, 0) in assets/item_icons.png, so the
// order here must match the order of icons in the image.
Item_Kind :: enum u8 {
	Gold,
	Healing_Potion,
	Short_Sword,
	Goblin_Dagger,
	Spiked_Club,
	Longsword,
	Leather_Armor,
	Chain_Shirt,
	Town_Portal_Scroll,
}

Item_Category :: enum u8 {
	Gold,
	Potion,
	Weapon,
	Armor,
	Scroll,
}

// How fast a weapon or armor lets its wearer counter-attack after a parry (see
// weapon_weight_riposte_modifier and armor_weight_riposte_modifier in rules.odin).
// A Heavy weapon can't riposte at all; Heavy armor merely makes riposting harder.
Weapon_Weight :: enum u8 {
	Light,
	Medium,
	Heavy,
}

Armor_Weight :: enum u8 {
	Light,
	Medium,
	Heavy,
}

Item_Definition :: struct {
	name:         string,
	category:     Item_Category,
	flavor:       string, // a short line for the tooltip
	damage_dice:  Dice,   // weapons
	weight:       Weapon_Weight, // weapons
	armor:        int,    // armor: every hit on you does this much less
	armor_weight: Armor_Weight, // armor
	heal_dice:    Dice,   // potions
	sound:        Weapon_Sound, // weapons: how swinging and hitting with it sounds
}

ITEMS := [Item_Kind]Item_Definition {
	.Gold           = {name = "Gold", category = .Gold, flavor = "Goblins love it. So do you."},
	.Healing_Potion = {name = "Healing potion", category = .Potion, heal_dice = {count = 2, sides = 4, bonus = 2}, flavor = "Tastes of cherries and iron."},
	.Short_Sword    = {name = "Short sword", category = .Weapon, damage_dice = {count = 1, sides = 6, bonus = 1}, weight = .Medium, sound = .Blade, flavor = "Plain and reliable."},
	.Goblin_Dagger  = {name = "Goblin dagger", category = .Weapon, damage_dice = {count = 2, sides = 3}, weight = .Light, sound = .Light, flavor = "Crude, but it bites."},
	.Spiked_Club    = {name = "Spiked club", category = .Weapon, damage_dice = {count = 2, sides = 4, bonus = 1}, weight = .Heavy, sound = .Heavy, flavor = "Pried from an ogre's fingers."},
	.Longsword      = {name = "Longsword", category = .Weapon, damage_dice = {count = 1, sides = 8, bonus = 2}, weight = .Medium, sound = .Blade, flavor = "Balanced, keen, old."},
	.Leather_Armor  = {name = "Leather armor", category = .Armor, armor = 1, armor_weight = .Light, flavor = "Stiff, but it turns a blade."},
	.Chain_Shirt    = {name = "Chain shirt", category = .Armor, armor = 2, armor_weight = .Medium, flavor = "Heavy rings, carefully mended."},
	.Town_Portal_Scroll = {name = "Scroll of Town Portal", category = .Scroll, flavor = "The ink is still faintly warm."},
}

// Punching with bare hands, when no weapon is wielded: a fist is Light, same as a dagger.
FIST_DICE :: Dice{count = 1, sides = 2}

// Gold and potions pile up in one slot; everything else takes a slot each.
is_stackable :: proc(kind: Item_Kind) -> bool {
	category := ITEMS[kind].category
	return category == .Gold || category == .Potion || category == .Scroll
}

dice_text :: proc(dice: Dice) -> string {
	if dice.bonus > 0 do return fmt.tprintf("%dd%d+%d", dice.count, dice.sides, dice.bonus)
	return fmt.tprintf("%dd%d", dice.count, dice.sides)
}

// The rules line of an item's tooltip, like "Damage 1d6+1". (What clicking does is
// shown on its own line, because it depends on where the item is.)
item_rules_text :: proc(kind: Item_Kind) -> string {
	definition := ITEMS[kind]
	switch definition.category {
	case .Gold:   return "Currency."
	case .Potion: return fmt.tprintf("Heals %s.", dice_text(definition.heal_dice))
	case .Weapon: return fmt.tprintf("Damage %s.", dice_text(definition.damage_dice))
	case .Armor:  return fmt.tprintf("Armor %d: hits on you do %d less.", definition.armor, definition.armor)
	case .Scroll: return "Opens a portal back to the village."
	}
	return ""
}

Item_Stack :: struct {
	kind:  Item_Kind,
	count: int, // more than 1 only for stackable items
}

// ---------------------------------------------------------------------------
// The player's inventory
// ---------------------------------------------------------------------------

BACKPACK_SLOTS :: 12

Inventory :: struct {
	gold:           int,
	gold_collected: int, // every coin ever picked up, for the score (spending won't lower it)
	backpack: [dynamic]Item_Stack, // at most BACKPACK_SLOTS stacks
	// Maybe(...) holds either a value or nothing: no weapon wielded, no armor worn.
	weapon:   Maybe(Item_Kind),
	armor:    Maybe(Item_Kind),
}

// Puts items into the inventory. Returns false if the backpack has no room.
add_to_inventory :: proc(inventory: ^Inventory, stack: Item_Stack) -> bool {
	if stack.kind == .Gold {
		inventory.gold += stack.count
		inventory.gold_collected += stack.count
		return true
	}
	if is_stackable(stack.kind) {
		for &existing in inventory.backpack {
			if existing.kind == stack.kind {
				existing.count += stack.count
				return true
			}
		}
	}
	if len(inventory.backpack) >= BACKPACK_SLOTS do return false
	append(&inventory.backpack, stack)
	return true
}

// Copies the equipped weapon and armor onto the player's rules numbers.
apply_equipment :: proc(scene: ^Scene) {
	inventory := &scene.inventory
	scene.player.damage_dice = FIST_DICE
	scene.player.weapon_sound = .Light
	scene.player.weapon_weight = .Light // unarmed hands are as quick as a dagger
	if weapon, wielding := inventory.weapon.?; wielding {
		scene.player.damage_dice = ITEMS[weapon].damage_dice
		scene.player.weapon_sound = ITEMS[weapon].sound
		scene.player.weapon_weight = ITEMS[weapon].weight
	}
	scene.player.armor = 0
	scene.player.armor_weight = .Light // unarmored is as nimble as it gets
	if armor, wearing := inventory.armor.?; wearing {
		scene.player.armor = ITEMS[armor].armor
		scene.player.armor_weight = ITEMS[armor].armor_weight
	}
}

// Clicking an item in the backpack: drink it, wield it, or wear it.
// Returns true if that used up the player's turn.
use_backpack_item :: proc(scene: ^Scene, slot_index: int) -> (used_a_turn: bool) {
	inventory := &scene.inventory
	stack := inventory.backpack[slot_index]
	definition := ITEMS[stack.kind]

	switch definition.category {
	case .Gold:
		return false
	case .Potion:
		player := &scene.player
		healed := min(roll_dice(definition.heal_dice), player.max_hit_points - player.hit_points)
		player.hit_points += healed
		inventory.backpack[slot_index].count -= 1
		if inventory.backpack[slot_index].count == 0 do ordered_remove(&inventory.backpack, slot_index)
		add_floating_number(&scene.effects, footprint_center(player, player.hex), CREATURES[player.kind].frame_size.y + 16, healed, rl.GREEN, is_heal = true)
		set_message(scene, "You drink the %s and heal %d.", definition.name, healed)
		return true
	case .Weapon:
		// Swap: the old weapon takes the new one's place in the backpack.
		previous, had_one := inventory.weapon.?
		inventory.weapon = stack.kind
		if had_one {
			inventory.backpack[slot_index] = Item_Stack{kind = previous, count = 1}
		} else {
			ordered_remove(&inventory.backpack, slot_index)
		}
		apply_equipment(scene)
		set_message(scene, "You wield the %s.", definition.name)
	case .Armor:
		previous, had_one := inventory.armor.?
		inventory.armor = stack.kind
		if had_one {
			inventory.backpack[slot_index] = Item_Stack{kind = previous, count = 1}
		} else {
			ordered_remove(&inventory.backpack, slot_index)
		}
		apply_equipment(scene)
		set_message(scene, "You put on the %s.", definition.name)
	case .Scroll:
		if !open_portal(scene) do return false // the message already explains why
		inventory.backpack[slot_index].count -= 1
		if inventory.backpack[slot_index].count == 0 do ordered_remove(&inventory.backpack, slot_index)
		return true
	}
	return false
}

// Buying from a villager's shop (see NPCS[role].sells in village.odin). Doesn't cost
// a turn: haggling in the village is safe.
buy_item :: proc(scene: ^Scene, item: Item_Kind, price: int) {
	if scene.inventory.gold < price {
		set_message(scene, "You can't afford that.")
		return
	}
	if !add_to_inventory(&scene.inventory, Item_Stack{item, 1}) {
		set_message(scene, "Your backpack is full.")
		return
	}
	scene.inventory.gold -= price
	set_message(scene, "You buy the %s.", ITEMS[item].name)
}

Equipment_Slot :: enum {
	Weapon,
	Armor,
}

// Clicking an equipment slot: take the item off and put it in the backpack.
unequip :: proc(scene: ^Scene, slot: Equipment_Slot) {
	inventory := &scene.inventory
	equipped := &inventory.weapon if slot == .Weapon else &inventory.armor
	kind, has_one := equipped.?
	if !has_one do return
	if !add_to_inventory(inventory, Item_Stack{kind = kind, count = 1}) {
		set_message(scene, "Your backpack is full.")
		return
	}
	equipped^ = nil
	apply_equipment(scene)
	set_message(scene, "You put the %s in your backpack.", ITEMS[kind].name)
}

// ---------------------------------------------------------------------------
// Loot tables
// ---------------------------------------------------------------------------

random_between :: proc(lowest, highest: int, generator: runtime.Random_Generator) -> int {
	return lowest + rand.int_max(highest - lowest + 1, generator)
}

roll_creature_loot :: proc(kind: Creature_Kind, depth: int, loot: ^[dynamic]Item_Stack) {
	generator := context.random_generator
	#partial switch kind {
	case .Goblin:
		if rand.float32(generator) < 0.6 do append(loot, Item_Stack{.Gold, random_between(2, 8 + depth, generator)})
		if rand.float32(generator) < 0.25 do append(loot, Item_Stack{.Healing_Potion, 1})
		if rand.float32(generator) < 0.15 do append(loot, Item_Stack{.Goblin_Dagger, 1})
	case .Ogre:
		append(loot, Item_Stack{.Gold, random_between(10, 25 + depth * 2, generator)})
		if rand.float32(generator) < 0.5 do append(loot, Item_Stack{.Healing_Potion, 1})
		if rand.float32(generator) < 0.4 do append(loot, Item_Stack{.Spiked_Club, 1})
	}
}

// Chests are filled while the level is generated, with the level's own random
// generator, so the same seed always hides the same treasure.
roll_chest_loot :: proc(depth: int, generator: runtime.Random_Generator, loot: ^[dynamic]Item_Stack) {
	append(loot, Item_Stack{.Gold, random_between(5, 15 + depth * 3, generator)})
	roll := rand.float32(generator)
	switch {
	case roll < 0.40:                 append(loot, Item_Stack{.Healing_Potion, 1})
	case roll < 0.60:                 append(loot, Item_Stack{.Leather_Armor, 1})
	case roll < 0.75:                 append(loot, Item_Stack{.Longsword, 1})
	case roll < 0.85 && depth >= 2:   append(loot, Item_Stack{.Chain_Shirt, 1})
	case:                             append(loot, Item_Stack{.Goblin_Dagger, 1})
	}
	if rand.float32(generator) < 0.3 do append(loot, Item_Stack{.Healing_Potion, 1})
}

// ---------------------------------------------------------------------------
// Containers: corpses and chests
// ---------------------------------------------------------------------------

Container_Kind :: enum u8 {
	Goblin_Corpse,
	Adventurer_Corpse,
	Ogre_Corpse,
	Chest,
	Dropped_Items, // things you put down; drawn as the icon of what's on top
}

Container :: struct {
	kind:            Container_Kind,
	anchor_hex:      hexgrid.Hex,
	footprint:       []hexgrid.Hex, // hexes it covers, relative to anchor_hex (an ogre's body covers three)
	items:           [dynamic]Item_Stack,
	has_been_opened: bool,
}

// Where each picture is in assets/objects.png (see OBJECT_LAYOUT in art_source/objects.py
// and items_and_objects_guide.png).
CONTAINER_SPRITE_REGIONS := [Container_Kind]rl.Rectangle {
	.Goblin_Corpse     = {0, 0, 24, 12},
	.Adventurer_Corpse = {24, 0, 24, 12},
	.Ogre_Corpse       = {48, 0, 48, 24},
	.Chest             = {0, 24, 20, 18}, // closed
	.Dropped_Items     = {0, 0, 16, 16},  // the item's own icon, from item_icons.png
}
OPEN_CHEST_SPRITE_REGION :: rl.Rectangle{20, 24, 20, 18}

container_name :: proc(kind: Container_Kind) -> string {
	switch kind {
	case .Goblin_Corpse:     return "Goblin corpse"
	case .Adventurer_Corpse: return "Your corpse"
	case .Ogre_Corpse:       return "Ogre corpse"
	case .Chest:             return "Chest"
	case .Dropped_Items:     return "Dropped items"
	}
	return ""
}

corpse_kind_for :: proc(creature: Creature_Kind) -> Container_Kind {
	switch creature {
	case .Adventurer: return .Adventurer_Corpse
	case .Goblin:     return .Goblin_Corpse
	case .Ogre:       return .Ogre_Corpse
	}
	return .Goblin_Corpse
}

// You can walk over corpses and dropped things, but not through a chest.
container_blocks_movement :: proc(container: ^Container) -> bool {
	return container.kind == .Chest
}

// Puts one item from the backpack on the floor at the player's feet. Dropped things
// go into a pile on that hex, which can be picked up again like any other loot.
drop_backpack_item :: proc(scene: ^Scene, slot_index: int, whole_stack := false) {
	inventory := &scene.inventory
	stack := inventory.backpack[slot_index]
	dropped := stack if whole_stack else Item_Stack{stack.kind, 1}

	if whole_stack || stack.count <= 1 {
		ordered_remove(&inventory.backpack, slot_index)
	} else {
		inventory.backpack[slot_index].count -= 1
	}

	level := current_level(scene)
	pile_index := -1
	for &container, index in level.containers {
		if container.kind == .Dropped_Items && container.anchor_hex == scene.player.hex do pile_index = index
	}
	if pile_index < 0 {
		append(&level.containers, Container {
			kind            = .Dropped_Items,
			anchor_hex      = scene.player.hex,
			footprint       = SINGLE_HEX_FOOTPRINT[:],
			has_been_opened = true, // it's your own pile: nothing to discover
		})
		pile_index = len(level.containers) - 1
	}
	pile := &level.containers[pile_index]
	for &existing in pile.items {
		if existing.kind == dropped.kind && is_stackable(dropped.kind) {
			existing.count += dropped.count
			set_message(scene, "You drop %d x %s.", dropped.count, ITEMS[dropped.kind].name)
			return
		}
	}
	append(&pile.items, dropped)
	if dropped.count > 1 {
		set_message(scene, "You drop %d x %s.", dropped.count, ITEMS[dropped.kind].name)
	} else {
		set_message(scene, "You drop the %s.", ITEMS[dropped.kind].name)
	}
}

// Takes an equipped item off and drops it straight on the floor.
drop_equipped :: proc(scene: ^Scene, slot: Equipment_Slot) {
	inventory := &scene.inventory
	equipped := &inventory.weapon if slot == .Weapon else &inventory.armor
	kind, has_one := equipped.?
	if !has_one do return
	equipped^ = nil
	apply_equipment(scene)
	append(&inventory.backpack, Item_Stack{kind, 1}) // put it in the pack for a moment...
	drop_backpack_item(scene, len(inventory.backpack) - 1, whole_stack = true) // ...then on the floor
}

container_covers :: proc(container: ^Container, hex: hexgrid.Hex) -> bool {
	for offset in container.footprint {
		if hexgrid.hex_add(container.anchor_hex, offset) == hex do return true
	}
	return false
}

// Steps from `hex` to the nearest hex the container covers.
container_distance :: proc(container: ^Container, hex: hexgrid.Hex) -> i32 {
	shortest := max(i32)
	for offset in container.footprint {
		shortest = min(shortest, hexgrid.hex_distance(hexgrid.hex_add(container.anchor_hex, offset), hex))
	}
	return shortest
}

container_center :: proc(container: ^Container) -> rl.Vector3 {
	sum: rl.Vector3
	for offset in container.footprint {
		sum += hex_floor_position(hexgrid.hex_add(container.anchor_hex, offset))
	}
	return sum / f32(len(container.footprint))
}

// Every container covering this hex, newest first, as indices into level.containers.
// Bodies can pile up: a goblin can die on a hex the ogre's body already covers.
// (Indices rather than pointers: new corpses get added to the list during play,
// and growing a list can move it in memory, which would leave pointers dangling.)
container_indices_at :: proc(level: ^Level, hex: hexgrid.Hex) -> [dynamic]int {
	indices := make([dynamic]int, context.temp_allocator)
	#reverse for &container, index in level.containers {
		if container_covers(&container, hex) do append(&indices, index)
	}
	return indices
}

footprint_for_container :: proc(kind: Container_Kind) -> []hexgrid.Hex {
	return TRIANGLE_FOOTPRINT[:] if kind == .Ogre_Corpse else SINGLE_HEX_FOOTPRINT[:]
}

leave_corpse :: proc(scene: ^Scene, creature: ^Actor) {
	corpse := Container {
		kind       = corpse_kind_for(creature.kind),
		anchor_hex = creature.hex,
		footprint  = actor_footprint(creature),
	}
	if creature != &scene.player {
		roll_creature_loot(creature.kind, scene.current_depth, &corpse.items)
		if creature.named != .None {
			append(&corpse.items, ..NAMED_CREATURES[creature.named].trophy[:])
		}
	}
	append(&current_level(scene).containers, corpse)
}
