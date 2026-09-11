package main

// The inventory and loot panels. They're drawn into the same small image as the
// game (426 x 240), so icons and text get the same big pixels as everything else.
// All positions here are in that small image's pixels.

import "core:fmt"
import rl "vendor:raylib"

Open_Panel :: enum {
	None,
	Inventory,
	Loot,
	Dialogue, // talking to a villager (see village.odin)
}

UI_FONT_SIZE    :: 10 // raylib's built-in font is pixel-exact at size 10
SLOT_SIZE       :: 20 // a 16 x 16 icon with a 2 pixel frame
SLOT_SPACING    :: 22
SLOTS_PER_ROW   :: 6

PANEL_BACKGROUND  :: rl.Color{24, 22, 30, 240}
PANEL_BORDER      :: rl.Color{128, 108, 78, 255}
SLOT_BACKGROUND   :: rl.Color{42, 40, 52, 255}
SLOT_BORDER       :: rl.Color{72, 68, 86, 255}
SLOT_HOVER_BORDER :: rl.Color{232, 202, 122, 255}
TEXT_COLOR        :: rl.Color{236, 230, 214, 255}
DIM_TEXT_COLOR    :: rl.Color{150, 144, 130, 255}
GOLD_TEXT_COLOR   :: rl.Color{248, 226, 122, 255}

INVENTORY_PANEL :: rl.Rectangle{83, 40, 260, 156}
LOOT_PANEL      :: rl.Rectangle{83, 52, 260, 128}
BAG_BUTTON      :: rl.Rectangle{LOW_RES_WIDTH - 64, LOW_RES_HEIGHT - 20, 60, 16}
TAKE_ALL_BUTTON :: rl.Rectangle{LOOT_PANEL.x + 8, LOOT_PANEL.y + LOOT_PANEL.height - 22, 60, 16}
CLOSE_BUTTON    :: rl.Rectangle{LOOT_PANEL.x + LOOT_PANEL.width - 56, LOOT_PANEL.y + LOOT_PANEL.height - 22, 48, 16}

backpack_slot_rectangle :: proc(index: int) -> rl.Rectangle {
	return {
		INVENTORY_PANEL.x + 8 + f32(index % SLOTS_PER_ROW) * SLOT_SPACING,
		INVENTORY_PANEL.y + 74 + f32(index / SLOTS_PER_ROW) * SLOT_SPACING,
		SLOT_SIZE,
		SLOT_SIZE,
	}
}

equipment_slot_rectangle :: proc(slot: Equipment_Slot) -> rl.Rectangle {
	return {INVENTORY_PANEL.x + 8 + f32(slot) * 56, INVENTORY_PANEL.y + 34, SLOT_SIZE, SLOT_SIZE}
}

loot_slot_rectangle :: proc(index: int) -> rl.Rectangle {
	return {
		LOOT_PANEL.x + 8 + f32(index % SLOTS_PER_ROW) * SLOT_SPACING,
		LOOT_PANEL.y + 24 + f32(index / SLOTS_PER_ROW) * SLOT_SPACING,
		SLOT_SIZE,
		SLOT_SIZE,
	}
}

mouse_is_over :: proc(scene: ^Scene, rectangle: rl.Rectangle) -> bool {
	return rl.CheckCollisionPointRec(scene.mouse_in_low_res, rectangle)
}

mouse_is_over_ui :: proc(scene: ^Scene) -> bool {
	if mouse_is_over(scene, BAG_BUTTON) do return true
	switch scene.open_panel {
	case .None:      return false
	case .Inventory: return mouse_is_over(scene, INVENTORY_PANEL)
	case .Loot:      return mouse_is_over(scene, LOOT_PANEL)
	case .Dialogue:  return mouse_is_over(scene, DIALOGUE_PANEL)
	}
	return false
}

// Opens the loot panel on one or more containers (a pile of bodies shows as one list).
open_loot_panel :: proc(scene: ^Scene, container_indices: []int) {
	scene.open_panel = .Loot
	clear(&scene.open_container_indices)
	append(&scene.open_container_indices, ..container_indices)
	for index in container_indices {
		current_level(scene).containers[index].has_been_opened = true
	}
}

// One item shown in the loot panel: which container it's in, and where in that container.
Loot_Entry :: struct {
	container_index: int,
	item_index:      int,
}

loot_entries :: proc(scene: ^Scene) -> [dynamic]Loot_Entry {
	entries := make([dynamic]Loot_Entry, context.temp_allocator)
	level := current_level(scene)
	for container_index in scene.open_container_indices {
		for item_index in 0 ..< len(level.containers[container_index].items) {
			append(&entries, Loot_Entry{container_index, item_index})
		}
	}
	return entries
}

// "Goblin corpse", or "Goblin corpse and Ogre corpse", or "Goblin corpse and 2 more".
pile_title :: proc(level: ^Level, container_indices: []int) -> string {
	switch len(container_indices) {
	case 0: return ""
	case 1: return container_name(level.containers[container_indices[0]].kind)
	case 2: return fmt.tprintf("%s and %s", container_name(level.containers[container_indices[0]].kind), container_name(level.containers[container_indices[1]].kind))
	}
	return fmt.tprintf("%s and %d more", container_name(level.containers[container_indices[0]].kind), len(container_indices) - 1)
}

// ---------------------------------------------------------------------------
// Clicks
// ---------------------------------------------------------------------------

// A right-click inside the inventory drops the item under the mouse (the whole stack
// with Shift). Returns true if it was used up here.
handle_ui_right_click :: proc(scene: ^Scene) -> bool {
	if scene.open_panel != .Inventory || !mouse_is_over(scene, INVENTORY_PANEL) do return false
	whole_stack := rl.IsKeyDown(.LEFT_SHIFT) || rl.IsKeyDown(.RIGHT_SHIFT)
	for slot in Equipment_Slot {
		if mouse_is_over(scene, equipment_slot_rectangle(slot)) {
			drop_equipped(scene, slot)
			return true
		}
	}
	for index in 0 ..< len(scene.inventory.backpack) {
		if mouse_is_over(scene, backpack_slot_rectangle(index)) {
			drop_backpack_item(scene, index, whole_stack)
			return true
		}
	}
	return true // a right-click anywhere else in the panel does nothing
}

// Returns true if the click was meant for the interface (so the game world ignores it).
handle_ui_click :: proc(scene: ^Scene) -> bool {
	if mouse_is_over(scene, BAG_BUTTON) {
		scene.open_panel = .None if scene.open_panel == .Inventory else .Inventory
		return true
	}

	switch scene.open_panel {
	case .None:
		return false

	case .Inventory:
		if !mouse_is_over(scene, INVENTORY_PANEL) {
			scene.open_panel = .None // clicking outside closes the panel
			return true
		}
		for slot in Equipment_Slot {
			if mouse_is_over(scene, equipment_slot_rectangle(slot)) do unequip(scene, slot)
		}
		for index in 0 ..< len(scene.inventory.backpack) {
			if !mouse_is_over(scene, backpack_slot_rectangle(index)) do continue
			if scene.turn_phase != .Player_Choosing {
				set_message(scene, "Wait for your turn.")
			} else if use_backpack_item(scene, index) {
				scene.turn_phase = .Player_Acting // drinking took the turn; the monsters act next
			}
			break
		}
		return true

	case .Dialogue:
		handle_dialogue_click(scene)
		return true

	case .Loot:
		if !mouse_is_over(scene, LOOT_PANEL) || mouse_is_over(scene, CLOSE_BUTTON) {
			scene.open_panel = .None
			return true
		}
		level := current_level(scene)
		if mouse_is_over(scene, TAKE_ALL_BUTTON) {
			for container_index in scene.open_container_indices {
				container := &level.containers[container_index]
				index := 0
				for index < len(container.items) {
					if !take_loot(scene, container, index) do index += 1 // didn't fit: leave it there
				}
			}
			if len(loot_entries(scene)) == 0 do scene.open_panel = .None
			return true
		}
		for entry, slot in loot_entries(scene) {
			if slot < BACKPACK_SLOTS && mouse_is_over(scene, loot_slot_rectangle(slot)) {
				take_loot(scene, &level.containers[entry.container_index], entry.item_index)
				break
			}
		}
		return true
	}
	return false
}

// Moves one stack from a container into the inventory. Returns false if it didn't fit.
take_loot :: proc(scene: ^Scene, container: ^Container, index: int) -> bool {
	stack := container.items[index]
	if !add_to_inventory(&scene.inventory, stack) {
		set_message(scene, "Your backpack is full.")
		return false
	}
	ordered_remove(&container.items, index)
	// An empty pile of dropped things leaves nothing behind (a body or chest stays).
	if container.kind == .Dropped_Items && len(container.items) == 0 {
		level := current_level(scene)
		for other, other_index in level.containers {
			if &level.containers[other_index] == container {
				ordered_remove(&level.containers, other_index)
				clear(&scene.open_container_indices)
				scene.open_panel = .None
				_ = other
				break
			}
		}
	}
	switch {
	case stack.kind == .Gold: set_message(scene, "You take %d gold.", stack.count)
	case stack.count > 1:     set_message(scene, "You take %d x %s.", stack.count, ITEMS[stack.kind].name)
	case:                     set_message(scene, "You take the %s.", ITEMS[stack.kind].name)
	}
	return true
}

// ---------------------------------------------------------------------------
// Drawing
// ---------------------------------------------------------------------------

draw_ui :: proc(scene: ^Scene) {
	draw_button(scene, BAG_BUTTON, "Items (I)")
	switch scene.open_panel {
	case .None:
	case .Inventory: draw_inventory_panel(scene)
	case .Loot:      draw_loot_panel(scene)
	case .Dialogue:  draw_dialogue_panel(scene)
	}
}

draw_panel :: proc(rectangle: rl.Rectangle, title: string) {
	rl.DrawRectangleRec(rectangle, PANEL_BACKGROUND)
	rl.DrawRectangleLinesEx(rectangle, 1, PANEL_BORDER)
	draw_text(title, i32(rectangle.x) + 8, i32(rectangle.y) + 6, GOLD_TEXT_COLOR)
}

draw_text :: proc(text: string, x, y: i32, color: rl.Color) {
	rl.DrawText(fmt.ctprintf("%s", text), x, y, UI_FONT_SIZE, color)
}

draw_button :: proc(scene: ^Scene, rectangle: rl.Rectangle, label: string) {
	hovered := mouse_is_over(scene, rectangle)
	rl.DrawRectangleRec(rectangle, SLOT_BACKGROUND if hovered else PANEL_BACKGROUND)
	rl.DrawRectangleLinesEx(rectangle, 1, SLOT_HOVER_BORDER if hovered else PANEL_BORDER)
	label_width := rl.MeasureText(fmt.ctprintf("%s", label), UI_FONT_SIZE)
	draw_text(label, i32(rectangle.x + rectangle.width / 2) - label_width / 2, i32(rectangle.y) + 3, TEXT_COLOR)
}

// One slot: a frame, the item's icon, and how many if more than one.
draw_slot :: proc(scene: ^Scene, rectangle: rl.Rectangle, stack: Maybe(Item_Stack)) -> (hovered: bool) {
	hovered = mouse_is_over(scene, rectangle)
	rl.DrawRectangleRec(rectangle, SLOT_BACKGROUND)
	rl.DrawRectangleLinesEx(rectangle, 1, SLOT_HOVER_BORDER if hovered else SLOT_BORDER)
	if item, has_item := stack.?; has_item {
		draw_item_icon(scene, item.kind, rectangle.x + 2, rectangle.y + 2)
		if item.count > 1 {
			// On a small dark box in the corner, so the digits stay readable over busy icons.
			count_text := fmt.ctprintf("%d", item.count)
			text_width := rl.MeasureText(count_text, UI_FONT_SIZE)
			x := i32(rectangle.x + rectangle.width) - text_width - 2
			y := i32(rectangle.y + rectangle.height) - 10
			rl.DrawRectangle(x - 1, y, text_width + 2, 9, rl.Color{0, 0, 0, 200})
			rl.DrawText(count_text, x, y, UI_FONT_SIZE, TEXT_COLOR)
		}
	}
	return hovered
}

draw_item_icon :: proc(scene: ^Scene, kind: Item_Kind, x, y: f32) {
	source := rl.Rectangle{f32(kind) * 16, 0, 16, 16}
	rl.DrawTexturePro(scene.item_icons, source, {x, y, 16, 16}, {}, 0, rl.WHITE)
}

// Three lines at the bottom of a panel describing the item under the mouse.
draw_tooltip :: proc(kind: Item_Kind, action_hint: string, x, y: i32) {
	draw_text(ITEMS[kind].name, x, y, TEXT_COLOR)
	draw_text(item_rules_text(kind), x, y + 11, GOLD_TEXT_COLOR)
	draw_text(action_hint if action_hint != "" else ITEMS[kind].flavor, x, y + 22, DIM_TEXT_COLOR)
}

draw_inventory_panel :: proc(scene: ^Scene) {
	inventory := &scene.inventory
	panel := INVENTORY_PANEL
	left, top := i32(panel.x), i32(panel.y)
	draw_panel(panel, "Inventory")

	// Gold, top right
	draw_item_icon(scene, .Gold, panel.x + panel.width - 60, panel.y + 3)
	draw_text(fmt.tprintf("%d", inventory.gold), i32(panel.x + panel.width) - 40, top + 7, GOLD_TEXT_COLOR)

	hovered_kind: Maybe(Item_Kind)
	hover_hint := ""

	// Equipment
	draw_text("Weapon", left + 8, top + 22, DIM_TEXT_COLOR)
	draw_text("Armor", left + 64, top + 22, DIM_TEXT_COLOR)
	for slot in Equipment_Slot {
		equipped := inventory.weapon if slot == .Weapon else inventory.armor
		stack: Maybe(Item_Stack)
		if kind, has_one := equipped.?; has_one do stack = Item_Stack{kind, 1}
		if draw_slot(scene, equipment_slot_rectangle(slot), stack) && equipped != nil {
			hovered_kind = equipped
			hover_hint = "Click to stow it. Right-click to drop it."
		}
	}
	draw_text(fmt.tprintf("Damage %s", dice_text(scene.player.damage_dice)), left + 124, top + 34, TEXT_COLOR)
	draw_text(fmt.tprintf("Armor %d", scene.player.armor), left + 124, top + 46, TEXT_COLOR)

	// Backpack
	draw_text(fmt.tprintf("Backpack  %d / %d", len(inventory.backpack), BACKPACK_SLOTS), left + 8, top + 62, DIM_TEXT_COLOR)
	for index in 0 ..< BACKPACK_SLOTS {
		stack: Maybe(Item_Stack)
		if index < len(inventory.backpack) do stack = inventory.backpack[index]
		if draw_slot(scene, backpack_slot_rectangle(index), stack) && stack != nil {
			kind := inventory.backpack[index].kind
			hovered_kind = kind
			switch ITEMS[kind].category {
			case .Gold:   hover_hint = ""
			case .Potion: hover_hint = "Click to drink it. Right-click to drop it."
			case .Weapon: hover_hint = "Click to wield it. Right-click to drop it."
			case .Armor:  hover_hint = "Click to wear it. Right-click to drop it."
			}
		}
	}

	if kind, has_one := hovered_kind.?; has_one {
		draw_tooltip(kind, hover_hint, left + 8, top + 120)
	} else {
		draw_text("Click an item to use it, right-click to drop it", left + 8, top + 120, DIM_TEXT_COLOR)
		draw_text("(hold Shift to drop a whole stack).", left + 8, top + 131, DIM_TEXT_COLOR)
	}
}

draw_loot_panel :: proc(scene: ^Scene) {
	level := current_level(scene)
	panel := LOOT_PANEL
	left, top := i32(panel.x), i32(panel.y)
	draw_panel(panel, pile_title(level, scene.open_container_indices[:]))

	entries := loot_entries(scene)
	hovered_entry: Maybe(Loot_Entry)
	for slot in 0 ..< BACKPACK_SLOTS {
		stack: Maybe(Item_Stack)
		if slot < len(entries) {
			stack = level.containers[entries[slot].container_index].items[entries[slot].item_index]
		}
		if draw_slot(scene, loot_slot_rectangle(slot), stack) && stack != nil {
			hovered_entry = entries[slot]
		}
	}

	if entry, has_one := hovered_entry.?; has_one {
		container := &level.containers[entry.container_index]
		hint := "Click to take it."
		if len(scene.open_container_indices) > 1 {
			// In a pile, say whose it is.
			hint = fmt.tprintf("From the %s. Click to take it.", container_name(container.kind))
		}
		draw_tooltip(container.items[entry.item_index].kind, hint, left + 8, top + 70)
	} else if len(entries) == 0 {
		draw_text("Nothing left.", left + 8, top + 70, DIM_TEXT_COLOR)
	} else {
		draw_text("Click an item to take it.", left + 8, top + 70, DIM_TEXT_COLOR)
	}
	draw_button(scene, TAKE_ALL_BUTTON, "Take all")
	draw_button(scene, CLOSE_BUTTON, "Close")
}

// A label over the corpse or chest under the mouse, like "Chest" or
// "Goblin corpse and Ogre corpse (empty)".
draw_container_label :: proc(scene: ^Scene, camera: rl.Camera3D) {
	if scene.open_panel != .None || !scene.mouse_is_over_map do return
	level := current_level(scene)
	indices := container_indices_at(level, scene.hovered_hex)
	if len(indices) == 0 || actor_at(scene, scene.hovered_hex) != nil do return

	label := pile_title(level, indices[:])
	all_emptied := true
	// Find the top of the highest picture on screen, so the label doesn't cover any of
	// them. (An ogre's body is centered where its three hexes meet, not on this hex.)
	camera_up := camera_up_direction(camera)
	label_bottom := rl.GetWorldToScreenEx(hex_floor_position(scene.hovered_hex), camera, LOW_RES_WIDTH, LOW_RES_HEIGHT)
	for index in indices {
		container := &level.containers[index]
		if !container.has_been_opened || len(container.items) > 0 do all_emptied = false
		picture_top := container_center(container) + camera_up * (CONTAINER_SPRITE_REGIONS[container.kind].height + 3)
		label_bottom.y = min(label_bottom.y, rl.GetWorldToScreenEx(picture_top, camera, LOW_RES_WIDTH, LOW_RES_HEIGHT).y)
	}
	if all_emptied do label = fmt.tprintf("%s (empty)", label)

	text := fmt.ctprintf("%s", label)
	width := rl.MeasureText(text, UI_FONT_SIZE)
	x := i32(label_bottom.x) - width / 2
	y := i32(label_bottom.y) - 11
	rl.DrawRectangle(x - 3, y - 2, width + 6, 13, PANEL_BACKGROUND)
	rl.DrawText(text, x, y, UI_FONT_SIZE, GOLD_TEXT_COLOR)
}
