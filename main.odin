package handmade_odin

import "base:runtime"
import fmt "core:fmt"
import os "core:os"
import win "core:sys/windows"

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

	// win.ShowWindow(hwnd, nCmdShow)
	// win.UpdateWindow(hwnd)

	msg: win.MSG

	for win.GetMessageW(&msg, nil, 0, 0) > 0 {
		win.TranslateMessage(&msg)
		win.DispatchMessageW(&msg)
	}

	os.exit(cast(int)msg.wParam)
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
