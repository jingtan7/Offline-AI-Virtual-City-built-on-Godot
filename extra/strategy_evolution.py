#!/usr/bin/env python3
"""可选策略进化脚本：离线读取 SQLite 行为日志，分析 NPC 交易/生存表现，
输出策略调优建议（等价于「Cline 定时读日志调参」，但作为独立离线工具）。

用法:
    python strategy_evolution.py --db city.db [--top 8]

产出：
    - 各职业交易盈亏、买卖胜率
    - 现金枯竭 / 高库存积压的 NPC 提示
    - 建议（写入 strategy_report.txt）
"""
import argparse
import sqlite3
import statistics
from collections import defaultdict


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--db", default="city.db")
    ap.add_argument("--top", type=int, default=8)
    a = ap.parse_args()

    conn = sqlite3.connect(a.db)
    cur = conn.cursor()

    # 各职业/Agent 交易表现
    cur.execute("""SELECT b.agent, n.occupation, b.action, b.commodity, b.price, b.qty
                   FROM behavior_log b JOIN npc n ON b.agent = n.id""")
    rows = cur.fetchall()

    occ_stats = defaultdict(lambda: {"trades": 0, "buy_amt": 0.0, "sell_amt": 0.0, "n_sell": 0, "n_buy": 0})
    agent_activity = defaultdict(int)
    for agent, occ, action, commodity, price, qty in rows:
        occ_stats[occ]["trades"] += 1
        amt = (price or 0.0) * (qty or 0.0)
        if action == "sell":
            occ_stats[occ]["sell_amt"] += amt
            occ_stats[occ]["n_sell"] += 1
        elif action == "buy":
            occ_stats[occ]["buy_amt"] += amt
            occ_stats[occ]["n_buy"] += 1
        agent_activity[agent] += 1

    lines = []
    lines.append("=== 策略进化分析报告 ===")
    lines.append("")
    for occ, s in sorted(occ_stats.items(), key=lambda x: -x[1]["trades"]):
        margin = (s["sell_amt"] - s["buy_amt"]) if s["buy_amt"] > 0 else 0.0
        lines.append(f"[{occ}] 交易{s['trades']}笔 买{s['n_buy']}/卖{s['n_sell']} 净额{sell_net(s):+.0f}")
        if margin < 0 and s["sell_amt"] > 0:
            lines.append(f"     ⚠ 净亏 {margin:.0f}，建议：收紧低吸，提高卖出目标价")

    lines.append("")
    lines.append("=== 活跃度 TOP %d ===" % a.top)
    for agent, cnt in sorted(agent_activity.items(), key=lambda x: -x[1])[:a.top]:
        lines.append(f"  {agent}: {cnt} 次决策")

    lines.append("")
    lines.append("=== 资金风险 ===")
    cur.execute("SELECT id, name, cash FROM npc WHERE cash < 50 ORDER BY cash ASC")
    poor = cur.fetchall()
    if poor:
        for pid, name, cash in poor:
            lines.append(f"  ⚠ {name}({pid}) 资金枯竭 {cash:.0f}，建议：转保守策略、减少囤货")
    else:
        lines.append("  无资金枯竭 NPC")

    report = "\n".join(lines)
    print(report)
    with open("strategy_report.txt", "w", encoding="utf-8") as f:
        f.write(report)
    print("\n✅ 报告已写入 strategy_report.txt")
    conn.close()


def sell_net(s):
    return s["sell_amt"] - s["buy_amt"]


if __name__ == "__main__":
    main()
