package game

import "core:math"
import "core:mem"


Offscreen_Buffer :: struct {
	memory: [^]u8,
	width:  i32,
	height: i32,
	pitch:  i32,
}

Sound_Output_Buffer :: struct {
	samples:      ^i16,
	sample_count: u32,
	sample_rate:  u32,
}

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

sine_t: f32 = 0.0

output_sound :: proc(buf: ^Sound_Output_Buffer, tone_hz: f32 = 440.0) {
	volume: f32 = 0.1
	wave_period: f32 = f32(buf.sample_rate) / tone_hz

	sample := cast(^i16)(buf.samples)

	for i in 0 ..< buf.sample_count {
		sine_value: f32 = math.sin(sine_t)
		sine_t = math.mod(sine_t + math.TAU / wave_period, math.TAU)

		sample_value := cast(i16)(sine_value * volume * cast(f32)(2 << 14))

		left := sample_value
		right := sample_value

		sample^ = left
		sample = mem.ptr_offset(sample, 1)
		sample^ = right
		sample = mem.ptr_offset(sample, 1)
	}
}

render :: proc(buf: ^Offscreen_Buffer, offset: [2]i32) {
	row := buf.memory

	for y in 0 ..< buf.height {
		pixel := cast([^]u32)row
		for x in 0 ..< buf.width {
			r := u8(x + offset.x)
			g := u8(y + offset.y)
			b := u8(0)

			pixel[0] = u32(r) << 8 | u32(g) << 16 | u32(b) << 24

			pixel = mem.ptr_offset(pixel, 1)
		}
		row = mem.ptr_offset(row, buf.pitch)
	}
}

update_step :: proc(
	input: ^Input,
	video_buffer: ^Offscreen_Buffer,
	Sound_Output_Buffer: ^Sound_Output_Buffer,
) {
	@(static) tone_hz: f32 = 440.07
	@(static) offset: [2]i32 = {0, 0}

	player_1_input := input.controllers[0]

	if (player_1_input.is_analog) {
		tone_hz = 440.0 + player_1_input.stick_y.end * 128.0
		offset.x += cast(i32)(4.0 * player_1_input.stick_x.end)
		offset.y += cast(i32)(4.0 * player_1_input.stick_y.end)
	} else {
		// no controller? :(
	}

	if (player_1_input.a.ended_down) {
		offset.y += 1
	}

	render(video_buffer, offset)
	output_sound(Sound_Output_Buffer, tone_hz)
}
