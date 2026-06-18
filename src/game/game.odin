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

	player_1_input := input.controllers[0]

	if (player_1_input.is_analog) {
		state.tone_hz = 440.0 + player_1_input.stick_y.end * 128.0
		state.offset.x += cast(i32)(4.0 * player_1_input.stick_x.end)
		state.offset.y += cast(i32)(4.0 * player_1_input.stick_y.end)
	} else {
		// no controller? :(
	}

	if (player_1_input.a.ended_down) {
		state.offset.y += 1
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
Input_Analog_Stick :: struct {
	start: f32,
	end:   f32,
	min:   f32,
	max:   f32,
}

Input_Button :: struct {
	half_transition_count: i8,
	ended_down:            bool,
}

Player_Input :: struct {
	stick_x:   Input_Analog_Stick,
	stick_y:   Input_Analog_Stick,
	up:        Input_Button,
	down:      Input_Button,
	left:      Input_Button,
	right:     Input_Button,
	a:         Input_Button,
	b:         Input_Button,
	x:         Input_Button,
	y:         Input_Button,
	is_analog: bool,
}

MAX_CONTROLELRS :: 4

Input :: struct {
	controllers: [MAX_CONTROLELRS]Player_Input,
}
