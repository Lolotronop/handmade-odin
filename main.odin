package handmade_odin

import "base:runtime"
import fmt "core:fmt"
import "core:mem"
import os "core:os"
import win "core:sys/windows"

running := false


bitmap_info: win.BITMAPINFO = {}
bitmap_memory: [^]u8 = nil

main :: proc() {
	instance := win.HINSTANCE(win.GetModuleHandleW(nil))
	assert(instance != nil, "Failed to fetch current instance")

	lpCmdLine := win.GetCommandLineW()
	fmt.printfln("Command line used to start this application was: %v", lpCmdLine)

	startup_info: win.STARTUPINFOW
	win.GetStartupInfoW(&startup_info)
	nCmdShow :=
		(startup_info.dwFlags & win.STARTF_USESHOWWINDOW) != 0 ? cast(win.c_int)startup_info.wShowWindow : win.SW_SHOWDEFAULT

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

	assert(hwnd != nil, "Window creation Failed")

	running = true

	// win.ShowWindow(hwnd, nCmdShow)
	// win.UpdateWindow(hwnd)

	msg: win.MSG


	res: win.LRESULT = 1

	offset_x: i32 = 0
	offset_y: i32 = 0
	for res > 0 && running {
		for win.PeekMessageA(&msg, nil, 0, 0, win.PM_REMOVE) {
			if msg.message == win.WM_QUIT {
				running = false
			}

			win.TranslateMessage(&msg)
			win.DispatchMessageW(&msg)
		}

		offset_x += 1
		offset_y += 1

		if offset_x >= 256 {
			offset_x = 0
		}
		if offset_y >= 256 {
			offset_y = 0
		}

		width := cast(i32)bitmap_info.bmiHeader.biWidth
		height := -cast(i32)bitmap_info.bmiHeader.biHeight

		render_gradient(width, height, offset_x, offset_y)
		rect: win.RECT
		win.GetClientRect(hwnd, &rect)
		dc := win.GetDC(hwnd)
		update_window(dc, rect, 0, 0, width, height)
		win.ReleaseDC(hwnd, dc)
	}

	os.exit(cast(int)msg.wParam)
}


resize_dib_section :: proc(width, height: i32) {
	if (bitmap_memory != nil) {
		win.VirtualFree(bitmap_memory, 0, win.MEM_RELEASE)
	}

	bitmap_info.bmiHeader.biSize = size_of(win.BITMAPINFO)
	bitmap_info.bmiHeader.biWidth = width
	bitmap_info.bmiHeader.biHeight = -height
	bitmap_info.bmiHeader.biPlanes = 1
	bitmap_info.bmiHeader.biBitCount = 32
	bitmap_info.bmiHeader.biCompression = win.BI_RGB

	err: mem.Allocator_Error
	bitmap_size: uint = uint(width) * uint(height) * 4
	bitmap_memory = cast([^]u8)(win.VirtualAlloc(
			nil,
			bitmap_size,
			win.MEM_COMMIT,
			win.PAGE_READWRITE,
		))

	// render_gradient(width, height, 128, 0)
}

render_gradient :: proc(width, height, offset_x, offset_y: i32) {
	pitch := width * 4
	row := bitmap_memory

	for y in 0 ..< height {
		pixel := cast([^]u32)row
		for x in 0 ..< width {
			r := u8(x + offset_x)
			g := u8(y + offset_y)
			b := u8(0)

			pixel[0] = u32(r) << 8 | u32(g) << 16 | u32(b) << 24

			pixel = mem.ptr_offset(pixel, 1)
		}
		row = mem.ptr_offset(row, pitch)
	}
}

update_window :: proc(device_context: win.HDC, window_rect: win.RECT, x, y, width, height: i32) {
	bitmap_width := bitmap_info.bmiHeader.biWidth
	bitmap_height := -bitmap_info.bmiHeader.biHeight
	window_width := window_rect.right - window_rect.left
	window_height := window_rect.bottom - window_rect.top

	win.StretchDIBits(
		device_context,
		0,
		0,
		window_width,
		window_height,
		0,
		0,
		bitmap_width,
		bitmap_height,
		bitmap_memory,
		&bitmap_info,
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

	// fmt.printfln("Message: %v %v", message, wparam)

	res: win.LRESULT

	switch (message) {
	case win.WM_SIZE:
		rect: win.RECT
		win.GetClientRect(window, &rect)
		width := rect.right - rect.left
		height := rect.bottom - rect.top
		if (bitmap_info.bmiHeader.biWidth != width || bitmap_info.bmiHeader.biHeight != height) {
			resize_dib_section(width, height)
		}
	case win.WM_DESTROY:
	case win.WM_CLOSE:
		running = false
	case win.WM_PAINT:
		paint: win.PAINTSTRUCT
		ctx := win.BeginPaint(window, &paint)
		rect := paint.rcPaint
		width := rect.right - rect.left
		height := rect.bottom - rect.top
		// win.PatBlt(ctx, rect.left, rect.top, width, height, win.BLACKNESS)
		update_window(ctx, rect, 0, 0, width, height)
		win.EndPaint(window, &paint)
	}

	res = win.DefWindowProcW(window, message, wparam, lparam)
	return res
}
