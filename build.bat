REM @echo off
REM to remove the console window add this flag:
REM -subsystem:windows

odin build src^
    -debug^
    -out:build/handmade-odin.exe^
    -vet-unused^
    -vet-unused-variables^
    -vet-unused-imports^
    -vet-shadowing^
    -vet-using-stmt^
    -warnings-as-errors^
