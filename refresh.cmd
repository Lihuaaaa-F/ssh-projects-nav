@echo off
chcp 65001 >nul
powershell -NoProfile -ExecutionPolicy Bypass -Command ". $env:USERPROFILE\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1"
