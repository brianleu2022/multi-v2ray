#!/bin/bash
# Author: Jrohy
# github: https://github.com/Jrohy/multi-v2ray

begin_path="$(pwd)"

install_way=0
show_help=0
remove=0
chinese=0

base_source_path="https://multi.netlify.app"
util_path="/etc/v2ray_util/util.cfg"
util_cfg="${base_source_path}/v2ray_util/util_core/util.cfg"
bash_completion_shell="${base_source_path}/v2ray"
clean_iptables_shell="${base_source_path}/v2ray_util/global_setting/clean_iptables.sh"

[[ -f /etc/redhat-release && "$SHELL" != *zsh* ]] && unalias -a
[[ "$SHELL" == *zsh* ]] && env_file=".zshrc" || env_file=".bashrc"

red="31m"
green="32m"
yellow="33m"
blue="36m"
fuchsia="35m"

colorEcho() {
    local color="$1"
    shift
    echo -e "\033[${color}$*\033[0m"
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

get_pip_cmd() {
    if command_exists pip; then
        echo "pip"
    elif command_exists pip3; then
        echo "pip3"
    elif command_exists python3; then
        echo "python3 -m pip"
    else
        return 1
    fi
}

find_v2ray_util_bin() {
    local path

    path="$(command -v v2ray-util 2>/dev/null)"
    [[ -n "$path" && -x "$path" ]] && { echo "$path"; return 0; }

    for path in \
        /usr/local/bin/v2ray-util \
        /usr/bin/v2ray-util \
        /root/.local/bin/v2ray-util
    do
        [[ -x "$path" ]] && { echo "$path"; return 0; }
    done

    return 1
}

get_rc_local_service_file() {
    systemctl status rc-local 2>/dev/null \
        | grep loaded \
        | egrep -o '[A-Za-z/._-]+/rc-local.service' \
        | head -n1
}

get_rc_local_exec_file() {
    local service_file="$1"
    [[ -n "$service_file" && -f "$service_file" ]] || return 1
    grep ExecStart "$service_file" | awk '{print $1}' | cut -d= -f2
}

append_line_if_missing() {
    local file="$1"
    local pattern="$2"
    local line="$3"

    [[ -f "$file" ]] || touch "$file"
    grep -q "$pattern" "$file" 2>/dev/null || echo "$line" >> "$file"
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --remove)
                remove=1
                ;;
            -h|--help)
                show_help=1
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
                ;;
        esac
        shift
    done
}

usage() {
    echo "bash v2ray.sh [-h|--help] [-k|--keep] [--remove]"
    echo "  -h, --help           Show help"
    echo "  -k, --keep           keep the config.json to update"
    echo "      --remove         remove v2ray,xray && multi-v2ray"
    echo "                       no params to new install"
    return 0
}

closeSELinux() {
    if [[ -s /etc/selinux/config ]] && grep -q 'SELINUX=enforcing' /etc/selinux/config; then
        sed -i 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/selinux/config
        setenforce 0 >/dev/null 2>&1
    fi
}

checkSys() {
    [[ "$(id -u)" != "0" ]] && {
        colorEcho "${red}" "Error: You must be root to run this script"
        exit 1
    }

    if command_exists apt-get; then
        package_manager="apt-get"
    elif command_exists dnf; then
        package_manager="dnf"
    elif command_exists yum; then
        package_manager="yum"
    else
        colorEcho "${red}" "Not support OS!"
        exit 1
    fi
}

installDependent() {
    if [[ "$package_manager" == "dnf" || "$package_manager" == "yum" ]]; then
        "$package_manager" install socat crontabs bash-completion which -y
    else
        "$package_manager" update -y
        "$package_manager" install socat cron bash-completion ntpdate gawk curl ca-certificates -y
    fi

    source <(curl -sL https://python3.netlify.app/install.sh)
}

removeV2Ray() {
    local pip_cmd rc_service rc_file

    bash <(curl -L -s https://multi.netlify.app/go.sh) --remove >/dev/null 2>&1
    rm -rf /etc/v2ray /var/log/v2ray >/dev/null 2>&1

    bash <(curl -L -s https://multi.netlify.app/go.sh) --remove -x >/dev/null 2>&1
    rm -rf /etc/xray /var/log/xray >/dev/null 2>&1

    bash <(curl -L -s "$clean_iptables_shell")

    pip_cmd="$(get_pip_cmd 2>/dev/null)"
    [[ -n "$pip_cmd" ]] && $pip_cmd uninstall v2ray_util -y >/dev/null 2>&1

    rm -rf \
        /usr/share/bash-completion/completions/v2ray.bash \
        /usr/share/bash-completion/completions/v2ray \
        /usr/share/bash-completion/completions/xray \
        /etc/bash_completion.d/v2ray.bash \
        /usr/local/bin/v2ray \
        /usr/local/bin/xray \
        /usr/local/bin/v2ray-util \
        /root/.local/bin/v2ray-util \
        /etc/v2ray_util \
        /etc/profile.d/iptables.sh \
        /root/.iptables \
        >/dev/null 2>&1

    crontab -l 2>/dev/null | sed '/SHELL=/d;/v2ray/d;/xray/d' > crontab.txt
    crontab crontab.txt >/dev/null 2>&1
    rm -f crontab.txt >/dev/null 2>&1

    if [[ "$package_manager" == "dnf" || "$package_manager" == "yum" ]]; then
        systemctl restart crond >/dev/null 2>&1
    else
        systemctl restart cron >/dev/null 2>&1
    fi

    sed -i '/v2ray/d' ~/"$env_file" 2>/dev/null
    sed -i '/xray/d' ~/"$env_file" 2>/dev/null
    source ~/"$env_file" >/dev/null 2>&1

    rc_service="$(get_rc_local_service_file)"
    rc_file="$(get_rc_local_exec_file "$rc_service")"
    [[ -n "$rc_file" && -f "$rc_file" ]] && sed -i '/iptables/d' "$rc_file"

    colorEcho "${green}" "uninstall success!"
}

setup_rc_local_iptables() {
    local rc_service rc_file local_ip iptable_way

    [[ -e /etc/profile.d/iptables.sh ]] && rm -f /etc/profile.d/iptables.sh

    rc_service="$(get_rc_local_service_file)"
    rc_file="$(get_rc_local_exec_file "$rc_service")"

    [[ -n "$rc_file" ]] || return 0

    if [[ ! -f "$rc_file" ]] || ! grep -q 'iptables' "$rc_file" 2>/dev/null; then
        local_ip="$(curl -s http://api.ipify.org 2>/dev/null)"
        [[ "$local_ip" == *:* ]] && iptable_way="ip6tables" || iptable_way="iptables"

        if [[ ! -f "$rc_file" ]] || ! grep -q '/bin/bash' "$rc_file" 2>/dev/null; then
            echo "#!/bin/bash" >> "$rc_file"
        fi

        if [[ -n "$rc_service" && -f "$rc_service" ]] && ! grep -q '\[Install\]' "$rc_service" 2>/dev/null; then
            cat >> "$rc_service" << EOF

[Install]
WantedBy=multi-user.target
EOF
            systemctl daemon-reload
        fi

        echo "[[ -e /root/.iptables ]] && ${iptable_way}-restore -c < /root/.iptables" >> "$rc_file"
        chmod +x "$rc_file"
        systemctl restart rc-local >/dev/null 2>&1
        systemctl enable rc-local >/dev/null 2>&1
        ${iptable_way}-save -c > /root/.iptables 2>/dev/null
    fi
}

install_v2ray_util() {
    local pip_cmd install_ok=0

    pip_cmd="$(get_pip_cmd)"
    [[ -z "$pip_cmd" ]] && {
        colorEcho "${red}" "pip no install!"
        exit 1
    }

    $pip_cmd install -U v2ray_util >/dev/null 2>&1 && install_ok=1

    if [[ "$install_ok" -ne 1 ]]; then
        if [[ "$pip_cmd" == "pip" || "$pip_cmd" == "pip3" ]]; then
            $pip_cmd install -U v2ray_util --break-system-packages >/dev/null 2>&1 && install_ok=1
        else
            python3 -m pip install -U v2ray_util --break-system-packages >/dev/null 2>&1 && install_ok=1
        fi
    fi

    [[ "$install_ok" -ne 1 ]] && {
        colorEcho "${red}" "v2ray_util install failed!"
        exit 1
    }
}

prepare_util_config() {
    if [[ -f "$util_path" ]]; then
        grep -q 'lang' "$util_path" 2>/dev/null || echo "lang=en" >> "$util_path"
    else
        mkdir -p /etc/v2ray_util
        curl -L -s "$util_cfg" > "$util_path"
    fi

    [[ "$chinese" -eq 1 ]] && sed -i 's/lang=en/lang=zh/g' "$util_path"
}

create_command_links() {
    local v2ray_util_bin

    v2ray_util_bin="$(find_v2ray_util_bin)"
    [[ -z "$v2ray_util_bin" ]] && {
        colorEcho "${red}" "v2ray-util command not found after install!"
        exit 1
    }

    rm -f /usr/local/bin/v2ray /usr/local/bin/xray >/dev/null 2>&1
    ln -sf "$v2ray_util_bin" /usr/local/bin/v2ray
    ln -sf "$v2ray_util_bin" /usr/local/bin/xray

    hash -r

    [[ ! -x /usr/local/bin/v2ray ]] && {
        colorEcho "${red}" "create /usr/local/bin/v2ray failed!"
        exit 1
    }

    [[ ! -x /usr/local/bin/xray ]] && {
        colorEcho "${red}" "create /usr/local/bin/xray failed!"
        exit 1
    }
}

update_bash_completion() {
    rm -f \
        /etc/bash_completion.d/v2ray.bash \
        /usr/share/bash-completion/completions/v2ray.bash \
        >/dev/null 2>&1

    curl -L -s "$bash_completion_shell" > /usr/share/bash-completion/completions/v2ray
    curl -L -s "$bash_completion_shell" > /usr/share/bash-completion/completions/xray

    if [[ "$SHELL" != *zsh* ]]; then
        source /usr/share/bash-completion/completions/v2ray >/dev/null 2>&1
        source /usr/share/bash-completion/completions/xray >/dev/null 2>&1
    fi
}

updateProject() {
    setup_rc_local_iptables
    install_v2ray_util
    prepare_util_config
    create_command_links
    update_bash_completion

    [[ "$install_way" -eq 0 ]] && bash <(curl -L -s https://multi.netlify.app/go.sh)
}

timeSync() {
    [[ "$install_way" -ne 0 ]] && return 0

    echo -e "Time Synchronizing.. "

    if command_exists ntpdate; then
        ntpdate pool.ntp.org
    elif command_exists chronyc; then
        chronyc -a makestep
    fi

    if [[ $? -eq 0 ]]; then
        colorEcho "${green}" "Time Sync Success"
        colorEcho "${blue}" "now: $(date -R)"
    fi
}

profileInit() {
    if [[ -f ~/"$env_file" ]] && grep -q 'v2ray' ~/"$env_file" 2>/dev/null; then
        sed -i '/v2ray/d' ~/"$env_file"
        source ~/"$env_file" >/dev/null 2>&1
    fi

    if [[ -f ~/"$env_file" ]] && ! grep -q 'PYTHONIOENCODING=utf-8' ~/"$env_file" 2>/dev/null; then
        echo "export PYTHONIOENCODING=utf-8" >> ~/"$env_file"
        source ~/"$env_file" >/dev/null 2>&1
    fi

    [[ "$install_way" -eq 0 ]] && v2ray new
    echo ""
}

installFinish() {
    local way

    cd "$begin_path" || exit 1

    [[ "$install_way" -eq 0 ]] && way="install" || way="update"
    colorEcho "${green}" "multi-v2ray ${way} success!\n"

    if [[ "$install_way" -eq 0 ]]; then
        clear
        hash -r
        v2ray info
        echo -e "please input 'v2ray' command to manage v2ray\n"
    fi
}

main() {
    parse_args "$@"

    [[ "$show_help" -eq 1 ]] && usage && return
    [[ "$remove" -eq 1 ]] && checkSys && removeV2Ray && return

    [[ "$install_way" -eq 0 ]] && colorEcho "${blue}" "new install\n"

    checkSys
    installDependent
    closeSELinux
    timeSync
    updateProject
    profileInit
    installFinish
}

main "$@"
