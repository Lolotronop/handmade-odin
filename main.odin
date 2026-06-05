package handmade_odin

import "base:runtime"
import fmt "core:fmt"
import os "core:os"
import win "core:sys/windows"

running := false


bitmap_info: win.BITMAPINFO = {}
bitmap_memory: rawptr = nil
bitmap_hanle: win.HBITMAP = nil

bitmap_device_context: win.HDC

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
	for res > 0 && running {
		win.GetMessageW(&msg, nil, 0, 0)
		win.TranslateMessage(&msg)
		win.DispatchMessageW(&msg)
	}

	os.exit(cast(int)msg.wParam)
}

resize_dib_section :: proc(width, height: i32) {
	if (bitmap_hanle != nil) {
		win.DeleteObject(cast(win.HGDIOBJ)bitmap_hanle)
		bitmap_hanle = nil
	}

	if (bitmap_device_context == nil) {
		bitmap_device_context = win.CreateCompatibleDC(nil)
	}

	bitmap_info.bmiHeader.biSize = size_of(win.BITMAPINFO)
	bitmap_info.bmiHeader.biWidth = width
	bitmap_info.bmiHeader.biHeight = height
	bitmap_info.bmiHeader.biPlanes = 1
	bitmap_info.bmiHeader.biBitCount = 32
	bitmap_info.bmiHeader.biCompression = win.BI_RGB

	bitmap_hanle = win.CreateDIBSection(
		bitmap_device_context,
		&bitmap_info,
		win.DIB_RGB_COLORS,
		&bitmap_memory,
		nil,
		0,
	)
}

update_window :: proc(device_context: win.HDC, x, y, width, height: i32) {
	win.StretchDIBits(
		device_context,
		x,
		y,
		width,
		height,
		x,
		y,
		width,
		height,
		nil,
		nil,
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

	fmt.printfln("Message: %v %v", message, wparam)

	res: win.LRESULT

	switch (message) {
	case win.WM_SIZE:
		rect: win.RECT
		win.GetClientRect(window, &rect)
		width := rect.right - rect.left
		height := rect.bottom - rect.top
		resize_dib_section(width, height)
	case win.WM_DESTROY:
	case win.WM_CLOSE:
		running = false
	case win.WM_PAINT:
		paint: win.PAINTSTRUCT
		ctx := win.BeginPaint(window, &paint)
		rect := paint.rcPaint
		width := rect.right - rect.left
		height := rect.bottom - rect.top
		win.PatBlt(ctx, rect.left, rect.top, width, height, win.WHITENESS)
		win.EndPaint(window, &paint)
	}

	res = win.DefWindowProcW(window, message, wparam, lparam)
	return res
}
