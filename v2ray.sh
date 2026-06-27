#!/bin/bash
# Author: Jrohy
# github: https://github.com/Jrohy/multi-v2ray
# Optimized for Debian 12+ (Pure nftables & apt)

# 记录最开始运行脚本的路径
begin_path="$(pwd)"

# 安装方式, 0为全新安装, 1为保留v2ray配置更新
install_way=0

# 定义操作变量, 0为否, 1为是
help=0
remove=0
chinese=0

base_source_path="https://multi.netlify.app"

util_path="/etc/v2ray_util/util.cfg"
util_cfg="$base_source_path/v2ray_util/util_core/util.cfg"
bash_completion_shell="$base_source_path/v2ray"
clean_iptables_shell="$base_source_path/v2ray_util/global_setting/clean_iptables.sh"

[[ -z "$(echo "$SHELL" | grep zsh)" ]] && env_file=".bashrc" || env_file=".zshrc"

####### color code ########
red="31m"
green="32m"
yellow="33m"
blue="36m"
fuchsia="35m"

colorEcho() {
    color=$1
    echo -e "\033[${color}${@:2}\033[0m"
}

get_pip_cmd() {
    if command -v pip >/dev/null 2>&1; then
        echo "pip"
        return 0
    elif command -v pip3 >/dev/null 2>&1; then
        echo "pip3"
        return 0
    elif command -v python3 >/dev/null 2>&1; then
        echo "python3 -m pip"
        return 0
    fi
    return 1
}

find_v2ray_util_bin() {
    local bin_path

    bin_path="$(command -v v2ray-util 2>/dev/null)"
    if [[ -n "$bin_path" && -x "$bin_path" ]]; then
        echo "$bin_path"
        return 0
    fi

    for bin_path in \
        /usr/local/bin/v2ray-util \
        /usr/bin/v2ray-util \
        /root/.local/bin/v2ray-util
    do
        if [[ -x "$bin_path" ]]; then
            echo "$bin_path"
            return 0
        fi
    done

    return 1
}

####### get params #########
while [[ $# > 0 ]]; do
    key="$1"
    case $key in
        --remove)
            remove=1
            ;;
        -h|--help)
            help=1
            ;;
        -k|--keep)
            install_way=1
            colorEcho "${blue}" "keep config to update\n"
            ;;
        --zh)
            chinese=1
            colorEcho "${blue}" "安装中文版..\n"
            ;;
        *)
            # unknown option
            ;;
    esac
    shift
done
#############################

help() {
    echo "bash v2ray.sh [-h|--help] [-k|--keep] [--remove]"
    echo "  -h, --help           Show help"
    echo "  -k, --keep           keep the config.json to update"
    echo "      --remove         remove v2ray,xray && multi-v2ray"
    echo "                       no params to new install"
    return 0
}

removeV2Ray() {
    local pip_cmd

    # 卸载V2ray脚本
    bash <(curl -L -s https://raw.githubusercontent.com/brianleu2022/multi-v2ray/refs/heads/master/go.sh) --remove >/dev/null 2>&1
    rm -rf /etc/v2ray >/dev/null 2>&1
    rm -rf /var/log/v2ray >/dev/null 2>&1

    # 卸载Xray脚本
    bash <(curl -L -s https://raw.githubusercontent.com/brianleu2022/multi-v2ray/refs/heads/master/go.sh) --remove -x >/dev/null 2>&1
    rm -rf /etc/xray >/dev/null 2>&1
    rm -rf /var/log/xray >/dev/null 2>&1

    # 清理v2ray相关规则
    bash <(curl -L -s "$clean_iptables_shell")
    if command -v nft >/dev/null 2>&1; then
        nft flush ruleset 2>/dev/null
    fi

    # 卸载multi-v2ray
    pip_cmd="$(get_pip_cmd 2>/dev/null)"
    if [[ -n "$pip_cmd" ]]; then
        $pip_cmd uninstall v2ray_util -y >/dev/null 2>&1
    fi

    rm -rf /usr/share/bash-completion/completions/v2ray.bash >/dev/null 2>&1
    rm -rf /usr/share/bash-completion/completions/v2ray >/dev/null 2>&1
    rm -rf /usr/share/bash-completion/completions/xray >/dev/null 2>&1
    rm -rf /etc/bash_completion.d/v2ray.bash >/dev/null 2>&1
    rm -rf /usr/local/bin/v2ray >/dev/null 2>&1
    rm -rf /usr/local/bin/xray >/dev/null 2>&1
    rm -rf /usr/local/bin/v2ray-util >/dev/null 2>&1
    rm -rf /root/.local/bin/v2ray-util >/dev/null 2>&1
    rm -rf /etc/v2ray_util >/dev/null 2>&1
    rm -rf /etc/profile.d/iptables.sh >/dev/null 2>&1
    rm -rf /root/.iptables >/dev/null 2>&1
    rm -rf /root/.nftables.conf >/dev/null 2>&1

    # 删除v2ray定时更新任务
    crontab -l 2>/dev/null | sed '/SHELL=/d;/v2ray/d;/xray/d' > crontab.txt
    crontab crontab.txt >/dev/null 2>&1
    rm -f crontab.txt >/dev/null 2>&1

    systemctl restart cron >/dev/null 2>&1

    # 删除multi-v2ray环境变量
    sed -i '/v2ray/d' ~/"$env_file" 2>/dev/null
    sed -i '/xray/d' ~/"$env_file" 2>/dev/null
    source ~/"$env_file" >/dev/null 2>&1

    colorEcho "${green}" "uninstall success!"
}

checkSys() {
    # 检查是否为Root
    [[ "$(id -u)" != "0" ]] && { colorEcho "${red}" "Error: You must be root to run this script"; exit 1; }

    # 锁定仅支持 apt 架构的 Debian 12+ 系统
    if ! command -v apt-get >/dev/null 2>&1; then
        colorEcho "${red}" "Not support OS! This script is optimized for Debian/Ubuntu systems."
        exit 1
    fi
}

# 安装依赖
installDependent() {
    apt-get update -y
    apt-get install socat cron bash-completion ntpdate gawk curl ca-certificates nftables -y

    # install python3 & pip
    source <(curl -sL https://python3.netlify.app/install.sh)
}

updateProject() {
    local pip_cmd pip_install_ok=0 v2ray_util_bin

    pip_cmd="$(get_pip_cmd)"
    [[ -z "$pip_cmd" ]] && colorEcho "${red}" "pip no install!" && exit 1

    [[ -e /etc/profile.d/iptables.sh ]] && rm -f /etc/profile.d/iptables.sh

    # --- nftables 规则持久化配置 (Debian 12+) ---
    if command -v nft >/dev/null 2>&1; then
        systemctl enable nftables >/dev/null 2>&1
        nft list ruleset > /root/.nftables.conf 2>/dev/null
        if [[ -f /etc/nftables.conf ]]; then
            if ! grep -q "/root/.nftables.conf" /etc/nftables.conf; then
                echo 'include "/root/.nftables.conf"' >> /etc/nftables.conf
            fi
        fi
    fi

    # Debian 12+ 强行兼容 PEP 668 规则限制
    $pip_cmd install -U v2ray_util >/dev/null 2>&1 && pip_install_ok=1

    if [[ $pip_install_ok -ne 1 ]]; then
        if [[ "$pip_cmd" == "pip" || "$pip_cmd" == "pip3" ]]; then
            $pip_cmd install -U v2ray_util --break-system-packages >/dev/null 2>&1 && pip_install_ok=1
        else
            python3 -m pip install -U v2ray_util --break-system-packages >/dev/null 2>&1 && pip_install_ok=1
        fi
    fi

    [[ $pip_install_ok -ne 1 ]] && colorEcho "${red}" "v2ray_util install failed!" && exit 1

    if [[ -e "$util_path" ]]; then
        [[ -z "$(grep lang "$util_path" 2>/dev/null)" ]] && echo "lang=en" >> "$util_path"
    else
        mkdir -p /etc/v2ray_util
        curl -L -s "$util_cfg" > "$util_path"
    fi

    [[ $chinese == 1 ]] && sed -i "s/lang=en/lang=zh/g" "$util_path"

    v2ray_util_bin="$(find_v2ray_util_bin)"
    [[ -z "$v2ray_util_bin" ]] && colorEcho "${red}" "v2ray-util command not found after install!" && exit 1

    rm -f /usr/local/bin/v2ray >/dev/null 2>&1
    ln -sf "$v2ray_util_bin" /usr/local/bin/v2ray
    rm -f /usr/local/bin/xray >/dev/null 2>&1
    ln -sf "$v2ray_util_bin" /usr/local/bin/xray

    hash -r

    [[ ! -x /usr/local/bin/v2ray ]] && colorEcho "${red}" "create /usr/local/bin/v2ray failed!" && exit 1
    [[ ! -x /usr/local/bin/xray ]] && colorEcho "${red}" "create /usr/local/bin/xray failed!" && exit 1

    # 移除旧的v2ray bash_completion脚本
    [[ -e /etc/bash_completion.d/v2ray.bash ]] && rm -f /etc/bash_completion.d/v2ray.bash
    [[ -e /usr/share/bash-completion/completions/v2ray.bash ]] && rm -f /usr/share/bash-completion/completions/v2ray.bash

    # 更新v2ray bash_completion脚本
    curl -L -s "$bash_completion_shell" > /usr/share/bash-completion/completions/v2ray
    curl -L -s "$bash_completion_shell" > /usr/share/bash-completion/completions/xray

    if [[ -z "$(echo "$SHELL" | grep zsh)" ]]; then
        source /usr/share/bash-completion/completions/v2ray >/dev/null 2>&1
        source /usr/share/bash-completion/completions/xray >/dev/null 2>&1
    fi

    # 安装V2ray主程序
    [[ ${install_way} == 0 ]] && bash <(curl -L -s https://raw.githubusercontent.com/brianleu2022/multi-v2ray/refs/heads/master/go.sh)
}

# 时间同步
timeSync() {
    if [[ ${install_way} == 0 ]]; then
        echo -e "Time Synchronizing.. "
        if command -v ntpdate >/dev/null 2>&1; then
            ntpdate pool.ntp.org
        elif command -v chronyc >/dev/null 2>&1; then
            chronyc -a makestep
        fi

        if [[ $? -eq 0 ]]; then
            colorEcho "${green}" "Time Sync Success"
            colorEcho "${blue}" "now: $(date -R)"
        fi
    fi
}

profileInit() {
    # 清理v2ray模块环境变量
    [[ -f ~/"$env_file" && -n "$(grep v2ray ~/"$env_file" 2>/dev/null)" ]] && sed -i '/v2ray/d' ~/"$env_file" && source ~/"$env_file" >/dev/null 2>&1

    # 解决Python3中文显示问题
    [[ -f ~/"$env_file" && -z "$(grep PYTHONIOENCODING=utf-8 ~/"$env_file" 2>/dev/null)" ]] && echo "export PYTHONIOENCODING=utf-8" >> ~/"$env_file" && source ~/"$env_file" >/dev/null 2>&1

    # 全新安装的新配置
    [[ ${install_way} == 0 ]] && v2ray new

    echo ""
}

installFinish() {
    # 回到原点
    cd "${begin_path}"

    [[ ${install_way} == 0 ]] && WAY="install" || WAY="update"
    colorEcho "${green}" "multi-v2ray ${WAY} success!\n"

    if [[ ${install_way} == 0 ]]; then
        clear
        hash -r
        v2ray info
        echo -e "please input 'v2ray' command to manage v2ray\n"
    fi
}

main() {
    [[ ${help} == 1 ]] && help && return
    [[ ${remove} == 1 ]] && removeV2Ray && return

    [[ ${install_way} == 0 ]] && colorEcho "${blue}" "new install\n"

    checkSys
    installDependent
    timeSync
    updateProject
    profileInit
    installFinish
}

main
