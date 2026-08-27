package game

import "core:math"
import "core:slice"

Thread_Context :: struct {}

// ==================================
// =========== MAIN LOOP ============
// ==================================
Game_State :: struct {
	player_position: [2]f32,
	active_tilemap:  [2]int,
}

Memory :: struct {
	// required to be cleared to 0
	permament:      []byte,
	transient:      []byte,
	is_initialized: bool,
}

Tile_Map :: struct {
	data:       []u32,
	count:      [2]u32,
	tile_dims:  [2]f32,
	upper_left: [2]f32,
}

World :: struct {
	maps: []Tile_Map,
	size: [2]int,
}

@(export)
update_and_render :: proc(
	thread: ^Thread_Context,
	memory: ^Memory,
	input: ^Input,
	video_buffer: ^Offscreen_Buffer,
) {
	assert(size_of(Game_State) <= len(memory.permament))

	// TODO: figure this one out, why to_type gives a nil pointer
	// state := slice.to_type(memory.permament, ^State)
	game_state := cast(^Game_State)&memory.permament[0]
	_ = game_state

	TILE_MAP_COUNT_X :: 17
	TILE_MAP_COUNT_Y :: 9
	tile_height := f32(video_buffer.height) / f32(TILE_MAP_COUNT_Y)
	tile_width: f32 = tile_height

	upper_left_x: f32 = -tile_width / 2
	upper_left_y: f32 = 0

	Tile_Data :: [TILE_MAP_COUNT_Y][TILE_MAP_COUNT_X]u32

	tile_data_00: Tile_Data = {
		{1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1},
		{1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1},
		{1, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 1},
		{1, 0, 1, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1},
		{1, 0, 1, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0},
		{1, 0, 1, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1},
		{1, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 0, 0, 1},
		{1, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1},
		{1, 1, 1, 1, 1, 1, 1, 1, 0, 1, 1, 1, 1, 1, 1, 1, 1},
	}

	tile_data_01: Tile_Data = {
		{1, 1, 1, 1, 1, 1, 1, 1, 0, 1, 1, 1, 1, 1, 1, 1, 1},
		{1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1},
		{1, 0, 0, 0, 0, 1, 0, 1, 1, 1, 0, 1, 0, 0, 0, 0, 1},
		{1, 0, 0, 0, 0, 1, 0, 1, 0, 1, 0, 1, 0, 0, 0, 0, 1},
		{1, 0, 0, 0, 0, 1, 0, 1, 0, 1, 0, 1, 0, 0, 0, 0, 0},
		{1, 0, 0, 0, 0, 1, 1, 1, 0, 1, 1, 1, 0, 0, 0, 0, 1},
		{1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1},
		{1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1},
		{1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1},
	}

	tile_data_10: Tile_Data = {
		{1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1},
		{1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1},
		{1, 0, 0, 0, 0, 0, 0, 1, 1, 0, 0, 1, 0, 0, 0, 0, 1},
		{1, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 0, 1},
		{0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 0, 1},
		{1, 0, 0, 0, 0, 0, 1, 1, 0, 0, 1, 1, 0, 0, 0, 0, 1},
		{1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1},
		{1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1},
		{1, 1, 1, 1, 1, 1, 1, 1, 0, 1, 1, 1, 1, 1, 1, 1, 1},
	}

	tile_data_11: Tile_Data = {
		{1, 1, 1, 1, 1, 1, 1, 1, 0, 1, 1, 1, 1, 1, 1, 1, 1},
		{1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1},
		{1, 0, 0, 0, 0, 1, 0, 1, 1, 1, 0, 1, 0, 0, 0, 0, 1},
		{1, 0, 0, 0, 0, 1, 0, 1, 0, 1, 0, 1, 0, 0, 0, 0, 1},
		{0, 0, 0, 0, 0, 1, 0, 1, 0, 1, 0, 1, 0, 0, 0, 0, 1},
		{1, 0, 0, 0, 0, 1, 1, 1, 0, 1, 1, 1, 0, 0, 0, 0, 1},
		{1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1},
		{1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1},
		{1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1},
	}

	maps: [2][2]Tile_Map = {
		{
			{
				data = slice.from_ptr(&tile_data_00[0][0], TILE_MAP_COUNT_X * TILE_MAP_COUNT_Y),
				tile_dims = {tile_height, tile_width},
				upper_left = {upper_left_x, upper_left_y},
				count = {TILE_MAP_COUNT_X, TILE_MAP_COUNT_Y},
			},
			{},
		},
		{{}, {}},
	}

	maps[0][1] = maps[0][0]
	maps[0][1].data = slice.from_ptr(&tile_data_01[0][0], TILE_MAP_COUNT_X * TILE_MAP_COUNT_Y)

	maps[1][0] = maps[0][0]
	maps[1][0].data = slice.from_ptr(&tile_data_10[0][0], TILE_MAP_COUNT_X * TILE_MAP_COUNT_Y)

	maps[1][1] = maps[0][0]
	maps[1][1].data = slice.from_ptr(&tile_data_11[0][0], TILE_MAP_COUNT_X * TILE_MAP_COUNT_Y)

	world := World {
		maps = slice.from_ptr(&maps[0][0], 4),
	}


	tile_map := get_tilemap_unchecked(&world, {0, 0})

	player_width: f32 = tile_map.tile_dims.x / 2
	player_height := player_width * 1.3

	get_tile_value_unchecked :: proc(tile_map: ^Tile_Map, pos: [2]int) -> u32 {
		index := pos.y * int(tile_map.count.x) + pos.x
		return tile_map.data[index]
	}

	get_tilemap_unchecked :: proc(world: ^World, pos: [2]int) -> ^Tile_Map {
		index := pos.y * int(world.size.x) + pos.x
		return &world.maps[index]
	}

	is_tilemap_point_empty :: proc(tile_map: ^Tile_Map, pos: [2]f32) -> bool {
		is_point_empty := false

		x := int(math.floor((pos.x - tile_map.upper_left.x) / tile_map.tile_dims.x))
		y := int(math.floor((pos.y - tile_map.upper_left.y) / tile_map.tile_dims.y))

		if x >= 0 && x < TILE_MAP_COUNT_X && y >= 0 && y < TILE_MAP_COUNT_Y {
			tile_map_value := get_tile_value_unchecked(tile_map, {x, y})
			if tile_map_value == 0 {
				is_point_empty = true
			}
		}

		return is_point_empty
	}

	is_world_point_empty :: proc(world: ^World, tilemap_pos: [2]int, pos: [2]f32) -> bool {
		tile_map := get_tilemap_unchecked(world, tilemap_pos)
		is_point_empty := false

		x := int(math.floor((pos.x - tile_map.upper_left.x) / tile_map.tile_dims.x))
		y := int(math.floor((pos.y - tile_map.upper_left.y) / tile_map.tile_dims.y))

		if x >= 0 && x < TILE_MAP_COUNT_X && y >= 0 && y < TILE_MAP_COUNT_Y {
			tile_map_value := get_tile_value_unchecked(tile_map, {x, y})
			if tile_map_value == 0 {
				is_point_empty = true
			}
		}

		return is_point_empty
	}


	if memory.is_initialized == false {
		game_state.player_position.x = 200
		game_state.player_position.y = 150
		memory.is_initialized = true
	}


	for controller in input.controllers {
		if controller.is_connected == false {
			continue
		}

		if controller.is_analog {
		} else {
			move: [2]f32 = {0, 0}

			move.x += controller.move_right.ended_down ? 1 : 0
			move.x -= controller.move_left.ended_down ? 1 : 0
			move.y += controller.move_down.ended_down ? 1 : 0
			move.y -= controller.move_up.ended_down ? 1 : 0

			speed: f32 = 100


			new_player_x := game_state.player_position.x + move.x * speed * input.dt
			new_player_y := game_state.player_position.y + move.y * speed * input.dt


			is_valid_player_position :=
				is_tilemap_point_empty(tile_map, {new_player_x, new_player_y}) &&
				is_tilemap_point_empty(
					tile_map,
					{new_player_x - player_width / 2, new_player_y},
				) &&
				is_tilemap_point_empty(tile_map, {new_player_x + player_width / 2, new_player_y})

			if is_valid_player_position {
				game_state.player_position.x = new_player_x
				game_state.player_position.y = new_player_y
			}

			if new_player_y < 0 {
				game_state.active_tilemap = 0
				game_state.player_position.y = f32(video_buffer.height) - 1
			} else if new_player_y > f32(video_buffer.height) {
				game_state.active_tilemap = 1
				game_state.player_position.y = 0
			}
		}
	}

	player_tile_x := int(
		math.floor((game_state.player_position.x - tile_map.upper_left.x) / tile_map.tile_dims.x),
	)
	player_tile_y := int(
		math.floor((game_state.player_position.y - tile_map.upper_left.y) / tile_map.tile_dims.y),
	)


	// debug purple background to see if I missed any part of the screen during
	// actual rendering
	when ODIN_DEBUG {
		render_rectangle(
			video_buffer,
			Rectangle {
				minX = 0,
				minY = 0,
				maxX = f32(video_buffer.width),
				maxY = f32(video_buffer.height),
			},
			Color{r = 1, g = 0, b = 1},
		)
	}


	for y_int in 0 ..< int(tile_map.count.y) {
		for x_int in 0 ..< int(tile_map.count.x) {
			value := get_tile_value_unchecked(tile_map, {y_int, x_int})
			x := f32(x_int)
			y := f32(y_int)
			minX := tile_map.upper_left.x + x * tile_map.tile_dims.x
			minY := tile_map.upper_left.y + y * tile_map.tile_dims.y

			rect := Rectangle {
				minX = minX,
				minY = minY,
				maxX = minX + tile_map.tile_dims.x,
				maxY = minY + tile_map.tile_dims.y,
			}
			if player_tile_x == x_int && player_tile_y == y_int {
				render_rectangle(video_buffer, rect, Color{r = 1, g = 1, b = 0})
			} else if value == 1 {
				render_rectangle(video_buffer, rect, Color{r = 1, g = 0, b = 0})
			} else {
				render_rectangle(video_buffer, rect, Color{r = 0.1, g = 0.8, b = 0.1})
			}
		}
	}


	minX := game_state.player_position.x - player_width / 2
	minY := game_state.player_position.y - player_height

	maxX := minX + player_width
	maxY := minY + player_height
	player_rect := Rectangle{minX, minY, maxX, maxY}
	render_rectangle(video_buffer, player_rect, Color{b = 1})

	render_rectangle(
		video_buffer,
		Rectangle {
			minX = game_state.player_position.x - 2,
			minY = game_state.player_position.y - 2,
			maxX = game_state.player_position.x + 2,
			maxY = game_state.player_position.y + 2,
		},
		Color{b = 1, g = 1, r = 1},
	)
}

@(export)
update_audio :: proc(thread: ^Thread_Context, memory: ^Memory, sound: ^Sound_Output_Buffer) {
	state := cast(^Game_State)&memory.permament[0]
	output_sound(state, sound)
}


// ==============================
// ========= RENDERING ==========
// ==============================
Pixel :: struct {
	b: u8,
	g: u8,
	r: u8,
	a: u8,
}

Color :: struct {
	r: f32,
	g: f32,
	b: f32,
}

color_to_pixel :: proc(color: Color) -> Pixel {
	map_range :: proc(value: f32) -> u8 {
		// when ODIN_DEBUG {
		// 	assert(value >= 0, "Range of 0-1")
		// 	assert(value <= 1, "Range of 0-1")
		// }
		return u8(math.round(clamp(value, 0, 1) * 255))
	}
	return Pixel{r = map_range(color.r), g = map_range(color.g), b = map_range(color.b), a = 255}
}

Offscreen_Buffer :: struct {
	pixels:       []Pixel,
	width:        i32,
	height:       i32,
	pitch_pixels: i32,
}

render_strange_gradient :: proc(buf: ^Offscreen_Buffer, offset: [2]i32) {
	for y in 0 ..< buf.height {
		for x in 0 ..< buf.width {
			buf.pixels[y * buf.pitch_pixels + x] = Pixel {
				r = u8(x + offset.x),
				g = u8(y + offset.y),
				b = u8(0),
				a = 255,
			}
		}
	}
}

Rectangle :: struct {
	minX: f32,
	minY: f32,
	maxX: f32,
	maxY: f32,
}

render_rectangle :: proc(buf: ^Offscreen_Buffer, rect: Rectangle, color: Color) {
	to_int_pixel :: proc(x: f32) -> i32 {return cast(i32)math.round(x)}

	left := clamp(to_int_pixel(rect.minX), 0, buf.width)
	right := clamp(to_int_pixel(rect.maxX), 0, buf.width)

	top := clamp(to_int_pixel(rect.minY), 0, buf.height)
	bottom := clamp(to_int_pixel(rect.maxY), 0, buf.height)

	// TODO(perf): will this benefit in perf from raw pointer math or the compiler is good enough
	// to not make me do that and I can rely on the usual array semantics here?
	pixel := color_to_pixel(color)
	for y in top ..< bottom {
		for x in left ..< right {
			buf.pixels[y * buf.pitch_pixels + x] = pixel
		}
	}
}


// ==========================
// ========= SOUND ==========
// ==========================
Sound_Sample :: struct {
	left:  i16,
	right: i16,
}

Sound_Output_Buffer :: struct {
	// len == how many samples does the game needs to fill
	samples:     []Sound_Sample,
	sample_rate: u32,
}

DEBUG_GENERATE_FREQ :: false
output_sound :: proc(state: ^Game_State, buf: ^Sound_Output_Buffer) {
	when DEBUG_GENERATE_FREQ {
		volume: f32 = 0.1
		wave_period: f32 = f32(buf.sample_rate) / tone_hz
	}

	for &sample in buf.samples {
		sample_value: i16 = 0

		when DEBUG_GENERATE_FREQ {
			sine_value: f32 = math.sin(state.sine_t)
			state.sine_t = math.mod(state.sine_t + math.TAU / wave_period, math.TAU)
			sample_value := cast(i16)(sine_value * volume * cast(f32)(2 << 14))
		}

		sample.left = sample_value
		sample.right = sample_value
	}
}


// ==========================
// ========= INPUT ==========
// ==========================
Input_Button :: struct {
	half_transition_count: i8,
	ended_down:            bool,
}

Button_Fields :: struct {
	move_up:      Input_Button,
	move_down:    Input_Button,
	move_left:    Input_Button,
	move_right:   Input_Button,
	action_up:    Input_Button,
	action_down:  Input_Button,
	action_left:  Input_Button,
	action_right: Input_Button,
	a:            Input_Button,
	b:            Input_Button,
	x:            Input_Button,
	y:            Input_Button,
	back:         Input_Button,
	start:        Input_Button,
}

Button_Storage :: struct #raw_union {
	buttons: [size_of(Button_Fields)]Input_Button,
	using _: Button_Fields,
}

Mouse_Button_Fields :: struct {
	left:    Input_Button,
	right:   Input_Button,
	middle:  Input_Button,
	back:    Input_Button,
	forward: Input_Button,
}

Mouse_Button_Storage :: struct #raw_union {
	buttons: [size_of(Mouse_Button_Fields)]Input_Button,
	using _: Mouse_Button_Fields,
}

Player_Input :: struct {
	stick_x:      f32,
	stick_y:      f32,
	using _:      Button_Storage,
	is_analog:    bool,
	is_connected: bool,
}

MAX_CONTROLELRS :: 5

Input :: struct {
	controllers:    [MAX_CONTROLELRS]Player_Input,
	mouse_buttons:  Mouse_Button_Storage,
	mouse:          [3]i32,
	dt:             f32,
	DEBUG_printfln: proc(format: string, args: ..any),
}
