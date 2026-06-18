package platform

import "core:fmt"
import "core:slice"
import win "core:sys/windows"

DEBUG_read_entire_file :: proc(filename: string) -> (data: []u8, ok: bool) #optional_ok {
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

DEBUG_free_file_memory :: proc(memory: []u8) {
	assert(ODIN_DEBUG)
	win.VirtualFree(&memory[0], 0, win.MEM_RELEASE)
}

DEBUG_write_entire_file :: proc(filename: string, data: []u8) {
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
