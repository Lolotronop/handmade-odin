package game

import "core:math"

Thread_Context :: struct {}

// ==================================
// =========== MAIN LOOP ============
// ==================================
Game_State :: struct {}

Memory :: struct {
	// required to be cleared to 0
	permament:      []byte,
	transient:      []byte,
	is_initialized: bool,
}

@(export)
update_step :: proc(
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

	if memory.is_initialized == false {
		memory.is_initialized = true
	}

	for controller in input.controllers {
		if controller.is_connected == false {
			continue
		}

		if controller.is_analog {
		} else {
			move: [2]i32 = {0, 0}

			move.x += controller.move_right.ended_down ? 1 : 0
			move.x -= controller.move_left.ended_down ? 1 : 0
			move.y += controller.move_down.ended_down ? 1 : 0
			move.y -= controller.move_up.ended_down ? 1 : 0

			_ = move
		}
	}

	// clear the screen
	render_rectangle(
		video_buffer,
		Rectangle {
			minX = 0,
			minY = 0,
			maxX = f32(video_buffer.width),
			maxY = f32(video_buffer.height),
		},
		Pixel{a = 255},
	)

	render_rectangle(
		video_buffer,
		Rectangle{minX = 10, minY = 10, maxX = 100, maxY = 100},
		Pixel{r = 255, g = 128, b = 128, a = 128},
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

render_rectangle :: proc(buf: ^Offscreen_Buffer, rect: Rectangle, color: Pixel) {
	to_int_pixel :: proc(x: f32) -> i32 {return cast(i32)math.round(x)}

	left := clamp(to_int_pixel(rect.minX), 0, buf.width)
	right := clamp(to_int_pixel(rect.maxX), 0, buf.width)

	top := clamp(to_int_pixel(rect.minY), 0, buf.height)
	bottom := clamp(to_int_pixel(rect.maxY), 0, buf.height)

	// TODO(perf): will this benefit in perf from raw pointer math or the compiler is good enough
	// to not make me do that and I can rely on the usual array semantics here?
	for y in top ..< bottom {
		for x in left ..< right {
			buf.pixels[y * buf.pitch_pixels + x] = color
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
	controllers:               [MAX_CONTROLELRS]Player_Input,
	mouse_buttons:             Mouse_Button_Storage,
	mouse:                     [3]i32,
	ms_to_advance_over_update: f32,
}
