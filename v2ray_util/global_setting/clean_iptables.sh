#!/bin/bash
# Optimized for Debian 12+ (Pure nftables & ss)
# This file serves as a replacement for clean_iptables.sh

clean_nftables() {
    # 检查 nft 命令是否存在，不存在说明完全没有 nftables 规则需要清理
    if ! command -v nft >/dev/null 2>&1; then
        return 0
    fi

    # 1. 获取当前系统正在监听的 TCP 和 UDP 端口列表 (使用现代的 ss 替代老旧的 netstat)
    # 结果会变成一个空格分隔的字符串，例如: " |80|443|10086| " 方便后续精准匹配
    local listening_ports=" |$(ss -tunpl | awk '{print $5}' | grep -oE '[0-9]+$' | sort -u | tr '\n' '|') "

    # 2. 从 nftables 中提取出当前所有针对特定端口的规则
    # 我们需要找到包含 'tcp dport' 或 'udp dport' 的规则，并提取出端口和它们在链中的 handle (句柄)
    # nftables 删除规则必须通过 handle 来精准删除
    nft list ruleset 2>/dev/null | grep -E 'dport' | while read -r line; do
        # 提取端口号
        local port=$(echo "$line" | grep -oE '(dport)[[:space:]]+[0-9]+' | awk '{print $2}')
        # 提取该条规则的 handle ID
        local handle=$(echo "$line" | grep -oE 'handle[[:space:]]+[0-9]+' | awk '{print $2}')
        # 提取表名 (table) 和 链名 (chain)
        # 默认 multi-v2ray 通常在 inet filter 中操作，这里做动态提取以防万一
        local table_info=$(nft list ruleset | grep -B 2 "$line" | grep -E '^table|^chain' | tr '\n' ' ')
        local table_name=$(echo "$table_info" | grep -oE 'table [a-zA-Z0-9_-]+ [a-zA-Z0-9_-]+' | awk '{print $3}')
        local family=$(echo "$table_info" | grep -oE 'table [a-zA-Z0-9_-]+' | awk '{print $2}')
        local chain_name=$(echo "$table_info" | grep -oE 'chain [a-zA-Z0-9_-]+' | awk '{print $2}')

        if [[ -n "$port" && -n "$handle" && -n "$chain_name" ]]; then
            # 3. 核心判断：如果开放的端口，不在当前系统监听的端口列表中
            if [[ ! "$listening_ports" =~ "|$port|" ]]; then
                # 执行删除：nft delete rule <family> <table_name> <chain_name> handle <id>
                nft delete rule "$family" "$table_name" "$chain_name" handle "$handle" 2>/dev/null
            fi
        fi
    done
}

# 执行清理动作
clean_nftables
