package handmade_odin

import "base:intrinsics"
import "base:runtime"
import "core:fmt"
import "core:math"
import "core:mem"
import os "core:os"
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
	memory:          [^]u8,
	width:           i32,
	height:          i32,
	pitch:           i32,
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
	nCmdShow :=
		(startup_info.dwFlags & win.STARTF_USESHOWWINDOW) != 0 ? cast(win.c_int)startup_info.wShowWindow : win.SW_SHOWDEFAULT

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
		win.VirtualFree(buf.memory, 0, win.MEM_RELEASE)
	}

	buf.width = dims.x
	buf.height = dims.y
	buf.pitch = dims.x * buf.bytes_per_pixel

	buf.info.bmiHeader.biSize = size_of(win.BITMAPINFO)
	buf.info.bmiHeader.biWidth = buf.width
	buf.info.bmiHeader.biHeight = -buf.height
	buf.info.bmiHeader.biPlanes = 1
	buf.info.bmiHeader.biBitCount = 32
	buf.info.bmiHeader.biCompression = win.BI_RGB

	bitmap_size: uint = uint(buf.width * buf.height * buf.bytes_per_pixel)
	pitch := buf.width * buf.bytes_per_pixel

	buf.memory = cast([^]u8)(win.VirtualAlloc(
			nil,
			bitmap_size,
			win.MEM_COMMIT | win.MEM_RESERVE,
			win.PAGE_READWRITE,
		))
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
		buf.memory,
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
		has_bit :: #force_inline proc(mask: u32, bit: u32) -> bool {
			when ODIN_DEBUG {assert(bit < 32)}
			return (mask & (1 << bit)) != 0
		}

		IS_UP_BIT :: 31
		WAS_DOWN_BIT :: 30
		ALT_DOWN_BIT :: 29

		keycode := wparam
		key_parameters := u32(lparam)

		was_down: bool = has_bit(key_parameters, WAS_DOWN_BIT)
		is_down: bool = !has_bit(key_parameters, IS_UP_BIT)
		alt_down: bool = has_bit(key_parameters, ALT_DOWN_BIT)

		if (was_down != is_down) { 	// filter repeats
			if (alt_down && keycode == win.VK_F4) {
				global_running = false
			}

			if (keycode == 'W') {
				fmt.println("W")
			} else if (keycode == 'A') {
				fmt.println("A")
			} else if (keycode == 'S') {
				fmt.println("S")
			} else if (keycode == 'D') {
				fmt.println("D")
			}
		}

	case win.WM_DESTROY:
		fallthrough
	case win.WM_CLOSE:
		global_running = false
	case win.WM_PAINT:
		paint: win.PAINTSTRUCT
		ctx := win.BeginPaint(window, &paint)

		dirty_dims := dimensions(paint.rcPaint)

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

	mem.copy(region1, source_buffer.samples, int(region1_size))
	mem.copy(region2, source_buffer.samples, int(region2_size))

	sound_output.running_sample_index += source_buffer.sample_count

	global_audio_buffer.Unlock(global_audio_buffer, region1, region1_size, region2, region2_size)
}

main :: proc() {
	instance, lpCmdLine, startup_info := kinda_winmain()
	window := create_window(instance)
	xinput_load()
	audio_buffer_size: u32 = SAMPLE_RATE * BYTES_PER_SAMPLE
	dsound_init(window, SAMPLE_RATE, audio_buffer_size)

	offscreen_buffer_resize(&global_back_buffer, {1280, 720})

	global_running = true
	msg: win.MSG
	res: win.LRESULT = 1
	offset: [2]i32 = {0, 0}

	sound_output: Sound_Output = {
		sample_rate          = SAMPLE_RATE,
		bytes_per_sample     = BYTES_PER_SAMPLE,
		buffer_size          = audio_buffer_size,
		running_sample_index = 0,
		latency_samples      = SAMPLE_RATE / 15,
	}


	global_audio_buffer.Play(global_audio_buffer, 0, 0, DSBPLAY_LOOPING)

	audio_buf := cast(^i16)win.VirtualAlloc(
		nil,
		auto_cast sound_output.buffer_size,
		win.MEM_COMMIT,
		win.PAGE_READWRITE,
	)

	end_counter: win.LARGE_INTEGER
	last_counter: win.LARGE_INTEGER
	win.QueryPerformanceCounter(&last_counter)

	perf_frequency: win.LARGE_INTEGER
	win.QueryPerformanceFrequency(&perf_frequency)

	last_cycle_count := intrinsics.read_cycle_counter()

	old_input := game.Input{}

	for res > 0 && global_running {
		for win.PeekMessageA(&msg, nil, 0, 0, win.PM_REMOVE) {
			if msg.message == win.WM_QUIT {
				global_running = false
			}

			win.TranslateMessage(&msg)
			win.DispatchMessageW(&msg)
		}

		new_input := game.Input{}

		max_controllers: u32 = math.min(game.MAX_CONTROLELRS, win.XUSER_MAX_COUNT)
		for controller_index: win.DWORD;
		    controller_index < max_controllers;
		    controller_index += 1 {
			state: win.XINPUT_STATE
			res := xinput_get_state(win.XUSER(controller_index), &state)

			old := &old_input.controllers[controller_index]
			new := &new_input.controllers[controller_index]

			if (res == .SUCCESS) {
				// controller is there
				pad := state.Gamepad

				new.is_analog = true

				process_button :: proc(
					pad: ^win.XINPUT_GAMEPAD,
					old_state: ^game.Input_Button,
					button_bit: win.XINPUT_GAMEPAD_BUTTON_BIT,
					new_state: ^game.Input_Button,
				) {
					new_state.ended_down = button_bit in pad.wButtons

					did_change := old_state.ended_down != new_state.ended_down
					new_state.half_transition_count = did_change ? 1 : 0
				}

				normalize_stick :: proc(value: i16) -> f32 {
					// xinput defines the range to be -32768 to 32767
					// because of win.SHORT being 16-bit signed int
					if value < 0 {
						return f32(value) / f32(1 << 15)
					} else {
						return f32(value) / f32(1 << 15 - 1)
					}
				}

				new.stick_x.end = normalize_stick(pad.sThumbLX)
				new.stick_y.end = normalize_stick(pad.sThumbLY)

				bits :: win.XINPUT_GAMEPAD_BUTTON_BIT

				process_button(&pad, &old.a, bits.A, &new.a)
				process_button(&pad, &old.b, bits.B, &new.b)
				process_button(&pad, &old.x, bits.X, &new.x)
				process_button(&pad, &old.y, bits.Y, &new.y)
				process_button(&pad, &old.left, bits.DPAD_LEFT, &new.left)
				process_button(&pad, &old.right, bits.DPAD_RIGHT, &new.right)
				process_button(&pad, &old.up, bits.DPAD_UP, &new.up)
				process_button(&pad, &old.down, bits.DPAD_DOWN, &new.down)

			} else {
				new.is_analog = false
				// no controller :(
			}
		}

		fmt.printfln(
			"stick_x: %f\tstick_y: %f",
			new_input.controllers[0].stick_x.end,
			new_input.controllers[0].stick_y.end,
		)

		offset.xy += 1

		dc := win.GetDC(window)

		play_cursor: win.DWORD
		write_cursor: win.DWORD
		global_audio_buffer.GetCurrentPosition(global_audio_buffer, &play_cursor, &write_cursor)

		target_cursor := play_cursor + sound_output.latency_samples * sound_output.bytes_per_sample
		target_cursor %= sound_output.buffer_size

		byte_to_lock := sound_output.running_sample_index * sound_output.bytes_per_sample
		byte_to_lock %= sound_output.buffer_size

		bytes_to_write: u32 = 0

		// [??????P--------Bwwwwwwwwwww]
		if byte_to_lock > target_cursor {
			bytes_to_write = sound_output.buffer_size - byte_to_lock
		}
		// [---BwwwwwwwwP--------------]
		if byte_to_lock < target_cursor {
			bytes_to_write = target_cursor - byte_to_lock
		}

		game_video_buffer := game.Offscreen_Buffer {
			memory = global_back_buffer.memory,
			width  = global_back_buffer.width,
			height = global_back_buffer.height,
			pitch  = global_back_buffer.pitch,
		}

		game_sound_buffer := game.Sound_Output_Buffer {
			samples      = audio_buf,
			sample_count = bytes_to_write / sound_output.bytes_per_sample,
			sample_rate  = sound_output.sample_rate,
		}


		game.update_step(&new_input, &game_video_buffer, &game_sound_buffer)

		old_input = new_input

		fill_sound_buffer(&sound_output, byte_to_lock, bytes_to_write, &game_sound_buffer)


		dims := dimensions(window)
		display_buffer(dc, dims, &global_back_buffer)
		win.ReleaseDC(window, dc)


		end_cycle_count := intrinsics.read_cycle_counter()
		cycle_count_elapsed := end_cycle_count - last_cycle_count
		last_cycle_count = end_cycle_count

		win.QueryPerformanceCounter(&end_counter)
		counter_elapsed := end_counter - last_counter
		perf_seconds := f64(counter_elapsed) / f64(perf_frequency)
		perf_ms := perf_seconds * 1000.0
		fps := u32(1000.0 / perf_ms)
		last_counter = end_counter

		// fmt.printfln(
		// 	"MS: %f\tfps: %d\tMCycles: %d",
		// 	perf_ms,
		// 	fps,
		// 	cycle_count_elapsed / (1000 * 1000),
		// )
	}

	os.exit(cast(int)msg.wParam)
}
