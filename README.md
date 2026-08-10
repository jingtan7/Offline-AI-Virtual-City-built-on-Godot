# Offline-AI-Virtual-City-built-on-Godot

离线 AI 虚拟城邦｜多智能体经济沙盘模拟器（Offline AI Virtual City built on Godot）

纯本地离线运行的多智能体经济沙盘：本地 LLM（Ollama）+ 工具调用 + 仿真经济 + AI Agent 集群 + RAG 记忆 + 沙盘可视化。

> 📦 仓库：https://github.com/jingtan7/Offline-AI-Virtual-City-built-on-Godot

## ✨ 功能亮点
- **全链路离线私有化**：Godot + Ollama(qwen2:7b) 纯本地，零网络依赖，游戏启动自动拉起 LLM
- **供需驱动自治物价**：无硬编码价格，完全由 Agent 行为涌现（短缺暴涨/过剩崩盘/囤货拉升）
- **多 Agent LLM 自主决策**：五职业人设 + 感知→自查→记忆→推理→执行工业级思考链路
- **本地 RAG 记忆**：零依赖向量库，Agent 越用越智能，针对玩家习惯反向博弈
- **沙盘可视化**：行情列表 / K线图 / 交易面板 / 市民对话 / 库存复盘
- **工具调用闭环**：market_query / code_execute / optimize_params（Ollama Function Calling）

## 🚀 运行
1. 安装 [Ollama](https://ollama.com/) 并 `ollama pull qwen2:7b`（工程启动时自动拉起）
2. 用 Godot 4.x 打开工程，运行主场景（自动进入城邦沙盘）

## 🧪 自动化测试
```powershell
Godot.exe --headless --path . res://Tests/test_runner.tscn
# 退出码 0 = 47/47 全部通过
```

## 🏗️ 开发进度
| 阶段 | 内容 | 状态 |
|---|---|---|
| 一 | Godot 工程 + 本地 AI 全栈环境（进程托管/统一接口/工具调用） | ✅ |
| 二 | 物资经济与多 Agent 数据体系 | ✅ |
| 三 | 城邦自治仿真经济算法（供需/撮合/事件/引擎） | ✅ |
| 四 | 多 AI Agent 智能体系统（LLM 决策工作流/五职业人设/并发调度） | ✅ |
| 五 | 本地 RAG 记忆与 Agent 自适应博弈 | ✅ |
| 六 | 城邦沙盘可视化与经济 UI（K线/交易/聊天/复盘） | ✅ |
| 七 | 多 Agent 经济全链路闭环联调 | ✅ |
| 八 | 系统优化与 AI 能力进阶 | ✅ |
| 九 | 工程化收尾与离线打包（导出配置/构建脚本/文档） | ✅ |

## 📁 目录结构
```
Scenes/    # 主场景
Scripts/   # 全局单例：AppManager/DataManager/GameLog/SimulationLoop
AI/        # AIService/LLMClient/ToolRunner/AgentBrain/AgentManager/AgentPrompts/MemoryStore/tools/prompts
Economy/   # 数据体系 + 仿真经济(供需/撮合/事件/引擎/统计)
UI/        # 城邦沙盘界面 + K线图表
Tests/     # 自动化测试（8 套件 47 项）
Tools/     # Python 本地工具服务（可选）
docs/      # 项目架构文档
```

## 📦 打包 Windows 单机 exe
```powershell
powershell -File build_windows.ps1
```
（需先安装 Godot Windows 导出模板）

## 📄 详细文档
- `docs/PROJECT_OVERVIEW.md` — 技术架构 / 核心机制 / 技术难点

## 离线说明
所有 AI 推理、工具调用、向量记忆、仿真运算均在本机完成（仅 127.0.0.1 回环），零外部网络依赖。


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
AI/        # AIService(进程托管)/LLMClient(统一接口)/ToolRunner(工具执行)/AgentData/tools/prompts
Economy/   # 数据体系 + 仿真经济(供需物价/撮合/事件/引擎)（阶段二/三完成）
UI/        # 沙盘可视化（阶段六）
Data/      # 配置/日志/存档
Assets/    # 美术资源
Tests/     # 自动化测试
Tools/     # 本地工具服务（Python）
```

## 离线说明
- 所有 AI 推理与工具调用均在本机完成（127.0.0.1 回环地址），零外部网络依赖。
