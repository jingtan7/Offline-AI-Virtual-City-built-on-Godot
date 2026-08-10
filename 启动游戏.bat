@echo off
chcp 65001 >nul
title 离线AI虚拟城邦 - 游戏启动
set "GODOT=D:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe"
set "PROJECT=D:\Offline-AI-Virtual-City-built-on-Godot"

if not exist "%GODOT%" (
    echo [错误] 找不到 Godot：%GODOT%
    echo 请修改本文件顶部的 GODOT 路径。
    pause
    exit /b 1
)
if not exist "%PROJECT%\project.godot" (
    echo [错误] 找不到工程：%PROJECT%
    pause
    exit /b 1
)

echo 正在启动 离线AI虚拟城邦...
echo 提示：游戏会自动探测/拉起本地 Ollama（qwen2:7b），请耐心等待 AI 服务就绪。
echo.
"%GODOT%" --path "%PROJECT%" res://Scenes/main.tscn
echo.
echo 游戏已退出。
pause
