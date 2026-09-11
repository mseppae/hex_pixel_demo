package main

// Scoring and the ranking list ("Hall of the Fallen").
//
// An adventure ends when you die. Its score is the deepest depth you reached, times
// POINTS_PER_DEPTH, plus all the gold you picked up along the way. The ten best runs
// are kept in saves/ranking.json, next to the save slots.

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:slice"
import "core:time"
import "core:time/timezone"
import rl "vendor:raylib"

POINTS_PER_DEPTH       :: 100
RANKING_SIZE           :: 10
RANKING_FORMAT_VERSION :: 1

Calendar_Date :: struct {
	year:  int,
	month: int,
	day:   int,
}

// No strings in here, so the list needs no memory bookkeeping: the killer is stored
// as a creature kind (a number in the file, so the enum rule from save.odin applies).
Ranking_Entry :: struct {
	points:         int,
	deepest_depth:  int,
	gold_collected: int,
	killed_by:      Creature_Kind,
	date:           Calendar_Date,
}

Ranking_File :: struct {
	version: int,
	entries: []Ranking_Entry,
}

score_for :: proc(deepest_depth, gold_collected: int) -> int {
	return deepest_depth * POINTS_PER_DEPTH + gold_collected
}

current_score :: proc(scene: ^Scene) -> int {
	return score_for(scene.deepest_depth, scene.inventory.gold_collected)
}

ranking_path :: proc() -> string {
	return fmt.tprintf("%s/ranking.json", saves_folder())
}

load_ranking :: proc(scene: ^Scene) {
	clear(&scene.ranking)
	data, read_error := os.read_entire_file(ranking_path(), context.temp_allocator)
	if read_error != nil do return // no ranking yet
	file: Ranking_File
	if json.unmarshal(data, &file, allocator = context.temp_allocator) != nil do return
	if file.version != RANKING_FORMAT_VERSION do return
	append(&scene.ranking, ..file.entries)
}

write_ranking :: proc(scene: ^Scene) -> bool {
	file := Ranking_File{version = RANKING_FORMAT_VERSION, entries = scene.ranking[:]}
	data, marshal_error := json.marshal(file, {pretty = true, use_spaces = true, spaces = 1}, context.temp_allocator)
	if marshal_error != nil do return false
	if !os.exists(saves_folder()) && os.make_directory(saves_folder()) != nil do return false
	return os.write_entire_file(ranking_path(), data) == nil
}

// Adds a run to the list, best first, keeping only the top RANKING_SIZE.
// Returns its place in the list, or -1 if it didn't make it.
add_to_ranking :: proc(scene: ^Scene, entry: Ranking_Entry) -> (place: int) {
	append(&scene.ranking, entry)
	// A stable sort keeps older runs above newer ones with the same score.
	slice.stable_sort_by(scene.ranking[:], proc(first, second: Ranking_Entry) -> bool {
		return first.points > second.points
	})
	place = -1
	#reverse for other, index in scene.ranking {
		if other == entry {
			place = index
			break
		}
	}
	if len(scene.ranking) > RANKING_SIZE do resize(&scene.ranking, RANKING_SIZE)
	if place >= RANKING_SIZE do place = -1
	return place
}

today :: proc() -> Calendar_Date {
	moment, _ := time.time_to_datetime(time.now())
	if region, found := timezone.region_load("local", context.temp_allocator); found {
		moment = timezone.datetime_to_tz(moment, region)
	}
	return {int(moment.year), int(moment.month), int(moment.day)}
}

// Called once, when the player's death animation has finished.
end_adventure :: proc(scene: ^Scene) {
	entry := Ranking_Entry {
		points         = current_score(scene),
		deepest_depth  = scene.deepest_depth,
		gold_collected = scene.inventory.gold_collected,
		killed_by      = scene.killed_by,
		date           = today(),
	}
	load_ranking(scene) // in case another copy of the game changed it meanwhile
	scene.last_run = entry
	scene.last_run_place = add_to_ranking(scene, entry)
	write_ranking(scene)

	// Death is final: every save of this adventure goes too.
	scene.deleted_save_count = delete_saves_of_adventure(scene.adventure_id)

	scene.ranking_after_death = true
	scene.menu = .Ranking
}

// "a goblin", "an ogre"
creature_with_article :: proc(kind: Creature_Kind) -> string {
	switch kind {
	case .Adventurer: return "another adventurer"
	case .Goblin:     return "a goblin"
	case .Ogre:       return "an ogre"
	}
	return "something"
}

// ---------------------------------------------------------------------------
// The ranking panel
// ---------------------------------------------------------------------------

RANKING_PANEL :: rl.Rectangle{58, 18, 310, 206}

ranking_button_rectangle :: proc(index: int) -> rl.Rectangle {
	// Buttons along the bottom, from the right.
	width: f32 = 92
	return {RANKING_PANEL.x + RANKING_PANEL.width - 8 - f32(index + 1) * width - f32(index) * 6, RANKING_PANEL.y + RANKING_PANEL.height - 22, width, 16}
}

ranking_buttons_after_death := [?]string{"Start menu", "New adventure"}

draw_ranking_panel :: proc(scene: ^Scene) {
	panel := RANKING_PANEL
	left, top := i32(panel.x), i32(panel.y)
	rows_top := top + 22

	if scene.ranking_after_death {
		draw_panel(panel, "You have fallen")
		run := scene.last_run
		draw_text(fmt.tprintf("Slain by %s on depth %d.", creature_with_article(run.killed_by), scene.current_depth), left + 8, top + 20, TEXT_COLOR)
		draw_text(fmt.tprintf("Depth %d x %d + %d gold = %d points", run.deepest_depth, POINTS_PER_DEPTH, run.gold_collected, run.points), left + 8, top + 32, GOLD_TEXT_COLOR)
		if scene.last_run_place >= 0 {
			draw_text(fmt.tprintf("Rank %d of %d.", scene.last_run_place + 1, len(scene.ranking)), left + 200, top + 20, TEXT_COLOR)
		} else {
			draw_text("Not in the top ten.", left + 200, top + 20, DIM_TEXT_COLOR)
		}
		if scene.deleted_save_count > 0 {
			draw_text("Its save is gone.", left + 200, top + 32, DIM_TEXT_COLOR)
		}
		rows_top = top + 50
	} else {
		draw_panel(panel, "Hall of the Fallen")
	}

	// Column headings, then one row per run.
	column_x := [5]i32{left + 8, left + 30, left + 80, left + 130, left + 182}
	headings := [5]string{"#", "Points", "Depth", "Gold", "Slain by"}
	for heading, column in headings do draw_text(heading, column_x[column], rows_top, DIM_TEXT_COLOR)

	if len(scene.ranking) == 0 {
		draw_text("No one has fallen yet.", left + 8, rows_top + 14, DIM_TEXT_COLOR)
	}
	for entry, index in scene.ranking {
		y := rows_top + 13 + i32(index) * 11
		if scene.ranking_after_death && index == scene.last_run_place {
			rl.DrawRectangle(left + 4, y - 1, i32(panel.width) - 8, 11, rl.Color{120, 96, 40, 160}) // this run
		}
		draw_text(fmt.tprintf("%d", index + 1), column_x[0], y, TEXT_COLOR)
		draw_text(fmt.tprintf("%d", entry.points), column_x[1], y, GOLD_TEXT_COLOR)
		draw_text(fmt.tprintf("%d", entry.deepest_depth), column_x[2], y, TEXT_COLOR)
		draw_text(fmt.tprintf("%d", entry.gold_collected), column_x[3], y, TEXT_COLOR)
		draw_text(fmt.tprintf("%s  %d-%02d-%02d", creature_with_article(entry.killed_by), entry.date.year, entry.date.month, entry.date.day), column_x[4], y, DIM_TEXT_COLOR)
	}

	if scene.ranking_after_death {
		for label, index in ranking_buttons_after_death {
			draw_button(scene, ranking_button_rectangle(index), label)
		}
	} else {
		draw_button(scene, ranking_button_rectangle(0), "Back")
	}
}

handle_ranking_click :: proc(scene: ^Scene) {
	if !scene.ranking_after_death {
		if mouse_is_over(scene, ranking_button_rectangle(0)) do scene.menu = .Start
		return
	}
	if mouse_is_over(scene, ranking_button_rectangle(0)) {
		go_to_start_menu_after_death(scene)
	} else if mouse_is_over(scene, ranking_button_rectangle(1)) { // New adventure
		scene.ranking_after_death = false
		start_new_game(scene, new_random_seed())
		scene.screen = .Playing
		scene.menu = .None
	}
}

go_to_start_menu_after_death :: proc(scene: ^Scene) {
	scene.ranking_after_death = false
	start_new_game(scene, 4471) // the usual backdrop; the fallen adventure can't be continued
	scene.screen = .Start_Menu
	scene.menu = .Start
}
