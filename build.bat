@echo off
REM to remove the console window add this flag:
REM -subsystem:windows

if "%1"=="full" (
odin build src^
    -debug^
    -out:build/handmade-odin.exe^
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
