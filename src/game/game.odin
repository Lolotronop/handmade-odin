package game

import "core:math"

// ==================================
// =========== MAIN LOOP ============
// ==================================
State :: struct {
	tone_hz: f32,
	offset:  [2]i32,
}

Memory :: struct {
	// required to be cleared to 0
	permament:      []byte,
	transient:      []byte,
	is_initialized: bool,
}

update_step :: proc(
	memory: ^Memory,
	input: ^Input,
	video_buffer: ^Offscreen_Buffer,
	Sound_Output_Buffer: ^Sound_Output_Buffer,
) {
	assert(size_of(State) <= len(memory.permament))

	// TODO: figure this one out, why to_type gives a nil pointer
	// state := slice.to_type(memory.permament, ^State)
	state := cast(^State)&memory.permament[0]

	if memory.is_initialized == false {
		memory.is_initialized = true

		state.tone_hz = 440.0
		state.offset.x = 0
		state.offset.y = 0
	}

	for controller in input.controllers {
		if controller.is_connected == false {
			continue
		}

		if controller.is_analog {
			if controller.stick_y != 0 {
				state.tone_hz = 440.0 + controller.stick_y * 128.0
			}
			state.offset.x += cast(i32)(4.0 * controller.stick_x)
			state.offset.y += cast(i32)(4.0 * controller.stick_y)
		} else {
			move: [2]i32 = {0, 0}

			move.x += controller.move_right.ended_down ? 1 : 0
			move.x -= controller.move_left.ended_down ? 1 : 0
			move.y -= controller.move_down.ended_down ? 1 : 0
			move.y += controller.move_up.ended_down ? 1 : 0

			state.offset.x += move.x * 4
			state.offset.y += move.y * 4

			if (move.x != 0 || move.y != 0) {
				state.tone_hz = 440.0 + f32(move.y * 128)
			}
		}

		if (controller.a.ended_down) {
			state.offset.y += 1
		}
	}

	render(video_buffer, state.offset)
	output_sound(Sound_Output_Buffer, state.tone_hz)
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

render :: proc(buf: ^Offscreen_Buffer, offset: [2]i32) {
	for y in 0 ..< buf.height {
		for x in 0 ..< buf.width {
			buf.pixels[y * buf.pitch_pixels + x] = Pixel {
				r = u8(x + offset.x),
				g = u8(y + offset.y),
				b = u8(0),
			}
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

global_sine_t: f32 = 0.0

output_sound :: proc(buf: ^Sound_Output_Buffer, tone_hz: f32 = 440.0) {
	volume: f32 = 0.1
	wave_period: f32 = f32(buf.sample_rate) / tone_hz

	for &sample in buf.samples {
		sine_value: f32 = math.sin(global_sine_t)
		global_sine_t = math.mod(global_sine_t + math.TAU / wave_period, math.TAU)

		sample_value := cast(i16)(sine_value * volume * cast(f32)(2 << 14))

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

Player_Input :: struct {
	stick_x:      f32,
	stick_y:      f32,
	using _:      Button_Storage,
	is_analog:    bool,
	is_connected: bool,
}

MAX_CONTROLELRS :: 5

Input :: struct {
	controllers: [MAX_CONTROLELRS]Player_Input,
}
