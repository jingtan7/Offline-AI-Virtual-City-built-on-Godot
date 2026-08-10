# 项目技术文档：Side-Scroller Pixel-Style Offline-AI Virtual City

横版卷轴像素离线 AI 虚拟城邦 —— 纯本地离线、零网络依赖的工业级 AI 全栈项目。

## 1. 整体技术架构

```
┌────────────────────────── 表现层（横版像素村庄） ──────────────────────────┐
│  VillageDirector.gd 村庄导演：TileMap地面/房屋/树/市场/农田/矿点/Camera2D横滚 │
│  VillageNPC.gd 像素NPC实体：Sprite2D + AnimationPlayer(walk/idle/work/trade) │
│  PixelAssets.gd 程序化像素生成器（零外部素材）                              │
│  VillageHUD.gd 叠加HUD（行情条/交易/市民对话/事件）                          │
└─────────────────────────────┬───────────────────────────────────────────────┘
                              │ 决策 → 行动指令（去集市/劳作/回家/闲逛）
┌─────────────────────────────▼───────────────────────────────────────────────┐
│  EconomyEngine.gd 仿真引擎（供需物价/撮合/事件/行情）                        │
│  AgentManager.gd 多Agent并发轮询  AgentBrain.gd 思考链路(感知→自查→记忆→推理) │
└──────────────┬───────────────────────────────┬──────────────────────────────┘
               │ 位置/行为/事件/行情              │ RAG 检索
┌──────────────▼──────────────┐   ┌─────────────▼──────────────┐
│  SQLiteService.gd           │   │  RAGService.gd             │
│  (godot-sqlite 插件)        │   │  (ChromaDB REST v2)        │
│  表：npc/inventory/orders/  │   │  每NPC独立集合(city/player/ │
│  market_bars/prices/        │   │  agent_xxxx)               │
│  behavior_log/event_log/    │   └─────────────┬──────────────┘
│  buildings/player           │                 │ 嵌入(本地bigram哈希)
└──────────────┬──────────────┘   ┌─────────────▼──────────────┐
               │                  │  MemoryStore（内置回退库）  │
               └──────────────────┴─────────────┬──────────────┘
┌──────────────────────────────────────────────▼──────────────┐
│  AIService.gd 进程托管 + LLMClient 统一接口 + ToolRunner 工具  │
│  Ollama 本地大模型（qwen2:7b）                               │
└──────────────────────────────────────────────────────────────┘
```

## 2. 核心机制

### 2.1 横版像素村庄
- 4160px 横向世界：TileMap 地面（草地/泥土/路）+ 15 座房屋 + 树 + 集市 + 水井 + 花丛
- 16×24 像素小人：五职业配色（农夫绿/矿工蓝/商人紫/工匠橙/投机者红），walk 双帧行走 + 上下浮动动画
- Camera2D 自动平移，点击 NPC 聚焦跟随

### 2.2 存储层（SQLite）
- godot-sqlite v4.9（官方匹配 Godot 4.7.1，内置 SQLite 3.51）
- WAL 模式 + 参数化查询（query_with_bindings）
- NPC 坐标/动画/状态/资金、库存、订单、行情、行为日志、事件全量结构化入库
- 插件未装时 ClassDB 探测自动回退 JSON 存档

### 2.3 RAG 记忆（ChromaDB）
- ChromaDB REST v2：每 NPC 独立集合 + city/player 全局集合
- 嵌入向量复用本地 bigram 哈希（零模型下载）
- 决策前检索 top-k 注入 Prompt；服务未启动回退内置向量库

### 2.4 多 Agent LLM 决策
- 感知(实时行情)→自查(资金库存)→记忆检索(RAG)→LLM推理→落地执行
- 输出强制 JSON：action(work/buy/sell/hold) + commodity + price + qty + reason
- LLM 决策后的 NPC 在村庄中走向集市/工作点并切换动画

## 3. 运行依赖
| 必备 | 说明 |
|---|---|
| Ollama + qwen2:7b | 市民大脑（游戏自动拉起） |
| ChromaDB | RAG 向量记忆（`pip install chromadb` + `chroma run --path data/chroma`） |
| godot-sqlite 插件 | 已随项目 `addons/` 提供（Windows） |

| 可选 | 说明 |
|---|---|
| MySQL | `extra/export_mysql.py` 批量导出行为日志做大数据分析 |
| 策略进化 | `extra/strategy_evolution.py` 离线生成职业调优报告 |

## 4. 关键技术难点
1. Godot 4.7 AnimationPlayer 无 `add_animation` → 用 AnimationLibrary
2. godot-sqlite 无 `query_with_args/is_open` → 用 `query_with_bindings/get_error_message`
3. ChromaDB v2 REST 路径（/api/v2）+ 并发建集合竞争 → 自旋锁 + 预创建
4. 横版 NPC 碰撞卡死 → NPC 之间不碰撞 + 唯一房屋位
5. autoload 命名冲突（Logger/类名遮蔽）→ 改名/去 class_name

