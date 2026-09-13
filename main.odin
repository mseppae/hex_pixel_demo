package main

// A hex-grid dungeon in pixel art, seen through a 3D camera.
//
//   Q / E   turn the camera 60 degrees
//   W / S   tilt the camera to the next preset angle
//   Click   walk one step toward a tile, or attack a monster standing next to you.
//           Click the stairs to walk onto them and take them.
//           Click a corpse or chest next to you to loot it.
//   I       open or close the inventory (or click "Items")
//   M       sound on / off
//   Right-click an item in the inventory to drop it (Shift: the whole stack)
//   Esc     close a panel, or open the menu (save, load, quit to the start menu)
//
// Files:
//   main.odin            setup, the frame loop, the camera, drawing
//   level.odin           tiles, levels, and the cave generator
//   creatures.odin       the settings for each kind of creature
//   actors.odin          characters and their animations
//   rules.odin           turns, stairs, combat, pathfinding
//   effects.odin         blood drops, blood stains, floating damage numbers
//   input.odin           catching quick clicks and trackpad taps
//   items.odin           items, the inventory, loot tables, corpses and chests
//   ui.odin              the inventory and loot panels
//   menu.odin            the start menu, the in-game menu, and the save slots
//   save.odin            save files: what goes in them, writing and reading them
//   ranking.odin         the score and the ranking list
//   sound.odin           sound effects
//   village.odin         the village, its people, quests and named creatures
//   content.odin         reads villagers, quests and named creatures from assets/content.json
//   hex_prism_mesh.odin  the 3D tile shapes with pixel art on their faces

import "core:fmt"
import "core:math"
import "core:math/rand"
import "core:slice"
import rl "vendor:raylib"
import "hexgrid"

// One world unit = one pixel of art. With size 16, a hex top is 28 x 32 art pixels.
HEX_SIZE     :: 16.0
FLOOR_HEIGHT :: 4.0  // matches the 4-pixel-tall floor side art
WALL_HEIGHT  :: 24.0 // matches the 24-pixel-tall wall side art

// The size of the small image the scene is drawn into before scaling up.
LOW_RES_WIDTH  :: 426
LOW_RES_HEIGHT :: 240

// How far the camera sits from what it looks at. With an orthographic camera this
// does not change the size of anything. It must be far enough that the stretched
// upright sprites (very tall when the camera looks almost straight down) stay in
// front of the camera, and near enough that everything on screen stays inside
// raylib's default drawing distance of 1000.
CAMERA_DISTANCE :: 700.0

// How far you can see, in steps. Everything farther away stays dark.
VIEW_RADIUS :: 5

// The camera tilts you can switch between with W / S, in degrees down from the horizon.
// Camera changes are instant, never animated: pixel art only looks crisp when the camera
// is at rest, and every in-between frame makes all the textures swim and then settle.
TILT_ANGLES := [?]f32{35, 45, 60, 75}
STARTING_TILT_INDEX :: 2 // 60 degrees

// The art is built into the program at compile time, so it cannot go missing at
// run time, no matter which folder the program is started from.
// These paths are relative to this source file.
TILES_PNG            :: #load("assets/tiles.png")
ADVENTURER_SHEET_PNG :: #load("assets/adventurer_sheet.png")
GOBLIN_SHEET_PNG     :: #load("assets/goblin_sheet.png")
OGRE_SHEET_PNG       :: #load("assets/ogre_sheet.png")
ITEM_ICONS_PNG       :: #load("assets/item_icons.png")
OBJECTS_PNG          :: #load("assets/objects.png") // corpses and chests
TREES_PNG            :: #load("assets/trees.png") // trees and bushes on forest tiles
PORTAL_PNG           :: #load("assets/portal.png") // a Scroll of Town Portal's rift

// Each sprite sheet has six columns (directions, in hexgrid.Direction order as seen
// on screen: right, back-right, back-left, left, front-left, front-right)
// and five rows (poses: idle, walk A, walk B, attack wind-up, strike).
// Frames are 16 x 24 for the adventurer and goblin, 40 x 48 for the ogre.

// A tiny shader for sprites. Normally even fully see-through pixels hide whatever is
// drawn behind them later (the graphics card still records their depth), which would
// make blood drops vanish in a rectangle around each character. "discard" skips those
// pixels completely. Everything else matches raylib's default shader.
SPRITE_CUTOUT_FRAGMENT_SHADER :: `#version 330
in vec2 fragTexCoord;
in vec4 fragColor;
uniform sampler2D texture0;
uniform vec4 colDiffuse;
out vec4 finalColor;
void main() {
    vec4 texel = texture(texture0, fragTexCoord);
    if (texel.a < 0.5) discard;
    finalColor = texel * colDiffuse * fragColor;
}
`

BACKGROUND_COLOR :: rl.Color{18, 20, 28, 255}

Scene :: struct {
	// The dungeon: every level visited so far, and where the player is.
	game_seed:     u64,
	levels:        [dynamic]^Level, // levels[0] is depth 1
	current_depth: int,
	player:        Actor,           // not part of any level: it travels between them
	inventory:     Inventory,       // the player's belongings
	adventure_id:  u64,             // marks this adventure's save files (see save.odin)
	deepest_depth: int,             // for the score
	killed_by:     Creature_Kind,   // set when the player dies
	portal:        Portal,          // a Scroll of Town Portal's open link, if any (see portal.odin)
	quest_states:  [Quest_Id]Quest_State,
	named_slain:   [Named_Creature]bool,
	dialogue_npc_index: int,        // which villager the dialogue panel shows

	// The ranking list
	ranking:             [dynamic]Ranking_Entry,
	ranking_after_death: bool,          // the ranking is showing the run that just ended
	last_run:            Ranking_Entry,
	last_run_place:      int,           // its place in the list, or -1
	deleted_save_count:  int,           // saves of the fallen adventure that were deleted

	// Turns
	turn_phase:             Turn_Phase,
	monster_turn_index:     int, // which monster of the current level is acting
	stairs_after_this_step: Stairs_Direction,
	level_change:           Level_Change,
	travel_destination:     Maybe(hexgrid.Hex), // walking toward this on its own, one step per turn, until it arrives or a monster wakes
	travel_adjacent_only:   bool,               // stop next to travel_destination (an NPC or chest) instead of walking onto it

	// Things only needed for drawing
	creature_sprites:          [Creature_Kind]rl.Texture2D,
	item_icons:                rl.Texture2D,
	object_sprites:            rl.Texture2D, // corpses and chests
	tree_sprites:              rl.Texture2D, // trees and bushes
	portal_sprite:             rl.Texture2D, // a Scroll of Town Portal's rift
	tile_meshes:               Tile_Meshes,
	tiles_material:            rl.Material,
	sprite_shader:             rl.Shader,
	effects:                   Effects,
	sound:                     Sound_System,
	screen_shake_seconds_left: f32,
	camera_up:                 rl.Vector3, // updated every frame; effects use it to find "above" on screen
	view_center:               hexgrid.Hex, // the hex under the player; you see VIEW_RADIUS steps around it

	// Menus
	screen:      Screen,
	menu:        Menu,
	slot_infos:  [SAVE_SLOT_COUNT]Slot_Info, // what's in each save slot, read when a slot list opens
	should_quit: bool,

	// Mouse, panels and messages
	hovered_hex:            hexgrid.Hex,
	mouse_is_over_map:      bool,
	mouse_in_low_res:       rl.Vector2,  // the mouse in the small image's pixels, for the panels
	open_panel:             Open_Panel,
	open_container_indices: [dynamic]int, // the containers the loot panel shows (a pile can hold several)
	message:           string,
	message_buffer:    [128]u8,
}

main :: proc() {
	rl.SetConfigFlags({.WINDOW_RESIZABLE})
	rl.InitWindow(1280, 720, "Hex dungeon")
	defer rl.CloseWindow()
	rl.SetTargetFPS(60)
	rl.SetExitKey(.KEY_NULL) // Esc opens the menu instead of closing the window
	install_click_catcher()  // so quick trackpad taps count as clicks

	load_content() // villagers, quests and named creatures, from assets/content.json

	scene: Scene
	init_sound_system(&scene.sound)
	defer close_sound_system(&scene.sound)
	defer {
		for level in scene.levels do destroy_level(level)
		delete(scene.levels)
		delete(scene.inventory.backpack)
		delete(scene.open_container_indices)
		delete(scene.ranking)
		delete_effects(&scene.effects)
	}

	scene.creature_sprites = {
		.Adventurer = load_embedded_png_texture(ADVENTURER_SHEET_PNG),
		.Goblin     = load_embedded_png_texture(GOBLIN_SHEET_PNG),
		.Ogre       = load_embedded_png_texture(OGRE_SHEET_PNG),
	}
	defer for sprite_sheet in scene.creature_sprites do rl.UnloadTexture(sprite_sheet)
	scene.item_icons = load_embedded_png_texture(ITEM_ICONS_PNG)
	scene.object_sprites = load_embedded_png_texture(OBJECTS_PNG)
	scene.tree_sprites = load_embedded_png_texture(TREES_PNG)
	scene.portal_sprite = load_embedded_png_texture(PORTAL_PNG)
	defer rl.UnloadTexture(scene.item_icons)
	defer rl.UnloadTexture(scene.object_sprites)
	defer rl.UnloadTexture(scene.tree_sprites)
	defer rl.UnloadTexture(scene.portal_sprite)

	scene.tile_meshes = build_tile_meshes()
	defer unload_tile_meshes(&scene.tile_meshes)
	scene.tiles_material = rl.LoadMaterialDefault()
	scene.tiles_material.maps[rl.MaterialMapIndex.ALBEDO].texture = load_embedded_png_texture(TILES_PNG)
	defer rl.UnloadMaterial(scene.tiles_material) // also unloads the tiles texture

	scene.sprite_shader = rl.LoadShaderFromMemory(nil, SPRITE_CUTOUT_FRAGMENT_SHADER)
	defer rl.UnloadShader(scene.sprite_shader)

	low_res_target := rl.LoadRenderTexture(LOW_RES_WIDTH, LOW_RES_HEIGHT)
	rl.SetTextureFilter(low_res_target.texture, .POINT)
	defer rl.UnloadRenderTexture(low_res_target)

	// The start menu shows a dungeon behind it, always the same one.
	start_new_game(&scene, 4471)
	scene.screen = .Start_Menu
	scene.menu = .Start
	load_ranking(&scene)

	camera_turns := 0 // how many 60 degree turns the camera has made
	tilt_index := STARTING_TILT_INDEX

	for !rl.WindowShouldClose() && !scene.should_quit {
		frame_seconds := rl.GetFrameTime()
		level := current_level(&scene)
		// The world stands still while a menu is open (including the start menu).
		paused := scene.menu != .None

		// ---- Keys for the panels and menus -------------------------------------------

		if rl.IsKeyPressed(.ESCAPE) do handle_escape_key(&scene)
		if rl.IsKeyPressed(.M) {
			scene.sound.muted = !scene.sound.muted
			set_message(&scene, "Sound off." if scene.sound.muted else "Sound on.")
		}
		if rl.IsKeyPressed(.I) && !paused {
			scene.open_panel = .None if scene.open_panel == .Inventory else .Inventory
		}
		if rl.IsKeyPressed(.L) && !paused {
			scene.open_panel = .None if scene.open_panel == .Quest_Log else .Quest_Log
		}
		if rl.IsKeyPressed(.T) && !paused && scene.turn_phase == .Player_Choosing {
			cycle_stance(&scene)
		}

		// ---- Camera -------------------------------------------------------------

		// A hex grid looks the same every 60 degrees, so turning by exactly 60 always
		// lands on a view where the art lines up the same crisp way.
		if rl.IsKeyPressed(.Q) do camera_turns -= 1
		if rl.IsKeyPressed(.E) do camera_turns += 1
		if rl.IsKeyPressed(.W) do tilt_index = min(tilt_index + 1, len(TILT_ANGLES) - 1)
		if rl.IsKeyPressed(.S) do tilt_index = max(tilt_index - 1, 0)
		camera_yaw_degrees := f32(camera_turns * 60)
		camera_pitch_degrees := TILT_ANGLES[tilt_index]

		// The camera looks straight at the player. (It used to glide a little behind,
		// which made the whole picture keep drifting and settling after every step.)
		player_position := actor_visual_position(&scene.player)
		player_position.y = FLOOR_HEIGHT // ignore the hop while walking
		camera := snap_camera_to_pixels(orbit_camera(camera_yaw_degrees, camera_pitch_degrees, player_position))
		scene.camera_up = camera_up_direction(camera)
		scene.view_center = hexgrid.pixel_to_hex({player_position.x, player_position.z}, HEX_SIZE)

		// Screen shake: nudge the camera by a random pixel or two each frame, fading out.
		// Only the drawing uses the shaken camera; mouse picking keeps the steady one.
		view_camera := camera
		if scene.screen_shake_seconds_left > 0 {
			shake_strength := 2.5 * scene.screen_shake_seconds_left / SCREEN_SHAKE_SECONDS
			shake_offset := rl.Vector3{rand.float32_range(-1, 1), 0, rand.float32_range(-1, 1)} * shake_strength
			view_camera.position += shake_offset
			view_camera.target += shake_offset
		}

		// ---- Where the low-res image goes on the window --------------------------

		window_width := f32(rl.GetScreenWidth())
		window_height := f32(rl.GetScreenHeight())
		// The largest whole-number scale that fits, so every pixel becomes an equal N x N block.
		pixel_scale := max(1, math.floor(min(window_width / LOW_RES_WIDTH, window_height / LOW_RES_HEIGHT)))
		scaled_image := rl.Rectangle {
			width  = LOW_RES_WIDTH * pixel_scale,
			height = LOW_RES_HEIGHT * pixel_scale,
		}
		scaled_image.x = (window_width - scaled_image.width) / 2
		scaled_image.y = (window_height - scaled_image.height) / 2

		// ---- Mouse picking ----------------------------------------------------

		// Convert the window mouse position into a position inside the small image,
		// then ask raylib for the ray from the camera through that point.
		mouse_in_low_res := (rl.GetMousePosition() - rl.Vector2{scaled_image.x, scaled_image.y}) / pixel_scale
		scene.mouse_in_low_res = mouse_in_low_res
		mouse_ray := rl.GetScreenToWorldRayEx(mouse_in_low_res, camera, LOW_RES_WIDTH, LOW_RES_HEIGHT)

		scene.mouse_is_over_map = false
		if mouse_ray.direction.y < 0 {
			// Where does the ray hit the top surface of the floor tiles?
			distance_along_ray := (FLOOR_HEIGHT - mouse_ray.position.y) / mouse_ray.direction.y
			floor_point := mouse_ray.position + mouse_ray.direction * distance_along_ray
			scene.hovered_hex = hexgrid.pixel_to_hex({floor_point.x, floor_point.z}, HEX_SIZE)
			can_see_it := hexgrid.hex_distance(scene.view_center, scene.hovered_hex) <= VIEW_RADIUS
			scene.mouse_is_over_map = is_on_map(level, scene.hovered_hex) && can_see_it
		}
		// While a panel or menu is open, or the mouse is over the interface, the map ignores the mouse.
		if paused || scene.open_panel != .None || mouse_is_over_ui(&scene) do scene.mouse_is_over_map = false

		// ---- Rules and animation ---------------------------------------------------

		if right_click_happened() do handle_ui_right_click(&scene)
		clicked := left_click_happened() // counts quick taps too, unlike rl.IsMouseButtonPressed
		if clicked && handle_menu_click(&scene) do clicked = false // menus get the first look...
		if clicked && handle_ui_click(&scene) do clicked = false   // ...then the panels...
		if clicked && (scene.mouse_is_over_map || scene.turn_phase == .Player_Dead) {
			handle_click(&scene, scene.hovered_hex)                // ...then the map
		}
		if !paused {
			update_actor(&scene, &scene.player, frame_seconds)
			for &monster in current_level(&scene).monsters {
				update_actor(&scene, &monster, frame_seconds)
			}
			update_effects(&scene.effects, current_level(&scene), frame_seconds)
			scene.screen_shake_seconds_left = max(0, scene.screen_shake_seconds_left - frame_seconds)
			advance_turns(&scene)
			update_level_change(&scene, frame_seconds)
		}

		// ---- Drawing ------------------------------------------------------------

		// First draw the scene into the small image...
		rl.BeginTextureMode(low_res_target)
		rl.ClearBackground(BACKGROUND_COLOR)
		draw_scene(&scene, view_camera)
		for &monster in current_level(&scene).monsters {
			if light_on_actor(&scene, &monster) > 0 do draw_hit_point_bar(&monster, view_camera)
		}
		draw_floating_numbers(&scene.effects, view_camera)
		if scene.screen == .Playing {
			draw_container_label(&scene, view_camera)
			draw_ui(&scene)
		}
		draw_menu(&scene)
		rl.EndTextureMode()

		// ...then show that image on the window, scaled up with hard pixel edges.
		rl.BeginDrawing()
		rl.ClearBackground(rl.BLACK)
		// Render textures are stored upside down, hence the negative height.
		whole_low_res_image := rl.Rectangle{0, 0, LOW_RES_WIDTH, -LOW_RES_HEIGHT}
		rl.DrawTexturePro(low_res_target.texture, whole_low_res_image, scaled_image, {0, 0}, 0, rl.WHITE)

		// Fade to black while changing levels.
		darkness := level_change_darkness(&scene)
		if darkness > 0 {
			rl.DrawRectangle(0, 0, i32(window_width), i32(window_height), rl.Fade(rl.BLACK, darkness))
		}

		if scene.screen == .Playing && scene.menu == .None { // menus cover the whole view
			player := &scene.player
			rl.DrawText("Q/E: turn   W/S: tilt   I: items   L: quests   T: stance   M: sound   Esc: menu   Click: walk, attack, loot, stairs", 16, 16, 20, rl.RAYWHITE)
			rl.DrawText(fmt.ctprintf("%s     HP %d / %d     Gold %d     Score %d", depth_name(scene.current_depth), player.hit_points, player.max_hit_points, scene.inventory.gold, current_score(&scene)), 16, 42, 20, rl.RED)
			rl.DrawText(fmt.ctprintf("%s", scene.message), 16, 68, 20, rl.GOLD)
		}
		rl.EndDrawing()
		free_all(context.temp_allocator)
	}
}

// An orthographic camera on a sphere around `focus`, looking at it.
// Orthographic means no perspective: far tiles are drawn as big as near ones,
// so every tile shows its art at exactly one art pixel per screen pixel.
orbit_camera :: proc(yaw_degrees, pitch_degrees: f32, focus: rl.Vector3) -> rl.Camera3D {
	yaw_radians := math.to_radians(yaw_degrees)
	pitch_radians := math.to_radians(pitch_degrees)
	offset_from_focus := rl.Vector3 {
		CAMERA_DISTANCE * math.cos(pitch_radians) * math.sin(yaw_radians),
		CAMERA_DISTANCE * math.sin(pitch_radians),
		CAMERA_DISTANCE * math.cos(pitch_radians) * math.cos(yaw_radians),
	}
	return rl.Camera3D {
		position   = focus + offset_from_focus,
		target     = focus,
		up         = {0, 1, 0},
		// For an orthographic camera, fovy is the height of the view in world units.
		// 240 units on a 240-pixel-tall image means one art pixel = one screen pixel.
		fovy       = LOW_RES_HEIGHT,
		projection = .ORTHOGRAPHIC,
	}
}

// Moving the camera by a fraction of a pixel makes every texture land slightly
// differently on the screen's pixels, so pixel art shimmers while the view moves.
// Rounding the camera's position to whole screen pixels keeps the picture stable:
// the world moves in clean one-pixel steps instead.
snap_camera_to_pixels :: proc(camera: rl.Camera3D) -> rl.Camera3D {
	view_direction := rl.Vector3Normalize(camera.target - camera.position)
	screen_right := rl.Vector3Normalize(rl.Vector3CrossProduct(view_direction, camera.up))
	screen_up := rl.Vector3CrossProduct(screen_right, view_direction)

	// In this orthographic view, one world unit along screen_right or screen_up is exactly one pixel.
	pixels_across := rl.Vector3DotProduct(camera.target, screen_right)
	pixels_up := rl.Vector3DotProduct(camera.target, screen_up)
	correction := screen_right * (math.round(pixels_across) - pixels_across) + screen_up * (math.round(pixels_up) - pixels_up)

	snapped := camera
	snapped.position += correction
	snapped.target += correction
	return snapped
}

// How brightly a hex is lit by its distance from you: full light nearby, fading over
// the last two rings like torchlight, and nothing at all beyond VIEW_RADIUS.
light_at_distance :: proc(distance: i32) -> f32 {
	switch {
	case distance <= VIEW_RADIUS - 2: return 1.0
	case distance == VIEW_RADIUS - 1: return 0.8
	case distance == VIEW_RADIUS:     return 0.55
	}
	return 0
}

light_at_hex :: proc(scene: ^Scene, hex: hexgrid.Hex) -> f32 {
	return light_at_distance(hexgrid.hex_distance(scene.view_center, hex))
}

// A creature is as brightly lit as its nearest hex (the ogre covers three).
light_on_actor :: proc(scene: ^Scene, actor: ^Actor) -> f32 {
	brightest: f32 = 0
	for offset in actor_footprint(actor) {
		brightest = max(brightest, light_at_hex(scene, hexgrid.hex_add(actor.hex, offset)))
	}
	return brightest
}

// A color darkened by the given light (1 = unchanged, 0 = black).
shade :: proc(color: rl.Color, light: f32) -> rl.Color {
	return {u8(f32(color.r) * light), u8(f32(color.g) * light), u8(f32(color.b) * light), color.a}
}

// Turns PNG file bytes that were built into the program into a GPU texture.
load_embedded_png_texture :: proc(png_bytes: []u8) -> rl.Texture2D {
	image := rl.LoadImageFromMemory(".png", raw_data(png_bytes), i32(len(png_bytes)))
	defer rl.UnloadImage(image)
	texture := rl.LoadTextureFromImage(image)
	// POINT filtering keeps every art pixel a hard-edged square instead of blurring it.
	rl.SetTextureFilter(texture, .POINT)
	return texture
}

draw_scene :: proc(scene: ^Scene, camera: rl.Camera3D) {
	level := current_level(scene)
	rl.BeginMode3D(camera)

	// Only the hexes around you are drawn, dimmer toward the edge. Every tile knows
	// its kind and variant, which decides the mesh (and so the art).
	tile_color := &scene.tiles_material.maps[rl.MaterialMapIndex.ALBEDO].color
	for tile, index in level.tiles {
		hex := hexgrid.grid_hex_at(level.size, index)
		light := light_at_hex(scene, hex)
		if light == 0 do continue
		tile_color^ = shade(rl.WHITE, light)
		map_position := hexgrid.hex_to_pixel(hex, HEX_SIZE)
		placement := rl.MatrixTranslate(map_position.x, 0, map_position.y)
		rl.DrawMesh(mesh_for_tile(&scene.tile_meshes, tile), scene.tiles_material, placement)
	}
	tile_color^ = rl.WHITE

	for stain in level.blood_stains {
		light := light_at_hex(scene, hexgrid.pixel_to_hex({stain.position.x, stain.position.z}, HEX_SIZE))
		if light > 0 do draw_blood_stain(stain, light)
	}

	if scene.mouse_is_over_map && scene.turn_phase == .Player_Choosing {
		hovered_creature := actor_at(scene, scene.hovered_hex)
		if hovered_creature != nil && hovered_creature != &scene.player {
			// Outline every hex the monster covers, so its size is clear.
			for offset in actor_footprint(hovered_creature) {
				draw_hex_outline(hexgrid.hex_add(hovered_creature.hex, offset), FLOOR_HEIGHT + 0.2, rl.RED)
			}
		} else if npc_index_at(level, scene.hovered_hex) >= 0 {
			draw_hex_outline(scene.hovered_hex, FLOOR_HEIGHT + 0.2, rl.GREEN)
		} else if pile := container_indices_at(level, scene.hovered_hex); len(pile) > 0 {
			// Outline everything lying there (an ogre's body covers three hexes).
			for index in pile {
				container := &level.containers[index]
				for offset in container.footprint {
					draw_hex_outline(hexgrid.hex_add(container.anchor_hex, offset), FLOOR_HEIGHT + 0.2, GOLD_TEXT_COLOR)
				}
			}
		} else if stairs_at(level, scene.hovered_hex) != .None {
			draw_hex_outline(scene.hovered_hex, FLOOR_HEIGHT + 0.2, rl.SKYBLUE)
		} else if portal_hex, on_portal := portal_hex_here(scene); on_portal && scene.hovered_hex == portal_hex {
			draw_hex_outline(scene.hovered_hex, FLOOR_HEIGHT + 0.2, rl.PURPLE)
		} else {
			draw_hex_outline(scene.hovered_hex, tile_top_height(level, scene.hovered_hex) + 0.2, rl.YELLOW)
		}
	}

	// Draw sprites from farthest to nearest. The cutout shader already stops empty
	// pixels from hiding things, but a creature fading out after death is partly
	// see-through, and those pixels only blend correctly over what's already drawn.
	Draw_Order_Entry :: struct {
		drawable:           union {^Actor, ^Container, ^Npc, ^Prop, ^Portal}, // a creature, a corpse or chest, a villager, a tree, or a portal
		light:              f32,
		distance_to_camera: f32,
	}
	draw_order := make([dynamic]Draw_Order_Entry, context.temp_allocator)
	append(&draw_order, Draw_Order_Entry{drawable = &scene.player, light = 1, distance_to_camera = rl.Vector3Distance(camera.position, actor_visual_position(&scene.player))})
	for &monster in level.monsters {
		if monster.is_dead && monster.death_seconds >= DEATH_SECONDS do continue
		light := light_on_actor(scene, &monster)
		if light == 0 do continue // out of sight
		append(&draw_order, Draw_Order_Entry{drawable = &monster, light = light, distance_to_camera = rl.Vector3Distance(camera.position, actor_visual_position(&monster))})
	}
	for &container in level.containers {
		light: f32 = 0
		for offset in container.footprint {
			light = max(light, light_at_hex(scene, hexgrid.hex_add(container.anchor_hex, offset)))
		}
		if light == 0 do continue
		append(&draw_order, Draw_Order_Entry{drawable = &container, light = light, distance_to_camera = rl.Vector3Distance(camera.position, container_center(&container))})
	}
	for &prop in level.props {
		light := light_at_hex(scene, prop.hex)
		if light == 0 do continue
		append(&draw_order, Draw_Order_Entry{drawable = &prop, light = light, distance_to_camera = rl.Vector3Distance(camera.position, prop_position(&prop))})
	}
	for &npc in level.npcs {
		light := light_at_hex(scene, npc.hex)
		if light == 0 do continue
		append(&draw_order, Draw_Order_Entry{drawable = &npc, light = light, distance_to_camera = rl.Vector3Distance(camera.position, hex_floor_position(npc.hex))})
	}
	if portal_hex, on_portal := portal_hex_here(scene); on_portal {
		light := light_at_hex(scene, portal_hex)
		if light > 0 {
			append(&draw_order, Draw_Order_Entry{drawable = &scene.portal, light = light, distance_to_camera = rl.Vector3Distance(camera.position, hex_floor_position(portal_hex))})
		}
	}
	slice.sort_by(draw_order[:], proc(first, second: Draw_Order_Entry) -> bool {
		return first.distance_to_camera > second.distance_to_camera
	})
	rl.BeginShaderMode(scene.sprite_shader)
	for entry in draw_order {
		switch drawable in entry.drawable {
		case ^Actor:     draw_actor(scene, drawable, camera, entry.light)
		case ^Container: draw_container(scene, drawable, camera, entry.light)
		case ^Npc:       draw_npc(scene, drawable, camera, entry.light)
		case ^Prop:      draw_prop(scene, drawable, camera, entry.light)
		case ^Portal:    draw_portal(scene, camera, entry.light)
		}
	}
	rl.EndShaderMode()

	draw_blood_drops(&scene.effects)
	rl.EndMode3D()
}

// A corpse or chest: an upright picture, like the creatures.
draw_container :: proc(scene: ^Scene, container: ^Container, camera: rl.Camera3D, light: f32) {
	source := CONTAINER_SPRITE_REGIONS[container.kind]
	texture := scene.object_sprites
	if container.kind == .Chest && container.has_been_opened do source = OPEN_CHEST_SPRITE_REGION
	if container.kind == .Dropped_Items {
		// A pile of dropped things is drawn as the icon of whatever lies on top.
		if len(container.items) == 0 do return
		texture = scene.item_icons
		source.x = f32(container.items[len(container.items) - 1].kind) * 16
	}
	size := rl.Vector2{source.width, source.height * upright_stretch(camera)}

	// Nudged a tiny bit away from the camera, along the line of sight. That doesn't move
	// it on screen, but it makes a creature standing on the same hex draw in front of
	// the body instead of flickering with it.
	view_direction := rl.Vector3Normalize(camera.target - camera.position)
	position := container_center(container) + view_direction * 1.5
	rl.DrawBillboardPro(camera, texture, source, position, {0, 1, 0}, size, {size.x / 2, 0}, 0, shade(rl.WHITE, light))
}

// A tree or bush: an upright picture, taller and wider than its hex, so its crown
// spills over the edges and the grid stops looking like a honeycomb.
PROP_FRAME :: rl.Vector2{32, 44}
PROP_VARIANT_COUNT :: 4 // three trees and a bush, in assets/trees.png

Prop :: struct {
	hex:     hexgrid.Hex,
	variant: u8,
	offset:  rl.Vector2, // nudged off the hex center, in world units
	scale:   f32,
}

prop_position :: proc(prop: ^Prop) -> rl.Vector3 {
	position := hex_floor_position(prop.hex)
	return position + {prop.offset.x, 0, prop.offset.y}
}

draw_prop :: proc(scene: ^Scene, prop: ^Prop, camera: rl.Camera3D, light: f32) {
	source := rl.Rectangle{f32(prop.variant) * PROP_FRAME.x, 0, PROP_FRAME.x, PROP_FRAME.y}
	size := rl.Vector2{PROP_FRAME.x * prop.scale, PROP_FRAME.y * prop.scale * upright_stretch(camera)}
	rl.DrawBillboardPro(camera, scene.tree_sprites, source, prop_position(prop), {0, 1, 0}, size, {size.x / 2, 0}, 0, shade(rl.WHITE, light))
}

// A Scroll of Town Portal's rift: a standing rift of shimmering color, like the trees
// and corpses drawn as an upright picture on its hex.
PORTAL_FRAME :: rl.Vector2{20, 32}

draw_portal :: proc(scene: ^Scene, camera: rl.Camera3D, light: f32) {
	portal_hex, on_portal := portal_hex_here(scene)
	if !on_portal do return
	source := rl.Rectangle{0, 0, PORTAL_FRAME.x, PORTAL_FRAME.y}
	size := rl.Vector2{PORTAL_FRAME.x, PORTAL_FRAME.y * upright_stretch(camera)}
	rl.DrawBillboardPro(camera, scene.portal_sprite, source, hex_floor_position(portal_hex), {0, 1, 0}, size, {size.x / 2, 0}, 0, shade(rl.WHITE, light))
}

// A tiny health bar above a wounded actor's head, drawn in the small image's pixels.
draw_hit_point_bar :: proc(actor: ^Actor, camera: rl.Camera3D) {
	if actor.is_dead || actor.hit_points == actor.max_hit_points do return
	definition := CREATURES[actor.kind]
	bar_width := i32(definition.frame_size.x * 0.75)
	above_head := actor_visual_position(actor) + camera_up_direction(camera) * (definition.frame_size.y + 3)
	screen_position := rl.GetWorldToScreenEx(above_head, camera, LOW_RES_WIDTH, LOW_RES_HEIGHT)
	bar_left := i32(screen_position.x) - bar_width / 2
	bar_top := i32(screen_position.y)
	filled_width := bar_width * i32(actor.hit_points) / i32(actor.max_hit_points)
	rl.DrawRectangle(bar_left - 1, bar_top - 1, bar_width + 2, 4, rl.BLACK)
	rl.DrawRectangle(bar_left, bar_top, bar_width, 2, rl.MAROON)
	rl.DrawRectangle(bar_left, bar_top, filled_width, 2, rl.RED)
}

draw_hex_outline :: proc(hex: hexgrid.Hex, height: f32, color: rl.Color) {
	center := hexgrid.hex_to_pixel(hex, HEX_SIZE)
	for corner_index in 0 ..< 6 {
		this_corner := center + hex_corner_offset(HEX_SIZE, corner_index)
		next_corner := center + hex_corner_offset(HEX_SIZE, (corner_index + 1) % 6)
		rl.DrawLine3D({this_corner.x, height, this_corner.y}, {next_corner.x, height, next_corner.y}, color)
	}
}
