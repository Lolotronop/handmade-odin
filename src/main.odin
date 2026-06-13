package handmade_odin

import "base:runtime"
import "core:fmt"
import "core:math"
import "core:mem"
import os "core:os"
import win "core:sys/windows"

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

render_gradient :: proc(buf: ^Offscreen_Buffer, offset: [2]i32) {
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
	freq:                 u32,
	volume:               f32, // 0.0 - 1.0
	wave_period:          u32,
	bytes_per_sample:     u32,
	buffer_size:          u32,
	running_sample_index: u32,
}

fill_sound_buffer :: proc(sound_output: ^Sound_Output, byte_to_lock: u32, bytes_to_write: u32) {
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

	sample_out := cast(^i16)region1
	region1_sample_count := region1_size / BYTES_PER_SAMPLE
	for sample_index: win.DWORD; sample_index < region1_sample_count; sample_index += 1 {

		t :=
			math.TAU *
			cast(f32)sound_output.running_sample_index /
			cast(f32)sound_output.wave_period
		sine_value: f32 = math.sin(t)

		sample_value := cast(i16)(sine_value * sound_output.volume * cast(f32)(2 << 14))

		left := sample_value
		right := sample_value

		sample_out^ = left
		sample_out = mem.ptr_offset(sample_out, 1)

		sample_out^ = right
		sample_out = mem.ptr_offset(sample_out, 1)
		sound_output.running_sample_index += 1
	}


	sample_out = cast([^]i16)region2
	region2_sample_count := region2_size / BYTES_PER_SAMPLE
	for sample_index: win.DWORD; sample_index < region2_sample_count; sample_index += 1 {

		t :=
			math.TAU *
			cast(f32)sound_output.running_sample_index /
			cast(f32)sound_output.wave_period
		sine_value: f32 = math.sin(t)

		sample_value := cast(i16)(sine_value * sound_output.volume * math.F16_MAX)

		left := sample_value
		right := sample_value

		sample_out^ = left
		sample_out = mem.ptr_offset(sample_out, 1)

		sample_out^ = right
		sample_out = mem.ptr_offset(sample_out, 1)
		sound_output.running_sample_index += 1
	}

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

	freq: u32 = 256
	sound_output: Sound_Output = {
		sample_rate          = SAMPLE_RATE,
		freq                 = freq,
		wave_period          = SAMPLE_RATE / freq,
		volume               = 0.4,
		bytes_per_sample     = BYTES_PER_SAMPLE,
		buffer_size          = audio_buffer_size,
		running_sample_index = 0,
	}


	fill_sound_buffer(&sound_output, 0, sound_output.buffer_size)
	global_audio_buffer.Play(global_audio_buffer, 0, 0, DSBPLAY_LOOPING)


	for res > 0 && global_running {
		for win.PeekMessageA(&msg, nil, 0, 0, win.PM_REMOVE) {
			if msg.message == win.WM_QUIT {
				global_running = false
			}

			win.TranslateMessage(&msg)
			win.DispatchMessageW(&msg)
		}

		for controller_index: win.DWORD;
		    controller_index < win.XUSER_MAX_COUNT;
		    controller_index += 1 {
			state: win.XINPUT_STATE
			res := xinput_get_state(win.XUSER(controller_index), &state)
			if (res == .SUCCESS) {
				// controller is there
				pad := state.Gamepad
				if .A in pad.wButtons {
					vib := win.XINPUT_VIBRATION {
						wLeftMotorSpeed  = u16(6000),
						wRightMotorSpeed = u16(6000),
					}
					xinput_set_state(win.XUSER(controller_index), &vib)
				} else {
					vib := win.XINPUT_VIBRATION {
						wLeftMotorSpeed  = u16(0),
						wRightMotorSpeed = u16(0),
					}
					xinput_set_state(win.XUSER(controller_index), &vib)
				}

				offset.x += i32(pad.sThumbLX) / 2048
				offset.y -= i32(pad.sThumbLY) / 2048
			} else {
				// no controller :(
			}
		}

		offset.xy += 1

		render_gradient(&global_back_buffer, offset)
		dc := win.GetDC(window)

		play_cursor: win.DWORD
		write_cursor: win.DWORD
		global_audio_buffer.GetCurrentPosition(global_audio_buffer, &play_cursor, &write_cursor)

		byte_to_lock :=
			(sound_output.running_sample_index * sound_output.bytes_per_sample) %
			sound_output.buffer_size

		bytes_to_write: u32 = 0

		// [??????P--------Bwwwwwwwwwww]
		if byte_to_lock > play_cursor {
			bytes_to_write = sound_output.buffer_size - byte_to_lock
		}
		// [---BwwwwwwwwP--------------]
		if byte_to_lock < play_cursor {
			bytes_to_write = play_cursor - byte_to_lock
		}
		fill_sound_buffer(&sound_output, byte_to_lock, bytes_to_write)


		dims := dimensions(window)
		display_buffer(dc, dims, &global_back_buffer)
		win.ReleaseDC(window, dc)
	}

	os.exit(cast(int)msg.wParam)
}
