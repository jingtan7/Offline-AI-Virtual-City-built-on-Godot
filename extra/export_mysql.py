#!/usr/bin/env python3
"""可选数据分析拓展：把 SQLite 存档导出到 MySQL（不参与游戏运行）。

用法:
    pip install mysql-connector-python
    python export_mysql.py --db <sqlite路径> --host 127.0.0.1 --user root --password xxx --database city_analysis

表：npc / behavior_log / market_bars / event_log / prices（批量 UPSERT）
"""
import argparse
import sqlite3
import sys

try:
    import mysql.connector
except ImportError:
    print("需要安装 mysql-connector-python: pip install mysql-connector-python")
    sys.exit(1)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--db", default="city.db")
    ap.add_argument("--host", default="127.0.0.1")
    ap.add_argument("--port", type=int, default=3306)
    ap.add_argument("--user", default="root")
    ap.add_argument("--password", default="")
    ap.add_argument("--database", default="city_analysis")
    a = ap.parse_args()

    conn = mysql.connector.connect(host=a.host, port=a.port, user=a.user, password=a.password, database=a.database)
    cur = conn.cursor()

    ddl = [
        """CREATE TABLE IF NOT EXISTS npc (
            id VARCHAR(32) PRIMARY KEY, name VARCHAR(64), occupation VARCHAR(32),
            x DOUBLE, y DOUBLE, anim VARCHAR(16), state INT, cash DOUBLE, risk VARCHAR(16),
            llm_controlled INT, hp DOUBLE)""",
        """CREATE TABLE IF NOT EXISTS behavior_log (
            id BIGINT AUTO_INCREMENT PRIMARY KEY, tick INT, agent VARCHAR(32),
            action VARCHAR(16), commodity VARCHAR(16), price DOUBLE, qty DOUBLE,
            reason VARCHAR(256), time BIGINT)""",
        """CREATE TABLE IF NOT EXISTS market_bars (
            id BIGINT AUTO_INCREMENT PRIMARY KEY, tick INT, commodity VARCHAR(16),
            open DOUBLE, close DOUBLE, high DOUBLE, low DOUBLE, prev_close DOUBLE,
            volume DOUBLE, pending INT, gap DOUBLE)""",
        """CREATE TABLE IF NOT EXISTS event_log (
            id BIGINT AUTO_INCREMENT PRIMARY KEY, tick INT, label VARCHAR(64), `desc` VARCHAR(512))""",
        """CREATE TABLE IF NOT EXISTS prices (
            id BIGINT AUTO_INCREMENT PRIMARY KEY, tick INT, commodity VARCHAR(16), price DOUBLE)""",
    ]
    for d in ddl:
        cur.execute(d)

    sqlite = sqlite3.connect(a.db)
    sc = sqlite.cursor()

    def copy(sql, mysql_sql, insert_sql):
        sc.execute(sql)
        rows = sc.fetchall()
        if not rows:
            return 0
        # 分批插入（每批 500）
        for i in range(0, len(rows), 500):
            batch = rows[i:i + 500]
            cur.executemany(mysql_sql, batch)
            conn.commit()
        print(f"  {insert_sql.split(' INTO ')[1].split(' ')[0]}: {len(rows)} 行")
        return len(rows)

    print("导出 SQLite -> MySQL:")
    copy("SELECT id,name,occupation,x,y,anim,state,cash,risk,llm_controlled,hp FROM npc",
         "REPLACE INTO npc (id,name,occupation,x,y,anim,state,cash,risk,llm_controlled,hp) VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)",
         "npc")
    copy("SELECT tick,agent,action,commodity,price,qty,reason,time FROM behavior_log",
         "INSERT INTO behavior_log (tick,agent,action,commodity,price,qty,reason,time) VALUES (%s,%s,%s,%s,%s,%s,%s,%s)",
         "behavior_log")
    copy("SELECT tick,commodity,open,close,high,low,prev_close,volume,pending,gap FROM market_bars",
         "INSERT INTO market_bars (tick,commodity,open,close,high,low,prev_close,volume,pending,gap) VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)",
         "market_bars")
    copy("SELECT tick,label,`desc` FROM event_log",
         "INSERT INTO event_log (tick,label,`desc`) VALUES (%s,%s,%s)",
         "event_log")
    copy("SELECT tick,commodity,price FROM prices",
         "INSERT INTO prices (tick,commodity,price) VALUES (%s,%s,%s)",
         "prices")
    sqlite.close()
    conn.close()
    print("✅ 导出完成")


if __name__ == "__main__":
    main()
