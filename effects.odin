package main

// Visual effects that don't affect the rules: blood drops flying through the air,
// stains they leave on the floor, and damage numbers floating up.

import "core:fmt"
import "core:math/rand"
import rl "vendor:raylib"
import "hexgrid"

GRAVITY :: 220.0 // world units per second, per second
MAX_BLOOD_STAINS :: 400
FLOATING_NUMBER_SECONDS :: 0.9

Blood_Drop :: struct {
	position: rl.Vector3,
	velocity: rl.Vector3,
	color:    rl.Color,
	size:     f32,
}

Blood_Stain :: struct {
	position: rl.Vector3,
	color:    rl.Color,
	size:     f32,
}

Floating_Number :: struct {
	position:          rl.Vector3, // the feet of whoever was hit
	height_above_feet: f32,        // where it starts: just above that creature's head
	amount:            int,
	is_heal:           bool, // shown as "+7" instead of "7"
	color:             rl.Color,
	seconds:           f32,  // time since it appeared
}

// Short-lived effects. Blood stains are not here: they belong to the level they
// fell on (see level.odin), so they're still there when you come back.
Effects :: struct {
	blood_drops:      [dynamic]Blood_Drop,
	floating_numbers: [dynamic]Floating_Number,
}

delete_effects :: proc(effects: ^Effects) {
	delete(effects.blood_drops)
	delete(effects.floating_numbers)
}

clear_effects :: proc(effects: ^Effects) {
	clear(&effects.blood_drops)
	clear(&effects.floating_numbers)
}

// Throws drops mostly in `away_direction` (away from the attacker), spread sideways and upward.
spawn_blood_spray :: proc(effects: ^Effects, origin, away_direction: rl.Vector3, color: rl.Color, drop_count: int) {
	sideways_direction := rl.Vector3{-away_direction.z, 0, away_direction.x}
	for _ in 0 ..< drop_count {
		velocity := away_direction * rand.float32_range(15, 75)
		velocity += sideways_direction * rand.float32_range(-35, 35)
		velocity.y += rand.float32_range(20, 80)

		shade := rand.float32_range(0.65, 1.0) // not every drop the exact same red
		drop_color := rl.Color{u8(f32(color.r) * shade), u8(f32(color.g) * shade), u8(f32(color.b) * shade), 255}

		append(&effects.blood_drops, Blood_Drop {
			position = origin,
			velocity = velocity,
			color    = drop_color,
			size     = rand.float32_range(0.8, 1.6),
		})
	}
}

add_floating_number :: proc(effects: ^Effects, position: rl.Vector3, height_above_feet: f32, amount: int, color: rl.Color, is_heal := false) {
	append(&effects.floating_numbers, Floating_Number {
		position          = position,
		height_above_feet = height_above_feet,
		amount            = amount,
		is_heal           = is_heal,
		color             = color,
	})
}

update_effects :: proc(effects: ^Effects, level: ^Level, frame_seconds: f32) {
	// Walk backwards so removing an item doesn't skip the next one.
	for index := len(effects.blood_drops) - 1; index >= 0; index -= 1 {
		drop := &effects.blood_drops[index]
		drop.velocity.y -= GRAVITY * frame_seconds
		drop.position += drop.velocity * frame_seconds

		if drop.position.y <= FLOOR_HEIGHT {
			landed_on := hexgrid.pixel_to_hex({drop.position.x, drop.position.z}, HEX_SIZE)
			if !is_wall(level, landed_on) {
				add_blood_stain(level, {drop.position.x, FLOOR_HEIGHT, drop.position.z}, drop.color, drop.size * 1.6)
			}
			unordered_remove(&effects.blood_drops, index)
		}
	}

	for index := len(effects.floating_numbers) - 1; index >= 0; index -= 1 {
		effects.floating_numbers[index].seconds += frame_seconds
		if effects.floating_numbers[index].seconds >= FLOATING_NUMBER_SECONDS {
			ordered_remove(&effects.floating_numbers, index)
		}
	}
}

add_blood_stain :: proc(level: ^Level, position: rl.Vector3, color: rl.Color, size: f32) {
	// Dried blood is darker than fresh drops.
	dark_color := rl.Color{u8(f32(color.r) * 0.7), u8(f32(color.g) * 0.7), u8(f32(color.b) * 0.7), 255}
	stain := Blood_Stain{position = position, color = dark_color, size = size}

	if len(level.blood_stains) < MAX_BLOOD_STAINS {
		append(&level.blood_stains, stain)
	} else {
		level.blood_stains[level.oldest_stain_index] = stain
		level.oldest_stain_index = (level.oldest_stain_index + 1) % MAX_BLOOD_STAINS
	}
}

// Floor stains go first so everything else is drawn over them.
draw_blood_stain :: proc(stain: Blood_Stain, light: f32) {
	// A very flat box, lifted a hair above the floor so it doesn't flicker into it.
	rl.DrawCube(stain.position + {0, 0.05, 0}, stain.size, 0.1, stain.size, shade(stain.color, light))
}

draw_blood_drops :: proc(effects: ^Effects) {
	for drop in effects.blood_drops {
		rl.DrawCube(drop.position, drop.size, drop.size, drop.size, drop.color)
	}
}

// Drawn on the small image after the 3D scene, so the digits use the same big pixels.
draw_floating_numbers :: proc(effects: ^Effects, camera: rl.Camera3D) {
	FONT_SIZE :: 10 // raylib's built-in font is drawn pixel-exact at size 10
	for number in effects.floating_numbers {
		progress := number.seconds / FLOATING_NUMBER_SECONDS
		// Start just above the head (and the health bar), then drift upward on screen.
		rising_position := number.position + camera_up_direction(camera) * (number.height_above_feet + 10 * progress)
		screen_position := rl.GetWorldToScreenEx(rising_position, camera, LOW_RES_WIDTH, LOW_RES_HEIGHT)

		text := fmt.ctprintf("+%d" if number.is_heal else "%d", number.amount)
		text_left := i32(screen_position.x) - rl.MeasureText(text, FONT_SIZE) / 2
		text_top := i32(screen_position.y)
		opacity := 1 - progress * progress // stays solid, then fades quickly at the end

		rl.DrawText(text, text_left + 1, text_top + 1, FONT_SIZE, rl.Fade(rl.BLACK, opacity))
		rl.DrawText(text, text_left, text_top, FONT_SIZE, rl.Fade(number.color, opacity))
	}
}
