#!/bin/bash

# ==========================================================
# 脚本名称: install_master.sh (IP-Sentinel 控制中枢部署脚本)
# 核心功能: 安装 SQLite3、初始化数据库表、配置后台守护进程
# ==========================================================

MASTER_DIR="/opt/ip_sentinel_master"
DB_FILE="${MASTER_DIR}/sentinel.db"

echo "========================================================"
echo "      🧠 准备部署 IP-Sentinel Master 控制中枢"
echo "========================================================"

# 1. 环境依赖安装
echo "[1/4] 安装核心依赖 (curl, jq, sqlite3)..."
if [ -f /etc/debian_version ]; then
    apt-get update -y >/dev/null 2>&1
    apt-get install -y curl jq sqlite3 procps >/dev/null 2>&1
elif [ -f /etc/redhat-release ]; then
    yum install -y curl jq sqlite >/dev/null 2>&1
fi

mkdir -p "$MASTER_DIR"

# 2. 交互配置机器人
echo -e "\n[2/4] 配置控制中枢机器人:"
read -p "请输入 Telegram Bot Token: " TG_TOKEN

cat > "${MASTER_DIR}/master.conf" << EOF
TG_TOKEN="$TG_TOKEN"
DB_FILE="$DB_FILE"
MASTER_DIR="$MASTER_DIR"
EOF

# 3. 初始化 SQLite 数据库
echo -e "\n[3/4] 正在初始化 SQLite 数据库表结构..."
sqlite3 "$DB_FILE" <<EOF
CREATE TABLE IF NOT EXISTS nodes (
    chat_id TEXT,
    node_name TEXT,
    agent_ip TEXT,
    agent_port TEXT,
    last_seen DATETIME DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY(chat_id, node_name)
);
EOF
echo "✅ 数据库创建成功: $DB_FILE"

# 4. 拉取核心调度代码并运行
echo -e "\n[4/4] 部署 TG 调度守护进程..."
curl -sL "https://git.94211762.xyz/hotyue/IP-Sentinel/raw/branch/main/master/tg_master.sh" -o "${MASTER_DIR}/tg_master.sh"
chmod +x "${MASTER_DIR}/tg_master.sh"

# 写入看门狗 Cron
crontab -l 2>/dev/null | grep -v "tg_master.sh" > /tmp/cron_master
echo "* * * * * pgrep -f tg_master.sh >/dev/null || nohup bash ${MASTER_DIR}/tg_master.sh >/dev/null 2>&1 &" >> /tmp/cron_master
crontab /tmp/cron_master
rm -f /tmp/cron_master

# 立刻启动
pgrep -f tg_master.sh >/dev/null || nohup bash "${MASTER_DIR}/tg_master.sh" >/dev/null 2>&1 &

echo "========================================================"
echo "🎉 Master 控制中枢部署完成！"
echo "🤖 机器人现已开始全局接客，等待边缘节点注册。"
echo "========================================================"