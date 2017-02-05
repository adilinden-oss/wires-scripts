@echo off
call :sub > out.log 2>&1
exit /b

:sub
c:\Strawberry\perl\bin\perl.exe c:%HOMEPATH%\Documents\wires2aprs\wires2aprs.pl
exit /b
