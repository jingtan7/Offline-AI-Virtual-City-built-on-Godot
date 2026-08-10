# 构建 Windows 离线单机 exe（阶段九）
# 用法：powershell -File build_windows.ps1
# 前置：Godot 编辑器已安装导出模板（编辑器 → 编辑器 → 管理导出模板 → 下载并安装 Windows 模板）

param(
    [string]$GodotExe = "D:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe"
)

$ErrorActionPreference = "Stop"
$project = Split-Path -Parent $PSScriptRoot
$outDir = Join-Path $project "build"
$out = Join-Path $outDir "Offline-AI-Virtual-City.exe"

New-Item -ItemType Directory -Path $outDir -Force | Out-Null
Write-Host ">>> 导出 Windows 可执行文件..."
Write-Host ">>> 工程: $project"
Write-Host ">>> 输出: $out"

& $GodotExe --headless --path $project --export-release "Windows Desktop" $out

if ($LASTEXITCODE -eq 0) {
    Write-Host ""
    Write-Host "======================================"
    Write-Host "  ✅ 导出成功: $out"
    Write-Host "  提示: 游戏启动时会自动拉起本地 Ollama 进程，请确保本机已安装 Ollama 与 qwen2:7b 模型。"
    Write-Host "======================================"
} else {
    Write-Host ""
    Write-Host "⚠️  导出失败（exit=$LASTEXITCODE）"
    Write-Host "   常见原因：未安装 Windows 导出模板。"
    Write-Host "   解决：Godot 编辑器 → 编辑器 → 管理导出模板 → 下载并安装。"
}
