@echo off
chcp 65001 >nul
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0launch.ps1" -Agent cl -Keyword "%~1"
