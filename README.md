# Offline-AI-Virtual-City-built-on-Godot

离线 AI 虚拟城邦｜多智能体经济沙盘模拟器（Offline AI Virtual City built on Godot）

纯本地离线运行的多智能体经济沙盘：本地 LLM（Ollama）+ 工具调用 + 仿真经济 + AI Agent 集群。

> 📦 仓库：https://github.com/jingtan7/Offline-AI-Virtual-City-built-on-Godot

## 技术栈
- **Godot 4.7**（2D 沙盘，纯本地单机）
- **Ollama + qwen2:7b**（离线 LLM 推理，本地 127.0.0.1:11434）
- **Function Calling 工具体系**（market_query / code_execute / optimize_params）
- 可选：Python 本地工具服务（`Tools/tool_server/tool_server.py`，端口 8770）

## 运行前置
1. 安装 [Ollama](https://ollama.com/) 并拉取模型：`ollama pull qwen2:7b`（工程启动时会自动拉起 Ollama 进程）
2. 用 Godot 4.x 打开本工程，运行主场景 `Scenes/main.tscn`

## Headless 验证（命令行）
```powershell
# 导入资源
Godot.exe --headless --path . --import

# 运行阶段一自动化测试（退出码 0 = 全部通过）
Godot.exe --headless --path . res://Tests/test_runner.tscn
```

## 目录结构
```
Scenes/    # 场景文件
Scripts/   # 全局单例：AppManager/DataManager/GameLog/SimulationLoop
AI/        # AIService(进程托管)/LLMClient(统一接口)/ToolRunner(工具执行)/tools/prompts
Economy/   # 仿真经济（阶段三）
UI/        # 沙盘可视化（阶段六）
Data/      # 配置/日志/存档
Assets/    # 美术资源
Tests/     # 自动化测试
Tools/     # 本地工具服务（Python）
```

## 离线说明
- 所有 AI 推理与工具调用均在本机完成（127.0.0.1 回环地址），零外部网络依赖。
