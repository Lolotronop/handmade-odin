@echo off
REM to remove the console window add this flag:
REM -subsystem:windows

REM I have portable MSVC installed in D:\soft\msvc on my laptop soooo
if exist "d:\soft\msvc\setup_x64.bat" call "d:\soft\msvc\setup_x64.bat"

if "%1"=="full" (
odin build src^
    -debug^
    -out:build/handmade-odin.exe^
    -subsystem:windows^
    -vet-unused^
    -vet-unused-variables^
    -vet-unused-imports^
    -vet-shadowing^
    -vet-using-stmt^
    -warnings-as-errors
)

odin build src/game^
    -debug^
    -build-mode:dll^
    -out:build/handmade-odin-lib.dll^
    -vet-unused^
    -vet-unused-variables^
    -vet-unused-imports^
    -vet-shadowing^
    -vet-using-stmt^
    -warnings-as-errors
