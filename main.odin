package handmade_odin

import "base:runtime"
import "core:fmt"
import "core:mem"
import os "core:os"
import win "core:sys/windows"

// I use `dims` to mean the dimensions of a thing
// so dims.x is with and dims.y is height

load_win_proc :: proc(module: win.HMODULE, name: cstring, destination: rawptr) {
	loaded := win.GetProcAddress(module, name)
	if loaded != nil {
		dest := cast(^uintptr)(destination)
		dest^ = auto_cast loaded
	}
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
	xinput := win.LoadLibraryW(win.L("xinput1_3.dll"))
	if xinput == nil {
		fmt.println("Failed to load xinput")
		return
	}

	load_win_proc(xinput, "XInputGetState", &xinput_get_state)
	load_win_proc(xinput, "XInputSetState", &xinput_set_state)
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

buffer_resize :: proc(buf: ^Offscreen_Buffer, dims: [2]i32) {
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
			win.MEM_COMMIT,
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
		is_bit_set :: #force_inline proc(mask: u32, bit: u32) -> bool {
			when ODIN_DEBUG {assert(bit < 32)}
			return (mask & (1 << bit)) != 0
		}

		IS_UP_BIT :: 31
		WAS_DOWN_BIT :: 30

		keycode := wparam
		key_parameters := u32(lparam)
		was_down: bool = is_bit_set(key_parameters, WAS_DOWN_BIT)
		is_down: bool = !is_bit_set(key_parameters, IS_UP_BIT)

		if (was_down != is_down) { 	// filter repeats
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

main :: proc() {
	instance, lpCmdLine, startup_info := kinda_winmain()
	window := create_window(instance)
	xinput_load()

	buffer_resize(&global_back_buffer, {1280, 720})


	global_running = true
	msg: win.MSG
	res: win.LRESULT = 1
	offset: [2]i32 = {0, 0}

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

		dims := dimensions(window)
		display_buffer(dc, dims, &global_back_buffer)
		win.ReleaseDC(window, dc)
	}

	os.exit(cast(int)msg.wParam)
}
