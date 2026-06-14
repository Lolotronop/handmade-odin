package handmade_odin

import win "core:sys/windows"

// Minimal DirectSound bindings used by the platform layer.  These are kept
// here (instead of relying on a linked import library) so DirectSoundCreate can
// be patched in at runtime with LoadLibrary/GetProcAddress just like XInput.

LPDIRECTSOUND :: ^IDirectSound
LPDIRECTSOUNDBUFFER :: ^IDirectSoundBuffer

DS_OK :: win.HRESULT(0)
DSERR_GENERIC :: win.HRESULT(-2005401590) // 0x8878000A: Generic DirectSound failure.
DSERR_NODRIVER :: win.HRESULT(-2005401480) // 0x88780078: No sound driver is available.
DSERR_INVALIDPARAM :: win.HRESULT(-2005401570) // 0x8878001E

direct_sound_create := proc "stdcall" (
	pcGuidDevice: win.LPCGUID,
	pDS: ^LPDIRECTSOUND,
	pUnkOuter: win.LPUNKNOWN,
) -> win.HRESULT {
	if pDS != nil {
		pDS^ = nil
	}
	return DSERR_NODRIVER
}

DSCAPS_PRIMARYMONO :: win.DWORD(0x00000001)
DSCAPS_PRIMARYSTEREO :: win.DWORD(0x00000002)
DSCAPS_PRIMARY8BIT :: win.DWORD(0x00000004)
DSCAPS_PRIMARY16BIT :: win.DWORD(0x00000008)
DSCAPS_CONTINUOUSRATE :: win.DWORD(0x00000010)
DSCAPS_EMULDRIVER :: win.DWORD(0x00000020)
DSCAPS_CERTIFIED :: win.DWORD(0x00000040)
DSCAPS_SECONDARYMONO :: win.DWORD(0x00000100)
DSCAPS_SECONDARYSTEREO :: win.DWORD(0x00000200)
DSCAPS_SECONDARY8BIT :: win.DWORD(0x00000400)
DSCAPS_SECONDARY16BIT :: win.DWORD(0x00000800)

DSSCL_NORMAL :: win.DWORD(0x00000001)
DSSCL_PRIORITY :: win.DWORD(0x00000002)
DSSCL_EXCLUSIVE :: win.DWORD(0x00000003)
DSSCL_WRITEPRIMARY :: win.DWORD(0x00000004)

DSBCAPS_PRIMARYBUFFER :: win.DWORD(0x00000001)
DSBCAPS_STATIC :: win.DWORD(0x00000002)
DSBCAPS_LOCHARDWARE :: win.DWORD(0x00000004)
DSBCAPS_LOCSOFTWARE :: win.DWORD(0x00000008)
DSBCAPS_CTRL3D :: win.DWORD(0x00000010)
DSBCAPS_CTRLFREQUENCY :: win.DWORD(0x00000020)
DSBCAPS_CTRLPAN :: win.DWORD(0x00000040)
DSBCAPS_CTRLVOLUME :: win.DWORD(0x00000080)
DSBCAPS_CTRLPOSITIONNOTIFY :: win.DWORD(0x00000100)
DSBCAPS_GLOBALFOCUS :: win.DWORD(0x00008000)
DSBCAPS_GETCURRENTPOSITION2 :: win.DWORD(0x00010000)

DSBLOCK_FROMWRITECURSOR :: win.DWORD(0x00000001)
DSBLOCK_ENTIREBUFFER :: win.DWORD(0x00000002)

DSBPLAY_LOOPING :: win.DWORD(0x00000001)

WAVE_FORMAT_PCM :: win.WORD(1)

DSBUFFERDESC :: struct {
	dwSize:          win.DWORD,
	dwFlags:         win.DWORD,
	dwBufferBytes:   win.DWORD,
	dwReserved:      win.DWORD,
	lpwfxFormat:     ^win.WAVEFORMATEX,
	guid3DAlgorithm: win.GUID,
}

DSCAPS :: struct {
	dwSize:                         win.DWORD,
	dwFlags:                        win.DWORD,
	dwMinSecondarySampleRate:       win.DWORD,
	dwMaxSecondarySampleRate:       win.DWORD,
	dwPrimaryBuffers:               win.DWORD,
	dwMaxHwMixingAllBuffers:        win.DWORD,
	dwMaxHwMixingStaticBuffers:     win.DWORD,
	dwMaxHwMixingStreamingBuffers:  win.DWORD,
	dwFreeHwMixingAllBuffers:       win.DWORD,
	dwFreeHwMixingStaticBuffers:    win.DWORD,
	dwFreeHwMixingStreamingBuffers: win.DWORD,
	dwMaxHw3DAllBuffers:            win.DWORD,
	dwMaxHw3DStaticBuffers:         win.DWORD,
	dwMaxHw3DStreamingBuffers:      win.DWORD,
	dwFreeHw3DAllBuffers:           win.DWORD,
	dwFreeHw3DStaticBuffers:        win.DWORD,
	dwFreeHw3DStreamingBuffers:     win.DWORD,
	dwTotalHwMemBytes:              win.DWORD,
	dwFreeHwMemBytes:               win.DWORD,
	dwMaxContigFreeHwMemBytes:      win.DWORD,
	dwUnlockTransferRateHwBuffers:  win.DWORD,
	dwPlayCpuOverheadSwBuffers:     win.DWORD,
	dwReserved1:                    win.DWORD,
	dwReserved2:                    win.DWORD,
}

IDirectSound :: struct #raw_union {
	#subtype iunknown: win.IUnknown,
	using vtable: ^IDirectSound_VTable,
}

IDirectSound_VTable :: struct {
	using iunknown_vtable: win.IUnknown_VTable,
	CreateSoundBuffer:     proc "system" (
		this: ^IDirectSound,
		pcDSBufferDesc: ^DSBUFFERDESC,
		ppDSBuffer: ^LPDIRECTSOUNDBUFFER,
		pUnkOuter: win.LPUNKNOWN,
	) -> win.HRESULT,
	GetCaps:               proc "system" (this: ^IDirectSound, pDSCaps: ^DSCAPS) -> win.HRESULT,
	DuplicateSoundBuffer:  proc "system" (
		this: ^IDirectSound,
		pDSBufferOriginal: LPDIRECTSOUNDBUFFER,
		ppDSBufferDuplicate: ^LPDIRECTSOUNDBUFFER,
	) -> win.HRESULT,
	SetCooperativeLevel:   proc "system" (
		this: ^IDirectSound,
		hwnd: win.HWND,
		dwLevel: win.DWORD,
	) -> win.HRESULT,
	Compact:               proc "system" (this: ^IDirectSound) -> win.HRESULT,
	GetSpeakerConfig:      proc "system" (
		this: ^IDirectSound,
		pdwSpeakerConfig: ^win.DWORD,
	) -> win.HRESULT,
	SetSpeakerConfig:      proc "system" (
		this: ^IDirectSound,
		dwSpeakerConfig: win.DWORD,
	) -> win.HRESULT,
	Initialize:            proc "system" (
		this: ^IDirectSound,
		pcGuidDevice: win.LPCGUID,
	) -> win.HRESULT,
}

IDirectSoundBuffer :: struct #raw_union {
	#subtype iunknown: win.IUnknown,
	using vtable: ^IDirectSoundBuffer_VTable,
}

IDirectSoundBuffer_VTable :: struct {
	using iunknown_vtable: win.IUnknown_VTable,
	GetCaps:               proc "system" (
		this: ^IDirectSoundBuffer,
		pDSBufferCaps: rawptr,
	) -> win.HRESULT,
	GetCurrentPosition:    proc "system" (
		this: ^IDirectSoundBuffer,
		pdwCurrentPlayCursor: ^win.DWORD,
		pdwCurrentWriteCursor: ^win.DWORD,
	) -> win.HRESULT,
	GetFormat:             proc "system" (
		this: ^IDirectSoundBuffer,
		pwfxFormat: ^win.WAVEFORMATEX,
		dwSizeAllocated: win.DWORD,
		pdwSizeWritten: ^win.DWORD,
	) -> win.HRESULT,
	GetVolume:             proc "system" (
		this: ^IDirectSoundBuffer,
		plVolume: ^win.LONG,
	) -> win.HRESULT,
	GetPan:                proc "system" (
		this: ^IDirectSoundBuffer,
		plPan: ^win.LONG,
	) -> win.HRESULT,
	GetFrequency:          proc "system" (
		this: ^IDirectSoundBuffer,
		pdwFrequency: ^win.DWORD,
	) -> win.HRESULT,
	GetStatus:             proc "system" (
		this: ^IDirectSoundBuffer,
		pdwStatus: ^win.DWORD,
	) -> win.HRESULT,
	Initialize:            proc "system" (
		this: ^IDirectSoundBuffer,
		pDirectSound: ^IDirectSound,
		pcDSBufferDesc: ^DSBUFFERDESC,
	) -> win.HRESULT,
	Lock:                  proc "system" (
		this: ^IDirectSoundBuffer,
		dwOffset: win.DWORD,
		dwBytes: win.DWORD,
		ppvAudioPtr1: ^rawptr,
		pdwAudioBytes1: ^win.DWORD,
		ppvAudioPtr2: ^rawptr,
		pdwAudioBytes2: ^win.DWORD,
		dwFlags: win.DWORD,
	) -> win.HRESULT,
	Play:                  proc "system" (
		this: ^IDirectSoundBuffer,
		dwReserved1: win.DWORD,
		dwPriority: win.DWORD,
		dwFlags: win.DWORD,
	) -> win.HRESULT,
	SetCurrentPosition:    proc "system" (
		this: ^IDirectSoundBuffer,
		dwNewPosition: win.DWORD,
	) -> win.HRESULT,
	SetFormat:             proc "system" (
		this: ^IDirectSoundBuffer,
		pcfxFormat: ^win.WAVEFORMATEX,
	) -> win.HRESULT,
	SetVolume:             proc "system" (
		this: ^IDirectSoundBuffer,
		lVolume: win.LONG,
	) -> win.HRESULT,
	SetPan:                proc "system" (
		this: ^IDirectSoundBuffer,
		lPan: win.LONG,
	) -> win.HRESULT,
	SetFrequency:          proc "system" (
		this: ^IDirectSoundBuffer,
		dwFrequency: win.DWORD,
	) -> win.HRESULT,
	Stop:                  proc "system" (this: ^IDirectSoundBuffer) -> win.HRESULT,
	Unlock:                proc "system" (
		this: ^IDirectSoundBuffer,
		pvAudioPtr1: rawptr,
		dwAudioBytes1: win.DWORD,
		pvAudioPtr2: rawptr,
		dwAudioBytes2: win.DWORD,
	) -> win.HRESULT,
	Restore:               proc "system" (this: ^IDirectSoundBuffer) -> win.HRESULT,
}
