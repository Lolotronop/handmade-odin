package handmade_odin

import "base:intrinsics"
import "base:runtime"
import "core:fmt"
import "core:math"
import "core:mem"
import os "core:os"
import "core:slice"
import win "core:sys/windows"

import "./game"

// I use `dims` to mean the dimensions of a thing
// so dims.x is with and dims.y is height

load_win_proc :: proc(module: win.HMODULE, name: cstring, destination: rawptr) -> bool {
	loaded := win.GetProcAddress(module, name)

	if loaded != nil {
		dest := cast(^uintptr)(destination)
		dest^ = auto_cast loaded
		return true
	}

	when ODIN_DEBUG {
		if loaded == nil {
			fmt.printfln("Failed to load %cs", name)
		}
	}

	return false
}

xinput_get_state: type_of(win.XInputGetState) = proc "stdcall" (
	user: win.XUSER,
	pState: ^win.XINPUT_STATE,
) -> win.System_Error {
	return .DEVICE_NOT_CONNECTED
}

xinput_set_state: type_of(win.XInputSetState) = proc "stdcall" (
	user: win.XUSER,
	pVibration: ^win.XINPUT_VIBRATION,
) -> win.System_Error {
	return .DEVICE_NOT_CONNECTED
}

xinput_load :: proc() {
	candidates: []win.LPCWSTR = {
		win.L("xinput9_1_0.dll"),
		win.L("xinput1_4.dll"),
		win.L("xinput1_3.dll"),
	}

	xinput: win.HMODULE = nil

	for candidate in candidates {
		xinput = win.LoadLibraryW(candidate)
		if xinput != nil {
			break
		}
	}

	if xinput == nil {
		fmt.println("Failed to load xinput")
		return
	}

	load_win_proc(xinput, "XInputGetState", &xinput_get_state)
	load_win_proc(xinput, "XInputSetState", &xinput_set_state)
}

dsound_load :: proc() -> (ok: bool) {
	ok = false

	dsound := win.LoadLibraryW(win.L("dsound.dll"))
	if dsound == nil {
		fmt.println("Failed to load dsound")
		return
	}

	load_win_proc(dsound, "DirectSoundCreate", &direct_sound_create) or_return

	return true
}


global_audio_buffer: LPDIRECTSOUNDBUFFER


dsound_init :: proc(window: win.HWND, samplerate: u32, buffer_size: u32) {
	if !dsound_load() {
		fmt.println("Failed to load dsound")
		return
	}

	ds: LPDIRECTSOUND

	direct_sound_create(nil, &ds, nil)

	if res := ds.SetCooperativeLevel(ds, window, DSSCL_PRIORITY); res != 0 {
		fmt.printfln("Failed to set cooperative level 0x%x", u32(res))
		return
	}

	format := win.WAVEFORMATEX {
		wFormatTag     = WAVE_FORMAT_PCM,
		nChannels      = 2,
		nSamplesPerSec = samplerate,
		wBitsPerSample = 16,
	}
	format.nBlockAlign = format.nChannels * format.wBitsPerSample / 8
	format.nAvgBytesPerSec = format.nSamplesPerSec * win.DWORD(format.nBlockAlign)


	secondary_buffer_description := DSBUFFERDESC {
		dwSize        = size_of(DSBUFFERDESC),
		dwFlags       = DSBCAPS_PRIMARYBUFFER,
		dwBufferBytes = 0,
	}

	// ----------------------------------------------
	// this is most likely redundant on modern systems
	// it is originally intended to set the sample rate
	// of the actual device, but since on windows these
	// days handles everything with a virtual mixer
	// it should not be necessary. but I have not tested that
	primary_buffer: LPDIRECTSOUNDBUFFER

	if res := ds.CreateSoundBuffer(ds, &secondary_buffer_description, &primary_buffer, nil);
	   res != 0 {
		fmt.printfln("Failed to create primary buffer 0x%x", u32(res))
		return
	}
	if res := primary_buffer.SetFormat(primary_buffer, &format); res != 0 {
		fmt.printfln("Failed to set format 0x%x", u32(res))
		return
	}
	// ----------------------------------------------

	buffer_description := DSBUFFERDESC {
		dwSize        = size_of(DSBUFFERDESC),
		dwBufferBytes = buffer_size,
		lpwfxFormat   = &format,
	}

	if res := ds.CreateSoundBuffer(ds, &buffer_description, &global_audio_buffer, nil); res != 0 {
		fmt.printfln("Failed to create secondary buffer 0x%x", u32(res))
		return
	}
}

global_running := false

dimensions :: proc {
	dimensions_rect,
	dimensions_window,
}

dimensions_rect :: #force_inline proc(rect: win.RECT) -> [2]i32 {
	return [2]i32{rect.right - rect.left, rect.bottom - rect.top}
}

dimensions_window :: proc(window: win.HWND) -> [2]i32 {
	rect: win.RECT
	win.GetClientRect(window, &rect)
	return dimensions_rect(rect)
}

Offscreen_Buffer :: struct {
	info:            win.BITMAPINFO,
	memory:          []byte,
	width:           i32,
	height:          i32,
	pitch_bytes:     i32,
	bytes_per_pixel: i32,
}

global_back_buffer: Offscreen_Buffer = {
	bytes_per_pixel = 4,
}

kinda_winmain :: proc() -> (win.HINSTANCE, win.LPCWSTR, win.STARTUPINFOW) {
	instance := win.HINSTANCE(win.GetModuleHandleW(nil))
	assert(instance != nil, "Failed to fetch current instance")

	lpCmdLine := win.GetCommandLineW()

	startup_info: win.STARTUPINFOW
	win.GetStartupInfoW(&startup_info)
	// TDOO: figure out what this even is
	nCmdShow :=
		(startup_info.dwFlags & win.STARTF_USESHOWWINDOW) != 0 ? cast(win.c_int)startup_info.wShowWindow : win.SW_SHOWDEFAULT
	_ = nCmdShow

	return instance, lpCmdLine, startup_info
}

create_window :: proc(instance: win.HINSTANCE) -> win.HWND {
	CLASS_NAME :: "Windows Window"

	cls := win.WNDCLASSW {
		style         = win.CS_OWNDC | win.CS_HREDRAW | win.CS_VREDRAW,
		lpfnWndProc   = win_proc,
		lpszClassName = CLASS_NAME,
		hInstance     = instance,
	}

	class := win.RegisterClassW(&cls)
	assert(class != 0, "Class creation failed")

	hwnd := win.CreateWindowW(
		CLASS_NAME,
		win.L("Windows Window"),
		win.WS_OVERLAPPEDWINDOW | win.WS_VISIBLE,
		win.CW_USEDEFAULT,
		win.CW_USEDEFAULT,
		win.CW_USEDEFAULT,
		win.CW_USEDEFAULT,
		nil,
		nil,
		instance,
		nil,
	)
	assert(hwnd != nil, "Window creation failed")

	return hwnd
}

offscreen_buffer_resize :: proc(buf: ^Offscreen_Buffer, dims: [2]i32) {
	if (buf.memory != nil) {
		win.VirtualFree(slice.first_ptr(buf.memory), 0, win.MEM_RELEASE)
	}

	buf.width = dims.x
	buf.height = dims.y
	buf.pitch_bytes = dims.x * buf.bytes_per_pixel

	buf.info.bmiHeader.biSize = size_of(win.BITMAPINFO)
	buf.info.bmiHeader.biWidth = buf.width
	buf.info.bmiHeader.biHeight = -buf.height
	buf.info.bmiHeader.biPlanes = 1
	buf.info.bmiHeader.biBitCount = 32
	buf.info.bmiHeader.biCompression = win.BI_RGB

	bitmap_size: uint = uint(buf.width * buf.height * buf.bytes_per_pixel)

	buf.memory = win_alloc(bitmap_size)
}

display_buffer :: proc(device_context: win.HDC, window_dims: [2]i32, buf: ^Offscreen_Buffer) {
	win.StretchDIBits(
		device_context,
		0,
		0,
		window_dims.x,
		window_dims.y,
		0,
		0,
		buf.width,
		buf.height,
		slice.first_ptr(buf.memory),
		&buf.info,
		win.DIB_RGB_COLORS,
		win.SRCCOPY,
	)
}

win_proc :: proc "stdcall" (
	window: win.HWND,
	message: win.UINT,
	wparam: win.WPARAM,
	lparam: win.LPARAM,
) -> win.LRESULT {
	context = runtime.default_context()

	res: win.LRESULT

	switch (message) {
	case win.WM_SYSKEYDOWN:
		fallthrough
	case win.WM_SYSKEYUP:
		fallthrough
	case win.WM_KEYDOWN:
		fallthrough
	case win.WM_KEYUP:
		// TODO: figure out if this is safe to ignore
		assert(false, "A keyboard message in the callback happened")

	case win.WM_DESTROY:
		fallthrough
	case win.WM_CLOSE:
		global_running = false
	case win.WM_PAINT:
		paint: win.PAINTSTRUCT
		ctx := win.BeginPaint(window, &paint)

		dirty_dims := dimensions(paint.rcPaint)
		_ = dirty_dims

		dims := dimensions(window)
		display_buffer(ctx, dims, &global_back_buffer)
		win.EndPaint(window, &paint)
	case:
		res = win.DefWindowProcW(window, message, wparam, lparam)
	}

	return res
}

SAMPLE_RATE :: 48000
BYTES_PER_SAMPLE :: 4 // LEFT(i16) RIGHT(i16)

Sound_Output :: struct {
	sample_rate:          u32,
	bytes_per_sample:     u32,
	buffer_size:          u32,
	running_sample_index: u32,
	latency_samples:      u32,
}

fill_sound_buffer :: proc(
	sound_output: ^Sound_Output,
	byte_to_lock: u32,
	bytes_to_write: u32,
	source_buffer: ^game.Sound_Output_Buffer,
) {
	region1: win.VOID
	region1_size: win.DWORD
	region2: win.VOID
	region2_size: win.DWORD
	global_audio_buffer.Lock(
		global_audio_buffer,
		byte_to_lock,
		bytes_to_write,
		&region1,
		&region1_size,
		&region2,
		&region2_size,
		0,
	)

	sample_count := u32(len(source_buffer.samples))

	if (sample_count > 0) {
		raw := slice.to_bytes(source_buffer.samples)
		from1 := &raw[0]
		mem.copy(region1, from1, int(region1_size))
		if (region1_size < sample_count * sound_output.bytes_per_sample) {
			mem.copy(region2, &raw[region1_size], int(region2_size))
		}
	}

	sound_output.running_sample_index += sample_count

	global_audio_buffer.Unlock(global_audio_buffer, region1, region1_size, region2, region2_size)
}

Kilabytes :: #force_inline proc($mb: u64) -> (bytes: u64) {return mb * 1024}
Megabytes :: #force_inline proc($mb: u64) -> (bytes: u64) {return mb * 1024 * 1024}
Gigabytes :: #force_inline proc($mb: u64) -> (bytes: u64) {return mb * 1024 * 1024 * 1024}

win_alloc :: proc(#any_int size: uint) -> []byte {
	return slice.bytes_from_ptr(
		win.VirtualAlloc(nil, size, win.MEM_COMMIT | win.MEM_RESERVE, win.PAGE_READWRITE),
		int(size),
	)
}

global_perf_freq: win.LARGE_INTEGER = 0

main :: proc() {
	instance, lpCmdLine, startup_info := kinda_winmain()
	_ = lpCmdLine
	_ = startup_info

	assert(win.timeBeginPeriod(1) == win.TIMERR_NOERROR) // 1ms timer resolution
	win.QueryPerformanceFrequency(&global_perf_freq)

	monitor_refresh_rate :: 60
	target_fps :: monitor_refresh_rate / 2
	target_ms_per_frame: f32 : 1000 / f32(target_fps)


	global_running = true
	msg: win.MSG
	res: win.LRESULT = 1


	window := create_window(instance)
	xinput_load()
	audio_buffer_size: u32 = SAMPLE_RATE * BYTES_PER_SAMPLE
	dsound_init(window, SAMPLE_RATE, audio_buffer_size)
	offscreen_buffer_resize(&global_back_buffer, {1280, 720})

	audio_latency_frames :: 3
	sound_output: Sound_Output = {
		sample_rate          = SAMPLE_RATE,
		bytes_per_sample     = BYTES_PER_SAMPLE,
		buffer_size          = audio_buffer_size,
		running_sample_index = 0,
		latency_samples      = audio_latency_frames * SAMPLE_RATE / u32(target_fps),
	}
	audio_buf := slice.reinterpret([]game.Sound_Sample, win_alloc(sound_output.buffer_size))
	sound_is_valid := false
	last_play_cursor: u32 = 0
	write_cursor: win.DWORD

	global_audio_buffer.Play(global_audio_buffer, 0, 0, DSBPLAY_LOOPING)


	old_input := game.Input{}

	game_memory := game.Memory{}
	game_memory.permament = win_alloc(Megabytes(64))
	game_memory.transient = win_alloc(Gigabytes(4))


	end_counter: win.LARGE_INTEGER
	last_counter := get_wall_clock()
	for res > 0 && global_running {
		// =============================
		// ========= READ INPUT ========
		// =============================
		new_input := game.Input{}

		old_keyboard_controller := &old_input.controllers[0]
		new_keyboard_controller := &new_input.controllers[0]
		for i in 0 ..< len(new_keyboard_controller.buttons) {
			new_keyboard_controller.buttons[i].ended_down =
				old_keyboard_controller.buttons[i].ended_down
		}
		new_keyboard_controller.is_connected = true

		for win.PeekMessageA(&msg, nil, 0, 0, win.PM_REMOVE) {
			if msg.message == win.WM_QUIT {
				global_running = false
			}

			switch msg.message {
			case win.WM_QUIT:
				global_running = false

			case win.WM_SYSKEYDOWN:
				fallthrough
			case win.WM_SYSKEYUP:
				fallthrough
			case win.WM_KEYDOWN:
				fallthrough
			case win.WM_KEYUP:
				has_bit :: #force_inline proc(mask: u32, bit: u32) -> bool {
					when ODIN_DEBUG {assert(bit < 32)}
					return (mask & (1 << bit)) != 0
				}

				process_keyboard :: proc(new_state: ^game.Input_Button, is_down: bool) {
					assert(new_state.ended_down != is_down)
					new_state.ended_down = is_down
					new_state.half_transition_count += 1
				}

				IS_UP_BIT :: 31
				WAS_DOWN_BIT :: 30
				ALT_DOWN_BIT :: 29

				keycode := msg.wParam
				key_parameters := u32(msg.lParam)

				was_down: bool = has_bit(key_parameters, WAS_DOWN_BIT)
				_ = was_down
				is_down: bool = !has_bit(key_parameters, IS_UP_BIT)
				alt_down: bool = has_bit(key_parameters, ALT_DOWN_BIT)

				if (alt_down && keycode == win.VK_F4) {
					global_running = false
				}

				if (was_down != is_down) {
					new := &new_input.controllers[0]

					if (keycode == 'W') {process_keyboard(&new.move_up, is_down)}
					if (keycode == 'A') {process_keyboard(&new.move_left, is_down)}
					if (keycode == 'S') {process_keyboard(&new.move_down, is_down)}
					if (keycode == 'D') {process_keyboard(&new.move_right, is_down)}
					if (keycode == 'E') {process_keyboard(&new.a, is_down)}
					if (keycode == 'Q') {process_keyboard(&new.b, is_down)}
				}
			case:
				win.TranslateMessage(&msg)
				win.DispatchMessageW(&msg)
			}

		}

		max_controllers: u32 = min(game.MAX_CONTROLELRS, win.XUSER_MAX_COUNT)
		for controller_index: win.DWORD;
		    controller_index < max_controllers;
		    controller_index += 1 {
			our_controller_index := controller_index + 1
			state: win.XINPUT_STATE
			res := xinput_get_state(win.XUSER(controller_index), &state)

			old := &old_input.controllers[our_controller_index]
			new := &new_input.controllers[our_controller_index]

			if res != .SUCCESS {
				new.is_analog = false
				new.is_connected = false
				continue
			}

			pad := state.Gamepad
			new.is_connected = true


			left_daedzone :: win.XINPUT_GAMEPAD_LEFT_THUMB_DEADZONE
			new.stick_x = normalize_stick(pad.sThumbLX, left_daedzone)
			new.stick_y = normalize_stick(pad.sThumbLY, left_daedzone)

			if new.stick_x != 0 || new.stick_y != 0 {
				new.is_analog = true
			}

			threshhold :: 0.5
			process_button(&pad, &old.move_right, new.stick_x > threshhold, &new.move_right)
			process_button(&pad, &old.move_left, new.stick_x < -threshhold, &new.move_left)
			process_button(&pad, &old.move_up, new.stick_y > threshhold, &new.move_up)
			process_button(&pad, &old.move_down, new.stick_y < -threshhold, &new.move_down)


			bits :: win.XINPUT_GAMEPAD_BUTTON_BIT
			// TODO: make this into a table of (bit, offset_of(old.a)) etc?
			process_button_bit(&pad, &old.a, bits.A, &new.a)
			process_button_bit(&pad, &old.b, bits.B, &new.b)
			process_button_bit(&pad, &old.x, bits.X, &new.x)
			process_button_bit(&pad, &old.y, bits.Y, &new.y)

			process_button_bit(&pad, &old.move_left, bits.DPAD_LEFT, &new.move_left)
			process_button_bit(&pad, &old.move_right, bits.DPAD_RIGHT, &new.move_right)
			process_button_bit(&pad, &old.move_up, bits.DPAD_UP, &new.move_up)
			process_button_bit(&pad, &old.move_down, bits.DPAD_DOWN, &new.move_down)

			process_button_bit(&pad, &old.back, bits.BACK, &new.back)
			process_button_bit(&pad, &old.start, bits.START, &new.start)

			if new.move_up.ended_down {new.stick_y = 1.0}
			if new.move_down.ended_down {new.stick_y = -1.0}
			if new.move_left.ended_down {new.stick_x = -1.0}
			if new.move_right.ended_down {new.stick_x = 1.0}


			process_button_bit :: proc(
				pad: ^win.XINPUT_GAMEPAD,
				old_state: ^game.Input_Button,
				button_bit: win.XINPUT_GAMEPAD_BUTTON_BIT,
				new_state: ^game.Input_Button,
			) {
				process_button(pad, old_state, button_bit in pad.wButtons, new_state)
			}

			process_button :: proc(
				pad: ^win.XINPUT_GAMEPAD,
				old_state: ^game.Input_Button,
				is_down: bool,
				new_state: ^game.Input_Button,
			) {
				new_state.ended_down = is_down

				did_change := old_state.ended_down != new_state.ended_down
				new_state.half_transition_count = did_change ? 1 : 0
			}

			normalize_stick :: proc(value: i16, deadzone: i16) -> f32 {
				// xinput defines the range to be -32768 to 32767
				// because of win.SHORT being 16-bit signed int
				if value < 0 && value < -deadzone {
					return f32(value) / f32(1 << 15)
				} else if value > 0 && value > deadzone {
					return f32(value) / f32(1 << 15 - 1)
				}
				return 0.0
			}
		}


		// ========================================
		// ========= DETERMINE SOUND THINGS =======
		// ========================================
		sample_count: u32 = 0
		bytes_to_write: u32 = 0
		byte_to_lock: u32 = 0
		if sound_is_valid {
			target_cursor :=
				(last_play_cursor + sound_output.latency_samples * sound_output.bytes_per_sample) %
				sound_output.buffer_size

			byte_to_lock = sound_output.running_sample_index * sound_output.bytes_per_sample
			byte_to_lock %= sound_output.buffer_size

			temp_play_cursor: win.DWORD
			global_audio_buffer.GetCurrentPosition(global_audio_buffer, &temp_play_cursor, nil)
			fmt.printfln(
				"play: %d\t lock: %d\t diff: %d",
				temp_play_cursor,
				byte_to_lock,
				i64(byte_to_lock) - i64(temp_play_cursor),
			)


			// [??????P--------Bwwwwwwwwwww]
			if byte_to_lock > target_cursor {
				bytes_to_write = sound_output.buffer_size - byte_to_lock
				bytes_to_write += target_cursor
			}

			// // [---BwwwwwwwwP--------------]
			if byte_to_lock < target_cursor {
				bytes_to_write = target_cursor - byte_to_lock
			}


			bytes_to_write = SAMPLE_RATE * BYTES_PER_SAMPLE / u32(target_fps)

			sample_count = bytes_to_write / sound_output.bytes_per_sample
		}


		// ========================================
		// ========= PREPARE THE FRAME ============
		// ========================================

		game_sound_buffer := game.Sound_Output_Buffer {
			samples     = audio_buf[:sample_count],
			sample_rate = sound_output.sample_rate,
		}

		game_video_buffer := game.Offscreen_Buffer {
			pixels       = slice.reinterpret([]game.Pixel, global_back_buffer.memory),
			width        = global_back_buffer.width,
			height       = global_back_buffer.height,
			pitch_pixels = global_back_buffer.pitch_bytes / global_back_buffer.bytes_per_pixel,
		}

		game.update_step(&game_memory, &new_input, &game_video_buffer, &game_sound_buffer)

		// ========================================
		// ========= WAIT FOR NEXT FRAME ==========
		// ========================================
		end_counter = get_wall_clock()
		perf_ms := elapsed_ms(last_counter, end_counter)
		if perf_ms < target_ms_per_frame {
			sleep_ms := u32(math.floor(target_ms_per_frame - perf_ms))
			if sleep_ms > 0 {win.Sleep(min(sleep_ms, 0))}
			perf_ms = elapsed_ms(last_counter, get_wall_clock())
			for perf_ms < target_ms_per_frame {
				perf_ms = elapsed_ms(last_counter, get_wall_clock())
			}
		} else {
			sound_is_valid = false
			fmt.printfln("Warning: frame took %.2fms", perf_ms)
		}
		end_counter = get_wall_clock()
		last_counter = end_counter

		// ========================================
		// ========= DISPLAY THE FRAME ============
		// ========================================
		if sound_is_valid {
			fill_sound_buffer(&sound_output, byte_to_lock, bytes_to_write, &game_sound_buffer)
		}

		when ODIN_DEBUG {
			{
				pad_x: i32 = 16
				pad_y: i32 = 16

				top := pad_y
				bottom := global_back_buffer.height - pad_y

				white :: game.Pixel {
					b = u8(255),
					g = u8(255),
					r = u8(255),
					a = u8(255),
				}
				purple :: game.Pixel {
					b = u8(255),
					g = u8(0),
					r = u8(255),
					a = u8(255),
				}
				green :: game.Pixel {
					b = u8(0),
					g = u8(255),
					r = u8(0),
					a = u8(255),
				}

				red :: game.Pixel {
					b = u8(0),
					g = u8(0),
					r = u8(255),
					a = u8(255),
				}

				color_multiply :: proc(color: game.Pixel, factor: f32) -> game.Pixel {
					return game.Pixel {
						b = u8(f32(color.b) * factor),
						g = u8(f32(color.g) * factor),
						r = u8(f32(color.r) * factor),
						a = u8(f32(color.a) * factor),
					}
				}

				C := f32(global_back_buffer.width - 2 * pad_x) / f32(audio_buffer_size)

				x_curr_play := pad_x + i32(C * f32(last_play_cursor))
				draw_vertical_line(&global_back_buffer, x_curr_play, top, bottom, white, 10)

				x_curr_write := pad_x + i32(C * f32(write_cursor))
				draw_vertical_line(&global_back_buffer, x_curr_write, top, bottom, purple, 6)

				x_curr_target := pad_x + i32(C * f32(byte_to_lock))
				draw_vertical_line(&global_back_buffer, x_curr_target, top, bottom, green, 4)

				draw_vertical_line :: proc(
					buf: ^Offscreen_Buffer,
					x, top, bottom: i32,
					color: game.Pixel,
					width: i32 = 2,
				) {
					pixels := slice.reinterpret([]game.Pixel, buf.memory)
					pitch := buf.pitch_bytes / buf.bytes_per_pixel
					for y in top ..< bottom {
						for i in 0 ..< width {
							pixels[x + i + y * pitch] = color
						}
					}
				}
			}
		}

		{
			dc := win.GetDC(window)
			defer win.ReleaseDC(window, dc)

			dims := dimensions(window)
			display_buffer(dc, dims, &global_back_buffer)
		}

		// ==========================================
		// ========= SWITCH BUFFERS N THINGS ========
		// ==========================================
		ok := global_audio_buffer.GetCurrentPosition(
			global_audio_buffer,
			&last_play_cursor,
			&write_cursor,
		)
		if ok == DS_OK {
			if sound_is_valid == false {
				sound_output.running_sample_index =
					write_cursor / sound_output.bytes_per_sample + sound_output.latency_samples
			}

			sound_is_valid = true
		} else {
			sound_is_valid = false
		}
		old_input = new_input
	}

	os.exit(cast(int)msg.wParam)
}

minmax :: #force_inline proc(a, b: $T) -> (T, T) {
	if a < b {return a, b} else {return b, a}
}

elapsed_ms :: #force_inline proc(start: win.LARGE_INTEGER, end: win.LARGE_INTEGER) -> f32 {
	// TODO: do I need this?
	a, b := minmax(start, end)
	return f32(b - a) / f32(global_perf_freq) * 1000.0
}

get_wall_clock :: #force_inline proc() -> win.LARGE_INTEGER {
	counter: win.LARGE_INTEGER
	win.QueryPerformanceCounter(&counter)
	return counter
}
