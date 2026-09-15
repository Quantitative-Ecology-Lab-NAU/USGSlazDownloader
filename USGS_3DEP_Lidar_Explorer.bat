@echo off
setlocal
cd /d "%~dp0"
set "RSCRIPT="
for /f "delims=" %%I in ('where Rscript.exe 2^>nul') do if not defined RSCRIPT set "RSCRIPT=%%I"
if not defined RSCRIPT for /f "delims=" %%I in ('dir /b /s "%LOCALAPPDATA%\Programs\R\R-*\bin\Rscript.exe" 2^>nul') do if not defined RSCRIPT set "RSCRIPT=%%I"
if not defined RSCRIPT for /f "delims=" %%I in ('dir /b /s "%LOCALAPPDATA%\Programs\R\R-*\bin\x64\Rscript.exe" 2^>nul') do if not defined RSCRIPT set "RSCRIPT=%%I"
if not defined RSCRIPT for /f "delims=" %%I in ('dir /b /s "%ProgramFiles%\R\R-*\bin\Rscript.exe" 2^>nul') do if not defined RSCRIPT set "RSCRIPT=%%I"
if not defined RSCRIPT for /f "delims=" %%I in ('dir /b /s "%ProgramFiles%\R\R-*\bin\x64\Rscript.exe" 2^>nul') do if not defined RSCRIPT set "RSCRIPT=%%I"
if not defined RSCRIPT (
  echo Rscript.exe was not found. Install R and ensure Rscript is on PATH.
  pause
  exit /b 1
)
"%RSCRIPT%" "%~dp0USGS_3DEP_Lidar_Explorer.R"
pause
