@echo off
chcp 65001 >nul
title 离线AI虚拟城邦 - Godot 编辑器
set "GODOT=D:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe"
set "PROJECT=D:\Offline-AI-Virtual-City-built-on-Godot"

if not exist "%GODOT%" (
    echo [错误] 找不到 Godot：%GODOT%
    echo 请修改本文件顶部的 GODOT 路径。
    pause
    exit /b 1
)

echo 正在打开 Godot 编辑器（工程已导入）...
echo 打开后按 F5 运行游戏，或按 F6 运行当前场景。
"%GODOT%" --path "%PROJECT%" -e
