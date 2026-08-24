package handmade_odin

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

	when ODIN_DEBUG {
		if loaded == nil {
			DEBUG_printf("Failed to load %cs", name)
		}
	}

	if loaded != nil {
		dest := cast(^uintptr)(destination)
		dest^ = auto_cast loaded
		return true
	}

	return false
}

Game_Code :: struct {
	update_step:         type_of(game.update_step),
	update_audio:        type_of(game.update_audio),
	module:              win.HMODULE,
	is_valid:            bool,
	dll_last_write_time: i64,
}

cat_string16 :: proc(sourceA: string16, sourceB: string16, dest: []u16) -> int {
	assert(len(sourceA) + len(sourceB) <= len(dest))
	for c, i in transmute([]u16)(sourceA) {dest[i] = c}
	for c, i in transmute([]u16)(sourceB) {dest[i + len(sourceA)] = c}
	return len(sourceA) + len(sourceB)
}


get_exe_path :: proc(platform_state: ^Platform_State) {
	len := win.GetModuleFileNameW(
		nil,
		&platform_state.EXE_file_name[0],
		u32(len(platform_state.EXE_file_name)),
	)

	full_path := string16(platform_state.EXE_file_name[:len])
	platform_state.one_past_last_slash = full_path

	for rune, i in full_path {
		if rune == '\\' {
			platform_state.one_past_last_slash = full_path[:i + 1]
		}
	}
}

build_exe_path_filename :: proc(
	platform_state: ^Platform_State,
	filename: string16,
	dest: []u16,
) -> int {
	return cat_string16(platform_state.one_past_last_slash, filename, dest)
}


load_game_code :: proc(platform_state: ^Platform_State, lib: ^Game_Code) -> (ok: bool) {
	SOURCE_DLL_NAME :: "handmade-odin-lib.dll"
	source_buf: [win.MAX_PATH]u16
	build_exe_path_filename(platform_state, SOURCE_DLL_NAME, source_buf[:])
	source_dll_full_path := cstring16(&source_buf[0])

	TEMP_DLL_NAME :: "handmade-odin-running-lib.dll"
	temp_buf: [win.MAX_PATH]u16
	build_exe_path_filename(platform_state, TEMP_DLL_NAME, temp_buf[:])
	temp_dll_full_path := cstring16(&temp_buf[0])

	time := get_file_time(source_dll_full_path)

	if time <= lib.dll_last_write_time {
		return true
	}

	if lib.module != nil {
		lib.update_audio = nil
		lib.update_step = nil
		lib.is_valid = false

		// TODO: this does not unload the dll instantly
		// because of that, CopyFileW call fails on the same frame.
		// it will eventually work after a couple of frames tho
		if !win.FreeLibrary(lib.module) {
			DEBUG_printfln("Failed to free library,\n err: %s", DEBUG_get_win_error())
			return false
		}
		lib.module = nil
	}

	if win.CopyFileW(source_dll_full_path, temp_dll_full_path, false) == false {
		DEBUG_printfln(
			"Failed to copy try %s to %s,\n err: %s",
			SOURCE_DLL_NAME,
			TEMP_DLL_NAME,
			DEBUG_get_win_error(),
		)
	}

	new_module := win.LoadLibraryW(win.L(TEMP_DLL_NAME))
	if new_module == nil {
		DEBUG_printfln("Failed to load %s", TEMP_DLL_NAME)
		return false
	}
	lib.module = new_module

	defer if lib.is_valid != true && lib.module != nil {
		win.FreeLibrary(lib.module)
	}

	load_win_proc(lib.module, "update_step", &lib.update_step) or_return
	load_win_proc(lib.module, "update_audio", &lib.update_audio) or_return

	lib.is_valid = true
	lib.dll_last_write_time = time

	return true
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

load_xinput :: proc() {
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
		DEBUG_println("Failed to load xinput")
		return
	}

	load_win_proc(xinput, "XInputGetState", &xinput_get_state)
	load_win_proc(xinput, "XInputSetState", &xinput_set_state)
}

load_dsound :: proc() -> (ok: bool) {
	ok = false

	dsound := win.LoadLibraryW(win.L("dsound.dll"))
	if dsound == nil {
		DEBUG_println("Failed to load dsound")
		return
	}

	load_win_proc(dsound, "DirectSoundCreate", &direct_sound_create) or_return

	return true
}


global_audio_buffer: LPDIRECTSOUNDBUFFER


dsound_init :: proc(window: win.HWND, samplerate: u32, buffer_size: u32) {
	if !load_dsound() {
		DEBUG_println("Failed to load dsound")
		return
	}

	ds: LPDIRECTSOUND

	direct_sound_create(nil, &ds, nil)

	if res := ds.SetCooperativeLevel(ds, window, DSSCL_PRIORITY); res != 0 {
		DEBUG_printfln("Failed to set cooperative level 0x%x", u32(res))
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
		DEBUG_printfln("Failed to create primary buffer 0x%x", u32(res))
		return
	}
	if res := primary_buffer.SetFormat(primary_buffer, &format); res != 0 {
		DEBUG_printfln("Failed to set format 0x%x", u32(res))
		return
	}
	// ----------------------------------------------

	buffer_description := DSBUFFERDESC {
		dwSize        = size_of(DSBUFFERDESC),
		dwBufferBytes = buffer_size,
		lpwfxFormat   = &format,
	}

	if res := ds.CreateSoundBuffer(ds, &buffer_description, &global_audio_buffer, nil); res != 0 {
		DEBUG_printfln("Failed to create secondary buffer 0x%x", u32(res))
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
		buf.width,
		buf.height,
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
	safety_bytes:         u32,
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

Kilabytes :: #force_inline proc($kb: u64) -> (bytes: u64) {return kb * 1024}
Megabytes :: #force_inline proc($mb: u64) -> (bytes: u64) {return mb * 1024 * 1024}
Gigabytes :: #force_inline proc($gb: u64) -> (bytes: u64) {return gb * 1024 * 1024 * 1024}

win_alloc :: proc(#any_int size: uint, large_pages: bool = false) -> []byte {
	flags: win.DWORD = win.MEM_COMMIT | win.MEM_RESERVE
	if large_pages {
		flags |= win.MEM_LARGE_PAGES
	}
	allocated := win.VirtualAlloc(nil, size, flags, win.PAGE_READWRITE)
	assert(allocated != nil)
	return slice.bytes_from_ptr(allocated, int(size))
}

global_perf_freq: win.LARGE_INTEGER = 0

STATE_FILE_NAME_COUNT :: win.MAX_PATH

Input_Replay_Buffer :: struct {
	file_handle:  win.HANDLE,
	map_handle:   win.HANDLE,
	filename:     [STATE_FILE_NAME_COUNT]u16,
	memory_block: []byte,
}

Platform_State :: struct {
	recording_handle:     win.HANDLE,
	playback_handle:      win.HANDLE,
	input_recoding_index: i32,
	input_playing_index:  i32,
	game_memory_block:    []byte,
	replay_buffers:       [4]Input_Replay_Buffer,
	EXE_file_name:        [STATE_FILE_NAME_COUNT]u16,
	one_past_last_slash:  string16,
}

get_input_file_location :: proc(platform_state: ^Platform_State, index: i32, dest: []u16) -> int {
	assert(index < len(platform_state.replay_buffers))
	temp: [64]byte
	fmt.bprintf(temp[:], "loop_edit_%d.hmi", index)
	temp2: [64]u16

	_ = win.utf8_to_utf16_buf(temp2[:], string(temp[:]))

	return build_exe_path_filename(platform_state, string16(temp2[:]), dest)
}

get_replay_buffer :: proc(platform_state: ^Platform_State, index: i32) -> ^Input_Replay_Buffer {
	assert(index < len(platform_state.replay_buffers))
	return &platform_state.replay_buffers[index]
}

begin_recording_input :: proc(platform_state: ^Platform_State, index: i32) {
	assert(index < len(platform_state.replay_buffers))
	platform_state.input_recoding_index = index
	replay_buffer := get_replay_buffer(platform_state, index)
	platform_state.recording_handle = replay_buffer.file_handle
	total_size := len(platform_state.game_memory_block)

	assert(total_size < 1 << 32)

	win.SetFilePointerEx(
		platform_state.recording_handle,
		win.LARGE_INTEGER(total_size),
		nil,
		win.FILE_BEGIN,
	)

	mem.copy(&replay_buffer.memory_block[0], &platform_state.game_memory_block[0], total_size)
}

end_recording_input :: proc(platform_state: ^Platform_State) {
	// win.CloseHandle(platform_state.recording_handle)
	platform_state.recording_handle = win.INVALID_HANDLE
	platform_state.input_recoding_index = 0
}

begin_input_playback :: proc(platform_state: ^Platform_State, index: i32) {
	replay_buffer := get_replay_buffer(platform_state, index)
	platform_state.input_playing_index = index
	platform_state.playback_handle = replay_buffer.file_handle
	total_size := len(platform_state.game_memory_block)

	win.SetFilePointerEx(
		platform_state.playback_handle,
		win.LARGE_INTEGER(total_size),
		nil,
		win.FILE_BEGIN,
	)

	mem.copy(&platform_state.game_memory_block[0], &replay_buffer.memory_block[0], total_size)
}

end_playback_input :: proc(platform_state: ^Platform_State) {
	// win.CloseHandle(platform_state.playback_handle)

	win.SetFilePointerEx(platform_state.playback_handle, 0, nil, win.FILE_BEGIN)
	platform_state.playback_handle = win.INVALID_HANDLE
	platform_state.input_playing_index = 0
}


record_input :: proc(platform_state: ^Platform_State, new_input: ^game.Input) {
	bytes_written: win.DWORD
	win.WriteFile(
		platform_state.recording_handle,
		new_input,
		size_of(game.Input),
		&bytes_written,
		nil,
	)
}


playback_input :: proc(platform_state: ^Platform_State, input: ^game.Input) {
	bytes_read: win.DWORD
	win.ReadFile(platform_state.playback_handle, input, size_of(game.Input), &bytes_read, nil)
	if bytes_read != size_of(game.Input) {
		playing_index := platform_state.input_playing_index
		end_playback_input(platform_state)
		begin_input_playback(platform_state, playing_index)
		win.ReadFile(platform_state.playback_handle, input, size_of(game.Input), &bytes_read, nil)
	}
}


process_keyboard :: proc(new_state: ^game.Input_Button, is_down: bool) {
	if new_state.ended_down != is_down {
		new_state.ended_down = is_down
		new_state.half_transition_count += 1
	}
}


main :: proc() {
	instance, lpCmdLine, startup_info := kinda_winmain()
	_ = lpCmdLine
	_ = startup_info

	assert(win.timeBeginPeriod(1) == win.TIMERR_NOERROR) // 1ms timer resolution
	win.QueryPerformanceFrequency(&global_perf_freq)

	global_running = true
	msg: win.MSG
	res: win.LRESULT = 1


	platform_state := Platform_State{}
	get_exe_path(&platform_state)


	game_lib: Game_Code = {}
	load_game_code(&platform_state, &game_lib)
	window := create_window(instance)

	monitor_refresh_rate: i32 = 60
	dc := win.GetDC(window)
	VREFRESH :: 116
	rate := win.GetDeviceCaps(dc, VREFRESH)
	win.ReleaseDC(window, dc)
	if rate > 1 {
		monitor_refresh_rate = rate
	}
	game_update_hz := u32(monitor_refresh_rate)
	game_update_hz = 30 // TODO: fix audio to work with higher fps
	target_ms_per_frame: f32 = 1000 / f32(game_update_hz)

	load_xinput()
	audio_buffer_size: u32 = SAMPLE_RATE * BYTES_PER_SAMPLE
	dsound_init(window, SAMPLE_RATE, audio_buffer_size)
	offscreen_buffer_resize(&global_back_buffer, {960, 540})

	sound_output: Sound_Output = {
		sample_rate          = SAMPLE_RATE,
		bytes_per_sample     = BYTES_PER_SAMPLE,
		buffer_size          = audio_buffer_size,
		running_sample_index = 0,
		latency_samples      = SAMPLE_RATE / u32(game_update_hz),
		safety_bytes         = (SAMPLE_RATE * BYTES_PER_SAMPLE) / u32(game_update_hz) / 3,
	}
	audio_buf := slice.reinterpret([]game.Sound_Sample, win_alloc(sound_output.buffer_size))
	sound_is_valid := false

	global_audio_buffer.Play(global_audio_buffer, 0, 0, DSBPLAY_LOOPING)

	permament_size := Megabytes(64)
	transient_size := Gigabytes(1)
	total_size := permament_size + transient_size

	platform_state.game_memory_block = win_alloc(total_size, large_pages = false)

	game_memory := game.Memory{}
	game_memory.permament = platform_state.game_memory_block[:permament_size]
	game_memory.transient = platform_state.game_memory_block[permament_size:permament_size +
	transient_size]

	for &replay_buffer, i in platform_state.replay_buffers {
		_ = get_input_file_location(&platform_state, i32(i), replay_buffer.filename[:])
		DEBUG_printfln("filename: %s", cstring16(&replay_buffer.filename[0]))

		replay_buffer.file_handle = win.CreateFileW(
			cstring16(&replay_buffer.filename[0]),
			win.GENERIC_READ | win.GENERIC_WRITE,
			0,
			nil,
			win.CREATE_ALWAYS,
			0,
			nil,
		)

		max_size_high := u32(total_size >> 32)
		max_size_low := u32(total_size & 0xffffffff)
		replay_buffer.map_handle = win.CreateFileMappingW(
			replay_buffer.file_handle,
			nil,
			win.PAGE_READWRITE,
			max_size_high,
			max_size_low,
			nil,
		)

		memory := win.MapViewOfFile(
			replay_buffer.map_handle,
			win.FILE_MAP_ALL_ACCESS,
			0,
			0,
			uint(total_size),
		)
		replay_buffer.memory_block = slice.bytes_from_ptr(memory, int(total_size))
	}


	old_input := game.Input{}

	end_counter: win.LARGE_INTEGER
	last_counter := get_wall_clock()
	flip_wall_clock := get_wall_clock()

	thread: game.Thread_Context
	for res > 0 && global_running {
		load_game_code(&platform_state, &game_lib)
		// =============================
		// ========= READ INPUT ========
		// =============================
		new_input := game.Input {
			ms_to_advance_over_update = target_ms_per_frame,
		}

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

					if keycode == 'W' {process_keyboard(&new.move_up, is_down)}
					if keycode == 'A' {process_keyboard(&new.move_left, is_down)}
					if keycode == 'S' {process_keyboard(&new.move_down, is_down)}
					if keycode == 'D' {process_keyboard(&new.move_right, is_down)}
					if keycode == 'E' {process_keyboard(&new.a, is_down)}
					if keycode == 'Q' {process_keyboard(&new.b, is_down)}

					if keycode == 'L' && is_down {
						if platform_state.input_recoding_index == 0 &&
						   platform_state.input_playing_index == 0 {
							begin_recording_input(&platform_state, 1)
						} else if platform_state.input_recoding_index != 0 {
							end_recording_input(&platform_state)
							begin_input_playback(&platform_state, 1)
						} else if platform_state.input_playing_index != 0 {
							end_playback_input(&platform_state)
							new_input = game.Input{}
						}
					}
				}
			case:
				win.TranslateMessage(&msg)
				win.DispatchMessageW(&msg)
			}

		}

		mouse_location: win.POINT
		win.GetCursorPos(&mouse_location)
		win.ScreenToClient(window, &mouse_location)
		new_input.mouse.x = mouse_location.x
		new_input.mouse.y = mouse_location.y

		// for &button in new_input.mouse_buttons.buttons {
		// 	button.ended_down = false
		// 	button.half_transition_count = 0
		// }

		mouse_keystate :: proc(code: i32) -> bool {
			val := win.GetKeyState(code)
			return transmute(u16)val & u16(1 << 15) != 0
		}

		process_keyboard(&new_input.mouse_buttons.left, mouse_keystate(win.VK_LBUTTON))
		process_keyboard(&new_input.mouse_buttons.right, mouse_keystate(win.VK_RBUTTON))
		process_keyboard(&new_input.mouse_buttons.middle, mouse_keystate(win.VK_MBUTTON))
		process_keyboard(&new_input.mouse_buttons.back, mouse_keystate(win.VK_XBUTTON1))
		process_keyboard(&new_input.mouse_buttons.forward, mouse_keystate(win.VK_XBUTTON2))

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

			new.is_analog = old.is_analog
			if new.stick_x != 0 || new.stick_y != 0 {
				new.is_analog = true
			}
			if bits.DPAD_LEFT | bits.DPAD_UP | bits.DPAD_DOWN | bits.DPAD_RIGHT in pad.wButtons {
				new.is_analog = false
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
		// ========= PREPARE THE VIDEO FRAME ======
		// ========================================

		game_video_buffer := game.Offscreen_Buffer {
			pixels       = slice.reinterpret([]game.Pixel, global_back_buffer.memory),
			width        = global_back_buffer.width,
			height       = global_back_buffer.height,
			pitch_pixels = global_back_buffer.pitch_bytes / global_back_buffer.bytes_per_pixel,
		}

		if platform_state.input_recoding_index != 0 {
			record_input(&platform_state, &new_input)
		}
		if platform_state.input_playing_index != 0 {
			playback_input(&platform_state, &new_input)
		}
		if game_lib.update_step != nil {
			game_lib.update_step(&thread, &game_memory, &new_input, &game_video_buffer)
		}


		// ========================================
		// ========= OUTPUT AUDIO =================
		// ========================================

		audio_wall_clock := get_wall_clock()
		from_begin_to_audio_ms := elapsed_ms(flip_wall_clock, audio_wall_clock)

		play_cursor: win.DWORD
		write_cursor: win.DWORD
		if global_audio_buffer.GetCurrentPosition(
			   global_audio_buffer,
			   &play_cursor,
			   &write_cursor,
		   ) ==
		   DS_OK {
			if sound_is_valid == false {
				sound_output.running_sample_index =
					write_cursor / sound_output.bytes_per_sample + sound_output.latency_samples
			}

			byte_to_lock := sound_output.running_sample_index * sound_output.bytes_per_sample
			byte_to_lock %= sound_output.buffer_size

			expected_sound_bytes_per_frame :=
				(sound_output.sample_rate * sound_output.bytes_per_sample) / game_update_hz
			ms_left_until_flip := target_ms_per_frame - from_begin_to_audio_ms
			expected_bytes_until_flip := u32(
				(ms_left_until_flip / target_ms_per_frame) * f32(expected_sound_bytes_per_frame),
			)

			expected_frame_boundary_byte := play_cursor + expected_bytes_until_flip
			safe_write_cursor := write_cursor
			if safe_write_cursor < play_cursor {
				safe_write_cursor += sound_output.buffer_size
			}
			assert(safe_write_cursor >= play_cursor)
			safe_write_cursor += sound_output.safety_bytes
			audio_card_is_low_latency := safe_write_cursor < expected_frame_boundary_byte

			target_cursor: u32
			if audio_card_is_low_latency {
				target_cursor = expected_frame_boundary_byte + expected_sound_bytes_per_frame
			} else {
				target_cursor =
					write_cursor + expected_sound_bytes_per_frame + sound_output.safety_bytes
			}
			target_cursor %= sound_output.buffer_size

			bytes_to_write: u32
			// [??????P--------Bwwwwwwwwwww]
			if byte_to_lock > target_cursor {
				bytes_to_write = sound_output.buffer_size - byte_to_lock
				bytes_to_write += target_cursor
			}

			// // [---BwwwwwwwwP--------------]
			if byte_to_lock < target_cursor {
				bytes_to_write = target_cursor - byte_to_lock
			}

			sample_count := bytes_to_write / sound_output.bytes_per_sample


			game_sound_buffer := game.Sound_Output_Buffer {
				samples     = audio_buf[:sample_count],
				sample_rate = sound_output.sample_rate,
			}

			if game_lib.update_audio != nil {
				game_lib.update_audio(&thread, &game_memory, &game_sound_buffer)
			}
			fill_sound_buffer(&sound_output, byte_to_lock, bytes_to_write, &game_sound_buffer)


			sound_is_valid = true
		} else {
			sound_is_valid = false
		}


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
			DEBUG_printfln("Warning: frame took %.2fms", perf_ms)
			sound_is_valid = false
		}
		end_counter = get_wall_clock()
		last_counter = end_counter

		// ========================================
		// ========= DISPLAY THE FRAME ============
		// ========================================

		when false && ODIN_DEBUG {
			{
				pad_x: i32 = 16
				pad_y: i32 = 16

				top := pad_y
				bottom := (global_back_buffer.height - pad_y) / 10

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
				blue :: game.Pixel {
					b = u8(255),
					g = u8(0),
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

				x_curr_play := pad_x + i32(C * f32(play_cursor))
				draw_vertical_line(&global_back_buffer, x_curr_play, top, bottom, white, 10)

				x_curr_write := pad_x + i32(C * f32(write_cursor))
				draw_vertical_line(&global_back_buffer, x_curr_write, top, bottom, purple, 6)

				x_runn_write :=
					pad_x +
					i32(
						C *
						f32(
							(sound_output.running_sample_index * sound_output.bytes_per_sample) %
							u32(audio_buffer_size),
						),
					)
				draw_vertical_line(&global_back_buffer, x_runn_write, top, bottom, blue, 4)

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
							clamped := clamp(x + i, 0, buf.width - 1)
							pixels[clamped + y * pitch] = color
						}
					}
				}
			}
		}

		{
			dc = win.GetDC(window)
			defer win.ReleaseDC(window, dc)

			dims := dimensions(window)
			display_buffer(dc, dims, &global_back_buffer)
			flip_wall_clock = get_wall_clock()
		}

		// ==========================================
		// ========= SWITCH BUFFERS N THINGS ========
		// ==========================================
		old_input = new_input

		free_all(context.temp_allocator)
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

get_file_time :: proc(filename: cstring16) -> (time: i64) {
	file_info: win.WIN32_FILE_ATTRIBUTE_DATA
	assert(win.GetFileAttributesExW(filename, win.GetFileExInfoStandard, &file_info) == true)
	return win.FILETIME_as_unix_nanoseconds(file_info.ftLastWriteTime)
}

DEBUG_get_win_error :: proc() -> string16 {
	err := win.GetLastError()
	buf := make([]u16, 1024, allocator = context.temp_allocator)
	len := win.FormatMessageW(
		win.FORMAT_MESSAGE_FROM_SYSTEM | win.FORMAT_MESSAGE_IGNORE_INSERTS,
		nil,
		err,
		win.MAKELANGID(win.LANG_NEUTRAL, win.SUBLANG_DEFAULT),
		&buf[0],
		u32(len(buf)),
		nil,
	)
	return string16(buf[:len])
}

// TODO: make a struct with function pointers passed to a game for these
DEBUG_print :: proc(str: string) {
	out := win.utf8_to_wstring_alloc(str, context.temp_allocator)
	win.OutputDebugStringW(out)
}

DEBUG_println :: proc(str: string) {
	DEBUG_print(str)
	DEBUG_print("\n")
}

DEBUG_printf :: proc(format: string, args: ..any) {
	str := fmt.tprintf(format, ..args)
	DEBUG_print(str)
}

DEBUG_printfln :: proc(format: string, args: ..any) {
	str := fmt.tprintfln(format, ..args)
	DEBUG_print(str)
}

DEBUG_read_entire_file :: proc(
	thread: game.Thread_Context,
	filename: string,
) -> (
	data: []u8,
	ok: bool,
) #optional_ok {
	assert(ODIN_DEBUG)

	ok = false
	wide := win.utf8_to_wstring(filename)
	file_handle := win.CreateFileW(
		wide,
		win.GENERIC_READ,
		win.FILE_SHARE_READ,
		nil,
		win.OPEN_EXISTING,
		win.FILE_ATTRIBUTE_NORMAL,
		nil,
	)
	defer win.CloseHandle(file_handle)

	assert(file_handle != win.INVALID_HANDLE_VALUE)

	file_size: win.LARGE_INTEGER
	assert(file_size <= 1 << 32 - 1)
	assert(win.GetFileSizeEx(file_handle, &file_size) == true)

	result := win.VirtualAlloc(nil, win.SIZE_T(file_size), win.MEM_COMMIT, win.PAGE_READWRITE)
	assert(result != nil)
	defer if !ok {
		win.VirtualFree(result, 0, win.MEM_RELEASE)
	}

	bytes_read: win.DWORD
	assert(
		win.ReadFile(file_handle, result, win.DWORD(file_size), &bytes_read, nil) == true,
		fmt.tprintf("Failed to read file %s", filename),
	)
	assert(bytes_read == u32(file_size))

	return slice.bytes_from_ptr(result, int(file_size)), true
}

DEBUG_free_file_memory :: proc(thread: ^game.Thread_Context, memory: []u8) {
	assert(ODIN_DEBUG)
	win.VirtualFree(&memory[0], 0, win.MEM_RELEASE)
}

DEBUG_write_entire_file :: proc(thread: ^game.Thread_Context, filename: string, data: []u8) {
	assert(ODIN_DEBUG)

	handle := win.CreateFileW(
		win.utf8_to_wstring(filename),
		win.GENERIC_WRITE,
		0,
		nil,
		win.CREATE_ALWAYS,
		0,
		nil,
	)
	defer win.CloseHandle(handle)
	assert(handle != win.INVALID_HANDLE_VALUE)

	bytes_written: win.DWORD
	win.WriteFile(handle, &data[0], win.DWORD(len(data)), &bytes_written, nil)

	assert(bytes_written == u32(len(data)))
}
