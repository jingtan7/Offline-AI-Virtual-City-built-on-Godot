# 项目技术文档：Offline-AI-Virtual-City-built-on-Godot

离线 AI 虚拟城邦｜多智能体经济沙盘模拟器 —— 纯本地离线、零网络依赖的工业级 AI 全栈项目。

## 1. 整体技术架构

```
┌──────────────────────────── 表现层 ────────────────────────────┐
│  CityUI.gd 城邦沙盘界面（总览/行情列表/K线/交易/聊天/库存复盘） │
│  KLineChart.gd 经济K线可视化（价格曲线+成交量柱）               │
└────────────────────────────┬───────────────────────────────────┘
                             │ tick 刷新
┌────────────────────────────▼───────────────────────────────────┐
│  EconomyEngine.gd 仿真主引擎（Autoload，SimulationLoop 驱动）   │
│   每tick：事件→Agent产出消耗→挂单→撮合→供需物价→行情入库        │
│  SupplyDemand.gd 供需物价 / MatchingEngine.gd 撮合引擎          │
│  EconomyEvent.gd 随机事件 / StatsService.gd 复盘统计            │
│  CityState.gd 城邦状态容器（物资/玩家/Agent/订单/行情，JSON存档）│
└────────────────────────────┬───────────────────────────────────┘
                             │ 挂单/行情/决策
┌────────────────────────────▼───────────────────────────────────┐
│  AgentManager.gd 多Agent并发轮询（异步LLM决策调度）              │
│  AgentBrain.gd 思考链路：感知→自查→记忆检索→LLM推理→落地        │
│  AgentPrompts.gd 五职业人设Prompt（农夫/矿工/商人/工匠/投机者）  │
│  MemoryStore.gd 本地向量记忆库（bigram哈希TF + 余弦检索）        │
└────────────────────────────┬───────────────────────────────────┘
                             │ 本地 HTTP (127.0.0.1:11434)
┌────────────────────────────▼───────────────────────────────────┐
│  AIService.gd 进程托管(探活/拉起/保活/销毁) + LLMClient 统一接口 │
│  ToolRunner.gd 工具执行器（market_query/code_execute/优化）      │
│  Ollama 本地大模型（qwen2:7b）                                  │
└─────────────────────────────────────────────────────────────────┘
```

## 2. 核心机制

### 2.1 供需驱动自治物价（无硬编码价格）
- 每 tick 聚合所有主体的产出/消耗/挂单 → 供需差值
- 结合存量水平（短缺溢价/过剩折价）、成交量放大（囤货拉升/抛售崩盘）、均值回归（横盘震荡）
- 价格变化夹在「单日波动限制」内

### 2.2 多主体撮合交易
- 价格优先 + 时间优先，AI↔AI / AI↔玩家
- 成交统一结算资金与库存，实时更新成交量与行情

### 2.3 多 Agent LLM 自主决策（工业级思考链路）
环境感知(实时物价/存量/事件) → 状态自查(资金/库存) → 记忆检索(RAG) → LLM离线推理 → 落地执行
- 强制结构化输出：`{"action":"work|buy|sell|hold","commodity","price","quantity","reason"}`
- LLM 决策后的 Agent 由 LLM 接管，引擎跳过规则行为
- 五类职业差异化人设：目标/约束/风险偏好/对话风格

### 2.4 本地 RAG 记忆与自适应博弈
- 零依赖向量库：字符 bigram 哈希 TF 向量 + 余弦相似度，JSON 持久化
- 入库：Agent 行为、城邦事件、行情时序摘要、玩家交易习惯
- Agent 每次决策前检索相关历史记忆注入 Prompt → 越用越智能
- 玩家操作习惯被记忆 → Agent 反向博弈

### 2.5 本地 LLM 部署与工具调用
- Ollama 进程托管：游戏启动自动唤醒、保活、退出销毁
- Function Calling 闭环：LLM 决策可调用 market_query / code_execute / optimize_params

## 3. 目录结构
```
Scenes/   主场景
Scripts/  全局单例（GameLog/DataManager/SimulationLoop/AppManager）
AI/       AIService/LLMClient/ToolRunner/AgentBrain/AgentManager/AgentPrompts/MemoryStore/tools/prompts
Economy/  Commodity/MarketBar/TradeOrder/PlayerData/AgentData/CityState
          SupplyDemand/MatchingEngine/EconomyEvent/EconomyEngine/StatsService
UI/       CityUI/KLineChart
Tests/    自动化测试（8 个套件）
Tools/    Python 本地工具服务（可选）
docs/     项目文档
```

## 4. 运行与验证
```powershell
# 前置：Ollama + qwen2:7b（工程会自动拉起）
# 编辑器运行：Godot 打开工程 → F5

# 自动化测试（headless）
Godot.exe --headless --path . res://Tests/test_runner.tscn

# Windows 打包
powershell -File build_windows.ps1
```

## 5. 关键技术难点
1. Ollama Function Calling 回传 HTTP 400（`function.index` 序列化）→ `_sanitize_tool_calls` 净化
2. autoload 名与 Godot 内置类撞名 → 改名 GameLog
3. LLM 输出不可控 → 强制 JSON 结构化 + `AgentBrain.normalize` 校验回退
4. 多 Agent 异步决策不阻塞仿真 → AgentManager 独立轮询 + llm_controlled 接管
5. 全离线向量记忆 → 本地 bigram 哈希嵌入（零依赖）
