package main

// Characters: what they are (rules data) and how they move on screen (animation data).
// The rules change instantly: when you step, your hex changes at once.
// The animation then catches up over a fraction of a second, so it looks smooth.

import "core:math"
import rl "vendor:raylib"
import "hexgrid"

HURT_SECONDS  :: 0.3
DEATH_SECONDS :: 0.8

// An attack, measured as a fraction of the actor's attack_seconds:
//   0.00 - 0.45  wind-up: weapon raised, leaning back
//   0.45 - 0.60  strike: lunging forward, the hit lands at 0.60
//   0.60 - 0.85  follow-through: weapon still down (the Strike pose)
//   0.85 - 1.00  back to standing
ATTACK_WIND_UP_END        :: 0.45
ATTACK_IMPACT             :: 0.6
ATTACK_FOLLOW_THROUGH_END :: 0.85
ATTACK_LUNGE_DISTANCE     :: 8.0 // world units = art pixels

// Rows of the sprite sheet. Columns are the six directions.
Pose :: enum {
	Idle           = 0,
	Walk_A         = 1,
	Walk_B         = 2,
	Attack_Wind_Up = 3,
	Strike         = 4,
}

// Two steps per hex: left foot, stand, right foot, stand.
WALK_CYCLE := [4]Pose{.Walk_A, .Idle, .Walk_B, .Idle}

// Which hexes a creature covers, relative to its anchor hex (the `hex` field).
SINGLE_HEX_FOOTPRINT := [1]hexgrid.Hex{{q = 0, r = 0}}
// Three hexes in a triangle: the anchor, its east neighbor and its south-east neighbor.
TRIANGLE_FOOTPRINT := [3]hexgrid.Hex{{q = 0, r = 0}, {q = 1, r = 0}, {q = 0, r = 1}}

Action :: enum {
	None,
	Walking,
	Attacking,
}

Dice :: struct {
	count: int,
	sides: int,
	bonus: int,
}

Actor :: struct {
	// What kind of creature this is (see creatures.odin)
	kind:                  Creature_Kind,
	named:                 Named_Creature, // .None for ordinary creatures (see village.odin)
	name:                  string,
	tint:                  rl.Color,       // multiplied with the sprite's colors; white = unchanged
	attack_verb:           string,        // "The ogre smashes you for 6."
	sprite_sheet:          rl.Texture2D,
	frame_size:            rl.Vector2,    // one frame of the sprite sheet, in pixels
	footprint:             []hexgrid.Hex, // hexes covered, relative to `hex`
	shadow_radius:         f32,
	blood_color:           rl.Color,
	damage_dice:           Dice,
	armor:                 int,           // every hit on this creature does this much less (at least 1)
	max_hit_points:        int,
	walk_seconds:          f32,
	attack_seconds:        f32,
	knockback_distance:    f32,           // how far a hit pushes it; heavy creatures barely move
	turns_between_actions: int,           // 1 = acts every turn, 2 = every other turn
	shakes_screen_on_hit:  bool,
	weapon_sound:          Weapon_Sound,  // the swoosh and impact of its attacks
	hurt_sound:            Sound_Id,
	death_sound:           Sound_Id,

	// Rules state
	hex:                hexgrid.Hex,      // the anchor hex; the footprint is placed relative to it
	facing:             hexgrid.Direction,
	hit_points:         int,
	is_dead:            bool,
	is_awake:           bool, // monsters sleep until you come close
	turns_waited:       int,

	// Animation state
	action:              Action,
	action_seconds:      f32,         // time since the current action started
	walk_start_hex:      hexgrid.Hex, // where the current walk began
	attack_target:       ^Actor,
	swing_has_sounded:   bool,
	attack_has_landed:   bool,
	hurt_seconds_left:   f32,         // counts down after being hit
	knockback_direction: rl.Vector3,  // which way the last hit pushed us
	death_seconds:       f32,         // time since dying
}

// ---------------------------------------------------------------------------
// Footprints
// ---------------------------------------------------------------------------

// Does the actor cover `hex` when its anchor stands on `anchor`?
footprint_covers :: proc(actor: ^Actor, anchor, hex: hexgrid.Hex) -> bool {
	for offset in actor.footprint {
		if hexgrid.hex_add(anchor, offset) == hex do return true
	}
	return false
}

// The shortest distance between any hex of one creature and any hex of the other.
// 1 means they stand next to each other and can fight.
footprint_distance :: proc(first: ^Actor, first_anchor: hexgrid.Hex, second: ^Actor, second_anchor: hexgrid.Hex) -> i32 {
	shortest := max(i32)
	for first_offset in first.footprint {
		for second_offset in second.footprint {
			distance := hexgrid.hex_distance(hexgrid.hex_add(first_anchor, first_offset), hexgrid.hex_add(second_anchor, second_offset))
			shortest = min(shortest, distance)
		}
	}
	return shortest
}

actors_distance :: proc(first, second: ^Actor) -> i32 {
	return footprint_distance(first, first.hex, second, second.hex)
}

hex_floor_position :: proc(hex: hexgrid.Hex) -> rl.Vector3 {
	map_position := hexgrid.hex_to_pixel(hex, HEX_SIZE)
	return {map_position.x, FLOOR_HEIGHT, map_position.y}
}

// The middle of the whole footprint: for one hex its center, for the ogre's
// triangle the corner where its three hexes meet. Sprites stand here.
footprint_center :: proc(actor: ^Actor, anchor: hexgrid.Hex) -> rl.Vector3 {
	sum: rl.Vector3
	for offset in actor.footprint {
		sum += hex_floor_position(hexgrid.hex_add(anchor, offset))
	}
	return sum / f32(len(actor.footprint))
}

// ---------------------------------------------------------------------------
// Starting and updating actions
// ---------------------------------------------------------------------------

start_walk :: proc(actor: ^Actor, destination: hexgrid.Hex) {
	actor.facing = direction_toward_position(footprint_center(actor, actor.hex), footprint_center(actor, destination))
	actor.walk_start_hex = actor.hex
	actor.hex = destination
	actor.action = .Walking
	actor.action_seconds = 0
}

start_attack :: proc(attacker, target: ^Actor) {
	attacker.facing = direction_toward_position(footprint_center(attacker, attacker.hex), footprint_center(target, target.hex))
	attacker.attack_target = target
	attacker.swing_has_sounded = false
	attacker.attack_has_landed = false
	attacker.action = .Attacking
	attacker.action_seconds = 0
}

update_actor :: proc(scene: ^Scene, actor: ^Actor, frame_seconds: f32) {
	actor.hurt_seconds_left = max(0, actor.hurt_seconds_left - frame_seconds)
	if actor.is_dead {
		actor.death_seconds += frame_seconds
	}

	switch actor.action {
	case .None:
	case .Walking:
		actor.action_seconds += frame_seconds
		if actor.action_seconds >= actor.walk_seconds {
			actor.action = .None
		}
	case .Attacking:
		actor.action_seconds += frame_seconds
		progress := actor.action_seconds / actor.attack_seconds
		// The swoosh starts as the wind-up ends and the attacker lunges forward.
		if !actor.swing_has_sounded && progress >= ATTACK_WIND_UP_END {
			actor.swing_has_sounded = true
			play_sound(&scene.sound, SWING_SOUNDS[actor.weapon_sound])
		}
		if !actor.attack_has_landed && progress >= ATTACK_IMPACT {
			actor.attack_has_landed = true
			resolve_attack_impact(scene, actor, actor.attack_target)
		}
		if progress >= 1 {
			actor.action = .None
		}
	}
}

// True while anything about this actor is still moving on screen.
actor_is_animating :: proc(actor: ^Actor) -> bool {
	still_dying := actor.is_dead && actor.death_seconds < DEATH_SECONDS
	return actor.action != .None || actor.hurt_seconds_left > 0 || still_dying
}

// Where the actor's feet are drawn this frame, including walking, lunging and knockback.
actor_visual_position :: proc(actor: ^Actor) -> rl.Vector3 {
	position := footprint_center(actor, actor.hex)

	switch actor.action {
	case .None:
	case .Walking:
		progress := clamp(actor.action_seconds / actor.walk_seconds, 0, 1)
		// Smoothstep: starts gently, speeds up, and stops gently.
		eased_progress := progress * progress * (3 - 2 * progress)
		start := footprint_center(actor, actor.walk_start_hex)
		position = start + (position - start) * eased_progress
		position.y += math.sin(progress * math.PI) * 2 // a small hop per hex
	case .Attacking:
		target_center := footprint_center(actor.attack_target, actor.attack_target.hex)
		toward_target := rl.Vector3Normalize(target_center - position)
		position += toward_target * attack_lunge_offset(actor.action_seconds / actor.attack_seconds)
	}

	if actor.hurt_seconds_left > 0 {
		push_strength := actor.hurt_seconds_left / HURT_SECONDS // 1 right after the hit, fading to 0
		position += actor.knockback_direction * actor.knockback_distance * push_strength
	}
	return position
}

// How far toward the target the attacker has moved at this point of the attack.
attack_lunge_offset :: proc(progress: f32) -> f32 {
	LEAN_BACK :: 2.0
	if progress < ATTACK_WIND_UP_END {
		return -LEAN_BACK * progress / ATTACK_WIND_UP_END
	}
	if progress < ATTACK_IMPACT {
		strike_progress := (progress - ATTACK_WIND_UP_END) / (ATTACK_IMPACT - ATTACK_WIND_UP_END)
		return -LEAN_BACK + (ATTACK_LUNGE_DISTANCE + LEAN_BACK) * strike_progress
	}
	recover_progress := clamp((progress - ATTACK_IMPACT) / (1 - ATTACK_IMPACT), 0, 1)
	return ATTACK_LUNGE_DISTANCE * (1 - recover_progress)
}

actor_pose :: proc(actor: ^Actor) -> Pose {
	switch actor.action {
	case .None:
	case .Walking:
		progress := clamp(actor.action_seconds / actor.walk_seconds, 0, 0.999)
		return WALK_CYCLE[int(progress * len(WALK_CYCLE))]
	case .Attacking:
		progress := actor.action_seconds / actor.attack_seconds
		if progress < ATTACK_WIND_UP_END do return .Attack_Wind_Up
		if progress < ATTACK_FOLLOW_THROUGH_END do return .Strike
	}
	return .Idle
}

// ---------------------------------------------------------------------------
// Drawing
// ---------------------------------------------------------------------------

// The camera's own "up" direction: moving along it moves straight up on screen,
// one world unit per screen pixel. Used to place things "above a head" on screen.
camera_up_direction :: proc(camera: rl.Camera3D) -> rl.Vector3 {
	view_direction := rl.Vector3Normalize(camera.target - camera.position)
	camera_right := rl.Vector3Normalize(rl.Vector3CrossProduct(view_direction, camera.up))
	return rl.Vector3CrossProduct(camera_right, view_direction)
}

draw_actor :: proc(actor: ^Actor, camera: rl.Camera3D, light: f32) {
	feet_position := actor_visual_position(actor)
	opacity: f32 = 1

	if actor.is_dead {
		death_progress := clamp(actor.death_seconds / DEATH_SECONDS, 0, 1)
		if death_progress >= 1 do return
		opacity = 1 - death_progress
		feet_position.y -= 8 * death_progress // sinks into the floor while fading
	}

	// A faint dark disc under the feet, so the sprite looks like it stands on the tile.
	shadow_position := rl.Vector3{feet_position.x, FLOOR_HEIGHT + 0.1, feet_position.z}
	rl.DrawCylinder(shadow_position, actor.shadow_radius, actor.shadow_radius, 0.1, 16, rl.Fade(rl.BLACK, 0.35 * opacity))

	// Sprites stand upright, like cardboard cutouts on the floor. Seen from the tilted
	// camera, an upright cutout looks squashed (at a 60 degree tilt, to half its height),
	// so it's stretched taller by exactly that amount and the pixels come out square.
	// (Leaning sprites back to face the camera also gives square pixels, but then a
	// tall sprite's top reaches backward into any wall standing behind it.)
	stretched_size := rl.Vector2{actor.frame_size.x, actor.frame_size.y * upright_stretch(camera)}
	world_up := rl.Vector3{0, 1, 0}

	column := sprite_frame_for(actor.facing, camera)
	row := int(actor_pose(actor))
	frame_in_sheet := rl.Rectangle {
		f32(column) * actor.frame_size.x,
		f32(row) * actor.frame_size.y,
		actor.frame_size.x,
		actor.frame_size.y,
	}
	bottom_center := rl.Vector2{stretched_size.x / 2, 0} // the feet touch feet_position

	rl.DrawBillboardPro(camera, actor.sprite_sheet, frame_in_sheet, feet_position, world_up, stretched_size, bottom_center, 0, rl.Fade(shade(actor.tint, light), opacity))

	// Hit flash: draw the same sprite again with additive blending, which adds its
	// colors on top of themselves and pushes them toward white. No shader needed.
	if actor.hurt_seconds_left > 0 {
		flash_strength := actor.hurt_seconds_left / HURT_SECONDS
		rl.BeginBlendMode(.ADDITIVE)
		for _ in 0 ..< 2 {
			rl.DrawBillboardPro(camera, actor.sprite_sheet, frame_in_sheet, feet_position, world_up, stretched_size, bottom_center, 0, rl.Fade(rl.WHITE, flash_strength))
		}
		rl.EndBlendMode()
	}
}

// How much taller an upright sprite must be to look its true height on screen.
// The camera's "up" leans back by the tilt angle, and its vertical part (y) is
// exactly the factor by which upright things get squashed.
upright_stretch :: proc(camera: rl.Camera3D) -> f32 {
	return 1 / camera_up_direction(camera).y
}

// Which of the six columns to show. The actor faces a direction in the world,
// but the camera may have turned, so we measure the facing's angle on screen:
// 0 degrees = right, 90 = away from the camera, 180 = left, 270 = toward the camera.
sprite_frame_for :: proc(facing: hexgrid.Direction, camera: rl.Camera3D) -> int {
	one_step := hexgrid.hex_to_pixel(hexgrid.DIRECTION_OFFSETS[facing], 1)
	facing_in_world := rl.Vector3{one_step.x, 0, one_step.y}

	view_direction := camera.target - camera.position
	screen_away := rl.Vector3Normalize({view_direction.x, 0, view_direction.z}) // "up" on screen, along the floor
	screen_right := rl.Vector3CrossProduct(screen_away, {0, 1, 0})

	right_amount := rl.Vector3DotProduct(facing_in_world, screen_right)
	away_amount := rl.Vector3DotProduct(facing_in_world, screen_away)
	screen_angle_degrees := math.to_degrees(math.atan2(away_amount, right_amount))

	// Columns are 60 degrees apart, starting with "right" at 0 degrees.
	column := int(math.round(screen_angle_degrees / 60))
	return ((column % 6) + 6) % 6
}
