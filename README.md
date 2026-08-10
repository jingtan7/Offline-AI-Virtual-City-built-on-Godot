# Side-Scroller Pixel-Style Offline-AI Virtual City

横版卷轴像素离线 AI 虚拟城邦（Offline-AI Virtual City built on Godot）

**横向延展的像素村庄**：房屋、树木、草地地面、自带行走/休憩/干活/交易动画的像素 NPC 小人——所有居民由本地大模型驱动，具备长期记忆与自主策略迭代。

> 📦 仓库：https://github.com/jingtan7/Offline-AI-Virtual-City-built-on-Godot

## 🎮 画面特征
- 横向卷轴村庄地图（TileMap 地面/草地/路 + 房屋/树/市场/农田/矿点，宽 4160px）
- 像素 NPC（16×24 五职业配色小人）拥有 **walk / idle / work / trade 全套 AnimationPlayer 动画**
- Camera2D 横向滚动、自动平移、点击 NPC 聚焦跟随
- HUD 叠加：行情条 / 交易按钮 / 市民对话 / 事件提示

## ⚙️ 技术栈与依赖

### 运行必备服务
| 服务 | 作用 | 安装 |
|---|---|---|
| **Ollama** | 每个像素市民的本地大脑 | https://ollama.com/ + `ollama pull qwen2:7b`（游戏启动自动拉起） |
| **ChromaDB** | RAG 长期向量记忆（每 NPC 独立集合） | `pip install chromadb` + `chroma run --path data/chroma` |
| **godot-sqlite 插件** | SQLite 结构化存档 | 从 [godot-sqlite v4.9](https://github.com/2shady4u/godot-sqlite/releases/tag/v4.9) 下载 `addons.zip` 解压到项目 `addons/` |

> 三者缺省均可降级运行：Ollama 缺席→规则决策；ChromaDB 缺席→内置向量库；godot-sqlite 缺席→JSON 存档。

### 可选数据分析组件
- **MySQL**：`extra/export_mysql.py` 把 SQLite 行为日志批量导出到 MySQL 做大规模 NPC/市场经济分析
- **策略进化**：`extra/strategy_evolution.py` 离线读日志生成职业交易表现与调优建议报告

## 🚀 运行
1. 安装 Ollama + qwen2:7b（游戏会自动拉起）
2. （推荐）启动 ChromaDB：`chroma run --path data/chroma`
3. 用 Godot 4.7 打开工程 → F5（或双击 `启动游戏.bat`）

## 🧪 自动化测试
```powershell
Godot.exe --headless --path . res://Tests/test_runner.tscn
# 退出码 0 = 55/55 通过
```

## 🏗️ 开发进度
| 阶段 | 内容 | 状态 |
|---|---|---|
| 一~三 | AI 全栈环境 / 数据体系 / 仿真经济算法 | ✅ |
| 四~五 | 多 Agent LLM 决策 / RAG 记忆自适应博弈 | ✅ |
| 六~七 | 沙盘 UI / 全链路闭环联调 | ✅ |
| 八 | 系统优化与 AI 能力进阶 | ✅ |
| 九改 | **横版像素村庄**（TileMap/像素NPC动画/横滚相机）+ SQLite 存储 + ChromaDB RAG + MySQL 可选分析 | ✅ |

## 📁 目录结构
```
Scenes/    # 主场景
Scripts/   # 全局单例（含 SQLiteService 存档）
AI/        # AIService/AgentBrain/AgentManager/AgentPrompts/MemoryStore/RAGService/ToolRunner
Economy/   # 仿真经济（供需/撮合/事件/引擎/统计）
Village/   # 横版村庄：PixelAssets(像素生成)/VillageDirector/VillageNPC/VillageHUD
UI/        # K线图表等
Tests/     # 自动化测试（10 套件 55 项）
extra/     # 可选分析：MySQL 导出 / 策略进化脚本
Tools/     # Python 本地工具服务
```

## 📄 详细文档
- `docs/PROJECT_OVERVIEW.md` — 技术架构 / 核心机制 / 技术难点

## 离线说明
所有 AI 推理、向量记忆、结构化存储均在本机（127.0.0.1 回环），零外部网络依赖。


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
