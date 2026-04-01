#!/bin/bash

# ==========================================================
# 脚本名称: tg_report.sh (Telegram 每日战报模块 V5.3 缝合加强版)
# 核心功能: 分析日志并推送 24 小时统计数据到 TG (修复 Markdown 断联Bug)
# ==========================================================

INSTALL_DIR="/opt/ip_sentinel"
CONFIG_FILE="${INSTALL_DIR}/config.conf"
LOG_FILE="${INSTALL_DIR}/logs/sentinel.log"

# 1. 加载配置并自检
if [ ! -f "$CONFIG_FILE" ]; then exit 1; fi
source "$CONFIG_FILE"

if [ -z "$TG_TOKEN" ] || [ -z "$CHAT_ID" ]; then
    echo "⚠️ 未配置 Telegram 机器人参数，取消播报。"
    exit 0
fi

# 2. 节点元数据抓取
NODE_NAME=$(hostname | cut -c 1-15)
CURRENT_IP=$(curl -4 -s -m 5 api.ip.sb/ip || echo "Unknown")

# 智能判断 IP 属性 (通过检查 ISP 标识)
ISP_INFO=$(curl -4 -s -m 5 api.ip.sb/geoip | jq -r '.organization' 2>/dev/null)
if [[ "$ISP_INFO" == *"Cloudflare"* ]]; then
    IP_TYPE="Cloudflare Warp 🛰️"
else
    IP_TYPE="Native 原生网卡 🏠"
fi

# 3. 截取过去 24 小时的日志
LOG_CONTENT=$(find "$LOG_FILE" -mtime -1 -exec cat {} \; 2>/dev/null)

if [ -z "$LOG_CONTENT" ]; then
    # 修复了换行问题，统一用 EOF 块构造
    read -r -d '' MSG <<EOT
🛑 **[IP-Sentinel] 告警：节点异常**
----------------------------
📍 **节点名称**: \`${NODE_NAME}\`
⚠️ **警告**: 过去 24 小时无运行日志！
🛠️ **建议**: 节点可能刚部署完毕，请手动执行一次 [执行深度伪装]。
EOT
else
    # 4. 数据精准分析
    TOTAL_SESSIONS=$(echo "$LOG_CONTENT" | grep "\[START\]" -c)
    SUCCESS_COUNT=$(echo "$LOG_CONTENT" | grep "✅" -c)
    FAILED_COUNT=$(echo "$LOG_CONTENT" | grep "❌" -c)
    UNKNOWN_COUNT=$(echo "$LOG_CONTENT" | grep "⚠️" -c)

    # 提取最近一次运行的时间和结论文本 
    # (⚠️ 核心 Bug 修复: 用 awk 切割并过滤掉中括号 []，防止触发 TG Markdown 语法错误导致消息丢弃)
    LAST_TIME=$(echo "$LOG_CONTENT" | grep "\[END" | tail -n 1 | awk '{print $1,$2}' | tr -d '[]')
    LAST_SCORE=$(echo "$LOG_CONTENT" | grep "\[SCORE\]" | tail -n 1 | awk -F'自检结论: ' '{print $2}' | tr -d '[]')

    # 计算成功率
    if [ "$TOTAL_SESSIONS" -gt 0 ]; then
        RATE=$(awk "BEGIN {printf \"%.1f\", ($SUCCESS_COUNT/$TOTAL_SESSIONS)*100}")
    else
        RATE=0
    fi

    # 状态表情逻辑：成功率 100% 显绿色，0% 显红色，中间显黄色
    if [ "$SUCCESS_COUNT" -eq "$TOTAL_SESSIONS" ] && [ "$TOTAL_SESSIONS" -gt 0 ]; then
        STATUS_EMOJI="🟢 隐匿完美"
    elif [ "$SUCCESS_COUNT" -gt 0 ]; then
        STATUS_EMOJI="🟡 伪装拉锯中"
    else
        STATUS_EMOJI="🔴 目标已暴露"
    fi

    # 动态国旗
    case "$REGION_CODE" in
        "JP") FLAG="🇯🇵" ;;
        "US") FLAG="🇺🇸" ;;
        "DE") FLAG="🇩🇪" ;;
        "SG") FLAG="🇸🇬" ;;
        *) FLAG="🌐" ;;
    esac

    # 5. 组装 Markdown 消息体 (吸收了老版本的优点)
    read -r -d '' MSG <<EOT
📊 **IP-Sentinel 每日简报 (${FLAG} ${REGION_NAME})**
----------------------------
📍 **节点名称**: \`${NODE_NAME}\`
📡 **出口 IP**: \`${CURRENT_IP}\`
🛡️ **IP 属性**: ${IP_TYPE}
🔰 **当前状态**: ${STATUS_EMOJI}

📅 **24H 统计数据**:
🚀 执行总数: ${TOTAL_SESSIONS} 次
✅ 成功伪装: ${SUCCESS_COUNT} 次
❌ 判定送中: ${FAILED_COUNT} 次
⚠️ 未知跳转: ${UNKNOWN_COUNT} 次
📈 综合胜率: **${RATE}%**

🕒 **最近执行快照**:
时间: ${LAST_TIME:-"暂无数据"}
结论: ${LAST_SCORE:-"暂无数据"}
----------------------------
💡 哨兵正在后台默默守护您的资产。
EOT
fi

# 6. 调用 API 推送 (增加返回值校验输出，方便查错)
RESPONSE=$(curl -s -m 10 -X POST "https://api.telegram.org/bot${TG_TOKEN}/sendMessage" \
    -d "chat_id=${CHAT_ID}" \
    -d "text=${MSG}" \
    -d "parse_mode=Markdown")

if [[ "$RESPONSE" != *"\"ok\":true"* ]]; then
    echo "❌ 战报发送失败！API 响应: $RESPONSE" >> "${INSTALL_DIR}/logs/error.log"
else
    echo "✅ 战报推送成功！"
fi