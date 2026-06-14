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
	samples: [48000 * 2]i16,
	count:   u32,
	rate:    u32,
}

sine_t: f32 = 0.0

output_sound :: proc(buf: ^Sound_Output_Buffer) {
	volume: f32 = 0.1
	tone_hz: f32 = 440.0
	wave_period: f32 = f32(buf.rate) / tone_hz

	for sample_index: u32; sample_index < buf.count * 2; sample_index += 2 {
		sine_value: f32 = math.sin(sine_t)
		sine_t = math.mod(sine_t + math.TAU / wave_period, math.TAU)

		sample_value := cast(i16)(sine_value * volume * cast(f32)(2 << 14))

		left := sample_value
		right := sample_value

		buf.samples[sample_index] = left
		buf.samples[sample_index + 1] = right
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

update_step :: proc(video_buffer: ^Offscreen_Buffer, Sound_Output_Buffer: ^Sound_Output_Buffer) {
	render(video_buffer, [2]i32{0, 0})
	output_sound(Sound_Output_Buffer)
}
