package main

// The start menu, the in-game menu (Esc), and the lists of save slots.
// Like the other panels, these are drawn into the small 426 x 240 image.

import "core:fmt"
import rl "vendor:raylib"

Screen :: enum {
	Start_Menu, // before an adventure: the dungeon is only a dimmed backdrop
	Playing,
}

Menu :: enum {
	None,
	Start,      // Start adventure / Load adventure / Quit
	Game,       // Continue / Save / Load / Quit to start menu
	Save_Slots,
	Load_Slots,
	Ranking,    // the Hall of the Fallen, from the start menu or after dying
}

START_MENU_PANEL :: rl.Rectangle{103, 44, 220, 144}
GAME_MENU_PANEL  :: rl.Rectangle{103, 40, 220, 170} // one more button, and a note under them
SLOTS_PANEL      :: rl.Rectangle{83, 36, 260, 166}
MENU_BUTTON_SIZE :: rl.Vector2{160, 16}

menu_panel :: proc(scene: ^Scene) -> rl.Rectangle {
	return START_MENU_PANEL if scene.menu == .Start else GAME_MENU_PANEL
}

menu_button_rectangle :: proc(scene: ^Scene, index: int) -> rl.Rectangle {
	panel := menu_panel(scene)
	return {
		panel.x + (panel.width - MENU_BUTTON_SIZE.x) / 2,
		panel.y + 42 + f32(index) * 22,
		MENU_BUTTON_SIZE.x,
		MENU_BUTTON_SIZE.y,
	}
}

slot_rectangle :: proc(slot: int) -> rl.Rectangle {
	return {SLOTS_PANEL.x + 8, SLOTS_PANEL.y + 22 + f32(slot) * 34, SLOTS_PANEL.width - 16, 30}
}

SLOTS_BACK_BUTTON :: rl.Rectangle{SLOTS_PANEL.x + SLOTS_PANEL.width - 64, SLOTS_PANEL.y + SLOTS_PANEL.height - 22, 56, 16}

start_menu_labels := [?]string{"Start adventure", "Load adventure", "Ranking", "Quit"}
game_menu_labels  := [?]string{"Continue", "Save adventure", "Load adventure", "Quit to start menu"}

open_slot_list :: proc(scene: ^Scene, menu: Menu) {
	scene.menu = menu
	refresh_slot_infos(scene)
}

// Esc: close whatever is open, one layer at a time; on the map, open the game menu.
handle_escape_key :: proc(scene: ^Scene) {
	switch {
	case scene.open_panel != .None:
		scene.open_panel = .None
	case scene.menu == .Save_Slots || scene.menu == .Load_Slots:
		scene.menu = .Start if scene.screen == .Start_Menu else .Game
	case scene.menu == .Ranking:
		if scene.ranking_after_death {
			go_to_start_menu_after_death(scene)
		} else {
			scene.menu = .Start
		}
	case scene.menu == .Game:
		scene.menu = .None
	case scene.menu == .None && scene.screen == .Playing:
		scene.menu = .Game
	}
}

// Returns true if a menu is open (so the click is used up here, either way).
handle_menu_click :: proc(scene: ^Scene) -> bool {
	switch scene.menu {
	case .None:
		return false

	case .Start:
		for _, index in start_menu_labels {
			if !mouse_is_over(scene, menu_button_rectangle(scene, index)) do continue
			switch index {
			case 0: // Start adventure
				start_new_game(scene, new_random_seed())
				scene.screen = .Playing
				scene.menu = .None
			case 1:
				open_slot_list(scene, .Load_Slots)
			case 2:
				load_ranking(scene)
				scene.ranking_after_death = false
				scene.menu = .Ranking
			case 3:
				scene.should_quit = true
			}
		}

	case .Game:
		for _, index in game_menu_labels {
			if !mouse_is_over(scene, menu_button_rectangle(scene, index)) do continue
			switch index {
			case 0:
				scene.menu = .None
			case 1:
				if can_save_now(scene) {
					open_slot_list(scene, .Save_Slots)
				} else {
					set_message(scene, "You can only save when it's your turn.")
					scene.menu = .None
				}
			case 2:
				open_slot_list(scene, .Load_Slots)
			case 3:
				scene.screen = .Start_Menu
				scene.menu = .Start
			}
		}

	case .Ranking:
		handle_ranking_click(scene)

	case .Save_Slots, .Load_Slots:
		if mouse_is_over(scene, SLOTS_BACK_BUTTON) {
			scene.menu = .Start if scene.screen == .Start_Menu else .Game
			return true
		}
		for slot in 0 ..< SAVE_SLOT_COUNT {
			if !mouse_is_over(scene, slot_rectangle(slot)) do continue
			if scene.menu == .Save_Slots {
				if save_to_slot(scene, slot) {
					set_message(scene, "Saved to slot %d.", slot + 1)
				} else {
					set_message(scene, "Couldn't save to slot %d (see %s).", slot + 1, saves_folder())
				}
				scene.menu = .None
			} else {
				info := &scene.slot_infos[slot]
				if !info.readable do break // empty or unreadable: nothing to load
				if load_from_slot(scene, slot) {
					scene.screen = .Playing
					scene.menu = .None
					set_message(scene, "Loaded slot %d. Depth %d.", slot + 1, scene.current_depth)
				} else {
					info.readable = false
				}
			}
			break
		}
	}
	return true
}

// ---------------------------------------------------------------------------
// Drawing
// ---------------------------------------------------------------------------

draw_menu :: proc(scene: ^Scene) {
	if scene.menu == .None do return
	// Darken the game behind the menu.
	rl.DrawRectangle(0, 0, LOW_RES_WIDTH, LOW_RES_HEIGHT, rl.Color{0, 0, 0, 150})

	switch scene.menu {
	case .None:
	case .Start:
		panel := START_MENU_PANEL
		rl.DrawRectangleRec(panel, PANEL_BACKGROUND)
		rl.DrawRectangleLinesEx(panel, 1, PANEL_BORDER)
		title: cstring = "HEX DUNGEON"
		title_width := rl.MeasureText(title, 20) // twice the pixel font size: every letter pixel is 2 x 2
		rl.DrawText(title, i32(panel.x + panel.width / 2) - title_width / 2, i32(panel.y) + 12, 20, GOLD_TEXT_COLOR)
		for label, index in start_menu_labels {
			draw_button(scene, menu_button_rectangle(scene, index), label)
		}
	case .Game:
		panel := GAME_MENU_PANEL
		draw_panel(panel, "Paused")
		for label, index in game_menu_labels {
			draw_button(scene, menu_button_rectangle(scene, index), label)
		}
		draw_text("Quitting loses progress since your", i32(panel.x) + 12, i32(panel.y + panel.height) - 26, DIM_TEXT_COLOR)
		draw_text("last save.", i32(panel.x) + 12, i32(panel.y + panel.height) - 15, DIM_TEXT_COLOR)
	case .Ranking:
		draw_ranking_panel(scene)
	case .Save_Slots, .Load_Slots:
		saving := scene.menu == .Save_Slots
		draw_panel(SLOTS_PANEL, "Save to which slot?" if saving else "Load which adventure?")
		for slot in 0 ..< SAVE_SLOT_COUNT {
			draw_slot_button(scene, slot, saving)
		}
		draw_button(scene, SLOTS_BACK_BUTTON, "Back")
	}
}

draw_slot_button :: proc(scene: ^Scene, slot: int, saving: bool) {
	info := &scene.slot_infos[slot]
	rectangle := slot_rectangle(slot)
	clickable := saving || info.readable
	hovered := clickable && mouse_is_over(scene, rectangle)
	rl.DrawRectangleRec(rectangle, SLOT_BACKGROUND)
	rl.DrawRectangleLinesEx(rectangle, 1, SLOT_HOVER_BORDER if hovered else SLOT_BORDER)

	left, top := i32(rectangle.x) + 6, i32(rectangle.y) + 4
	switch {
	case info.readable:
		draw_text(fmt.tprintf("Slot %d    Depth %d    HP %d / %d    Gold %d", slot + 1, info.depth, info.hit_points, info.max_hit_points, info.gold), left, top, TEXT_COLOR)
		draw_text(fmt.tprintf("Saved %s%s", slot_saved_at(info), "  (click to overwrite)" if saving else ""), left, top + 12, DIM_TEXT_COLOR)
	case info.exists:
		draw_text(fmt.tprintf("Slot %d", slot + 1), left, top, TEXT_COLOR)
		draw_text("From another version of the game.", left, top + 12, DIM_TEXT_COLOR)
	case:
		draw_text(fmt.tprintf("Slot %d", slot + 1), left, top, TEXT_COLOR if saving else DIM_TEXT_COLOR)
		draw_text("Empty", left, top + 12, DIM_TEXT_COLOR)
	}
}
