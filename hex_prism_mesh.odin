package main

import "core:math"
import rl "vendor:raylib"

// A rectangle inside the texture atlas, measured in art pixels.
Atlas_Region :: struct {
	left:   f32,
	top:    f32,
	width:  f32,
	height: f32,
}

// Where each piece of art lives in assets/tiles.png (see atlas_layout_guide.png).
// This is the contract between the image and the code:
// if you move or resize something in the image, update these numbers.
ATLAS_SIZE_PIXELS :: 128

FLOOR_TOP_REGIONS := [FLOOR_VARIANT_COUNT]Atlas_Region {
	{left = 2,  top = 2, width = 28, height = 32}, // plain
	{left = 34, top = 2, width = 28, height = 32}, // cracked
	{left = 66, top = 2, width = 28, height = 32}, // pebbles
	{left = 98, top = 2, width = 28, height = 32}, // mossy
}
WALL_TOP_REGIONS := [WALL_VARIANT_COUNT]Atlas_Region {
	{left = 2,  top = 38, width = 28, height = 32}, // plain
	{left = 34, top = 38, width = 28, height = 32}, // mossy
	{left = 66, top = 38, width = 28, height = 32}, // cracked
}
// A wall's side uses the same variant number as its top.
WALL_SIDE_REGIONS := [WALL_VARIANT_COUNT]Atlas_Region {
	{left = 34, top = 74, width = 16, height = 24},
	{left = 54, top = 74, width = 16, height = 24},
	{left = 74, top = 74, width = 16, height = 24},
}
STAIRS_DOWN_TOP_REGION :: Atlas_Region{left = 98, top = 38, width = 28, height = 32}
STAIRS_UP_TOP_REGION   :: Atlas_Region{left = 2,  top = 74, width = 28, height = 32}
FLOOR_SIDE_REGION      :: Atlas_Region{left = 94, top = 74, width = 16, height = 4}

// Turns "this far across and down inside a region" (0.0 to 1.0)
// into texture coordinates for the whole atlas (also 0.0 to 1.0).
atlas_texture_coordinate :: proc(region: Atlas_Region, fraction_across, fraction_down: f32) -> rl.Vector2 {
	return {
		(region.left + fraction_across * region.width) / ATLAS_SIZE_PIXELS,
		(region.top + fraction_down * region.height) / ATLAS_SIZE_PIXELS,
	}
}

// Corner of a pointy-top hex, relative to its center, on the flat map.
// Corner 0 is at -30 degrees (upper right), then clockwise on screen.
hex_corner_offset :: proc(hex_size: f32, corner_index: int) -> rl.Vector2 {
	angle := math.to_radians(f32(60 * corner_index - 30))
	return {hex_size * math.cos(angle), hex_size * math.sin(angle)}
}

Mesh_Builder :: struct {
	positions:           []f32, // 3 numbers per vertex: x, y, z
	texture_coordinates: []f32, // 2 numbers per vertex: u, v
	colors:              []u8,  // 4 numbers per vertex: r, g, b, a
	vertex_count:        int,
}

add_vertex :: proc(builder: ^Mesh_Builder, position: rl.Vector3, texture_coordinate: rl.Vector2, brightness: u8) {
	vertex_index := builder.vertex_count
	builder.positions[vertex_index * 3 + 0] = position.x
	builder.positions[vertex_index * 3 + 1] = position.y
	builder.positions[vertex_index * 3 + 2] = position.z
	builder.texture_coordinates[vertex_index * 2 + 0] = texture_coordinate.x
	builder.texture_coordinates[vertex_index * 2 + 1] = texture_coordinate.y
	builder.colors[vertex_index * 4 + 0] = brightness
	builder.colors[vertex_index * 4 + 1] = brightness
	builder.colors[vertex_index * 4 + 2] = brightness
	builder.colors[vertex_index * 4 + 3] = 255
	builder.vertex_count += 1
}

// A six-sided column: the top shows `top_region` of the atlas, each of the
// six walls shows `side_region`. The base sits at y = 0, the top at y = prism_height.
// The flat map's (x, y) becomes the world's (x, z).
build_hex_prism_mesh :: proc(hex_size, prism_height: f32, top_region, side_region: Atlas_Region) -> rl.Mesh {
	TRIANGLE_COUNT :: 6 + 6 * 2 // top face: 6 slices; sides: 2 triangles each
	VERTEX_COUNT   :: TRIANGLE_COUNT * 3

	// raylib frees mesh data with its own allocator in UnloadMesh, so allocate with it too.
	builder := Mesh_Builder {
		positions           = make([]f32, VERTEX_COUNT * 3, rl.MemAllocator()),
		texture_coordinates = make([]f32, VERTEX_COUNT * 2, rl.MemAllocator()),
		colors              = make([]u8, VERTEX_COUNT * 4, rl.MemAllocator()),
	}

	hex_width  := math.SQRT_THREE * hex_size
	hex_height := 2 * hex_size

	// Top face: six triangles from the center out to each pair of corners.
	// The texture covers the hex's bounding box, so the art is drawn as a
	// 28 x 32 picture with the hex shape inside it.
	top_center := rl.Vector3{0, prism_height, 0}
	top_center_texture := atlas_texture_coordinate(top_region, 0.5, 0.5)
	for corner_index in 0 ..< 6 {
		this_corner := hex_corner_offset(hex_size, corner_index)
		next_corner := hex_corner_offset(hex_size, (corner_index + 1) % 6)

		this_texture := atlas_texture_coordinate(top_region, this_corner.x / hex_width + 0.5, this_corner.y / hex_height + 0.5)
		next_texture := atlas_texture_coordinate(top_region, next_corner.x / hex_width + 0.5, next_corner.y / hex_height + 0.5)

		// Vertex order decides which side is the "front"; this order faces up.
		add_vertex(&builder, top_center, top_center_texture, 255)
		add_vertex(&builder, {next_corner.x, prism_height, next_corner.y}, next_texture, 255)
		add_vertex(&builder, {this_corner.x, prism_height, this_corner.y}, this_texture, 255)
	}

	// Sides: one rectangle per edge, made of two triangles.
	// Pixel art has no real lighting, so each side gets a fixed brightness
	// as if lit by a sun in the north-west. That keeps walls readable in 3D.
	sun_direction := rl.Vector2Normalize({-1, -1})
	for corner_index in 0 ..< 6 {
		this_corner := hex_corner_offset(hex_size, corner_index)
		next_corner := hex_corner_offset(hex_size, (corner_index + 1) % 6)

		outward_angle := math.to_radians(f32(60 * corner_index))
		outward_direction := rl.Vector2{math.cos(outward_angle), math.sin(outward_angle)}
		facing_the_sun := (rl.Vector2DotProduct(outward_direction, sun_direction) + 1) / 2 // 0.0 to 1.0
		brightness := u8(140 + 100 * facing_the_sun)

		this_bottom := rl.Vector3{this_corner.x, 0, this_corner.y}
		next_bottom := rl.Vector3{next_corner.x, 0, next_corner.y}
		this_top    := rl.Vector3{this_corner.x, prism_height, this_corner.y}
		next_top    := rl.Vector3{next_corner.x, prism_height, next_corner.y}

		// Seen from outside, the next corner is on the left, this corner on the right.
		this_bottom_texture := atlas_texture_coordinate(side_region, 1, 1)
		next_bottom_texture := atlas_texture_coordinate(side_region, 0, 1)
		this_top_texture    := atlas_texture_coordinate(side_region, 1, 0)
		next_top_texture    := atlas_texture_coordinate(side_region, 0, 0)

		add_vertex(&builder, this_bottom, this_bottom_texture, brightness)
		add_vertex(&builder, next_top, next_top_texture, brightness)
		add_vertex(&builder, next_bottom, next_bottom_texture, brightness)

		add_vertex(&builder, this_bottom, this_bottom_texture, brightness)
		add_vertex(&builder, this_top, this_top_texture, brightness)
		add_vertex(&builder, next_top, next_top_texture, brightness)
	}

	mesh := rl.Mesh {
		vertexCount   = VERTEX_COUNT,
		triangleCount = TRIANGLE_COUNT,
		vertices      = raw_data(builder.positions),
		texcoords     = raw_data(builder.texture_coordinates),
		colors        = raw_data(builder.colors),
	}
	rl.UploadMesh(&mesh, false)
	return mesh
}
