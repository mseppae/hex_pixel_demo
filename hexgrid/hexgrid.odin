package hexgrid

import "core:math"

// ---------------------------------------------------------------------------
// Coordinates
// ---------------------------------------------------------------------------

// A hex position in axial coordinates.
//
// q and r are the standard names used in every hex tutorial (like x and y for
// squares), so they are kept here. Everything else in this file is spelled out.
//
// The third cube coordinate, s, is always -q - r (because q + r + s = 0),
// so it is calculated when needed instead of stored.
Hex :: struct {
	q: i32, // grows toward the east
	r: i32, // grows toward the south (both south-east and south-west)
}

// The hidden third coordinate. Grows toward the west and north-west.
hex_s :: proc(hex: Hex) -> i32 {
	return -hex.q - hex.r
}

hex_add :: proc(position, offset: Hex) -> Hex {
	return Hex{q = position.q + offset.q, r = position.r + offset.r}
}

// The offset you need to add to `from` to arrive at `to`.
hex_difference :: proc(from, to: Hex) -> Hex {
	return Hex{q = to.q - from.q, r = to.r - from.r}
}

// ---------------------------------------------------------------------------
// Directions and neighbors
// ---------------------------------------------------------------------------

// Listed counter-clockwise as seen on screen, starting from east.
Direction :: enum u8 {
	East,
	North_East,
	North_West,
	West,
	South_West,
	South_East,
}

// One step in each direction. Each step raises one of q, r, s by 1
// and lowers another by 1, so q + r + s stays 0.
DIRECTION_OFFSETS := [Direction]Hex {
	.East       = {q = 1,  r = 0},
	.North_East = {q = 1,  r = -1},
	.North_West = {q = 0,  r = -1},
	.West       = {q = -1, r = 0},
	.South_West = {q = -1, r = 1},
	.South_East = {q = 0,  r = 1},
}

hex_neighbor :: proc(hex: Hex, direction: Direction) -> Hex {
	return hex_add(hex, DIRECTION_OFFSETS[direction])
}

// The list is counter-clockwise, so turning left is "next in the list".
turn_left :: proc(direction: Direction) -> Direction {
	return Direction((int(direction) + 1) % len(Direction))
}

// Adding 5 is the same as subtracting 1, but never goes negative.
turn_right :: proc(direction: Direction) -> Direction {
	return Direction((int(direction) + 5) % len(Direction))
}

// ---------------------------------------------------------------------------
// Distance
// ---------------------------------------------------------------------------

// Number of steps between two hexes.
// Each step changes the total |delta_q| + |delta_r| + |delta_s| by 2,
// so the number of steps is that total divided by 2.
hex_distance :: proc(from, to: Hex) -> i32 {
	delta := hex_difference(from, to)

	delta_q := abs(delta.q)
	delta_r := abs(delta.r)
	delta_s := abs(hex_s(delta))

	return (delta_q + delta_r + delta_s) / 2
}

// ---------------------------------------------------------------------------
// Converting between hexes and pixels (pointy-top layout)
// ---------------------------------------------------------------------------

// hex_size is the distance from a hex's center to one of its corners.
// Pixel positions are relative to the center of hex (0, 0).
// [2]f32 is the same type as raylib's Vector2.
hex_to_pixel :: proc(hex: Hex, hex_size: f32) -> [2]f32 {
	// One q step moves one hex width right:         (sqrt(3) * size, 0)
	// One r step moves to the south-east neighbor:   (sqrt(3)/2 * size, 1.5 * size)
	pixel_x := hex_size * math.SQRT_THREE * (f32(hex.q) + f32(hex.r) / 2)
	pixel_y := hex_size * 1.5 * f32(hex.r)
	return {pixel_x, pixel_y}
}

// A position between hex centers, before rounding to a real hex.
Fractional_Hex :: struct {
	q: f32,
	r: f32,
}

// The reverse of hex_to_pixel: solve its two equations for q and r,
// then round to the nearest real hex.
pixel_to_hex :: proc(pixel: [2]f32, hex_size: f32) -> Hex {
	fractional := Fractional_Hex {
		q = (math.SQRT_THREE / 3 * pixel.x - pixel.y / 3) / hex_size,
		r = (2.0 / 3 * pixel.y) / hex_size,
	}
	return hex_round(fractional)
}

// Rounds a fractional position to the hex that contains it.
// Rounding q and r separately picks the wrong hex near the edges,
// so all three coordinates are rounded and the least trustworthy one is rebuilt.
hex_round :: proc(fractional: Fractional_Hex) -> Hex {
	fractional_s := -fractional.q - fractional.r

	rounded_q := math.round(fractional.q)
	rounded_r := math.round(fractional.r)
	rounded_s := math.round(fractional_s)

	// How far did rounding move each coordinate?
	rounding_error_q := abs(rounded_q - fractional.q)
	rounding_error_r := abs(rounded_r - fractional.r)
	rounding_error_s := abs(rounded_s - fractional_s)

	// Whichever moved the most gets recomputed from the other two,
	// so that q + r + s = 0 holds again.
	if rounding_error_q > rounding_error_r && rounding_error_q > rounding_error_s {
		rounded_q = -rounded_r - rounded_s
	} else if rounding_error_r > rounding_error_s {
		rounded_r = -rounded_q - rounded_s
	}
	// If s moved the most, nothing to fix: Hex only stores q and r.

	return Hex{q = i32(rounded_q), r = i32(rounded_r)}
}

// ---------------------------------------------------------------------------
// Straight lines (line of sight, projectiles)
// ---------------------------------------------------------------------------

// Every hex on the straight line from `from` to `to`, including both ends.
// The caller owns the returned array and must delete() it.
hex_line :: proc(from, to: Hex, allocator := context.allocator) -> [dynamic]Hex {
	step_count := hex_distance(from, to)
	line := make([dynamic]Hex, 0, step_count + 1, allocator)

	for step in 0 ..= step_count {
		// How far along the line this point is, from 0.0 to 1.0.
		progress: f32 = 0 if step_count == 0 else f32(step) / f32(step_count)

		point_on_line := Fractional_Hex {
			q = f32(from.q) + f32(to.q - from.q) * progress,
			r = f32(from.r) + f32(to.r - from.r) * progress,
		}

		// A tiny nudge so a point never lands exactly on the edge between
		// two hexes, where rounding could go either way.
		point_on_line.q += 1e-6
		point_on_line.r += 2e-6

		append(&line, hex_round(point_on_line))
	}
	return line
}

// ---------------------------------------------------------------------------
// Storage: a rectangular map in a flat array
// ---------------------------------------------------------------------------

// The size of a rectangular map, stored row by row in a flat array.
// What each cell holds is up to the game; this module only does the index math.
Grid_Size :: struct {
	width:  i32,
	height: i32,
}

grid_cell_count :: proc(size: Grid_Size) -> int {
	return int(size.width * size.height)
}

// Where a hex lives in the flat array, or inside = false if it is off the map.
grid_index :: proc(size: Grid_Size, hex: Hex) -> (index: int, inside: bool) {
	row := hex.r
	if row < 0 || row >= size.height {
		return 0, false
	}

	// Undo the slant: going down the left edge, q drops by one every two rows.
	// row is never negative here, so integer division rounds down as needed.
	column := hex.q + row / 2
	if column < 0 || column >= size.width {
		return 0, false
	}

	return int(row * size.width + column), true
}

// The reverse of grid_index: which hex lives at this position of the flat array.
grid_hex_at :: proc(size: Grid_Size, index: int) -> Hex {
	row := i32(index) / size.width
	column := i32(index) % size.width
	return Hex{q = column - row / 2, r = row}
}
