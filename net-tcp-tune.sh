#!/bin/bash
#=============================================================================
# BBR v3 终极优化脚本 - Ultimate Edition
# 功能：结合 XanMod 官方内核的稳定性 + 专业队列算法调优
# 特点：安全性 + 性能 双优化
#=============================================================================
# 版本管理规则：
# 1. 正式版本迭代时修改 SCRIPT_VERSION，并更新版本备注（保留最新5条）
# 2. 临时热修/不发版时只修改 SCRIPT_LAST_UPDATE，用于快速识别脚本是否已更新
#=============================================================================
# v5.6.0 更新: 新增菜单 98「更新脚本」，从 flyto23/bbr 拉取最新版并安装到 /usr/local/bin；移除临时SOCKS5代理、虚拟内存管理、查看系统详细状态(原9-11)，一键反代改为 9 (by Eric86777)
# v5.5.0 更新: 精简版：移除代理部署(原12-16)、IP/网络检测与第三方工具(原18-33)，仅保留内核/BBR优化/系统配置/一键反代/一键优化，菜单重新编号（一键优化保留 66 快捷入口） (by Eric86777)
# v5.4.22 更新: 纯IPv6机器保护(一键优化跳过禁用IPv6、Realm修复保留原监听)；cloudflared安装先下载到临时文件验证后再替换；Caddy安装按CPU架构选择下载包并在临时目录验证后安装 (by Eric86777)
# v5.4.21 更新: 修复旧版官方安装(无xray账号、服务以nobody运行、日志属nobody)的Xray卸载被“专用 xray 账号不存在”拦住 (by Eric86777)
# v5.4.20 更新: 功能3提速与修复：tcp_notsent_lowat恢复内核默认(长距离起步提速)；缓冲区按内存封顶并设置tcp_mem；tcp_rmem起步值改回131072；内核不支持的参数自动注释；多队列网卡保留mq (by Eric86777)

SCRIPT_VERSION="5.6.0"
SCRIPT_LAST_UPDATE="新增在线更新，移除临时代理/虚拟内存/详细状态"
#=============================================================================

#=============================================================================
# 📋 推荐配置方案（基于实测优化）
#=============================================================================
# 
# 💡 测试环境：经过本人十几二十几台不同服务器的测试
#    包括酷雪云北京9929等多个节点的实测验证
# 
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 
# ⭐ 首选方案（推荐）：
#    步骤1 → 执行菜单选项 1：BBR v3 内核安装
#    步骤2 → 执行菜单选项 3：BBR 直连/落地优化（智能带宽检测）
#            选择子选项 1 进行自动检测
#    步骤3 → 执行菜单选项 6：Realm转发timeout修复（如使用 Realm 转发）
# 
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 
# ⚡ 极简方案（一键）：
#    执行菜单选项 66：一键全自动优化
#    （自动完成 内核安装 → BBR 直连优化 → DNS 净化 → Realm 修复 → IPv6 处理）
# 
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 
#=============================================================================

# 颜色定义（保留中文变量名以兼容现有代码）
gl_hong='\033[31m'      # 红色
gl_lv='\033[32m'        # 绿色
gl_huang='\033[33m'     # 黄色
gl_bai='\033[0m'        # 重置
gl_kjlan='\033[96m'     # 亮青色
gl_zi='\033[35m'        # 紫色
gl_hui='\033[90m'       # 灰色

# 显示宽度计算（中文占2列，ASCII占1列）
get_display_width() {
    local str="$1"
    local byte_len=$(printf '%s' "$str" | LC_ALL=C wc -c | tr -d ' ')
    local char_len=${#str}
    local extra=$((byte_len - char_len))
    local wide=$((extra / 2))
    echo $((char_len + wide))
}

# 格式化字符串到固定显示宽度（截断+填充，确保宽度精确）
format_fixed_width() {
    local str="$1"
    local target_width=$2
    local current_width=$(get_display_width "$str")

    # 如果太长，截断
    if [ "$current_width" -gt "$target_width" ]; then
        local result=""
        local i=0
        local len=${#str}
        while [ $i -lt $len ]; do
            local char="${str:$i:1}"
            local test_str="${result}${char}"
            local test_width=$(get_display_width "$test_str")
            if [ "$test_width" -gt $((target_width - 2)) ]; then
                str="${result}.."
                break
            fi
            result="$test_str"
            i=$((i + 1))
        done
        current_width=$(get_display_width "$str")
    fi

    # 填充到目标宽度
    local padding=$((target_width - current_width))
    if [ $padding -gt 0 ]; then
        printf "%s%*s" "$str" "$padding" ""
    else
        printf "%s" "$str"
    fi
}

# GitHub 代理设置
gh_proxy="https://"

# 脚本仓库地址与本地安装路径（菜单 98 在线更新使用）
SCRIPT_REPO_URL="https://github.com/flyto23/bbr"
SCRIPT_RAW_BASE="https://raw.githubusercontent.com/flyto23/bbr/refs/heads/main"
SCRIPT_LOCAL_PATH="/usr/local/bin/net-tcp-tune.sh"

# 配置文件路径（使用独立文件，不破坏系统配置）
# sysctl.d 下的文件按文件名顺序加载，同名参数后加载者生效。旧文件名 99-bbr-ultimate.conf
# 排在字母开头的文件之前，会被其覆盖（如商家镜像预置的 /etc/sysctl.d/local.conf），
# 而冲突检查只识别数字开头的文件名，查不到这类文件。v5.4.11 起改用 zzz- 前缀，
# 保证功能3的配置最后加载；旧文件在重新执行功能3时自动迁移（删除）。
SYSCTL_CONF="/etc/sysctl.d/zzz-bbr-ultimate.conf"
SYSCTL_CONF_LEGACY="/etc/sysctl.d/99-bbr-ultimate.conf"

#=============================================================================
# 常量定义（版本号、URL 等集中管理）
#=============================================================================

# 版本号（SCRIPT_VERSION / SCRIPT_LAST_UPDATE 在文件头部定义）

#=============================================================================
# 日志系统
#=============================================================================

readonly LOG_FILE="/var/log/net-tcp-tune.log"
LOG_LEVEL="${LOG_LEVEL:-INFO}"
NETTCP_TEMP_DIRS=""

# 统一日志函数
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    # 写入日志文件（静默失败）
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE" 2>/dev/null || true

    # 根据级别输出到终端
    case "$level" in
        ERROR)
            echo -e "${gl_hong}[ERROR] $message${gl_bai}" >&2
            ;;
        WARN)
            echo -e "${gl_huang}[WARN] $message${gl_bai}"
            ;;
        INFO)
            [ "$LOG_LEVEL" != "ERROR" ] && echo -e "${gl_lv}[INFO] $message${gl_bai}"
            ;;
        DEBUG)
            [ "$LOG_LEVEL" = "DEBUG" ] && echo -e "${gl_hui}[DEBUG] $message${gl_bai}"
            ;;
    esac
}

# 便捷日志函数
log_error() { log "ERROR" "$@"; }
log_warn()  { log "WARN" "$@"; }
log_info()  { log "INFO" "$@"; }
log_debug() { log "DEBUG" "$@"; }

#=============================================================================
# 错误处理
#=============================================================================

# 清理临时文件
cleanup_temp_files() {
    local temp_dir
    for temp_dir in $NETTCP_TEMP_DIRS; do
        case "$temp_dir" in
            /tmp/net-tcp-tune.*|/private/tmp/net-tcp-tune.*)
                [ -d "$temp_dir" ] && rm -rf "$temp_dir" 2>/dev/null || true
                ;;
        esac
    done
}

# 退出时清理
trap cleanup_temp_files EXIT

#=============================================================================
# 工具函数
#=============================================================================

check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${gl_hong}错误: ${gl_bai}此脚本需要 root 权限运行！"
        echo "请使用: sudo bash $0"
        exit 1
    fi
}

break_end() {
    [ "$AUTO_MODE" = "1" ] && return
    echo -e "${gl_lv}操作完成${gl_bai}"
    echo "按任意键继续..."
    read -n 1 -s -r -p ""
    echo ""
}

clean_sysctl_conf() {
    # 备份主配置文件
    if [ -f /etc/sysctl.conf ] && ! [ -f /etc/sysctl.conf.bak.original ]; then
        cp /etc/sysctl.conf /etc/sysctl.conf.bak.original
    fi
    
    # 注释所有冲突参数
    sed -i '/^net\.core\.rmem_max/s/^/# /' /etc/sysctl.conf 2>/dev/null
    sed -i '/^net\.core\.wmem_max/s/^/# /' /etc/sysctl.conf 2>/dev/null
    sed -i '/^net\.ipv4\.tcp_rmem/s/^/# /' /etc/sysctl.conf 2>/dev/null
    sed -i '/^net\.ipv4\.tcp_wmem/s/^/# /' /etc/sysctl.conf 2>/dev/null
    sed -i '/^net\.core\.default_qdisc/s/^/# /' /etc/sysctl.conf 2>/dev/null
    sed -i '/^net\.ipv4\.tcp_congestion_control/s/^/# /' /etc/sysctl.conf 2>/dev/null
}

# 注释 /etc/sysctl.conf 中与指定配置文件同名的全部参数行
# 原因：sysctl --system 总是最后加载 /etc/sysctl.conf（与文件名排序无关），其中的同名参数会
# 盖掉 sysctl.d 下所有文件。clean_sysctl_conf 只处理其中 6 个参数，其余同名项（如 swappiness、
# tcp_fin_timeout）在运行期仍会被盖回。这里按配置文件里实际写了哪些参数逐个处理，
# 只注释同名行，其它行不动；备份沿用 /etc/sysctl.conf.bak.original。
comment_sysctl_conf_duplicates() {
    local our_conf="$1"
    local target="/etc/sysctl.conf"
    [ -f "$our_conf" ] || return 0
    [ -f "$target" ] || return 0

    if ! [ -f /etc/sysctl.conf.bak.original ]; then
        cp "$target" /etc/sysctl.conf.bak.original 2>/dev/null
    fi

    local key key_re commented=0
    while IFS= read -r key; do
        [ -n "$key" ] || continue
        key_re=${key//./\\.}
        if grep -qE "^[[:space:]]*${key_re}[[:space:]]*=" "$target" 2>/dev/null; then
            if sed -i -E "s/^([[:space:]]*${key_re}[[:space:]]*=.*)\$/# \1/" "$target" 2>/dev/null; then
                commented=$((commented + 1))
            fi
        fi
    done < <(grep -E '^[[:space:]]*[a-zA-Z0-9_.]+[[:space:]]*=' "$our_conf" 2>/dev/null \
             | sed -E 's/^[[:space:]]*([a-zA-Z0-9_.]+)[[:space:]]*=.*/\1/' | sort -u)

    if [ "$commented" -gt 0 ]; then
        echo "已注释 /etc/sysctl.conf 中 ${commented} 个与本配置同名的参数（备份: /etc/sysctl.conf.bak.original）"
    fi
    return 0
}

install_package() {
    local packages=("$@")
    local missing_packages=()
    local os_release="/etc/os-release"
    local os_id=""
    local os_like=""
    local pkg_manager=""
    local update_cmd=()
    local install_cmd=()

    for package in "${packages[@]}"; do
        if ! command -v "$package" &>/dev/null; then
            missing_packages+=("$package")
        fi
    done

    if [ "${#missing_packages[@]}" -eq 0 ]; then
        return 0
    fi

    if [ -r "$os_release" ]; then
        # shellcheck disable=SC1091
        . "$os_release"
        os_id="${ID,,}"
        os_like="${ID_LIKE,,}"
    fi

    local detection="${os_id} ${os_like}"

    if [[ "$detection" =~ (debian|ubuntu) ]]; then
        pkg_manager="apt"
        update_cmd=(apt-get update)
        install_cmd=(apt-get install -y)
    elif [[ "$detection" =~ (rhel|centos|fedora|rocky|alma|redhat) ]]; then
        if command -v dnf &>/dev/null; then
            pkg_manager="dnf"
            update_cmd=(dnf makecache)
            install_cmd=(dnf install -y)
        elif command -v yum &>/dev/null; then
            pkg_manager="yum"
            update_cmd=(yum makecache)
            install_cmd=(yum install -y)
        else
            echo "错误: 未找到可用的 RHEL 系包管理器 (dnf 或 yum)" >&2
            return 1
        fi
    else
        echo "错误: 未支持的 Linux 发行版，无法自动安装依赖。请手动安装: ${missing_packages[*]}" >&2
        return 1
    fi

    if [ ${#update_cmd[@]} -gt 0 ]; then
        echo -e "${gl_huang}正在更新软件仓库...${gl_bai}"
        if ! "${update_cmd[@]}"; then
            echo "错误: 使用 ${pkg_manager} 更新软件仓库失败。" >&2
            return 1
        fi
    fi

    for package in "${missing_packages[@]}"; do
        echo -e "${gl_huang}正在安装 $package...${gl_bai}"
        if ! "${install_cmd[@]}" "$package"; then
            echo "错误: ${pkg_manager} 安装 $package 失败，请检查上方输出信息。" >&2
            return 1
        fi
    done
}

safe_download_script() {
    local url=$1
    local output_file=$2
    local part_file="${output_file}.part"
    local rc=1

    rm -f "$part_file"

    if command -v curl &>/dev/null; then
        curl -fsSL --connect-timeout 10 --max-time 60 --retry 2 --retry-delay 1 "$url" -o "$part_file"
        rc=$?
    elif command -v wget &>/dev/null; then
        wget -q --timeout=30 --tries=3 -O "$part_file" "$url"
        rc=$?
    else
        rm -f "$part_file"
        return 1
    fi

    if [ $rc -ne 0 ] || [ ! -s "$part_file" ]; then
        rm -f "$part_file"
        return 1
    fi

    if ! mv "$part_file" "$output_file"; then
        rm -f "$part_file"
        return 1
    fi

    return 0
}

verify_downloaded_script() {
    local file=$1

    if [ ! -s "$file" ]; then
        return 1
    fi

    if LC_ALL=C head -c 512 "$file" | grep -qiE '<!DOCTYPE|<html|404: Not Found|AccessDenied|Access Denied'; then
        return 1
    fi

    # shebang 必须在首行，同时处理 UTF-8 BOM (ef bb bf) 开头的情况
    local shebang
    shebang=$(LC_ALL=C head -n 1 "$file" | sed 's/^\xef\xbb\xbf//') || return 1
    echo "$shebang" | grep -Eq '(^#![[:space:]]*/([^[:space:]]*/)?(ba)?sh([[:space:]]|$))|(^#![[:space:]]*/usr/bin/env([[:space:]]+-S)?[[:space:]]+(ba)?sh([[:space:]]|$))'
}

run_remote_script() {
    if [ $# -lt 1 ]; then
        echo -e "${gl_hong}❌ 缺少脚本 URL${gl_bai}"
        return 1
    fi

    local url="$1"
    local interpreter="bash"
    if [ $# -ge 2 ]; then
        interpreter="$2"
        shift 2
    else
        shift 1
    fi

    local tmp_dir tmp_file
    tmp_dir=$(mktemp -d /tmp/net-tcp-tune.XXXXXX) || {
        echo -e "${gl_hong}❌ 无法创建临时目录${gl_bai}"
        return 1
    }
    NETTCP_TEMP_DIRS="${NETTCP_TEMP_DIRS}${NETTCP_TEMP_DIRS:+ }${tmp_dir}"
    tmp_file="${tmp_dir}/script.sh"

    if ! safe_download_script "$url" "$tmp_file"; then
        echo -e "${gl_hong}❌ 下载脚本失败: ${url}${gl_bai}"
        rm -rf "$tmp_dir"
        return 1
    fi

    if ! verify_downloaded_script "$tmp_file"; then
        echo -e "${gl_hong}❌ 脚本校验失败，已取消执行${gl_bai}"
        rm -rf "$tmp_dir"
        return 1
    fi

    local rc
    if [ "${1:-}" = "-s" ]; then
        shift
        "$interpreter" -s "$@" < "$tmp_file"
    else
        "$interpreter" "$tmp_file" "$@"
    fi
    rc=$?
    rm -rf "$tmp_dir"
    return $rc
}

check_disk_space() {
    local required_gb=$1
    local required_space_mb=$((required_gb * 1024))
    local available_space_mb=$(df -m / | awk 'NR==2 {print $4}')

    if [ "$available_space_mb" -lt "$required_space_mb" ]; then
        echo -e "${gl_huang}警告: ${gl_bai}磁盘空间不足！"
        echo "当前可用: $((available_space_mb/1024))G | 最低需求: ${required_gb}G"
        read -e -p "是否继续？(Y/N): " continue_choice
        case "$continue_choice" in
            [Yy]) return 0 ;;
            *) return 1 ;;
        esac
    fi
}

# 通用 IP 优先级设置函数
# 参数: $1 = "ipv4" 或 "ipv6"
set_ip_priority() {
    local ip_type="$1"

    # 参数校验
    if [ "$ip_type" != "ipv4" ] && [ "$ip_type" != "ipv6" ]; then
        echo -e "${gl_hong}错误：参数必须是 ipv4 或 ipv6${gl_bai}"
        return 1
    fi

    # 根据类型设置变量
    if [ "$ip_type" = "ipv4" ]; then
        local title="IPv4"
        local ipv4_precedence=100
        local ipv6_precedence=10
        local curl_flag="-4"
        local secondary_flag="-6"
        local primary="IPv4"
        local secondary="IPv6"
    else
        local title="IPv6"
        local ipv4_precedence=10
        local ipv6_precedence=100
        local curl_flag="-6"
        local secondary_flag="-4"
        local primary="IPv6"
        local secondary="IPv4"
    fi

    clear
    echo -e "${gl_kjlan}=== 设置${title}优先 ===${gl_bai}"
    echo ""

    # 备份原配置文件并记录原始状态
    if [ -f /etc/gai.conf ]; then
        cp /etc/gai.conf "/etc/gai.conf.bak.$(date +%Y%m%d_%H%M%S)"
        echo "已备份原配置文件到 /etc/gai.conf.bak.*"
        # 记录原先存在文件
        echo "existed" > /etc/gai.conf.original_state
    else
        # 记录原先不存在文件
        echo "not_existed" > /etc/gai.conf.original_state
        echo "原先无配置文件，已记录原始状态"
    fi

    echo "正在设置 ${title} 优先..."

    # 创建配置文件
    cat > /etc/gai.conf << EOF
# Configuration for getaddrinfo(3).
#
# 设置 ${title} 优先

# IPv4 addresses
precedence ::ffff:0:0/96  ${ipv4_precedence}

# IPv6 addresses
precedence ::/0           ${ipv6_precedence}

# IPv4-mapped IPv6 addresses
precedence ::1/128        50

# Link-local addresses
precedence fe80::/10      1
precedence fec0::/10      1
precedence fc00::/7       1

# Site-local addresses (deprecated)
precedence 2002::/16      30
EOF

    # 刷新 nscd 缓存（如果安装了）
    if command -v nscd &> /dev/null; then
        systemctl restart nscd 2>/dev/null || service nscd restart 2>/dev/null || true
        echo "已刷新 nscd DNS 缓存"
    fi

    # 刷新 systemd-resolved 缓存（如果使用）
    if command -v resolvectl &> /dev/null; then
        resolvectl flush-caches 2>/dev/null || true
        echo "已刷新 systemd-resolved DNS 缓存"
    fi

    echo -e "${gl_lv}✅ ${title} 优先已设置${gl_bai}"
    echo ""
    echo "当前出口 IP 地址："
    echo "------------------------------------------------"
    curl ${curl_flag} ip.sb 2>/dev/null || curl ip.sb
    echo ""
    echo "------------------------------------------------"
    echo ""
    echo -e "${gl_huang}提示：${gl_bai}"
    echo "1. 配置已生效，无需重启系统"
    echo "2. 新启动的程序将自动使用 ${title} 优先"
    echo "3. 如需强制指定，可使用: curl ${curl_flag} ip.sb (强制${primary}) 或 curl ${secondary_flag} ip.sb (强制${secondary})"
    echo "4. 已运行的长连接服务（如Nginx、Docker容器）可能需要重启服务才能应用"
    echo ""

    break_end
}

manage_ip_priority() {
    while true; do
        clear
        echo -e "${gl_kjlan}=== 设置IPv4/IPv6优先级 ===${gl_bai}"
        echo ""
        echo "1. 设置IPv4优先"
        echo "2. 设置IPv6优先"
        echo "3. 恢复IP优先级配置"
        echo "0. 返回主菜单"
        echo ""
        echo "------------------------------------------------"
        read -p "请选择操作 [0-3]: " ip_priority_choice
        echo ""
        
        case $ip_priority_choice in
            1)
                set_ip_priority "ipv4"
                ;;
            2)
                set_ip_priority "ipv6"
                ;;
            3)
                restore_gai_conf
                ;;
            0)
                break
                ;;
            *)
                echo -e "${gl_hong}无效选择，请重新输入${gl_bai}"
                sleep 2
                ;;
        esac
    done
}

restore_gai_conf() {
    clear
    echo -e "${gl_kjlan}=== 恢复 IP 优先级配置 ===${gl_bai}"
    echo ""

    # 检查是否有原始状态记录
    if [ ! -f /etc/gai.conf.original_state ]; then
        echo -e "${gl_huang}⚠️  未找到原始状态记录${gl_bai}"
        echo "可能的原因："
        echo "1. 从未使用过本脚本设置过 IPv4/IPv6 优先级"
        echo "2. 原始状态记录文件已被删除"
        echo ""
        
        # 列出所有备份文件
        if ls /etc/gai.conf.bak.* 2>/dev/null; then
            echo "发现以下备份文件："
            ls -lh /etc/gai.conf.bak.* 2>/dev/null
            echo ""
            echo "是否要手动恢复最新的备份？[y/n]"
            read -p "请选择: " manual_restore
            if [[ "$manual_restore" == "y" || "$manual_restore" == "Y" ]]; then
                latest_backup=$(ls -t /etc/gai.conf.bak.* 2>/dev/null | head -1)
                if [ -n "$latest_backup" ]; then
                    cp "$latest_backup" /etc/gai.conf
                    echo -e "${gl_lv}✅ 已从备份恢复: $latest_backup${gl_bai}"
                fi
            fi
        else
            echo "也未找到任何备份文件。"
            echo ""
            echo "是否要删除当前的 gai.conf 文件（恢复到系统默认）？[y/n]"
            read -p "请选择: " delete_conf
            if [[ "$delete_conf" == "y" || "$delete_conf" == "Y" ]]; then
                rm -f /etc/gai.conf
                echo -e "${gl_lv}✅ 已删除 gai.conf，系统将使用默认配置${gl_bai}"
            fi
        fi
    else
        # 读取原始状态
        original_state=$(cat /etc/gai.conf.original_state)
        
        if [ "$original_state" == "not_existed" ]; then
            echo "检测到原先${gl_huang}没有${gl_bai} gai.conf 文件"
            echo "恢复操作将${gl_hong}删除${gl_bai}当前的 gai.conf 文件"
            echo ""
            echo "确认要恢复到原始状态吗？[y/n]"
            read -p "请选择: " confirm
            
            if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
                rm -f /etc/gai.conf
                rm -f /etc/gai.conf.original_state
                echo -e "${gl_lv}✅ 已删除 gai.conf，恢复到原始状态（无配置文件）${gl_bai}"
                
                # 刷新缓存
                if command -v nscd &> /dev/null; then
                    systemctl restart nscd 2>/dev/null || service nscd restart 2>/dev/null || true
                fi
                if command -v resolvectl &> /dev/null; then
                    resolvectl flush-caches 2>/dev/null || true
                fi
            else
                echo "已取消恢复操作"
            fi
            
        elif [ "$original_state" == "existed" ]; then
            echo "检测到原先${gl_lv}存在${gl_bai} gai.conf 文件"
            
            # 查找最新的备份
            latest_backup=$(ls -t /etc/gai.conf.bak.* 2>/dev/null | head -1)
            
            if [ -n "$latest_backup" ]; then
                echo "找到备份文件: $latest_backup"
                echo ""
                echo "确认要从备份恢复吗？[y/n]"
                read -p "请选择: " confirm
                
                if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
                    cp "$latest_backup" /etc/gai.conf
                    rm -f /etc/gai.conf.original_state
                    echo -e "${gl_lv}✅ 已从备份恢复配置${gl_bai}"
                    
                    # 刷新缓存
                    if command -v nscd &> /dev/null; then
                        systemctl restart nscd 2>/dev/null || service nscd restart 2>/dev/null || true
                        echo "已刷新 nscd DNS 缓存"
                    fi
                    if command -v resolvectl &> /dev/null; then
                        resolvectl flush-caches 2>/dev/null || true
                        echo "已刷新 systemd-resolved DNS 缓存"
                    fi
                    
                    echo ""
                    echo "当前出口 IP 地址："
                    echo "------------------------------------------------"
                    curl ip.sb
                    echo ""
                    echo "------------------------------------------------"
                else
                    echo "已取消恢复操作"
                fi
            else
                echo -e "${gl_hong}错误: 未找到备份文件${gl_bai}"
            fi
        fi
    fi
    
    echo ""
    break_end
}

# BEGIN BOOT_RECOVERY
# The installed helper is emitted here so curl/bash installations are self-contained.
boot_recovery_emit_helper() {
    cat <<'BOOT_RECOVERY_HELPER'
#!/bin/bash
# NET_TCP_BOOT_RECOVERY_V1 -- generated by net-tcp-tune.sh; no downloads.
set -uo pipefail
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
BR_ETC=/etc
BR_LOCAL=/usr/local
BR_RUN=/run/net-tcp-boot-recovery
BR_BACKUPS=/var/backups/net-tcp-boot-recovery

br_log() { printf 'boot-recovery: %s\n' "$*" >&2; }
br_enabled() { [ "$(systemctl is-enabled "$1" 2>/dev/null)" = enabled ]; }
br_loopback_dns_listening() {
    local addr="$1"
    command -v ss >/dev/null 2>&1 || return 1
    ss -H -lnut 'sport = :53' 2>/dev/null | awk -v ip="$addr" '
        { for (i=1; i<=NF; i++) {
            endpoint=$i; sub(/%[^:]+:/, ":", endpoint)
            if (endpoint == ip ":53" || endpoint == "0.0.0.0:53" || endpoint == "*:53") found=1
        } }
        END { exit !found }'
}
br_dns_file_ready() {
    local server
    [ -r "$BR_ETC/resolv.conf" ] || return 1
    while IFS= read -r server; do
        case "$server" in
            127.*) br_loopback_dns_listening "$server" && return 0 ;;
            ::1) command -v ss >/dev/null 2>&1 && ss -H -lnut 'sport = :53' 2>/dev/null | grep -Fq '[::1]:53' && return 0 ;;
            *.*|*:*) return 0 ;;
        esac
    done < <(awk '$1 == "nameserver" && $2 !~ /[^[:alnum:].:%_-]/ { print $2 }' "$BR_ETC/resolv.conf")
    return 1
}
br_wait_dns() {
    local budget="${1:-40}" deadline remaining domain limit
    [[ "$budget" =~ ^[0-9]+$ ]] && [ "$budget" -ge 1 ] && [ "$budget" -le 300 ] || return 2
    command -v timeout >/dev/null 2>&1 && command -v getent >/dev/null 2>&1 || {
        br_log 'timeout/getent missing; DNS readiness cannot be verified'; return 1;
    }
    deadline=$((SECONDS + budget))
    while [ "$SECONDS" -lt "$deadline" ]; do
        if br_dns_file_ready; then
            for domain in www.apple.com www.cloudflare.com www.baidu.com; do
                remaining=$((deadline - SECONDS))
                [ "$remaining" -gt 0 ] || break
                limit=10; [ "$remaining" -ge 10 ] || limit="$remaining"
                if timeout "$limit" getent ahosts "$domain" >/dev/null 2>&1; then return 0; fi
            done
        fi
        [ "$SECONDS" -lt "$deadline" ] && sleep 1
    done
    br_log "DNS not ready after ${budget}s (readable resolv.conf, usable nameserver and successful lookup required)"
    return 1
}
# DNS can be policy-limited or temporarily unavailable. Wait for the common
# cold-boot race, then let each proxy handle its own targets; a probe failure
# must not disable otherwise usable IP/internal-domain traffic.
br_prepare_app_dns() {
    br_wait_dns "${1:-40}" && return 0
    br_log 'DNS probe did not succeed; business startup continues with its native DNS/restart policy'
    return 0
}
br_valid_dns() { [[ "$1" =~ ^[[:alnum:].:%#_-]+$ ]]; }
br_restore_dns() {
    local primary="${1:-}" secondary="${2:-}" budget="${3:-40}" deadline iface remaining
    br_valid_dns "$primary" && br_valid_dns "$secondary" || { br_log 'invalid DNS address'; return 2; }
    [[ "$budget" =~ ^[0-9]+$ ]] && [ "$budget" -ge 1 ] && [ "$budget" -le 120 ] || return 2
    for tool in resolvectl ip timeout getent; do
        command -v "$tool" >/dev/null 2>&1 || { br_log "missing $tool"; return 1; }
    done
    deadline=$((SECONDS + budget))
    while [ "$SECONDS" -lt "$deadline" ]; do
        iface=$(ip route show default 2>/dev/null | awk '$1 == "default" { print $5; exit }')
        if [ -z "$iface" ]; then
            iface=$(ip -6 route show default 2>/dev/null | awk '$1 == "default" { print $5; exit }')
        fi
        if [[ "$iface" =~ ^[[:alnum:]_.:-]+$ ]] &&
            timeout 3 resolvectl status >/dev/null 2>&1 &&
            timeout 3 resolvectl dns "$iface" "$primary" "$secondary" >/dev/null 2>&1 &&
            timeout 3 resolvectl domain "$iface" '~.' >/dev/null 2>&1 &&
            timeout 3 resolvectl default-route "$iface" yes >/dev/null 2>&1; then
            remaining=$((deadline - SECONDS))
            if [ "$remaining" -gt 0 ] && br_wait_dns "$remaining"; then
                br_log "DNS restored and verified on $iface"; return 0
            fi
        fi
        [ "$SECONDS" -lt "$deadline" ] && sleep 1
    done
    br_log 'DNS restore failed; systemd will retry (network/resolver/configuration may be unavailable)'
    return 1
}
br_backup() {
    local src="$1" dir
    [ ! -L "$BR_BACKUPS" ] || return 1
    (umask 077; mkdir -p "$BR_BACKUPS") || return 1
    dir=$(mktemp -d "$BR_BACKUPS/repair.XXXXXXXX") || return 1
    cp -p "$src" "$dir/$(basename "$src")" || return 1
    br_log "backup: $dir/$(basename "$src")"
}
br_migrate_resolved() {
    local file="$BR_ETC/systemd/system/systemd-resolved.service.d/dbus-fix.conf" expected actual
    [ -e "$file" ] || [ -L "$file" ] || return 0
    [ -f "$file" ] && [ ! -L "$file" ] || { br_log "refuse non-regular $file"; return 1; }
    expected=$(cat <<'LEGACY_DBUS'
# Debian 13 D-Bus接口注册修复
# 确保D-Bus完全启动后再启动systemd-resolved
[Unit]
After=dbus.service
Requires=dbus.service

[Service]
# 启动后等待1秒，确保D-Bus接口注册完成
ExecStartPost=/bin/sleep 1
LEGACY_DBUS
)
    actual=$(cat "$file") || return 1
    [ "$actual" = "$expected" ] || { br_log "custom $file preserved; review its dependencies manually"; return 1; }
    br_backup "$file" && rm -- "$file" || return 1
    br_log 'removed the managed resolved/D-Bus ordering cycle; resolver itself was not restarted'
}
br_check_ifupdown_ipv6() {
    # Follow literal source/source-directory includes without evaluating shell code.
    local -a files seen
    local file key pattern candidate entry i=0 conflict=0 old_ifs
    files=("$BR_ETC/network/interfaces"); seen=("")
    while [ "$i" -lt "${#files[@]}" ]; do
        [ "$i" -lt 128 ] || { br_log 'too many ifupdown includes; refusing IPv6 change'; return 1; }
        file="${files[$i]}"; i=$((i + 1))
        [ -f "$file" ] || continue
        for entry in "${seen[@]}"; do [ "$entry" != "$file" ] || continue 2; done
        seen+=("$file")
        if awk '$1 == "iface" && $3 == "inet6" { found=1 } END { exit !found }' "$file"; then
            br_log "active inet6 stanza in $file; IPv4 and cloud-init configuration must be reconciled before disabling IPv6"
            conflict=1
        fi
        while read -r key pattern; do
            [ -n "$pattern" ] || continue
            case "$pattern" in *'$'*|*'`'*|*'~'*) br_log "unresolved include in $file; refusing IPv6 change"; conflict=1; continue;; esac
            case "$pattern" in /*) ;; *) pattern="$(dirname "$file")/$pattern";; esac
            # Globbing only, never eval/source. Whitespace in include paths is unsupported by ifupdown.
            old_ifs="$IFS"; IFS=$'\n'
            if [ "$key" = source-directory ]; then
                for candidate in "$pattern"/*; do
                    [[ "$(basename "$candidate")" =~ ^[[:alnum:]_-]+$ ]] && files+=("$candidate")
                done
            else
                for candidate in $pattern; do files+=("$candidate"); done
            fi
            IFS="$old_ifs"
        done < <(awk '$1 == "source" || $1 == "source-directory" { for (i=2; i<=NF && $i !~ /^#/; i++) print $1, $i }' "$file")
    done
    [ "$conflict" -eq 0 ]
}
br_current_ipv6_conflict() {
    if [ "$(sysctl -n net.ipv6.conf.all.disable_ipv6 2>/dev/null)" = 1 ] ||
        { [ -f "$BR_ETC/sysctl.d/99-disable-ipv6.conf" ] && grep -Eq '^net\.ipv6\.conf\.(all|default)\.disable_ipv6[[:space:]]*=[[:space:]]*1' "$BR_ETC/sysctl.d/99-disable-ipv6.conf"; }; then
        br_check_ifupdown_ipv6
    fi
}
br_trusted_file() {
    local owner mode
    [ -f "$1" ] && [ ! -L "$1" ] || return 1
    read -r owner mode < <(stat -c '%u %a' "$1" 2>/dev/null || stat -f '%u %Lp' "$1" 2>/dev/null)
    [ "$owner" = 0 ] && [[ "$mode" =~ ^[0-7]{3,4}$ ]] && [ "$((8#$mode & 8#022))" -eq 0 ]
}
br_snell_runtime_owned() {
    local unit="$1" fragment dropins file
    fragment=$(systemctl show -p FragmentPath --value "$unit" 2>/dev/null) || return 1
    case "$fragment" in "$BR_ETC/systemd/system/$unit"|/lib/systemd/system/"$unit"|/usr/lib/systemd/system/"$unit") ;; *) return 1;; esac
    br_trusted_file "$fragment" || return 1
    [ "$(grep -c '^ExecStart=' "$fragment")" = 1 ] || return 1
    case "$unit" in
        snell.service|snell-[0-9]*.service)
            grep -Eq '^ExecStart=/usr/local/bin/snell-server -c /etc/snell/(snell-server|snell-[0-9]+)\.conf$' "$fragment" &&
                grep -Eq '^Description=Snell Proxy Service( \(Port[[:space:]]*[0-9]+\))?$' "$fragment" || return 1;;
        snellv6-[0-9]*.service)
            grep -Eq '^ExecStart=/usr/local/bin/snell-server-v6 -c /etc/snell-v6/snell-[0-9]+\.conf$' "$fragment" &&
                grep -Eq '^Description=Snell V6 Proxy Service \(Port[[:space:]]*[0-9]+\)$' "$fragment" || return 1;;
        *) return 1;;
    esac
    # A guard left by an older release is not proof of current ownership. Read
    # loaded drop-ins every time: replacement commands/namespaces are preserved.
    dropins=$(systemctl show -p DropInPaths --value "$unit" 2>/dev/null) || return 1
    for file in "$fragment" $dropins; do
        br_trusted_file "$file" || return 1
        if grep -Eq '^[[:space:]]*ExecStart(Pre|Post)?[[:space:]]*=' "$file" && [ "$file" != "$fragment" ]; then
            [ "$file" = "$BR_ETC/systemd/system/${unit}.d/90-net-tcp-boot-recovery.conf" ] || return 1
        fi
        if [ "$file" = "$fragment" ] && grep -Eq '^[[:space:]]*ExecStart(Pre|Post)[[:space:]]*=' "$file"; then return 1; fi
        grep -Eq '^[[:space:]]*(RootDirectory|RootImage|PrivateNetwork|NetworkNamespacePath|JoinsNamespaceOf|InaccessiblePaths|NoExecPaths|ExecPaths|SystemCallFilter|DynamicUser|PrivateUsers|TemporaryFileSystem|BindPaths|BindReadOnlyPaths)[[:space:]]*=' "$file" && return 1
    done
    return 0
}
br_snell_units() {
    systemctl list-unit-files 'snell*.service' --no-legend --no-pager 2>/dev/null |
        awk '$1 ~ /^snell\.service$/ || $1 ~ /^snell-[0-9]+\.service$/ || $1 ~ /^snellv6-[0-9]+\.service$/ { print $1 }' |
        while IFS= read -r unit; do
            local guard="$BR_ETC/systemd/system/${unit}.d/90-net-tcp-boot-recovery.conf"
            br_trusted_file "$guard" && br_snell_runtime_owned "$unit" || continue
            # Exact generated body, including either released invocation form.
            cmp -s "$guard" <(printf '%s\n' '# NET_TCP_BOOT_RECOVERY_V1' '[Unit]' \
                'After=network-online.target nss-lookup.target systemd-resolved.service dns-purify-persist.service' \
                'Wants=network-online.target' '[Service]' \
                'ExecStartPre=/usr/local/libexec/net-tcp-boot-recovery --prepare-app-dns 40') ||
            cmp -s "$guard" <(printf '%s\n' '# NET_TCP_BOOT_RECOVERY_V1' '[Unit]' \
                'After=network-online.target nss-lookup.target systemd-resolved.service dns-purify-persist.service' \
                'Wants=network-online.target' '[Service]' \
                'ExecStartPre=/usr/local/libexec/net-tcp-boot-recovery --wait-dns 40') || continue
            printf '%s\n' "$unit"
        done
}

br_remove_app_guards() {
    local file unit expected actual failed=0
    expected=$(cat <<'MANAGED_DNS_GUARD'
# NET_TCP_BOOT_RECOVERY_V1
[Unit]
After=network-online.target nss-lookup.target systemd-resolved.service dns-purify-persist.service
Wants=network-online.target
[Service]
ExecStartPre=/usr/local/libexec/net-tcp-boot-recovery --wait-dns 40
MANAGED_DNS_GUARD
)
    for file in "$BR_ETC"/systemd/system/*.service.d/90-net-tcp-boot-recovery.conf; do
        [ -e "$file" ] || [ -L "$file" ] || continue
        unit=$(basename "$(dirname "$file")"); unit="${unit%.d}"
        [[ "$unit" =~ ^(snell\.service|snell-[0-9]+\.service|snellv6-[0-9]+\.service|xray(@[[:alnum:]_.:-]+)?\.service)$ ]] || continue
        [ -f "$file" ] && [ ! -L "$file" ] || { failed=1; continue; }
        actual=$(cat "$file") || { failed=1; continue; }
        if [ "$actual" = "$expected" ] || [ "$actual" = "${expected/--wait-dns/--prepare-app-dns}" ]; then
            br_backup "$file" && rm -- "$file" || { failed=1; continue; }
            rmdir "$(dirname "$file")" 2>/dev/null || true
        else
            br_log "customized startup guard preserved: $file"; failed=1
        fi
    done
    file="$BR_ETC/systemd/system/net-tcp-boot-watch.timer"
    if [ -f "$file" ] && grep -q '^# NET_TCP_BOOT_RECOVERY_V1$' "$file"; then
        systemctl disable --now net-tcp-boot-watch.timer || failed=1
    fi
    # Keep the inert shared executable: custom drop-ins or a previous installation
    # may still reference it. Removing it would create an ExecStartPre= failure.
    [ "$failed" -eq 0 ]
}
br_dns_runtime_owned() {
    local wrapper="$BR_LOCAL/bin/dns-purify-apply.sh" unit="$BR_ETC/systemd/system/dns-purify-persist.service" primary secondary actual expected digest fragment dropins
    br_trusted_file "$wrapper" && br_trusted_file "$unit" || return 1
    primary=$(sed -n 's/^DNS_PRIMARY="\([^"]*\)"$/\1/p' "$wrapper")
    secondary=$(sed -n 's/^DNS_SECONDARY="\([^"]*\)"$/\1/p' "$wrapper")
    br_valid_dns "$primary" && br_valid_dns "$secondary" || return 1
    expected=$(cat <<EOF
#!/bin/bash
# NET_TCP_BOOT_RECOVERY_V1
# 由 net-tcp-tune.sh DNS净化功能自动生成
DNS_PRIMARY="$primary"
DNS_SECONDARY="$secondary"
exec /usr/local/libexec/net-tcp-boot-recovery --restore-dns "\$DNS_PRIMARY" "\$DNS_SECONDARY" 40
EOF
)
    actual=$(cat "$wrapper") || return 1
    [ "$actual" = "$expected" ] || return 1
    # Exact boot_recovery_emit_dns_service body (5.4.14 onward), not its marker.
    digest=$(sha256sum "$unit" 2>/dev/null) || return 1
    [ "${digest%% *}" = 86c5119482a3efffe0b7fcb3e90d971dd2a4301c561f7f446f999ebc2336072b ] || return 1
    fragment=$(systemctl show -p FragmentPath --value dns-purify-persist.service 2>/dev/null) || return 1
    dropins=$(systemctl show -p DropInPaths --value dns-purify-persist.service 2>/dev/null) || return 1
    [ "$fragment" = "$unit" ] && [ -z "$dropins" ]
}
br_watch() {
    local unit invocation dns_line state now previous=0 count=0 key stamp attempts
    command -v flock >/dev/null 2>&1 || { br_log 'flock missing'; return 1; }
    [ ! -L "$BR_RUN" ] || return 1
    (umask 077; mkdir -p "$BR_RUN") || return 1
    exec 9>"$BR_RUN/watch.lock"; flock -n 9 || return 0
    if ! br_wait_dns 5; then
        # Only retry our active oneshot; preserve deliberately stopped/disabled services.
        if br_dns_runtime_owned &&
            br_enabled dns-purify-persist.service && systemctl is-active --quiet dns-purify-persist.service; then
            systemctl --no-block try-restart dns-purify-persist.service || return 1
        fi
        return 1
    fi
    while IFS= read -r unit; do
        br_enabled "$unit" && systemctl is-active --quiet "$unit" || continue
        invocation=$(systemctl show -p InvocationID --value "$unit" 2>/dev/null)
        [[ "$invocation" =~ ^[[:xdigit:]]{32}$ ]] || continue
        dns_line=$(journalctl -u "$unit" "_SYSTEMD_INVOCATION_ID=$invocation" -o cat --no-pager 2>/dev/null |
            awk '/Effective IPv4 DNS:/ { last=$0 } END { print last }')
        printf '%s\n' "$dns_line" | grep -Eq 'Effective IPv4 DNS:[[:space:]]*127\.0\.0\.1([[:space:],]|$)' || continue
        br_loopback_dns_listening 127.0.0.1 && continue
        state="$BR_RUN/${unit}.attempts"
        [ ! -L "$state" ] || return 1
        previous=0; count=0
        if [ -f "$state" ]; then read -r previous count < "$state"; fi
        [[ "$previous" =~ ^[0-9]+$ && "$count" =~ ^[0-9]+$ ]] || { previous=0; count=0; }
        now=$(date +%s)
        [ "$((now - previous))" -lt 3600 ] || count=0
        [ "$count" -lt 2 ] && { [ "$previous" -eq 0 ] || [ "$((now - previous))" -ge 300 ]; } || continue
        br_enabled "$unit" && systemctl is-active --quiet "$unit" || continue
        printf '%s %s\n' "$now" "$((count + 1))" > "$state"
        # try-restart also checks activity in systemd, closing the manual-stop race.
        if systemctl --no-block try-restart "$unit"; then
            br_log "requested recovery of $unit: current invocation selected unserved 127.0.0.1 DNS; system DNS is healthy"
        else
            br_log "could not request recovery of $unit"; return 1
        fi
    done < <(br_snell_units)
}
br_main() {
    case "${1:-}" in
        --wait-dns) br_wait_dns "${2:-40}";;
        --prepare-app-dns) br_prepare_app_dns "${2:-40}";;
        --restore-dns) shift; br_restore_dns "$@";;
        --migrate-resolved) br_migrate_resolved;;
        --check-ifupdown-ipv6) br_check_ifupdown_ipv6;;
        --check-current-ipv6) br_current_ipv6_conflict;;
        --remove-app-guards) br_remove_app_guards && systemctl daemon-reload;;
        --watch) br_watch;;
        *) br_log 'unknown command'; return 2;;
    esac
}
if [ "${BASH_SOURCE[0]}" = "$0" ]; then br_main "$@"; fi
BOOT_RECOVERY_HELPER
}

boot_recovery_put() {
    local dest="$1" mode="$2" legacy="${3:-no}" tmp backup_dir
    [ ! -L "$dest" ] && { [ ! -e "$dest" ] || [ -f "$dest" ]; } || { echo "拒绝覆盖非普通文件: $dest" >&2; return 1; }
    mkdir -p "$(dirname "$dest")" || return 1
    tmp=$(mktemp "$(dirname "$dest")/.boot-recovery.XXXXXXXX") || return 1
    cat > "$tmp" || { rm -f "$tmp"; return 1; }
    if [ -f "$dest" ] && cmp -s "$tmp" "$dest"; then rm -f "$tmp"; chmod "$mode" "$dest"; return $?; fi
    if [ -f "$dest" ]; then
        if [ "$legacy" != yes ] && ! grep -q 'NET_TCP_BOOT_RECOVERY_V1' "$dest"; then
            echo "保留自定义文件，请人工检查: $dest" >&2; rm -f "$tmp"; return 1
        fi
        mkdir -p /var/backups/net-tcp-boot-recovery || { rm -f "$tmp"; return 1; }
        backup_dir=$(mktemp -d /var/backups/net-tcp-boot-recovery/assets.XXXXXXXX) || { rm -f "$tmp"; return 1; }
        cp -p "$dest" "$backup_dir/$(basename "$dest")" || { rm -f "$tmp"; return 1; }
    fi
    chmod "$mode" "$tmp" && mv -f "$tmp" "$dest" || { rm -f "$tmp"; return 1; }
    BOOT_RECOVERY_CHANGED=1
}
boot_recovery_install_assets() {
    # Preflight applies to DNS callers as well as proxy migration.
    boot_recovery_require_tools || return 1
    # Exact bodies or a known released hash only; keep operator edits intact.
    boot_recovery_asset_can_install /usr/local/libexec/net-tcp-boot-recovery boot_recovery_emit_helper &&
        boot_recovery_asset_can_install /etc/systemd/system/net-tcp-boot-watch.service boot_recovery_emit_watch_service &&
        boot_recovery_asset_can_install /etc/systemd/system/net-tcp-boot-watch.timer boot_recovery_emit_watch_timer || return 1
    boot_recovery_prepare_exec_dir || return 1
    boot_recovery_put /usr/local/libexec/net-tcp-boot-recovery 755 < <(boot_recovery_emit_helper) || return 1
    [ -x /usr/local/libexec/net-tcp-boot-recovery ] || {
        echo '启动恢复程序不可执行；请检查/usr/local/libexec所在挂载的noexec和路径权限，未更改挂载或祖先目录。' >&2
        return 1
    }
    boot_recovery_put /etc/systemd/system/net-tcp-boot-watch.service 644 < <(boot_recovery_emit_watch_service) || return 1
    boot_recovery_put /etc/systemd/system/net-tcp-boot-watch.timer 644 < <(boot_recovery_emit_watch_timer)
}
boot_recovery_asset_can_install() {
    local dest="$1" emitter="$2"
    [ ! -L "$dest" ] && { [ ! -e "$dest" ] || { boot_recovery_trusted_file "$dest" &&
        { cmp -s "$dest" <("$emitter") || boot_recovery_released_asset "$dest"; }; }; } && return 0
    echo "保留自定义恢复组件，迁移未完成: $dest" >&2
    return 1
}
boot_recovery_released_asset() {
    local digest
    [ "$1" = /usr/local/libexec/net-tcp-boot-recovery ] || return 1
    command -v sha256sum >/dev/null 2>&1 || return 1
    digest=$(sha256sum "$1") || return 1
    # Exact helper emitted by 047f3f6, defc354 and dedd7ad (5.4.14-5.4.16).
    [ "${digest%% *}" = 7d5fee9f4db168068288c4252057c4402097575f8bfc1ffd708ec4bbc76fe89b ]
}
boot_recovery_guard_can_install() {
    local dest="/etc/systemd/system/${1}.d/90-net-tcp-boot-recovery.conf"
    [ ! -L "$dest" ] && { [ ! -e "$dest" ] || { boot_recovery_trusted_file "$dest" &&
        { cmp -s "$dest" <(boot_recovery_emit_guard) || cmp -s "$dest" <(boot_recovery_emit_guard | sed 's/--prepare-app-dns/--wait-dns/'); }; }; } && return 0
    echo "保留自定义启动保护: $dest" >&2
    return 1
}
boot_recovery_resolved_can_migrate() {
    local file=/etc/systemd/system/systemd-resolved.service.d/dbus-fix.conf actual expected
    [ -e "$file" ] || [ -L "$file" ] || return 0
    boot_recovery_trusted_file "$file" || return 1
    expected=$(cat <<'KNOWN_DBUS_DROPIN'
# Debian 13 D-Bus接口注册修复
# 确保D-Bus完全启动后再启动systemd-resolved
[Unit]
After=dbus.service
Requires=dbus.service

[Service]
# 启动后等待1秒，确保D-Bus接口注册完成
ExecStartPost=/bin/sleep 1
KNOWN_DBUS_DROPIN
)
    actual=$(cat "$file") || return 1
    [ "$actual" = "$expected" ] || { echo "保留自定义resolved配置: $file" >&2; return 1; }
}
boot_recovery_require_tools() {
    local tool
    for tool in flock timeout getent ss awk grep sed stat; do
        command -v "$tool" >/dev/null 2>&1 || {
            echo "缺少启动恢复依赖 ${tool}，未安装或修改启动恢复组件；请在安装/更新操作中补齐依赖。" >&2; return 1;
        }
    done
}
boot_recovery_prepare_exec_dir() {
    local directory=/usr/local/libexec ancestor owner="" mode=""
    # Do not loosen unrelated ancestors, follow symlinks, or install root-run
    # code below a directory writable by another account.
    for ancestor in / /usr /usr/local; do
        [ -d "$ancestor" ] && [ ! -L "$ancestor" ] || {
            echo "启动恢复程序祖先目录异常，已保留: $ancestor" >&2; return 1;
        }
        read -r owner mode < <(boot_recovery_path_metadata "$ancestor")
        [ "$owner" = 0 ] && [[ "$mode" =~ ^[0-7]{3,4}$ ]] &&
            [ "$((8#$mode & 8#022))" -eq 0 ] && [ "$((8#$mode & 8#111))" -eq "$((8#111))" ] || {
            echo "启动恢复程序祖先目录不可信或缺少搜索权限，未自动更改: $ancestor" >&2; return 1;
        }
    done
    [ ! -L "$directory" ] && { [ ! -e "$directory" ] || [ -d "$directory" ]; } || {
        echo "启动恢复目录不是普通目录，已保留: $directory" >&2; return 1;
    }
    if [ ! -d "$directory" ]; then mkdir -m 755 "$directory" || return 1; fi
    read -r owner mode < <(boot_recovery_path_metadata "$directory")
    [ "$owner" = 0 ] && [[ "$mode" =~ ^[0-7]{3,4}$ ]] && [ "$((8#$mode & 8#022))" -eq 0 ] || {
        echo "启动恢复目录不是root所有或可被其他账户写入，已保留: $directory" >&2; return 1;
    }
    if [ "$((8#$mode & 8#111))" -ne "$((8#111))" ]; then
        # Search permission lets snell/xray execute the known helper by name.
        # Preserve read/write bits: 0700 becomes 0711, without exposing listings.
        chmod a+x "$directory" || return 1
        BOOT_RECOVERY_CHANGED=1
    fi
}
boot_recovery_emit_watch_service() {
    cat <<'WATCH_SERVICE'
# NET_TCP_BOOT_RECOVERY_V1
[Unit]
Description=Check managed DNS and stale Snell resolver initialization
After=network-online.target
[Service]
Type=oneshot
ExecStart=/usr/local/libexec/net-tcp-boot-recovery --watch
TimeoutStartSec=30
WATCH_SERVICE
}
boot_recovery_emit_watch_timer() {
    cat <<'WATCH_TIMER'
# NET_TCP_BOOT_RECOVERY_V1
[Unit]
Description=Periodically check managed DNS and active Snell instances
[Timer]
OnBootSec=45
OnUnitInactiveSec=60
AccuracySec=5
[Install]
WantedBy=timers.target
WATCH_TIMER
}
boot_recovery_patch_unit() {
    local unit="$1"
    [[ "$unit" =~ ^(snell\.service|snell-[0-9]+\.service|snellv6-[0-9]+\.service|xray(@[[:alnum:]_.:-]+)?\.service)$ ]] || return 1
    local dest="/etc/systemd/system/${unit}.d/90-net-tcp-boot-recovery.conf"
    boot_recovery_guard_can_install "$unit" || return 1
    boot_recovery_put "$dest" 644 < <(boot_recovery_emit_guard)
}
boot_recovery_emit_guard() {
    cat <<'DNS_GUARD'
# NET_TCP_BOOT_RECOVERY_V1
[Unit]
After=network-online.target nss-lookup.target systemd-resolved.service dns-purify-persist.service
Wants=network-online.target
[Service]
ExecStartPre=/usr/local/libexec/net-tcp-boot-recovery --prepare-app-dns 40
DNS_GUARD
}
boot_recovery_legacy_dns_apply_matches() {
    local file="$1" primary="$2" secondary="$3" expected actual
    expected=$(
        cat <<'LEGACY_DNS_HEAD'
#!/bin/bash
# DNS净化持久化脚本 - 开机自动恢复网卡级DNS配置
# 由 net-tcp-tune.sh DNS净化功能自动生成
# 安全说明：仅重新应用 resolvectl 运行时配置，不修改网络服务

LEGACY_DNS_HEAD
        printf 'DNS_PRIMARY="%s"\nDNS_SECONDARY="%s"\n' "$primary" "$secondary"
        cat <<'LEGACY_DNS_BODY'

# 前置检查：resolvectl 是否可用
if ! command -v resolvectl >/dev/null 2>&1; then
    echo "dns-purify: resolvectl 不可用，跳过" | systemd-cat -t dns-purify 2>/dev/null || true
    exit 0
fi

# 检测默认网卡（动态获取，适应网卡名变更）
IFACE=$(ip route | grep '^default' | awk '{print $5}' | head -n1)

if [ -z "$IFACE" ]; then
    echo "dns-purify: 未检测到默认网卡，跳过" | systemd-cat -t dns-purify 2>/dev/null || true
    exit 0
fi

# 等待 systemd-resolved 完全就绪（最多等30秒）
for i in $(seq 1 15); do
    if resolvectl status >/dev/null 2>&1; then
        break
    fi
    sleep 2
done

# 应用网卡级DNS配置
resolvectl dns "$IFACE" "$DNS_PRIMARY" "$DNS_SECONDARY" 2>/dev/null
resolvectl domain "$IFACE" "~." 2>/dev/null
resolvectl default-route "$IFACE" yes 2>/dev/null

# 验证DNS可用性
sleep 2
if getent hosts google.com >/dev/null 2>&1 || getent hosts baidu.com >/dev/null 2>&1; then
    echo "dns-purify: DNS配置恢复成功 (接口: $IFACE, DNS: $DNS_PRIMARY $DNS_SECONDARY)" | systemd-cat -t dns-purify 2>/dev/null || true
else
    echo "dns-purify: DNS验证未通过，但配置已应用 (接口: $IFACE)" | systemd-cat -t dns-purify 2>/dev/null || true
fi
LEGACY_DNS_BODY
    )
    actual=$(cat "$file") || return 1
    [ "$actual" = "$expected" ]
}
boot_recovery_legacy_dns_unit_matches() {
    local expected actual
    expected=$(cat <<'LEGACY_DNS_UNIT'
[Unit]
Description=DNS Purify - Restore DNS Configuration on Boot
Documentation=https://github.com/Eric86777/vps-tcp-tune
After=systemd-resolved.service network-online.target
Wants=network-online.target
Wants=systemd-resolved.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/bin/dns-purify-apply.sh
TimeoutStartSec=60

[Install]
WantedBy=multi-user.target
LEGACY_DNS_UNIT
    )
    actual=$(cat "$1") || return 1
    [ "$actual" = "$expected" ]
}
boot_recovery_write_dns_service() {
    local primary="$1" secondary="$2" old=/usr/local/bin/dns-purify-apply.sh unit=/etc/systemd/system/dns-purify-persist.service
    [[ "$primary" =~ ^[[:alnum:].:%#_-]+$ && "$secondary" =~ ^[[:alnum:].:%#_-]+$ ]] || return 1
    # Exact legacy bodies only: a matching comment/Description alone is not ownership proof.
    if [ -e "$old" ]; then
        # Verify against its own literal values before changing DNS providers.
        boot_recovery_project_dns || {
            echo "保留自定义DNS脚本: $old" >&2; return 1;
        }
    fi
    if [ -e "$unit" ]; then
        [ ! -L "$unit" ] && { boot_recovery_legacy_dns_unit_matches "$unit" || cmp -s "$unit" <(boot_recovery_emit_dns_service); } || {
            echo "保留自定义DNS服务: $unit" >&2; return 1;
        }
    fi
    boot_recovery_put "$old" 755 yes < <(boot_recovery_emit_dns_apply "$primary" "$secondary") || return 1
    boot_recovery_put "$unit" 644 yes < <(boot_recovery_emit_dns_service)
}
boot_recovery_emit_dns_apply() {
    local primary="$1" secondary="$2"
    cat <<DNS_APPLY
#!/bin/bash
# NET_TCP_BOOT_RECOVERY_V1
# 由 net-tcp-tune.sh DNS净化功能自动生成
DNS_PRIMARY="$primary"
DNS_SECONDARY="$secondary"
exec /usr/local/libexec/net-tcp-boot-recovery --restore-dns "\$DNS_PRIMARY" "\$DNS_SECONDARY" 40
DNS_APPLY
}
boot_recovery_emit_dns_service() {
    cat <<'DNS_SERVICE'
# NET_TCP_BOOT_RECOVERY_V1
[Unit]
Description=DNS Purify - Restore DNS Configuration on Boot
After=systemd-resolved.service network-online.target
Wants=systemd-resolved.service network-online.target
StartLimitIntervalSec=0
[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/bin/dns-purify-apply.sh
Restart=on-failure
RestartSec=10
TimeoutStartSec=60
[Install]
WantedBy=multi-user.target
DNS_SERVICE
}
boot_recovery_patch_enabled_units() {
    local unit
    while IFS= read -r unit; do
        [ -n "$unit" ] || continue
        [ "$(systemctl is-enabled "$unit" 2>/dev/null)" = enabled ] || continue
        boot_recovery_patch_unit "$unit" || return 1
    done < <(boot_recovery_project_units)
}
boot_recovery_project_dns() {
    local file=/usr/local/bin/dns-purify-apply.sh expected actual
    [ -f "$file" ] || return 1
    boot_recovery_trusted_file "$file" || return 2
    BOOT_RECOVERY_DNS_PRIMARY=$(sed -n 's/^DNS_PRIMARY="\([^"]*\)"$/\1/p' "$file")
    BOOT_RECOVERY_DNS_SECONDARY=$(sed -n 's/^DNS_SECONDARY="\([^"]*\)"$/\1/p' "$file")
    if [[ "$BOOT_RECOVERY_DNS_PRIMARY" =~ ^[[:alnum:].:%#_-]+$ && "$BOOT_RECOVERY_DNS_SECONDARY" =~ ^[[:alnum:].:%#_-]+$ ]]; then
        boot_recovery_legacy_dns_apply_matches "$file" "$BOOT_RECOVERY_DNS_PRIMARY" "$BOOT_RECOVERY_DNS_SECONDARY" && return 0
        expected=$(cat <<EOF
#!/bin/bash
# NET_TCP_BOOT_RECOVERY_V1
# 由 net-tcp-tune.sh DNS净化功能自动生成
DNS_PRIMARY="$BOOT_RECOVERY_DNS_PRIMARY"
DNS_SECONDARY="$BOOT_RECOVERY_DNS_SECONDARY"
exec /usr/local/libexec/net-tcp-boot-recovery --restore-dns "\$DNS_PRIMARY" "\$DNS_SECONDARY" 40
EOF
        )
        actual=$(cat "$file") || return 2
        [ "$actual" != "$expected" ] || return 0
    fi
    # Known project provenance plus edits is a conflict, never an overwrite grant.
    if grep -q 'NET_TCP_BOOT_RECOVERY_V1\|由 net-tcp-tune.sh DNS净化功能自动生成' "$file"; then
        echo "保留自定义DNS脚本，自动恢复迁移未完成: $file" >&2; return 2
    fi
    return 1
}
boot_recovery_path_metadata() {
    stat -c '%u %a' "$1" 2>/dev/null || stat -f '%u %Lp' "$1" 2>/dev/null
}
boot_recovery_trusted_file() {
    local file="$1" owner="" mode=""
    [ -f "$file" ] && [ ! -L "$file" ] || return 1
    read -r owner mode < <(boot_recovery_path_metadata "$file")
    [ "$owner" = 0 ] && [[ "$mode" =~ ^[0-7]{3,4}$ ]] && [ "$((8#$mode & 8#022))" -eq 0 ]
}
boot_recovery_xray_owned() {
    local record=/var/lib/net-tcp-tune/xray-install.json override=/etc/systemd/system/xray.service.d/override.conf expected actual
    if boot_recovery_trusted_file "$record" && command -v python3 >/dev/null 2>&1 &&
        python3 - "$record" <<'BOOT_XRAY_RECORD'
import json, sys
try:
    with open(sys.argv[1], encoding="utf-8") as stream:
        record = json.load(stream)
    valid = isinstance(record, dict) and record.get("version") == 1 and isinstance(record.get("paths"), list) and "/usr/local/bin/xray" in record["paths"]
except (OSError, ValueError, TypeError):
    valid = False
sys.exit(0 if valid else 1)
BOOT_XRAY_RECORD
    then return 0; fi
    boot_recovery_trusted_file "$override" || return 1
    expected=$(cat <<'XRAY_PROJECT_OVERRIDE'
[Service]
Restart=always
RestartSec=5
KillMode=mixed
KillSignal=SIGTERM
TimeoutStopSec=5s
OOMScoreAdjust=-500

[Unit]
StartLimitIntervalSec=60
StartLimitBurst=10
XRAY_PROJECT_OVERRIDE
    )
    actual=$(cat "$override") || return 1
    [ "$actual" = "$expected" ]
}
boot_recovery_runtime_dropins() {
    local unit="$1" directory name prefix file
    local -a names=(service "$unit")
    case "$unit" in *@*.service) names+=("${unit%%@*}@.service");; esac
    name="${unit%.service}"
    while [[ "$name" == *-* ]]; do
        name="${name%-*}"
        names+=("${name}-.service")
    done
    for directory in /etc/systemd/system /run/systemd/system /usr/local/lib/systemd/system /usr/lib/systemd/system /lib/systemd/system; do
        for prefix in "${names[@]}"; do
            for file in "$directory/${prefix}.d/"*.conf; do
                [ -e "$file" ] || [ -L "$file" ] || continue
                printf '%s\n' "$file"
            done
        done
    done
}
boot_recovery_runtime_compatible() {
    local unit="$1" fragment="" loaded_dropins="" file body expected allowed="" directory
    fragment=$(systemctl show -p FragmentPath --value "$unit" 2>/dev/null) || return 1
    loaded_dropins=$(systemctl show -p DropInPaths --value "$unit" 2>/dev/null) || return 1
    if [ -n "$fragment" ]; then
        case "$fragment" in /etc/systemd/system/"$unit"|/lib/systemd/system/"$unit"|/usr/lib/systemd/system/"$unit") ;; *) return 1;; esac
        boot_recovery_trusted_file "$fragment" || return 1
    fi
    # Query effective drop-ins, including template/global/prefix overrides, and
    # inspect not-yet-loaded local drop-ins before a fresh unit is installed.
    while IFS= read -r file; do
        [ -n "$file" ] || continue
        # systemd retains a removed drop-in's path until daemon-reload. Repair
        # may recreate only our absent guard; all other unreadable paths fail.
        if [ "$file" = "/etc/systemd/system/${unit}.d/90-net-tcp-boot-recovery.conf" ] &&
            [ ! -e "$file" ] && [ ! -L "$file" ]; then continue; fi
        boot_recovery_trusted_file "$file" || return 1
        grep -Eq '^[[:space:]]*(RootDirectory|RootImage|PrivateNetwork|NetworkNamespacePath|JoinsNamespaceOf|InaccessiblePaths|NoExecPaths|ExecPaths|SystemCallFilter|DynamicUser|PrivateUsers|TemporaryFileSystem|BindPaths|BindReadOnlyPaths)[[:space:]]*=' "$file" && return 1
        if [ "$file" = "$fragment" ] && grep -Eq '^[[:space:]]*ExecStart(Pre|Post)[[:space:]]*=' "$file"; then return 1; fi
        if [ "$file" != "$fragment" ] && grep -Eq '^[[:space:]]*ExecStart(Pre|Post)?[[:space:]]*=' "$file"; then
            if cmp -s "$file" <(boot_recovery_emit_guard) ||
                cmp -s "$file" <(boot_recovery_emit_guard | sed 's/--prepare-app-dns/--wait-dns/'); then continue; fi
            body=$(sed '/^[[:space:]]*#/d; /^[[:space:]]*$/d' "$file") || return 1
            expected=$(printf '%s\n' '[Service]' 'ExecStart=' 'ExecStart=/usr/local/bin/xray run -config /usr/local/etc/xray/config.json')
            [ "$unit" = xray.service ] && [ "$body" = "$expected" ] || return 1
        fi
    done < <(printf '%s\n' "$fragment"; printf '%s\n' "$loaded_dropins" | tr ' ' '\n'; boot_recovery_runtime_dropins "$unit")
    return 0
}
boot_recovery_project_units() {
    local file unit xray_owned=no
    boot_recovery_xray_owned && xray_owned=yes
    for file in /etc/systemd/system/snell*.service /lib/systemd/system/snell*.service /usr/lib/systemd/system/snell*.service \
        /etc/systemd/system/xray*.service; do
        boot_recovery_trusted_file "$file" || continue
        unit=$(basename "$file")
        case "$unit" in
            snell.service|snell-[0-9]*.service)
                [[ "$unit" =~ ^(snell\.service|snell-[0-9]+\.service)$ ]] || continue
                grep -Eq '^ExecStart=/usr/local/bin/snell-server -c /etc/snell/(snell-server|snell-[0-9]+)\.conf$' "$file" &&
                    grep -Eq '^Description=Snell Proxy Service( \(Port[[:space:]]*[0-9]+\))?$' "$file" || continue;;
            snellv6-[0-9]*.service)
                [[ "$unit" =~ ^snellv6-[0-9]+\.service$ ]] || continue
                grep -Eq '^ExecStart=/usr/local/bin/snell-server-v6 -c /etc/snell-v6/snell-[0-9]+\.conf$' "$file" &&
                    grep -Eq '^Description=Snell V6 Proxy Service \(Port[[:space:]]*[0-9]+\)$' "$file" || continue;;
            xray.service|xray@*.service)
                [ "$xray_owned" = yes ] && [[ "$unit" =~ ^xray(@[[:alnum:]_.:-]+)?\.service$ ]] || continue
                grep -Eq '^ExecStart=/usr/local/bin/xray run -config /usr/local/etc/xray/(config|%i|[[:alnum:]_.-]+)\.json$' "$file" || continue;;
            *) continue;;
        esac
        if boot_recovery_runtime_compatible "$unit"; then
            printf '%s\n' "$unit"
        else
            echo "保留自定义运行环境，未给 ${unit} 自动添加启动恢复。" >&2
        fi
    done | awk '!seen[$0]++'
}
boot_recovery_migrate() (
    # A service operation owns only its explicit targets. DNS/network maintenance
    # is separate; an unrelated custom service must not veto a core install.
    local mode="${1:-auto}" units="" unit dns_state=1 legacy_dropin=/etc/systemd/system/systemd-resolved.service.d/dbus-fix.conf
    shift || return 1
    BOOT_RECOVERY_CHANGED=0
    if [ "$mode" = install ]; then
        [ "$#" -gt 0 ] || return 1
    else
        units=$(boot_recovery_project_units) || return 1
        if boot_recovery_project_dns; then dns_state=0; else dns_state=$?; fi
        [ "$dns_state" -ne 2 ] || return 1
    fi
    for unit in "$@"; do
        [[ "$unit" =~ ^(snell\.service|snell-[0-9]+\.service|snellv6-[0-9]+\.service|xray(@[[:alnum:]_.:-]+)?\.service)$ ]] || return 1
        units="${units}${units:+
}${unit}"
    done
    [ -n "$units" ] || [ "$dns_state" -eq 0 ] || return 0
    boot_recovery_require_tools || return 1
    exec 209>/run/net-tcp-boot-repair.lock
    flock -n 209 || { echo '另一个启动恢复修复正在运行' >&2; return 1; }
    # Preflight the complete selected set before writing any shared component.
    boot_recovery_asset_can_install /usr/local/libexec/net-tcp-boot-recovery boot_recovery_emit_helper &&
        boot_recovery_asset_can_install /etc/systemd/system/net-tcp-boot-watch.service boot_recovery_emit_watch_service &&
        boot_recovery_asset_can_install /etc/systemd/system/net-tcp-boot-watch.timer boot_recovery_emit_watch_timer || return 1
    while IFS= read -r unit; do
        if [ -n "$unit" ]; then
            boot_recovery_runtime_compatible "$unit" || { echo "保留 ${unit} 的自定义运行环境，启动恢复未迁移。" >&2; return 1; }
            boot_recovery_guard_can_install "$unit" || return 1
        fi
    done < <(printf '%s\n' "$units" | awk '!seen[$0]++')
    if [ "$mode" != install ]; then
        boot_recovery_resolved_can_migrate || return 1
        if [ "$dns_state" -eq 0 ] && { [ -e /etc/systemd/system/dns-purify-persist.service ] || [ -L /etc/systemd/system/dns-purify-persist.service ]; }; then
            boot_recovery_trusted_file /etc/systemd/system/dns-purify-persist.service || return 1
            { boot_recovery_legacy_dns_unit_matches /etc/systemd/system/dns-purify-persist.service ||
                cmp -s /etc/systemd/system/dns-purify-persist.service <(boot_recovery_emit_dns_service); } || return 1
        fi
    fi
    boot_recovery_install_assets || return 1
    if [ "$mode" != install ]; then
        [ ! -e "$legacy_dropin" ] || BOOT_RECOVERY_CHANGED=1
        /usr/local/libexec/net-tcp-boot-recovery --migrate-resolved || return 1
        if [ "$dns_state" -eq 0 ]; then
            boot_recovery_write_dns_service "$BOOT_RECOVERY_DNS_PRIMARY" "$BOOT_RECOVERY_DNS_SECONDARY" || return 1
        fi
    fi
    while IFS= read -r unit; do
        [ -z "$unit" ] || boot_recovery_patch_unit "$unit" || return 1
    done < <(printf '%s\n' "$units" | awk '!seen[$0]++')
    systemctl daemon-reload >/dev/null || return 1
    if [ "$(systemctl is-enabled net-tcp-boot-watch.timer 2>/dev/null)" != enabled ] ||
        ! systemctl is-active --quiet net-tcp-boot-watch.timer; then
        systemctl enable --now net-tcp-boot-watch.timer || return 1
    fi
    [ "$(systemctl is-enabled net-tcp-boot-watch.timer 2>/dev/null)" = enabled ] &&
        systemctl is-active --quiet net-tcp-boot-watch.timer || return 1
    # IPv6 conflicts are checked by the operation that disables IPv6, never by
    # unrelated proxy install/update paths after their recovery files were saved.
    if [ "$BOOT_RECOVERY_CHANGED" -ne 0 ] || [ "$mode" = repair ]; then
        echo '启动恢复配置已补齐；业务enable/手动停止状态保持，未直接重启机器、网络或业务服务。'
    fi
)

run_boot_recovery_repair() {
    [ "$#" -eq 0 ] || { echo '用法: --repair-boot-recovery（不重启机器或网络，不启动手动停止的业务）' >&2; return 2; }
    boot_recovery_migrate repair
}
# DNS owns these shared assets only for the duration of its transaction. Save
# bytes/metadata and the timer's independent enabled and active states, even if
# the helper already existed; helper presence is not a rollback boundary.
boot_recovery_snapshot_dns_assets() {
    local state_dir="$1" path key=0 owner mode
    mkdir -p "$state_dir/boot-assets" || return 1
    : > "$state_dir/boot-assets.map" || return 1
    for path in /usr/local/libexec/net-tcp-boot-recovery \
        /etc/systemd/system/net-tcp-boot-watch.service /etc/systemd/system/net-tcp-boot-watch.timer; do
        key=$((key + 1))
        printf '%s|%s\n' "$path" "$key" >> "$state_dir/boot-assets.map" || return 1
        if [ -e "$path" ] || [ -L "$path" ]; then
            cp -a "$path" "$state_dir/boot-assets/$key" || return 1
        else
            : > "$state_dir/boot-assets/$key.absent" || return 1
        fi
    done
    # Later standalone rollback must not remove a helper needed by proxies that
    # were installed after this DNS snapshot. Record current consumers by bytes.
    mkdir -p "$state_dir/boot-consumers" || return 1
    : > "$state_dir/boot-consumers.map" || return 1
    key=0
    for path in /etc/systemd/system/*.service /etc/systemd/system/*.service.d/*.conf; do
        [ "$path" != /etc/systemd/system/net-tcp-boot-watch.service ] || continue
        [ -f "$path" ] && [ ! -L "$path" ] || continue
        grep -Fq /usr/local/libexec/net-tcp-boot-recovery "$path" || continue
        key=$((key + 1))
        cp -a "$path" "$state_dir/boot-consumers/$key" || return 1
        printf '%s|%s\n' "$path" "$key" >> "$state_dir/boot-consumers.map" || return 1
    done
    if [ -d /usr/local/libexec ] && [ ! -L /usr/local/libexec ]; then
        read -r owner mode < <(boot_recovery_path_metadata /usr/local/libexec)
        printf '%s\n' "$mode" > "$state_dir/boot-libexec.mode" || return 1
    fi
    systemctl is-enabled net-tcp-boot-watch.timer > "$state_dir/boot-watch.enabled" 2>/dev/null || true
    if systemctl is-active --quiet net-tcp-boot-watch.timer; then
        echo active > "$state_dir/boot-watch.active"
    else
        echo inactive > "$state_dir/boot-watch.active"
    fi
    {
        printf '#!/bin/bash\n'
        declare -f boot_recovery_restore_dns_assets
        printf '\nboot_recovery_restore_dns_assets "$(dirname "$0")" "${1:-}"\n'
    } > "$state_dir/boot-recovery-restore.sh" || return 1
    chmod 700 "$state_dir/boot-recovery-restore.sh"
}
boot_recovery_restore_dns_assets() (
    local state_dir="$1" path key enabled active mode failed=0 keep_helper=0 consumer previous previous_key matched
    [ -f "$state_dir/boot-assets.map" ] || return 1
    if [ "${2:-}" != --lock-held ]; then
        command -v flock >/dev/null 2>&1 || return 1
        exec 207>/run/net-tcp-boot-repair.lock
        flock -n 207 || { echo '另一个启动恢复/DNS操作正在运行，回滚未继续。' >&2; return 1; }
    fi
    for consumer in /etc/systemd/system/*.service /etc/systemd/system/*.service.d/*.conf; do
        [ "$consumer" != /etc/systemd/system/net-tcp-boot-watch.service ] || continue
        [ -f "$consumer" ] && [ ! -L "$consumer" ] || continue
        grep -Fq /usr/local/libexec/net-tcp-boot-recovery "$consumer" || continue
        matched=0
        if [ -f "$state_dir/boot-consumers.map" ]; then
            while IFS='|' read -r previous previous_key; do
                if [ "$consumer" = "$previous" ] && cmp -s "$consumer" "$state_dir/boot-consumers/$previous_key"; then
                    matched=1; break
                fi
            done < "$state_dir/boot-consumers.map"
        fi
        [ "$matched" -eq 1 ] || keep_helper=1
    done
    if [ "$keep_helper" -eq 1 ]; then
        echo '检测到DNS快照后新增/改变的服务引用；保留当前shared helper/watch及其状态，防止破坏后来安装的服务。' >&2
        return 0
    fi
    enabled=$(cat "$state_dir/boot-watch.enabled" 2>/dev/null)
    active=$(cat "$state_dir/boot-watch.active" 2>/dev/null)
    # Stop only a timer that was inactive before this DNS operation. Business
    # services are never stopped/restarted by this asset rollback.
    if [ "$active" != active ] && systemctl is-active --quiet net-tcp-boot-watch.timer; then
        systemctl stop net-tcp-boot-watch.timer || failed=1
    fi
    case "$enabled" in
        enabled) ;;
        # A DNS install may have added a persistent wants link to a previously
        # runtime-only timer. Remove it before recreating the runtime state.
        *) systemctl disable net-tcp-boot-watch.timer >/dev/null 2>&1 || true;;
    esac
    while IFS='|' read -r path key; do
        [ -n "$path" ] && [[ "$key" =~ ^[0-9]+$ ]] || { failed=1; continue; }
        if [ -e "$state_dir/boot-assets/$key" ] || [ -L "$state_dir/boot-assets/$key" ]; then
            rm -f "$path" && mkdir -p "$(dirname "$path")" &&
                cp -a "$state_dir/boot-assets/$key" "$path" || failed=1
        elif [ -f "$state_dir/boot-assets/$key.absent" ]; then
            rm -f "$path" || failed=1
        else
            failed=1
        fi
    done < "$state_dir/boot-assets.map"
    if [ -f "$state_dir/boot-libexec.mode" ]; then
        mode=$(cat "$state_dir/boot-libexec.mode")
        [[ "$mode" =~ ^[0-7]{3,4}$ ]] && chmod "$mode" /usr/local/libexec || failed=1
    fi
    systemctl daemon-reload || failed=1
    case "$enabled" in
        enabled) systemctl enable net-tcp-boot-watch.timer || failed=1;;
        enabled-runtime) systemctl enable --runtime net-tcp-boot-watch.timer || failed=1;;
    esac
    [ "$active" != active ] || systemctl start net-tcp-boot-watch.timer || failed=1
    [ "$failed" -eq 0 ]
)
# END BOOT_RECOVERY

disable_ipv6_temporary() {
    clear
    echo -e "${gl_kjlan}=== 临时禁用IPv6 ===${gl_bai}"
    echo ""
    echo "此操作将临时禁用IPv6，重启后自动恢复"
    echo "------------------------------------------------"
    echo ""
    
    read -e -p "$(echo -e "${gl_huang}确认临时禁用IPv6？(Y/N): ${gl_bai}")" confirm
    
    case "$confirm" in
        [Yy])
            echo ""
            echo "正在禁用IPv6..."
            
            # 临时禁用IPv6
            sysctl -w net.ipv6.conf.all.disable_ipv6=1 >/dev/null 2>&1
            sysctl -w net.ipv6.conf.default.disable_ipv6=1 >/dev/null 2>&1
            sysctl -w net.ipv6.conf.lo.disable_ipv6=1 >/dev/null 2>&1
            
            # 验证状态
            local ipv6_status=$(sysctl -n net.ipv6.conf.all.disable_ipv6 2>/dev/null)
            
            echo ""
            if [ "$ipv6_status" = "1" ]; then
                echo -e "${gl_lv}✅ IPv6 已临时禁用${gl_bai}"
                echo ""
                echo -e "${gl_zi}注意：${gl_bai}"
                echo "  - 此设置仅在当前会话有效"
                echo "  - 重启后 IPv6 将自动恢复"
                echo "  - 如需永久禁用，请选择'永久禁用IPv6'选项"
            else
                echo -e "${gl_hong}❌ IPv6 禁用失败${gl_bai}"
            fi
            ;;
        *)
            echo "已取消"
            ;;
    esac
    
    echo ""
    break_end
}

disable_ipv6_permanent() {
    if ! bash <(boot_recovery_emit_helper) --check-ifupdown-ipv6; then
        echo -e "${gl_hong}❌ 检测到ifupdown IPv6配置冲突，未写入sysctl或网络配置。请先协调cloud-init/inet6配置。${gl_bai}"
        return 1
    fi
    clear
    echo -e "${gl_kjlan}=== 永久禁用IPv6 ===${gl_bai}"
    echo ""
    echo "此操作将永久禁用IPv6，重启后仍然生效"
    echo "------------------------------------------------"
    echo ""
    
    # 检查是否已经永久禁用
    if [ -f /etc/sysctl.d/99-disable-ipv6.conf ]; then
        echo -e "${gl_huang}⚠️  检测到已存在永久禁用配置${gl_bai}"
        echo ""
        if [ "$AUTO_MODE" = "1" ]; then
            confirm=Y
        else
            read -e -p "$(echo -e "${gl_huang}是否重新执行永久禁用？(Y/N): ${gl_bai}")" confirm
        fi

        case "$confirm" in
            [Yy])
                ;;
            *)
                echo "已取消"
                break_end
                return 1
                ;;
        esac
    fi
    
    echo ""
    if [ "$AUTO_MODE" = "1" ]; then
        confirm=Y
    else
        read -e -p "$(echo -e "${gl_huang}确认永久禁用IPv6？(Y/N): ${gl_bai}")" confirm
    fi

    case "$confirm" in
        [Yy])
            echo ""
            echo -e "${gl_zi}[步骤 1/3] 备份当前IPv6状态...${gl_bai}"
            
            # 读取当前IPv6状态并备份
            local ipv6_all=$(sysctl -n net.ipv6.conf.all.disable_ipv6 2>/dev/null || echo "0")
            local ipv6_default=$(sysctl -n net.ipv6.conf.default.disable_ipv6 2>/dev/null || echo "0")
            local ipv6_lo=$(sysctl -n net.ipv6.conf.lo.disable_ipv6 2>/dev/null || echo "0")
            
            # 创建备份文件
            cat > /etc/sysctl.d/.ipv6-state-backup.conf << BACKUPEOF
# IPv6 State Backup - Created on $(date '+%Y-%m-%d %H:%M:%S')
# This file is used to restore IPv6 state when canceling permanent disable
net.ipv6.conf.all.disable_ipv6=${ipv6_all}
net.ipv6.conf.default.disable_ipv6=${ipv6_default}
net.ipv6.conf.lo.disable_ipv6=${ipv6_lo}
BACKUPEOF
            
            echo -e "${gl_lv}✅ 状态已备份${gl_bai}"
            echo ""
            
            echo -e "${gl_zi}[步骤 2/3] 创建永久禁用配置...${gl_bai}"
            
            # 创建永久禁用配置文件
            cat > /etc/sysctl.d/99-disable-ipv6.conf << EOF
# Permanently Disable IPv6
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1
EOF
            
            echo -e "${gl_lv}✅ 配置文件已创建${gl_bai}"
            echo ""
            
            echo -e "${gl_zi}[步骤 3/3] 应用配置...${gl_bai}"
            
            # 应用配置
            sysctl --system >/dev/null 2>&1
            
            # 验证状态
            local ipv6_status=$(sysctl -n net.ipv6.conf.all.disable_ipv6 2>/dev/null)
            
            echo ""
            if [ "$ipv6_status" = "1" ]; then
                echo -e "${gl_lv}✅ IPv6 已永久禁用${gl_bai}"
                echo ""
                echo -e "${gl_zi}说明：${gl_bai}"
                echo "  - 配置文件: /etc/sysctl.d/99-disable-ipv6.conf"
                echo "  - 备份文件: /etc/sysctl.d/.ipv6-state-backup.conf"
                echo "  - 重启后此配置仍然生效"
                echo "  - 如需恢复，请选择'取消永久禁用'选项"
            else
                echo -e "${gl_hong}❌ IPv6 禁用失败${gl_bai}"
                # 如果失败，删除配置文件
                rm -f /etc/sysctl.d/99-disable-ipv6.conf
                rm -f /etc/sysctl.d/.ipv6-state-backup.conf
            fi
            ;;
        *)
            echo "已取消"
            ;;
    esac
    
    echo ""
    break_end
}

cancel_ipv6_permanent_disable() {
    clear
    echo -e "${gl_kjlan}=== 取消永久禁用IPv6 ===${gl_bai}"
    echo ""
    echo "此操作将完全还原到执行永久禁用前的状态"
    echo "------------------------------------------------"
    echo ""
    
    # 检查是否存在永久禁用配置
    if [ ! -f /etc/sysctl.d/99-disable-ipv6.conf ]; then
        echo -e "${gl_huang}⚠️  未检测到永久禁用配置${gl_bai}"
        echo ""
        echo "可能原因："
        echo "  - 从未执行过'永久禁用IPv6'操作"
        echo "  - 配置文件已被手动删除"
        echo ""
        break_end
        return 1
    fi
    
    read -e -p "$(echo -e "${gl_huang}确认取消永久禁用并恢复原始状态？(Y/N): ${gl_bai}")" confirm
    
    case "$confirm" in
        [Yy])
            echo ""
            echo -e "${gl_zi}[步骤 1/4] 删除永久禁用配置...${gl_bai}"
            
            # 删除永久禁用配置文件
            rm -f /etc/sysctl.d/99-disable-ipv6.conf
            echo -e "${gl_lv}✅ 配置文件已删除${gl_bai}"
            echo ""
            
            echo -e "${gl_zi}[步骤 2/4] 检查备份文件...${gl_bai}"
            
            # 检查备份文件
            if [ -f /etc/sysctl.d/.ipv6-state-backup.conf ]; then
                echo -e "${gl_lv}✅ 找到备份文件${gl_bai}"
                echo ""
                
                echo -e "${gl_zi}[步骤 3/4] 从备份还原原始状态...${gl_bai}"
                
                # 读取备份的原始值
                local backup_all=$(grep 'net.ipv6.conf.all.disable_ipv6' /etc/sysctl.d/.ipv6-state-backup.conf | awk -F'=' '{print $2}')
                local backup_default=$(grep 'net.ipv6.conf.default.disable_ipv6' /etc/sysctl.d/.ipv6-state-backup.conf | awk -F'=' '{print $2}')
                local backup_lo=$(grep 'net.ipv6.conf.lo.disable_ipv6' /etc/sysctl.d/.ipv6-state-backup.conf | awk -F'=' '{print $2}')
                
                # 恢复原始值
                sysctl -w net.ipv6.conf.all.disable_ipv6=${backup_all} >/dev/null 2>&1
                sysctl -w net.ipv6.conf.default.disable_ipv6=${backup_default} >/dev/null 2>&1
                sysctl -w net.ipv6.conf.lo.disable_ipv6=${backup_lo} >/dev/null 2>&1
                
                # 删除备份文件
                rm -f /etc/sysctl.d/.ipv6-state-backup.conf
                
                echo -e "${gl_lv}✅ 已从备份还原原始状态${gl_bai}"
            else
                echo -e "${gl_huang}⚠️  未找到备份文件${gl_bai}"
                echo ""
                
                echo -e "${gl_zi}[步骤 3/4] 恢复到系统默认（启用IPv6）...${gl_bai}"
                
                # 恢复到系统默认（启用IPv6）
                sysctl -w net.ipv6.conf.all.disable_ipv6=0 >/dev/null 2>&1
                sysctl -w net.ipv6.conf.default.disable_ipv6=0 >/dev/null 2>&1
                sysctl -w net.ipv6.conf.lo.disable_ipv6=0 >/dev/null 2>&1
                
                echo -e "${gl_lv}✅ 已恢复到系统默认（IPv6启用）${gl_bai}"
            fi
            
            echo ""
            echo -e "${gl_zi}[步骤 4/4] 应用配置...${gl_bai}"
            
            # 应用配置
            sysctl --system >/dev/null 2>&1
            
            # 验证状态
            local ipv6_status=$(sysctl -n net.ipv6.conf.all.disable_ipv6 2>/dev/null)
            
            echo ""
            if [ "$ipv6_status" = "0" ]; then
                echo -e "${gl_lv}✅ IPv6 已恢复启用${gl_bai}"
                echo ""
                echo -e "${gl_zi}说明：${gl_bai}"
                echo "  - 所有相关配置文件已清理"
                echo "  - IPv6 已完全恢复到执行永久禁用前的状态"
                echo "  - 重启后此状态依然保持"
            else
                echo -e "${gl_huang}⚠️  IPv6 状态: 禁用（值=${ipv6_status}）${gl_bai}"
                echo ""
                echo "可能原因："
                echo "  - 系统中存在其他IPv6禁用配置"
                echo "  - 手动执行 sysctl -w 命令重新启用IPv6"
            fi
            ;;
        *)
            echo "已取消"
            ;;
    esac
    
    echo ""
    break_end
}

manage_ipv6() {
    while true; do
        clear
        echo -e "${gl_kjlan}=== IPv6 管理 ===${gl_bai}"
        echo ""
        
        # 显示当前IPv6状态
        local ipv6_status=$(sysctl -n net.ipv6.conf.all.disable_ipv6 2>/dev/null)
        local status_text=""
        local status_color=""
        
        if [ "$ipv6_status" = "0" ]; then
            status_text="启用"
            status_color="${gl_lv}"
        else
            status_text="禁用"
            status_color="${gl_hong}"
        fi
        
        echo -e "当前状态: ${status_color}${status_text}${gl_bai}"
        echo ""
        
        # 检查是否存在永久禁用配置
        if [ -f /etc/sysctl.d/99-disable-ipv6.conf ]; then
            echo -e "${gl_huang}⚠️  检测到永久禁用配置文件${gl_bai}"
            echo ""
        fi
        
        echo "------------------------------------------------"
        echo "1. 临时禁用IPv6（重启后恢复）"
        echo "2. 永久禁用IPv6（重启后仍生效）"
        echo "3. 取消永久禁用（完全还原）"
        echo "0. 返回主菜单"
        echo "------------------------------------------------"
        read -e -p "请输入选择: " choice
        
        case "$choice" in
            1)
                disable_ipv6_temporary
                ;;
            2)
                disable_ipv6_permanent
                ;;
            3)
                cancel_ipv6_permanent_disable
                ;;
            0)
                return
                ;;
            *)
                echo "无效选择"
                sleep 2
                ;;
        esac
    done
}

#=============================================================================
# 旧版 MTU 优化自动清理（v4.9.2 起移除功能4，保留清理逻辑）
# 功能3 的 tcp_mtu_probing=1 + clamp-mss-to-pmtu 已覆盖 MTU 智能探测
#=============================================================================

auto_cleanup_legacy_mtu() {
    # 检测旧版功能4的配置文件是否存在
    [ -f /usr/local/etc/mtu-optimize.conf ] || return 0

    # 恢复默认路由 MTU
    local default_route
    default_route=$(ip -4 route show default 2>/dev/null | head -1)
    if [ -n "$default_route" ]; then
        local clean_route
        clean_route=$(echo "$default_route" | sed 's/ mtu lock [0-9]*//;s/ mtu [0-9]*//')
        ip route replace $clean_route 2>/dev/null
    fi

    # 恢复链路 MTU
    local saved_iface saved_original_mtu
    saved_iface=$(grep '^DEFAULT_IFACE=' /usr/local/etc/mtu-optimize.conf 2>/dev/null | cut -d= -f2)
    saved_original_mtu=$(grep '^ORIGINAL_MTU=' /usr/local/etc/mtu-optimize.conf 2>/dev/null | cut -d= -f2)
    if [ -n "$saved_iface" ] && [ -n "$saved_original_mtu" ]; then
        ip link set dev "$saved_iface" mtu "$saved_original_mtu" 2>/dev/null
    fi

    # 清理旧版 iptables set-mss 规则
    if command -v iptables &>/dev/null; then
        local comment_tag="net-tcp-tune-mss"
        local del_mss
        while read -r del_mss; do
            [ -n "$del_mss" ] || continue
            iptables -t mangle -D OUTPUT -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss "$del_mss" -m comment --comment "$comment_tag" 2>/dev/null || true
        done < <(iptables -t mangle -S OUTPUT 2>/dev/null | grep "$comment_tag" | sed -n 's/.*--set-mss \([0-9]\+\).*/\1/p')
        while read -r del_mss; do
            [ -n "$del_mss" ] || continue
            iptables -t mangle -D POSTROUTING -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss "$del_mss" -m comment --comment "$comment_tag" 2>/dev/null || true
        done < <(iptables -t mangle -S POSTROUTING 2>/dev/null | grep "$comment_tag" | sed -n 's/.*--set-mss \([0-9]\+\).*/\1/p')
    fi

    # 清理配置文件和持久化服务
    rm -f /usr/local/etc/mtu-optimize.conf
    if [ -f /usr/local/bin/bbr-optimize-apply.sh ] && grep -q "MTU 优化恢复 (mtu-optimize)" /usr/local/bin/bbr-optimize-apply.sh 2>/dev/null; then
        sed -i '/# MTU 优化恢复 (mtu-optimize)/,/^[[:space:]]*fi[[:space:]]*$/d' /usr/local/bin/bbr-optimize-apply.sh 2>/dev/null || true
    fi
    if [ -f /etc/systemd/system/mtu-optimize-persist.service ]; then
        systemctl disable mtu-optimize-persist.service 2>/dev/null
        rm -f /etc/systemd/system/mtu-optimize-persist.service
        rm -f /usr/local/bin/mtu-optimize-apply.sh
        systemctl daemon-reload 2>/dev/null
    fi

    echo -e "${gl_huang}⚠️ 检测到旧版MTU优化配置（已被功能3的tcp_mtu_probing替代），已自动清理${gl_bai}"
    sleep 2
}


server_reboot() {
    read -e -p "$(echo -e "${gl_huang}提示: ${gl_bai}现在重启服务器使配置生效吗？(Y/N): ")" rboot
    case "$rboot" in
        [Yy])
            echo "正在重启..."
            reboot
            ;;
        *)
            echo "已取消，请稍后手动执行: reboot"
            ;;
    esac
}

#=============================================================================
# 带宽检测和缓冲区计算函数
#=============================================================================

# 带宽检测函数
detect_bandwidth() {
    # 所有交互式输出重定向到stderr，避免被命令替换捕获
    echo "" >&2
    echo -e "${gl_kjlan}=== 服务器带宽检测 ===${gl_bai}" >&2
    echo "" >&2
    echo "请选择带宽配置方式：" >&2
    echo "1. 自动检测（推荐，自动选择最近服务器）" >&2
    echo "2. 手动指定测速服务器（指定服务器ID）" >&2
    echo "3. 手动选择预设档位（9个常用带宽档位）" >&2
    echo "" >&2
    
    read -e -p "请输入选择 [1]: " bw_choice
    bw_choice=${bw_choice:-1}

    case "$bw_choice" in
        1)
            # 自动检测带宽 - 选择最近服务器
            echo "" >&2
            echo -e "${gl_huang}正在运行 speedtest 测速...${gl_bai}" >&2
            echo -e "${gl_zi}提示: 自动选择距离最近的服务器${gl_bai}" >&2
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
            echo "" >&2
            
            # 检查speedtest是否安装
            if ! command -v speedtest &>/dev/null; then
                echo -e "${gl_huang}speedtest 未安装，正在安装...${gl_bai}" >&2
                # 调用脚本中已有的安装逻辑（简化版）
                local cpu_arch=$(uname -m)
                local download_url
                case "$cpu_arch" in
                    x86_64)
                        download_url="https://install.speedtest.net/app/cli/ookla-speedtest-1.2.0-linux-x86_64.tgz"
                        ;;
                    aarch64)
                        download_url="https://install.speedtest.net/app/cli/ookla-speedtest-1.2.0-linux-aarch64.tgz"
                        ;;
                    *)
                        echo -e "${gl_hong}错误: 不支持的架构 ${cpu_arch}${gl_bai}" >&2
                        echo "将使用通用带宽值 500 Mbps" >&2
                        echo "500"
                        return 1
                        ;;
                esac
                
                cd /tmp && \
                wget -q "$download_url" -O speedtest.tgz && \
                tar -xzf speedtest.tgz && \
                mv speedtest /usr/local/bin/ && \
                rm -f speedtest.tgz
                
                if [ $? -ne 0 ]; then
                    echo -e "${gl_hong}安装失败，将使用通用值${gl_bai}" >&2
                    echo "500"
                    return 1
                fi
            fi
            
            # 智能测速：获取附近服务器列表，按距离依次尝试
            echo -e "${gl_zi}正在搜索附近测速服务器...${gl_bai}" >&2
            
            # 获取附近服务器列表（按延迟排序）
            local servers_list=$(speedtest --accept-license --servers 2>/dev/null | sed -nE 's/^[[:space:]]*([0-9]+).*/\1/p' | head -n 10)
            
            if [ -z "$servers_list" ]; then
                echo -e "${gl_huang}无法获取服务器列表，使用自动选择...${gl_bai}" >&2
                servers_list="auto"
            else
                local server_count=$(echo "$servers_list" | wc -l)
                echo -e "${gl_lv}✅ 找到 ${server_count} 个附近服务器${gl_bai}" >&2
            fi
            echo "" >&2
            
            local speedtest_output=""
            local upload_speed=""
            local attempt=0
            local max_attempts=5  # 最多尝试5个服务器
            
            # 逐个尝试服务器
            for server_id in $servers_list; do
                attempt=$((attempt + 1))
                
                if [ $attempt -gt $max_attempts ]; then
                    echo -e "${gl_huang}已尝试 ${max_attempts} 个服务器，停止尝试${gl_bai}" >&2
                    break
                fi
                
                if [ "$server_id" = "auto" ]; then
                    echo -e "${gl_zi}[尝试 ${attempt}] 自动选择最近服务器...${gl_bai}" >&2
                    speedtest_output=$(speedtest --accept-license 2>&1)
                else
                    echo -e "${gl_zi}[尝试 ${attempt}] 测试服务器 #${server_id}...${gl_bai}" >&2
                    speedtest_output=$(speedtest --accept-license --server-id="$server_id" 2>&1)
                fi
                
                echo "$speedtest_output" >&2
                echo "" >&2
                
                # 提取上传速度
                upload_speed=""
                if echo "$speedtest_output" | grep -q "Upload:"; then
                    upload_speed=$(echo "$speedtest_output" | sed -nE 's/.*[Uu]pload:[[:space:]]*([0-9]+(\.[0-9]+)?).*/\1/p' | head -n1)
                fi
                if [ -z "$upload_speed" ]; then
                    upload_speed=$(echo "$speedtest_output" | grep -i "Upload:" | awk '{for(i=1;i<=NF;i++) if($i ~ /^[0-9]+\.[0-9]+$/) {print $i; exit}}')
                fi
                
                # 检查是否成功
                if [ -n "$upload_speed" ] && ! echo "$speedtest_output" | grep -qi "FAILED\|error"; then
                    local success_server=$(echo "$speedtest_output" | grep "Server:" | head -n1 | sed 's/.*Server: //')
                    echo -e "${gl_lv}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}" >&2
                    echo -e "${gl_lv}✅ 测速成功！${gl_bai}" >&2
                    echo -e "${gl_zi}使用服务器: ${success_server}${gl_bai}" >&2
                    echo -e "${gl_lv}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}" >&2
                    echo "" >&2
                    break
                else
                    local failed_server=$(echo "$speedtest_output" | grep "Server:" | head -n1 | sed 's/.*Server: //' | sed 's/[[:space:]]*$//')
                    if [ -n "$failed_server" ]; then
                        echo -e "${gl_huang}⚠️  失败: ${failed_server}${gl_bai}" >&2
                    else
                        echo -e "${gl_huang}⚠️  此服务器失败${gl_bai}" >&2
                    fi
                    echo -e "${gl_zi}继续尝试下一个服务器...${gl_bai}" >&2
                    echo "" >&2
                fi
            done
            
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
            echo "" >&2
            
            # 所有尝试都失败了
            if [ -z "$upload_speed" ] || echo "$speedtest_output" | grep -qi "FAILED\|error"; then
                echo -e "${gl_huang}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}" >&2
                echo -e "${gl_huang}⚠️  无法自动检测带宽${gl_bai}" >&2
                echo -e "${gl_huang}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}" >&2
                echo "" >&2
                echo -e "${gl_zi}原因: 测速服务器可能暂时不可用${gl_bai}" >&2
                echo "" >&2
                echo -e "${gl_kjlan}默认配置方案：${gl_bai}" >&2
                echo -e "  带宽:       ${gl_huang}1000 Mbps (1 Gbps)${gl_bai}" >&2
                echo -e "  缓冲区:     ${gl_huang}根据地区自动计算${gl_bai}" >&2
                echo -e "  适用场景:   ${gl_zi}标准 1Gbps 服务器（覆盖大多数场景）${gl_bai}" >&2
                echo "" >&2
                echo -e "${gl_huang}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}" >&2
                echo "" >&2
                
                # 询问用户确认
                read -e -p "是否使用默认值 1000 Mbps？(Y/N) [Y]: " use_default
                use_default=${use_default:-Y}
                
                case "$use_default" in
                    [Yy])
                        echo "" >&2
                        echo -e "${gl_lv}✅ 使用默认配置: 1000 Mbps${gl_bai}" >&2
                        echo "1000"
                        return 0
                        ;;
                    [Nn])
                        echo "" >&2
                        echo -e "${gl_zi}请手动输入带宽值${gl_bai}" >&2
                        local manual_bandwidth=""
                        while true; do
                            read -e -p "请输入上传带宽（单位：Mbps，如 500、1000、2000）: " manual_bandwidth
                            if [[ "$manual_bandwidth" =~ ^[0-9]+$ ]] && [ "$manual_bandwidth" -gt 0 ]; then
                                echo "" >&2
                                echo -e "${gl_lv}✅ 使用自定义值: ${manual_bandwidth} Mbps${gl_bai}" >&2
                                echo "$manual_bandwidth"
                                return 0
                            else
                                echo -e "${gl_hong}❌ 请输入有效的数字${gl_bai}" >&2
                            fi
                        done
                        ;;
                    *)
                        echo "" >&2
                        echo -e "${gl_huang}输入无效，使用默认值 1000 Mbps${gl_bai}" >&2
                        echo "1000"
                        return 0
                        ;;
                esac
            fi
            
            # 转为整数并验证
            local upload_mbps=${upload_speed%.*}
            if ! [[ "$upload_mbps" =~ ^[0-9]+$ ]] || [ "$upload_mbps" -le 0 ] 2>/dev/null; then
                echo -e "${gl_huang}⚠️ 检测到的带宽值异常 (${upload_speed})，使用默认值 1000 Mbps${gl_bai}" >&2
                upload_mbps=1000
            fi

            echo -e "${gl_lv}✅ 检测到上传带宽: ${upload_mbps} Mbps${gl_bai}" >&2
            echo "" >&2

            # 返回带宽值
            echo "$upload_mbps"
            return 0
            ;;
        2)
            # 手动指定测速服务器ID
            echo "" >&2
            echo -e "${gl_kjlan}=== 手动指定测速服务器 ===${gl_bai}" >&2
            echo "" >&2
            
            # 检查speedtest是否安装
            if ! command -v speedtest &>/dev/null; then
                echo -e "${gl_huang}speedtest 未安装，正在安装...${gl_bai}" >&2
                local cpu_arch=$(uname -m)
                local download_url
                case "$cpu_arch" in
                    x86_64)
                        download_url="https://install.speedtest.net/app/cli/ookla-speedtest-1.2.0-linux-x86_64.tgz"
                        ;;
                    aarch64)
                        download_url="https://install.speedtest.net/app/cli/ookla-speedtest-1.2.0-linux-aarch64.tgz"
                        ;;
                    *)
                        echo -e "${gl_hong}错误: 不支持的架构 ${cpu_arch}${gl_bai}" >&2
                        echo "将使用通用值 1000 Mbps" >&2
                        echo "1000"
                        return 1
                        ;;
                esac
                
                cd /tmp && \
                wget -q "$download_url" -O speedtest.tgz && \
                tar -xzf speedtest.tgz && \
                mv speedtest /usr/local/bin/ && \
                rm -f speedtest.tgz
                
                if [ $? -ne 0 ]; then
                    echo -e "${gl_hong}安装失败，将使用默认值 1000 Mbps${gl_bai}" >&2
                    echo "1000"
                    return 1
                fi
                echo -e "${gl_lv}✅ speedtest 安装成功${gl_bai}" >&2
                echo "" >&2
            fi
            
            # 显示如何查看服务器列表
            echo -e "${gl_zi}📋 如何查看可用的测速服务器：${gl_bai}" >&2
            echo "" >&2
            echo -e "  方法1：查看所有服务器列表" >&2
            echo -e "  ${gl_huang}speedtest --servers${gl_bai}" >&2
            echo "" >&2
            echo -e "  方法2：只显示附近服务器（推荐）" >&2
            echo -e "  ${gl_huang}speedtest --servers | head -n 20${gl_bai}" >&2
            echo "" >&2
            echo -e "${gl_zi}💡 服务器列表格式说明：${gl_bai}" >&2
            echo -e "  每行开头的数字就是服务器ID" >&2
            echo -e "  例如: ${gl_huang}12345${gl_bai}) 服务商名称 (位置, 距离)" >&2
            echo "" >&2
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
            echo "" >&2
            
            # 询问是否现在查看服务器列表
            read -e -p "是否现在查看附近的测速服务器列表？(Y/N) [Y]: " show_list
            show_list=${show_list:-Y}
            
            if [[ "$show_list" =~ ^[Yy]$ ]]; then
                echo "" >&2
                echo -e "${gl_kjlan}附近的测速服务器列表：${gl_bai}" >&2
                echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
                speedtest --accept-license --servers 2>/dev/null | head -n 20 >&2
                echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
                echo "" >&2
            fi
            
            # 输入服务器ID
            local server_id=""
            while true; do
                read -e -p "$(echo -e "${gl_huang}请输入测速服务器ID（纯数字）: ${gl_bai}")" server_id
                
                if [[ "$server_id" =~ ^[0-9]+$ ]]; then
                    break
                else
                    echo -e "${gl_hong}❌ 无效输入，请输入纯数字的服务器ID${gl_bai}" >&2
                fi
            done
            
            # 使用指定服务器测速
            echo "" >&2
            echo -e "${gl_huang}正在使用服务器 #${server_id} 测速...${gl_bai}" >&2
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
            echo "" >&2
            
            local speedtest_output=$(speedtest --accept-license --server-id="$server_id" 2>&1)
            echo "$speedtest_output" >&2
            echo "" >&2
            
            # 提取上传速度
            local upload_speed=""
            if echo "$speedtest_output" | grep -q "Upload:"; then
                upload_speed=$(echo "$speedtest_output" | sed -nE 's/.*[Uu]pload:[[:space:]]*([0-9]+(\.[0-9]+)?).*/\1/p' | head -n1)
            fi
            if [ -z "$upload_speed" ]; then
                upload_speed=$(echo "$speedtest_output" | grep -i "Upload:" | awk '{for(i=1;i<=NF;i++) if($i ~ /^[0-9]+\.[0-9]+$/) {print $i; exit}}')
            fi
            
            # 检查测速是否成功
            if [ -n "$upload_speed" ] && ! echo "$speedtest_output" | grep -qi "FAILED\|error"; then
                local upload_mbps=${upload_speed%.*}
                if ! [[ "$upload_mbps" =~ ^[0-9]+$ ]] || [ "$upload_mbps" -le 0 ] 2>/dev/null; then
                    echo -e "${gl_huang}⚠️ 检测到的带宽值异常 (${upload_speed})，使用默认值 1000 Mbps${gl_bai}" >&2
                    upload_mbps=1000
                fi
                echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
                echo -e "${gl_lv}✅ 测速成功！${gl_bai}" >&2
                echo -e "${gl_lv}检测到上传带宽: ${upload_mbps} Mbps${gl_bai}" >&2
                echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
                echo "" >&2
                echo "$upload_mbps"
                return 0
            else
                echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
                echo -e "${gl_hong}❌ 测速失败${gl_bai}" >&2
                echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
                echo "" >&2
                echo -e "${gl_zi}可能原因：${gl_bai}" >&2
                echo "  - 服务器ID不存在或已下线" >&2
                echo "  - 网络连接问题" >&2
                echo "  - 该服务器暂时不可用" >&2
                echo "" >&2
                
                read -e -p "是否使用默认值 1000 Mbps？(Y/N) [Y]: " use_default
                use_default=${use_default:-Y}
                
                if [[ "$use_default" =~ ^[Yy]$ ]]; then
                    echo "" >&2
                    echo -e "${gl_lv}✅ 使用默认配置: 1000 Mbps${gl_bai}" >&2
                    echo "1000"
                    return 0
                else
                    echo "" >&2
                    echo -e "${gl_zi}请手动输入带宽值${gl_bai}" >&2
                    local manual_bandwidth=""
                    while true; do
                        read -e -p "请输入上传带宽（单位：Mbps，如 500、1000、2000）: " manual_bandwidth
                        if [[ "$manual_bandwidth" =~ ^[0-9]+$ ]] && [ "$manual_bandwidth" -gt 0 ]; then
                            echo "" >&2
                            echo -e "${gl_lv}✅ 使用自定义值: ${manual_bandwidth} Mbps${gl_bai}" >&2
                            echo "$manual_bandwidth"
                            return 0
                        else
                            echo -e "${gl_hong}❌ 请输入有效的数字${gl_bai}" >&2
                        fi
                    done
                fi
            fi
            ;;
        3)
            # 手动选择预设档位
            echo "" >&2
            echo -e "${gl_kjlan}=== 手动选择带宽档位 ===${gl_bai}" >&2
            echo "" >&2
            echo "请选择带宽档位：" >&2
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
            echo "" >&2
            echo -e "${gl_huang}【小带宽 VPS】${gl_bai}" >&2
            echo "1. 100 Mbps   (NAT/极小带宽)" >&2
            echo "2. 200 Mbps   (小型VPS)" >&2
            echo "3. 300 Mbps   (入门服务器)" >&2
            echo "" >&2
            echo -e "${gl_huang}【中等带宽】${gl_bai}" >&2
            echo "4. 500 Mbps   (标准小带宽)" >&2
            echo "5. 700 Mbps   (准千兆)" >&2
            echo "6. 1 Gbps ⭐  (标准VPS/最常见)" >&2
            echo "" >&2
            echo -e "${gl_huang}【高带宽服务器】${gl_bai}" >&2
            echo "7. 1.5 Gbps   (中高端VPS)" >&2
            echo "8. 2 Gbps     (高性能VPS)" >&2
            echo "9. 2.5 Gbps   (准万兆)" >&2
            echo "" >&2
            echo -e "${gl_zi}提示: 缓冲区大小将根据后续选择的地区自动计算${gl_bai}" >&2
            echo "" >&2
            echo -e "${gl_zi}【其他选项】${gl_bai}" >&2
            echo "10. 自定义输入（手动指定任意带宽值）" >&2
            echo "0. 返回上级菜单" >&2
            echo "" >&2
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
            echo "" >&2
            
            # 读取用户选择
            local preset_choice=""
            read -e -p "请输入选择 [6]: " preset_choice
            preset_choice=${preset_choice:-6}  # 默认选择6 (1 Gbps)
            
            case "$preset_choice" in
                1)
                    echo "" >&2
                    echo -e "${gl_lv}✅ 已选择: 100 Mbps${gl_bai}" >&2
                    echo "100"
                    return 0
                    ;;
                2)
                    echo "" >&2
                    echo -e "${gl_lv}✅ 已选择: 200 Mbps${gl_bai}" >&2
                    echo "200"
                    return 0
                    ;;
                3)
                    echo "" >&2
                    echo -e "${gl_lv}✅ 已选择: 300 Mbps${gl_bai}" >&2
                    echo "300"
                    return 0
                    ;;
                4)
                    echo "" >&2
                    echo -e "${gl_lv}✅ 已选择: 500 Mbps${gl_bai}" >&2
                    echo "500"
                    return 0
                    ;;
                5)
                    echo "" >&2
                    echo -e "${gl_lv}✅ 已选择: 700 Mbps${gl_bai}" >&2
                    echo "700"
                    return 0
                    ;;
                6)
                    echo "" >&2
                    echo -e "${gl_lv}✅ 已选择: 1000 Mbps${gl_bai}" >&2
                    echo "1000"
                    return 0
                    ;;
                7)
                    echo "" >&2
                    echo -e "${gl_lv}✅ 已选择: 1500 Mbps${gl_bai}" >&2
                    echo "1500"
                    return 0
                    ;;
                8)
                    echo "" >&2
                    echo -e "${gl_lv}✅ 已选择: 2000 Mbps${gl_bai}" >&2
                    echo "2000"
                    return 0
                    ;;
                9)
                    echo "" >&2
                    echo -e "${gl_lv}✅ 已选择: 2500 Mbps${gl_bai}" >&2
                    echo "2500"
                    return 0
                    ;;
                10)
                    # 自定义输入
                    echo "" >&2
                    echo -e "${gl_zi}=== 自定义输入 ===${gl_bai}" >&2
                    echo "" >&2
                    local manual_bandwidth=""
                    while true; do
                        read -e -p "请输入带宽值（单位：Mbps，如 750、1200）: " manual_bandwidth
                        if [[ "$manual_bandwidth" =~ ^[0-9]+$ ]] && [ "$manual_bandwidth" -gt 0 ]; then
                            echo "" >&2
                            echo -e "${gl_lv}✅ 使用自定义值: ${manual_bandwidth} Mbps${gl_bai}" >&2
                            echo "$manual_bandwidth"
                            return 0
                        else
                            echo -e "${gl_hong}❌ 请输入有效的正整数${gl_bai}" >&2
                        fi
                    done
                    ;;
                0)
                    # 返回上级菜单
                    echo "" >&2
                    echo -e "${gl_huang}已取消选择，返回上级菜单${gl_bai}" >&2
                    echo "1000"  # 返回默认值，避免空值
                    return 1
                    ;;
                *)
                    echo "" >&2
                    echo -e "${gl_hong}无效选择，使用默认值 1000 Mbps${gl_bai}" >&2
                    echo "1000"
                    return 1
                    ;;
            esac
            ;;
        *)
            echo -e "${gl_huang}无效选择，使用默认值 1000 Mbps${gl_bai}" >&2
            echo "1000"
            return 1
            ;;
    esac
}

# 缓冲区大小计算函数
calculate_buffer_size() {
    local bandwidth=$1
    local region=${2:-asia}  # asia（亚太）或 overseas（美欧）
    local buffer_mb
    local bandwidth_level

    # 输入验证：确保 bandwidth 是正整数
    if ! [[ "$bandwidth" =~ ^[0-9]+$ ]] || [ "$bandwidth" -le 0 ] 2>/dev/null; then
        local fallback_mb=16
        [ "$region" = "overseas" ] && fallback_mb=64
        echo -e "${gl_huang}⚠️ 带宽值无效 (${bandwidth})，使用默认值 ${fallback_mb}MB${gl_bai}" >&2
        echo "$fallback_mb"
        return 0
    fi

    if [ "$region" = "overseas" ]; then
        # ===== 美国/欧洲档位（RTT ~200ms，buffer ≈ BDP × 2.5，上限 64MB）=====
        if [ "$bandwidth" -eq 100 ]; then
            buffer_mb=8
            bandwidth_level="预设档位（100 Mbps·远距离）"
        elif [ "$bandwidth" -eq 200 ]; then
            buffer_mb=16
            bandwidth_level="预设档位（200 Mbps·远距离）"
        elif [ "$bandwidth" -eq 300 ]; then
            buffer_mb=20
            bandwidth_level="预设档位（300 Mbps·远距离）"
        elif [ "$bandwidth" -eq 500 ]; then
            buffer_mb=32
            bandwidth_level="预设档位（500 Mbps·远距离）"
        elif [ "$bandwidth" -eq 700 ]; then
            buffer_mb=48
            bandwidth_level="预设档位（700 Mbps·远距离）"
        elif [ "$bandwidth" -eq 1000 ]; then
            buffer_mb=64
            bandwidth_level="预设档位（1 Gbps·远距离）"
        elif [ "$bandwidth" -eq 1500 ]; then
            buffer_mb=64
            bandwidth_level="预设档位（1.5 Gbps·远距离）"
        elif [ "$bandwidth" -eq 2000 ]; then
            buffer_mb=64
            bandwidth_level="预设档位（2 Gbps·远距离）"
        elif [ "$bandwidth" -eq 2500 ]; then
            buffer_mb=64
            bandwidth_level="预设档位（2.5 Gbps·远距离）"
        # 非预设值的区间兜底。两条规则：
        #   1) 实测值离某个预设档不足 10% 时按该档计算（千兆口实测通常是 9xx，应按 1 Gbps 档）
        #   2) 带宽越大缓冲区不减小（各区间不低于其左侧预设档的值）
        # 各区间取值均 ≥ 旧版同带宽的取值，不会比旧版小
        elif [ "$bandwidth" -lt 270 ]; then
            buffer_mb=16
            bandwidth_level="小带宽（< 270 Mbps·远距离）"
        elif [ "$bandwidth" -lt 450 ]; then
            buffer_mb=20
            bandwidth_level="270-449 Mbps·远距离（按 300 Mbps 档）"
        elif [ "$bandwidth" -lt 500 ]; then
            buffer_mb=32
            bandwidth_level="450-499 Mbps·远距离（按 500 Mbps 档）"
        elif [ "$bandwidth" -lt 900 ]; then
            buffer_mb=48
            bandwidth_level="中等带宽（500-899 Mbps·远距离）"
        elif [ "$bandwidth" -lt 1000 ]; then
            buffer_mb=64
            bandwidth_level="900-999 Mbps·远距离（按 1 Gbps 档）"
        elif [ "$bandwidth" -lt 2000 ]; then
            buffer_mb=64
            bandwidth_level="标准带宽（1-2 Gbps·远距离）"
        else
            buffer_mb=64
            bandwidth_level="高带宽（> 2 Gbps·远距离）"
        fi
    else
        # ===== 亚太地区档位（RTT ~50ms，原有逻辑不变）=====
        if [ "$bandwidth" -eq 100 ]; then
            buffer_mb=6
            bandwidth_level="预设档位（100 Mbps）"
        elif [ "$bandwidth" -eq 200 ]; then
            buffer_mb=8
            bandwidth_level="预设档位（200 Mbps）"
        elif [ "$bandwidth" -eq 300 ]; then
            buffer_mb=10
            bandwidth_level="预设档位（300 Mbps）"
        elif [ "$bandwidth" -eq 500 ]; then
            buffer_mb=12
            bandwidth_level="预设档位（500 Mbps）"
        elif [ "$bandwidth" -eq 700 ]; then
            buffer_mb=14
            bandwidth_level="预设档位（700 Mbps）"
        elif [ "$bandwidth" -eq 1000 ]; then
            buffer_mb=16
            bandwidth_level="预设档位（1 Gbps）"
        elif [ "$bandwidth" -eq 1500 ]; then
            buffer_mb=20
            bandwidth_level="预设档位（1.5 Gbps）"
        elif [ "$bandwidth" -eq 2000 ]; then
            buffer_mb=24
            bandwidth_level="预设档位（2 Gbps）"
        elif [ "$bandwidth" -eq 2500 ]; then
            buffer_mb=28
            bandwidth_level="预设档位（2.5 Gbps）"
        # 非预设值的区间兜底（规则同上：离预设档不足 10% 按该档；带宽越大缓冲区不减小；
        # 各区间取值均 ≥ 旧版同带宽的取值）
        elif [ "$bandwidth" -lt 270 ]; then
            buffer_mb=8
            bandwidth_level="小带宽（< 270 Mbps）"
        elif [ "$bandwidth" -lt 450 ]; then
            buffer_mb=10
            bandwidth_level="270-449 Mbps（按 300 Mbps 档）"
        elif [ "$bandwidth" -lt 630 ]; then
            buffer_mb=12
            bandwidth_level="450-629 Mbps（按 500 Mbps 档）"
        elif [ "$bandwidth" -lt 900 ]; then
            buffer_mb=14
            bandwidth_level="630-899 Mbps（按 700 Mbps 档）"
        elif [ "$bandwidth" -lt 1350 ]; then
            buffer_mb=16
            bandwidth_level="900-1349 Mbps（按 1 Gbps 档）"
        elif [ "$bandwidth" -lt 1800 ]; then
            buffer_mb=20
            bandwidth_level="1350-1799 Mbps（按 1.5 Gbps 档）"
        elif [ "$bandwidth" -lt 2250 ]; then
            buffer_mb=24
            bandwidth_level="1800-2249 Mbps（按 2 Gbps 档）"
        elif [ "$bandwidth" -lt 10000 ]; then
            buffer_mb=28
            bandwidth_level="2250 Mbps 以上（按 2.5 Gbps 档）"
        else
            buffer_mb=32
            bandwidth_level="极高带宽（> 10 Gbps）"
        fi
    fi

    # 显示计算结果（输出到stderr）
    local region_label="亚太地区"
    [ "$region" = "overseas" ] && region_label="美国/欧洲"
    echo "" >&2
    echo -e "${gl_kjlan}根据带宽和地区计算最优缓冲区:${gl_bai}" >&2
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
    echo -e "  检测带宽: ${gl_huang}${bandwidth} Mbps${gl_bai}" >&2
    echo -e "  服务地区: ${gl_huang}${region_label}${gl_bai}" >&2
    echo -e "  带宽等级: ${bandwidth_level}" >&2
    echo -e "  推荐缓冲区: ${gl_lv}${buffer_mb} MB${gl_bai}" >&2
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
    echo "" >&2
    
    # 询问确认
    if [ "$AUTO_MODE" = "1" ]; then
        confirm=Y
    else
        read -e -p "$(echo -e "${gl_huang}是否使用推荐值 ${buffer_mb}MB？(Y/N) [Y]: ${gl_bai}")" confirm
        confirm=${confirm:-Y}
    fi

    case "$confirm" in
        [Yy])
            # 返回缓冲区大小（MB）
            echo "$buffer_mb"
            return 0
            ;;
        *)
            local default_mb=16
            [ "$region" = "overseas" ] && default_mb=32
            echo "" >&2
            echo -e "${gl_huang}已取消，将使用通用值 ${default_mb}MB${gl_bai}" >&2
            echo "$default_mb"
            return 1
            ;;
    esac
}

#=============================================================================
# tcp_max_tw_buckets 取值计算
# 内核默认值 = TCP ehash 表大小 / 2（随内存增大：1G≈4096、2G≈8192、4G≈16384），
# 官方文档明确要求不得人为调低。旧版固定写 5000，在 ≥2G 内存的机器上反而低于默认值。
# 现规则：取 max(5000, 内核默认值)，任何机器都不低于旧版取值，也不低于内核默认值。
#=============================================================================
calculate_tw_buckets() {
    local floor_val=5000
    local candidate=0
    local ehash
    ehash=$(sysctl -n net.ipv4.tcp_ehash_entries 2>/dev/null)
    if [[ "$ehash" =~ ^[0-9]+$ ]] && [ "$ehash" -gt 0 ]; then
        # 内核 ≥ 6.1：直接读 ehash 表大小，得到准确的默认值
        candidate=$((ehash / 2))
    else
        # 旧内核（无 tcp_ehash_entries）或容器内读不到：保留当前运行值，避免调低
        local current
        current=$(sysctl -n net.ipv4.tcp_max_tw_buckets 2>/dev/null)
        if [[ "$current" =~ ^[0-9]+$ ]]; then
            candidate=$current
        fi
    fi
    if [ "$candidate" -gt "$floor_val" ]; then
        echo "$candidate"
    else
        echo "$floor_val"
    fi
}

#=============================================================================
# tcp_mem 取值计算（TCP 全局内存，单位：页）
# 不设置时内核只给约 1/16 内存作压力线、约 9% 作上限。中转机每个用户占两条连接，
# 几条大流同时跑就会撞线，内核进入内存压力后会同时压缩所有连接的缓冲区。
# 现规则：1/16 内存开始收紧、1/8 进入压力、1/4 硬上限，三档都不低于内核默认值。
# 按实际页大小换算（arm64 可能是 16K/64K 页，不能写死 4K）。
#=============================================================================
calculate_tcp_mem() {
    local mem_mb=$1
    local page_size
    page_size=$(getconf PAGESIZE 2>/dev/null)
    [[ "$page_size" =~ ^[0-9]+$ ]] && [ "$page_size" -gt 0 ] || page_size=4096
    awk -v m="$mem_mb" -v ps="$page_size" 'BEGIN{
        pg = m * 1048576 / ps
        low = int(pg / 16); pres = int(pg / 8); max = int(pg / 4)
        if (low < 4096) low = 4096; if (pres < 8192) pres = 8192; if (max < 16384) max = 16384
        printf "%d %d %d", low, pres, max
    }'
}

#=============================================================================
# 按内存限制单连接缓冲区上限
# 单连接最多占 tcp_mem 上限的 1/8（≈ 内存的 1/32），保证至少 8 条大流能同时跑满；
# 否则小内存机（如 1G 跑美西 1Gbps 档的 64MB）几条大流就吃光 TCP 全局内存。
# 下限 4MB，低于此连百兆长距离都跑不满。用法：cap_buffer_by_memory <缓冲区MB> <内存MB>
#=============================================================================
cap_buffer_by_memory() {
    local buffer_mb=$1
    local mem_mb=$2
    if ! [[ "$mem_mb" =~ ^[0-9]+$ ]] || [ "$mem_mb" -le 0 ]; then
        echo "$buffer_mb"
        return 0
    fi
    local cap_mb=$((mem_mb / 32))
    [ "$cap_mb" -lt 4 ] && cap_mb=4
    if [ "$buffer_mb" -gt "$cap_mb" ]; then
        echo -e "${gl_huang}⚠️ 内存 ${mem_mb}MB，单连接缓冲区按内存的 1/32 封顶：${buffer_mb}MB → ${cap_mb}MB${gl_bai}" >&2
        echo "$cap_mb"
    else
        echo "$buffer_mb"
    fi
}

#=============================================================================
# 逐项校验 sysctl 配置文件，把内核不接受的参数就地注释
# 被拒的参数留在文件里，systemd-sysctl.service 每次开机都会 failed，用户只看到
# 一个红色的系统服务，看不出是哪个参数。直接试写每一项（不解析 sysctl -p 的报错文本，
# 其格式随 procps 版本和语言环境变化）；试写成功的同时也就应用了该参数。
# 输出被注释的项数。用法：sysctl_apply_validated <配置文件>
#=============================================================================
sysctl_apply_validated() {
    local conf="$1"
    local line key val lineno=0 rejected=0 bad_lines=""
    [ -f "$conf" ] || { echo 0; return 0; }
    while IFS= read -r line || [ -n "$line" ]; do
        lineno=$((lineno + 1))
        case "$line" in ''|\#*|[[:space:]]\#*) continue ;; esac
        [[ "$line" == *=* ]] || continue
        key=$(printf '%s' "${line%%=*}" | tr -d ' \t')
        val=$(printf '%s' "${line#*=}" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
        [ -n "$key" ] || continue
        if [ ! -e "/proc/sys/${key//.//}" ] || ! sysctl -qw "${key}=${val}" >/dev/null 2>&1; then
            bad_lines="${bad_lines}${lineno} "
            echo -e "${gl_huang}  内核不接受 ${key} = ${val}，已在配置中注释${gl_bai}" >&2
            rejected=$((rejected + 1))
        fi
    done < "$conf"
    # 按行号注释（同名参数出现多次时只处理被拒的那一行），读完再统一改文件
    local n
    for n in $bad_lines; do
        sed -i "${n}s/^/# 本内核不支持，已自动注释: /" "$conf"
    done
    echo "$rejected"
}

#=============================================================================
# 配置冲突检测与清理（避免被其他 sysctl 覆盖）
#=============================================================================
check_and_clean_conflicts() {
    echo -e "${gl_kjlan}=== 检查 sysctl 配置冲突 ===${gl_bai}"
    local conflicts=()
    # 搜索 /etc/sysctl.d/ 下可能覆盖 tcp_rmem/tcp_wmem 的高序号文件
    for conf in /etc/sysctl.d/[0-9]*-*.conf; do
        [ -f "$conf" ] || continue
        [ "$conf" = "$SYSCTL_CONF" ] && continue
        # 本脚本旧版文件名：由功能3在新文件写入成功后迁移删除，不当作外部冲突处理
        [ "$conf" = "$SYSCTL_CONF_LEGACY" ] && continue
        if grep -qE "(^|\s)net\.ipv4\.tcp_(rmem|wmem)" "$conf" 2>/dev/null; then
            base=$(basename "$conf")
            num=$(echo "$base" | sed -n 's/^\([0-9]\+\).*/\1/p')
            # 99 及以上优先生效，可能覆盖本脚本
            if [ -n "$num" ] && [ "$num" -ge 99 ]; then
                conflicts+=("$conf")
            fi
        fi
    done

    # 主配置文件直接设置也会覆盖
    local has_sysctl_conflict=0
    if [ -f /etc/sysctl.conf ] && grep -qE "(^|\s)net\.ipv4\.tcp_(rmem|wmem)" /etc/sysctl.conf 2>/dev/null; then
        has_sysctl_conflict=1
    fi

    if [ ${#conflicts[@]} -eq 0 ] && [ $has_sysctl_conflict -eq 0 ]; then
        echo -e "${gl_lv}✓ 未发现可能的覆盖配置${gl_bai}"
        return 0
    fi

    echo -e "${gl_huang}发现可能的覆盖配置：${gl_bai}"
    for f in "${conflicts[@]}"; do
        echo "  - $f"; grep -E "net\.ipv4\.tcp_(rmem|wmem)" "$f" | sed 's/^/      /'
    done
    [ $has_sysctl_conflict -eq 1 ] && echo "  - /etc/sysctl.conf (含 tcp_rmem/tcp_wmem)"

    if [ "$AUTO_MODE" = "1" ]; then
        ans=Y
    else
        read -e -p "是否自动禁用/注释这些覆盖配置？(Y/N): " ans
    fi
    case "$ans" in
        [Yy])
            # 注释 /etc/sysctl.conf 中相关行
            if [ $has_sysctl_conflict -eq 1 ]; then
                # 先创建一次备份，再用 sed -i 逐行注释（避免多次 .bak 覆盖）
                cp /etc/sysctl.conf /etc/sysctl.conf.bak.conflict 2>/dev/null
                sed -i '/^net\.ipv4\.tcp_wmem/s/^/# /' /etc/sysctl.conf 2>/dev/null
                sed -i '/^net\.ipv4\.tcp_rmem/s/^/# /' /etc/sysctl.conf 2>/dev/null
                sed -i '/^net\.core\.rmem_max/s/^/# /' /etc/sysctl.conf 2>/dev/null
                sed -i '/^net\.core\.wmem_max/s/^/# /' /etc/sysctl.conf 2>/dev/null
                echo -e "${gl_lv}✓ 已注释 /etc/sysctl.conf 中的相关配置（备份: .bak.conflict）${gl_bai}"
            fi
            # 将高优先级冲突文件重命名禁用
            for f in "${conflicts[@]}"; do
                if [ ! -f "$f" ]; then
                    echo -e "${gl_lv}✓ 已跳过: $(basename "$f")（已处理）${gl_bai}"
                    continue
                fi
                if mv "$f" "${f}.disabled.$(date +%Y%m%d_%H%M%S)" 2>/dev/null; then
                    echo -e "${gl_lv}✓ 已禁用: $(basename "$f")${gl_bai}"
                else
                    echo -e "${gl_hong}✗ 无法禁用: $(basename "$f")，请手动处理${gl_bai}"
                fi
            done
            ;;
        *)
            echo -e "${gl_huang}已跳过自动清理，可能导致新配置未完全生效${gl_bai}"
            ;;
    esac
}

#=============================================================================
# 立即生效与防分片函数（无需重启）
#=============================================================================

# 获取需应用 qdisc 的网卡（排除常见虚拟接口）
eligible_ifaces() {
    for d in /sys/class/net/*; do
        [ -e "$d" ] || continue
        dev=$(basename "$d")
        case "$dev" in
            lo|docker*|veth*|br-*|virbr*|zt*|tailscale*|wg*|tun*|tap*) continue;;
        esac
        echo "$dev"
    done
}

# 给单个网卡设置 fq
# 多队列网卡（发送队列 > 1）保留根 mq，只把每个子队列换成 fq；直接把根换成一个 fq
# 会让所有发送队列挤进同一个 qdisc、共用一把锁。单队列网卡直接把根换成 fq。
# 内核自建的 mq 句柄是 0:，其子队列无法用 parent :N 寻址，需先换成 1: 句柄（子队列保留）。
# mq 设置失败时退回根 fq（与旧版行为一致）。本函数也会原样写入开机恢复脚本。
# 网卡上已有生效的限速/队列设置（如其他工具的端口限速 HTB、CAKE 等）时不覆盖，返回 2；
# BBR 自带发送节奏控制，不依赖 fq。只剩空壳的 HTB（没有子类、默认类也不存在）照常换成 fq。
fq_apply_iface() {
    local dev="$1" txq handle parents p root def
    root=$(tc qdisc show dev "$dev" 2>/dev/null | awk '$1=="qdisc" && / root /{print $2; exit}')
    case "$root" in
        ''|fq|fq_codel|mq|noqueue|pfifo_fast|pfifo|sfq) ;;
        htb)
            def=$(tc qdisc show dev "$dev" 2>/dev/null | awk '$2=="htb" && / root /{for(i=1;i<NF;i++) if($i=="default"){v=$(i+1); sub(/^0x/,"",v); print v; exit}}')
            # 除 1:1 父类外还有任何类（含直接挂在根下的，如其他工具的 1:10），即为生效中的限速
            if tc class show dev "$dev" 2>/dev/null | grep -v '^class htb 1:1 root ' | grep -q .; then
                return 2
            fi
            if [ -n "$def" ] && [ "$def" != 0 ] && tc class show dev "$dev" 2>/dev/null | grep -qE "^class htb [0-9a-f]+:${def} "; then
                return 2
            fi
            # 空壳：先删掉，网卡回到默认队列后再按下面的逻辑设置（多队列网卡才能正确建出 mq）
            tc qdisc del dev "$dev" root 2>/dev/null
            ;;
        *) return 2 ;;
    esac
    txq=$(ls -d /sys/class/net/"$dev"/queues/tx-* 2>/dev/null | wc -l)
    if [ "$txq" -gt 1 ]; then
        handle=$(tc qdisc show dev "$dev" 2>/dev/null | awk '$1=="qdisc" && $2=="mq" && / root /{print $3; exit}')
        if [ "$handle" = "1:" ] || tc qdisc replace dev "$dev" root handle 1: mq 2>/dev/null; then
            parents=$(tc qdisc show dev "$dev" 2>/dev/null | awk '$1=="qdisc"{for(i=1;i<NF;i++) if($i=="parent" && index($(i+1),"1:")==1) print $(i+1)}')
            if [ -n "$parents" ]; then
                for p in $parents; do
                    tc qdisc replace dev "$dev" parent "$p" fq 2>/dev/null || break
                done
                # 全部子队列都已是 fq 才算成功
                tc qdisc show dev "$dev" 2>/dev/null | awk '$1=="qdisc" && / parent 1:/ && $2!="fq"{bad=1} END{exit bad}' && return 0
            fi
        fi
    fi
    tc qdisc replace dev "$dev" root fq 2>/dev/null
}

# tc fq 立即生效（无需重启）
apply_tc_fq_now() {
    if ! command -v tc >/dev/null 2>&1; then
        echo -e "${gl_huang}警告: 未检测到 tc（iproute2），跳过 fq 应用${gl_bai}"
        return 0
    fi
    local applied=0 rc
    # 因已有限速/队列设置而保留未动的网卡，供调用方提示
    FQ_SKIPPED_IFACES=""
    for dev in $(eligible_ifaces); do
        fq_apply_iface "$dev"
        rc=$?
        if [ $rc -eq 0 ]; then
            applied=$((applied+1))
        elif [ $rc -eq 2 ]; then
            FQ_SKIPPED_IFACES="${FQ_SKIPPED_IFACES} ${dev}"
        fi
    done
    [ $applied -gt 0 ] && echo -e "${gl_lv}已对 $applied 个网卡应用 fq（即时生效）${gl_bai}" || echo -e "${gl_huang}未发现可应用 fq 的网卡${gl_bai}"
    [ -n "$FQ_SKIPPED_IFACES" ] && echo -e "${gl_huang}网卡${FQ_SKIPPED_IFACES} 已有限速/队列设置（端口限速、CAKE 等），已保留未覆盖${gl_bai}"
    return 0
}

# MSS clamp（防分片）自动启用
apply_mss_clamp() {
    local action=$1  # enable|disable
    if ! command -v iptables >/dev/null 2>&1; then
        echo -e "${gl_huang}警告: 未检测到 iptables，跳过 MSS clamp${gl_bai}"
        return 0
    fi
    if [ "$action" = "enable" ]; then
        iptables -t mangle -C FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu >/dev/null 2>&1 \
          || iptables -t mangle -A FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu
    else
        iptables -t mangle -D FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu >/dev/null 2>&1 || true
    fi
}

#=============================================================================
# BBR 配置函数（智能检测版）
#=============================================================================

# 读取当前内核 tcp_bbr 模块版本号（XanMod 的 BBR v3 输出 3；系统自带 BBR 无版本字段，输出为空）
# 拥塞控制算法名在 v1 / v3 下都叫 bbr，只看名字无法区分版本
detect_bbr_module_version() {
    local ver=""
    if command -v modinfo &>/dev/null; then
        ver=$(modinfo tcp_bbr 2>/dev/null | awk '/^version:/ {print $2; exit}')
    fi
    if [ -z "$ver" ] && [ -r /sys/module/tcp_bbr/version ]; then
        ver=$(tr -d '[:space:]' < /sys/module/tcp_bbr/version 2>/dev/null)
    fi
    echo "$ver"
}

# 直连/落地优化配置
bbr_configure_direct() {
    echo -e "${gl_kjlan}=== 配置 BBR v3 + FQ 直连/落地优化（智能检测版） ===${gl_bai}"
    echo ""
    
    # 步骤 1：带宽检测和缓冲区计算
    echo ""
    echo -e "${gl_zi}[步骤 1/5] 检测服务器带宽并计算最优缓冲区...${gl_bai}"

    local detected_bandwidth=$(detect_bandwidth)

    # 地区选择（影响缓冲区大小：高延迟地区需要更大缓冲区）
    local region="asia"
    local region_choice=""
    echo ""
    echo -e "${gl_kjlan}请选择服务器主要服务的地区：${gl_bai}"
    echo ""
    echo "1. 亚太地区（港/日/新/韩等）⭐ 推荐"
    echo "   延迟较低（RTT < 100ms），使用标准缓冲区"
    echo ""
    echo "2. 美国/欧洲（跨太平洋/大西洋）"
    echo "   延迟较高（RTT 150-300ms），使用大缓冲区"
    echo ""
    read -e -p "请输入选择 [1]: " region_choice
    region_choice=${region_choice:-1}
    case "$region_choice" in
        2) region="overseas" ;;
        *) region="asia" ;;
    esac

    local buffer_mb=$(calculate_buffer_size "$detected_bandwidth" "$region")
    # 物理内存：缓冲区封顶、tcp_mem 和虚拟内存参数都按它推导
    local mem_total=$(free -m | awk 'NR==2{print $2}')
    buffer_mb=$(cap_buffer_by_memory "$buffer_mb" "$mem_total")
    local buffer_bytes=$((buffer_mb * 1024 * 1024))
    local tcp_mem
    tcp_mem=$(calculate_tcp_mem "$mem_total")

    echo -e "${gl_lv}✅ 将使用 ${buffer_mb}MB 缓冲区配置${gl_bai}"
    sleep 2
    
    echo ""
    echo -e "${gl_zi}[步骤 2/5] 清理配置冲突...${gl_bai}"
    echo "正在检查配置冲突..."
    
    # 备份主配置文件（如果还没备份）
    if [ -f /etc/sysctl.conf ] && ! [ -f /etc/sysctl.conf.bak.original ]; then
        cp /etc/sysctl.conf /etc/sysctl.conf.bak.original
        echo "已备份: /etc/sysctl.conf -> /etc/sysctl.conf.bak.original"
    fi
    
    # 注释掉 /etc/sysctl.conf 中的 TCP 缓冲区配置（避免覆盖）
    if [ -f /etc/sysctl.conf ]; then
        clean_sysctl_conf
        echo "已清理 /etc/sysctl.conf 中的冲突配置"
    fi
    
    # 删除可能存在的软链接
    if [ -L /etc/sysctl.d/99-sysctl.conf ]; then
        rm -f /etc/sysctl.d/99-sysctl.conf
        echo "已删除配置软链接"
    fi
    
    # 检查并清理可能覆盖的新旧配置冲突
    check_and_clean_conflicts

    # 步骤 2：创建独立配置文件（使用动态缓冲区）
    echo ""
    echo -e "${gl_zi}[步骤 3/5] 创建配置文件...${gl_bai}"
    echo "正在创建新配置..."
    
    # 根据物理内存调整虚拟内存参数（mem_total 已在步骤 1 取得）
    local vm_swappiness=5
    local vm_dirty_ratio=15
    local vm_min_free_kbytes=65536
    
    # 根据内存大小微调虚拟内存参数
    if [ "$mem_total" -lt 2048 ]; then
        vm_swappiness=20
        vm_dirty_ratio=20
        vm_min_free_kbytes=32768
    fi
    
    # TIME_WAIT 上限：不低于内核按内存给出的默认值（旧版固定 5000 在大内存机器上偏低）
    local tw_buckets
    tw_buckets=$(calculate_tw_buckets)

    cat > "$SYSCTL_CONF" << EOF
# BBR v3 Direct/Endpoint Configuration (Intelligent Detection Edition)
# Generated on $(date)
# Bandwidth: ${detected_bandwidth} Mbps | Region: ${region} | Buffer: ${buffer_mb} MB

# 队列调度算法
net.core.default_qdisc=fq

# 拥塞控制算法
net.ipv4.tcp_congestion_control=bbr

# TCP 缓冲区优化（智能检测：${buffer_mb}MB）
net.core.rmem_max=${buffer_bytes}
net.core.wmem_max=${buffer_bytes}
# 接收起步值 131072 = 新内核默认值（旧版 87380 是老内核默认值，等于把起步调小了）
net.ipv4.tcp_rmem=4096 131072 ${buffer_bytes}
net.ipv4.tcp_wmem=4096 65536 ${buffer_bytes}

# TCP 全局内存（页）：内存 1/16 开始收紧、1/8 进入压力、1/4 硬上限
net.ipv4.tcp_mem=${tcp_mem}

# ===== 直连/落地优化参数 =====

# TIME_WAIT 重用（启用，提高并发）
net.ipv4.tcp_tw_reuse=1

# 端口范围（最大化）
net.ipv4.ip_local_port_range=1024 65535

# 连接队列（高性能）
net.core.somaxconn=4096
net.ipv4.tcp_max_syn_backlog=8192

# 网络队列（高带宽优化）
net.core.netdev_max_backlog=5000

# 高级TCP优化
net.ipv4.tcp_slow_start_after_idle=0
net.ipv4.tcp_mtu_probing=1

# ===== Reality终极优化参数 =====

# 发送低水位：恢复内核默认（不限制）
# 旧版设 16384，实测在 2 核中转机、170ms 线路上让连接起步阶段供数不足，
# 前 3 秒平均速度低约 40%，跑满后速度无差别。写明默认值而不是删掉这一行：
# 重跑本功能时运行中的旧值会立即改回，/etc/sysctl.conf 里的同名旧值也会被注释
net.ipv4.tcp_notsent_lowat=4294967295

# 连接回收优化（tw_buckets 取 max(5000, 内核默认值)，不人为调低）
net.ipv4.tcp_fin_timeout=15
net.ipv4.tcp_max_tw_buckets=${tw_buckets}

# TCP Fast Open（节省1个RTT，加速连接建立）
net.ipv4.tcp_fastopen=3

# TCP保活优化（更快检测死连接）
net.ipv4.tcp_keepalive_time=300
net.ipv4.tcp_keepalive_intvl=30
net.ipv4.tcp_keepalive_probes=5

# UDP缓冲区（QUIC/Hysteria 支持）
net.ipv4.udp_rmem_min=8192
net.ipv4.udp_wmem_min=8192

# TCP安全增强
net.ipv4.tcp_syncookies=1

# 虚拟内存优化（根据物理内存调整）
vm.swappiness=${vm_swappiness}
vm.dirty_ratio=${vm_dirty_ratio}
vm.dirty_background_ratio=5
vm.overcommit_memory=1
vm.min_free_kbytes=${vm_min_free_kbytes}
vm.vfs_cache_pressure=50

# CPU调度优化
kernel.sched_autogroup_enabled=0
kernel.numa_balancing=0
EOF

    # 检查配置文件是否创建成功
    if [ ! -f "$SYSCTL_CONF" ] || [ ! -s "$SYSCTL_CONF" ]; then
        echo -e "${gl_hong}❌ 配置文件创建失败！请检查磁盘空间和权限${gl_bai}"
        return 1
    fi

    # 迁移旧文件名：新文件写入成功后才删除旧的 99-bbr-ultimate.conf，避免两份并存
    if [ -f "$SYSCTL_CONF_LEGACY" ]; then
        if rm -f "$SYSCTL_CONF_LEGACY"; then
            echo "已迁移旧版配置文件: $(basename "$SYSCTL_CONF_LEGACY") → $(basename "$SYSCTL_CONF")"
        fi
    fi

    # /etc/sysctl.conf 中与本配置同名的参数全部注释（sysctl --system 最后加载它，会盖掉本配置）
    comment_sysctl_conf_duplicates "$SYSCTL_CONF"

    # 步骤 3：应用配置
    echo ""
    echo -e "${gl_zi}[步骤 4/5] 应用所有优化参数...${gl_bai}"
    echo "正在应用配置..."
    local sysctl_rejected
    sysctl_rejected=$(sysctl_apply_validated "$SYSCTL_CONF")
    if [ "${sysctl_rejected:-0}" -gt 0 ]; then
        echo -e "${gl_huang}⚠️ ${sysctl_rejected} 项参数本内核不支持，已在配置中注释（避免开机 systemd-sysctl 报错）${gl_bai}"
        echo -e "${gl_zi}其余参数均已生效，不影响整体优化${gl_bai}"
    else
        echo -e "${gl_lv}✓ 所有 sysctl 参数已成功应用${gl_bai}"
    fi

    # 立即应用 fq，并启用 MSS clamp（无需重启）
    echo "正在应用队列与防分片（无需重启）..."
    apply_tc_fq_now >/dev/null 2>&1
    if [ -n "$FQ_SKIPPED_IFACES" ]; then
        echo -e "${gl_huang}ℹ 网卡${FQ_SKIPPED_IFACES} 已有端口限速/CAKE 等设置，已保留未覆盖（BBR 自带发送节奏控制，不受影响）${gl_bai}"
    fi
    apply_mss_clamp enable >/dev/null 2>&1

    # 持久化 tc fq 和 iptables MSS clamp（重启后自动恢复）
    echo "正在配置重启持久化..."
    # 创建 systemd 服务实现 tc fq + MSS clamp 开机恢复
    # 排在端口限速开机恢复服务（如曾安装）之后：先由它建好 HTB，本服务再看到限速就跳过，不会互相覆盖
    cat > /etc/systemd/system/bbr-optimize-persist.service << 'PERSISTEOF'
[Unit]
Description=BBR Optimize - Restore tc fq and MSS clamp after boot
After=network-online.target ptm-boot-restore.service
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/bin/bbr-optimize-apply.sh

[Install]
WantedBy=multi-user.target
PERSISTEOF

    # fq_apply_iface 原样写入恢复脚本，开机与即时生效走同一份逻辑
    {
        echo '#!/bin/bash'
        echo '# BBR Optimize 重启恢复脚本 - 自动生成，勿手动编辑'
        declare -f fq_apply_iface
        cat << 'APPLYEOF'
# 应用 tc fq 到所有物理网卡（多队列网卡保留 mq，子队列设 fq）
for d in /sys/class/net/*; do
    [ -e "$d" ] || continue
    dev=$(basename "$d")
    case "$dev" in
        lo|docker*|veth*|br-*|virbr*|zt*|tailscale*|wg*|tun*|tap*) continue;;
    esac
    fq_apply_iface "$dev"
done
# 应用 iptables MSS clamp
if command -v iptables >/dev/null 2>&1; then
    iptables -t mangle -C FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu >/dev/null 2>&1 \
      || iptables -t mangle -A FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu
fi
# 禁用透明大页
if [ -f /sys/kernel/mm/transparent_hugepage/enabled ]; then
    echo never > /sys/kernel/mm/transparent_hugepage/enabled 2>/dev/null
fi
# 优化 TCP 初始拥塞窗口（加速连接起步）
DEF_ROUTE=$(ip route show default 2>/dev/null | head -1)
if [ -n "$DEF_ROUTE" ]; then
    CLEAN_ROUTE=$(echo "$DEF_ROUTE" | sed 's/ initcwnd [0-9]*//g; s/ initrwnd [0-9]*//g')
    ip route change $CLEAN_ROUTE initcwnd 32 initrwnd 32 2>/dev/null
fi
# RPS/RFS 多核网络优化（遍历所有物理网卡）
CPU_COUNT=$(nproc 2>/dev/null || echo 1)
if [ "$CPU_COUNT" -gt 1 ]; then
    RPS_MASK=$(printf '%x' $((2**CPU_COUNT - 1)))
    FLOW_ENTRIES=$((4096 * CPU_COUNT))
    echo "$FLOW_ENTRIES" > /proc/sys/net/core/rps_sock_flow_entries 2>/dev/null
    for D in /sys/class/net/*; do
        [ -e "$D" ] || continue
        DEV=$(basename "$D")
        case "$DEV" in
            lo|docker*|veth*|br-*|virbr*|zt*|tailscale*|wg*|tun*|tap*) continue;;
        esac
        [ -d "/sys/class/net/$DEV/queues" ] || continue
        for RXQ in /sys/class/net/$DEV/queues/rx-*/rps_cpus; do
            [ -f "$RXQ" ] && echo "$RPS_MASK" > "$RXQ" 2>/dev/null
        done
        for RXQ_DIR in /sys/class/net/$DEV/queues/rx-*/; do
            [ -f "${RXQ_DIR}rps_flow_cnt" ] && echo "$((FLOW_ENTRIES / CPU_COUNT))" > "${RXQ_DIR}rps_flow_cnt" 2>/dev/null
        done
    done
fi
APPLYEOF
    } > /usr/local/bin/bbr-optimize-apply.sh
    chmod +x /usr/local/bin/bbr-optimize-apply.sh
    systemctl daemon-reload 2>/dev/null
    systemctl enable bbr-optimize-persist.service 2>/dev/null
    echo -e "${gl_lv}✓ tc fq / MSS clamp / 透明大页 重启持久化已配置${gl_bai}"

    # 配置文件描述符限制
    echo "正在优化文件描述符限制..."
    if ! grep -q "^\* soft nofile 524288" /etc/security/limits.conf 2>/dev/null && \
       ! grep -q "BBR - 文件描述符优化" /etc/security/limits.conf 2>/dev/null; then
        cat >> /etc/security/limits.conf << 'LIMITSEOF'
# BBR - 文件描述符优化
* soft nofile 524288
* hard nofile 524288
LIMITSEOF
    fi
    ulimit -n 524288 2>/dev/null

    # 禁用透明大页面（当前运行时）
    if [ -f /sys/kernel/mm/transparent_hugepage/enabled ]; then
        echo never > /sys/kernel/mm/transparent_hugepage/enabled 2>/dev/null
    fi

    # 优化 TCP 初始拥塞窗口（加速连接起步，节省1-2个RTT）
    echo "正在优化 TCP 初始拥塞窗口..."
    local def_route
    def_route=$(ip route show default 2>/dev/null | head -1)
    if [ -n "$def_route" ]; then
        # 清除已有的 initcwnd/initrwnd 再重新设置，避免重复
        local clean_route
        clean_route=$(echo "$def_route" | sed 's/ initcwnd [0-9]*//g; s/ initrwnd [0-9]*//g')
        if ip route change $clean_route initcwnd 32 initrwnd 32 2>/dev/null; then
            echo -e "${gl_lv}✓ initcwnd=32 initrwnd=32 已应用（加速 TCP 连接起步）${gl_bai}"
        else
            echo -e "${gl_huang}⚠️ initcwnd 设置失败（不影响其他优化）${gl_bai}"
        fi
    else
        echo -e "${gl_huang}⚠️ 未检测到默认路由，跳过 initcwnd 优化${gl_bai}"
    fi

    # RPS/RFS 多核网络优化（将网卡收包分散到所有 CPU 核心）
    local cpu_count
    cpu_count=$(nproc 2>/dev/null || echo 1)
    if [ "$cpu_count" -gt 1 ]; then
        echo "正在配置 RPS/RFS 多核网络优化..."
        # 计算 CPU 掩码（所有核心参与）：2核=3, 4核=f, 8核=ff
        local rps_mask
        rps_mask=$(printf '%x' $((2**cpu_count - 1)))
        local flow_entries=$((4096 * cpu_count))
        echo "$flow_entries" > /proc/sys/net/core/rps_sock_flow_entries 2>/dev/null
        # 遍历所有物理网卡（排除虚拟/隧道接口）
        local rps_ok=0
        local rps_devs=""
        local dev
        for d in /sys/class/net/*; do
            [ -e "$d" ] || continue
            dev=$(basename "$d")
            case "$dev" in
                lo|docker*|veth*|br-*|virbr*|zt*|tailscale*|wg*|tun*|tap*) continue;;
            esac
            [ -d "/sys/class/net/$dev/queues" ] || continue
            # 设置 RPS：将收包分散到所有核心
            for rxq in /sys/class/net/$dev/queues/rx-*/rps_cpus; do
                if [ -f "$rxq" ]; then
                    echo "$rps_mask" > "$rxq" 2>/dev/null
                    # 写入后读回验证（有些环境 echo 返回0但内核没接受）
                    local verify_val
                    verify_val=$(cat "$rxq" 2>/dev/null | tr -d ',' | sed 's/^0*//')
                    [ -z "$verify_val" ] && verify_val="0"
                    [ "$verify_val" = "$rps_mask" ] && rps_ok=1
                fi
            done
            # 设置 RFS：同一连接的包尽量在同一核处理（减少 cache miss）
            for rxq_dir in /sys/class/net/$dev/queues/rx-*/; do
                if [ -f "${rxq_dir}rps_flow_cnt" ]; then
                    echo "$((flow_entries / cpu_count))" > "${rxq_dir}rps_flow_cnt" 2>/dev/null
                fi
            done
            rps_devs="${rps_devs} ${dev}"
        done
        if [ $rps_ok -eq 1 ]; then
            echo -e "${gl_lv}✓ RPS/RFS 已启用（${cpu_count} 核，掩码: 0x${rps_mask}，网卡:${rps_devs}）${gl_bai}"
        else
            echo -e "${gl_huang}⚠️ RPS 设置未生效（当前虚拟化环境可能不支持，不影响其他优化）${gl_bai}"
        fi
    else
        echo -e "${gl_zi}ℹ 单核 CPU，跳过 RPS/RFS（单核无需分担）${gl_bai}"
    fi

    # 步骤 4：验证配置是否真正生效
    echo ""
    echo -e "${gl_zi}[步骤 5/5] 验证配置...${gl_bai}"
    
    local actual_qdisc=$(sysctl -n net.core.default_qdisc 2>/dev/null)
    local actual_cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)
    local actual_wmem=$(sysctl -n net.ipv4.tcp_wmem 2>/dev/null | awk '{print $3}')
    local actual_rmem=$(sysctl -n net.ipv4.tcp_rmem 2>/dev/null | awk '{print $3}')
    
    echo ""
    echo -e "${gl_kjlan}=== 配置验证 ===${gl_bai}"
    
    # 验证队列算法
    if [ "$actual_qdisc" = "fq" ]; then
        echo -e "队列算法: ${gl_lv}$actual_qdisc ✓${gl_bai}"
    else
        echo -e "队列算法: ${gl_huang}$actual_qdisc (期望: fq) ⚠${gl_bai}"
    fi
    
    # 验证拥塞控制
    if [ "$actual_cc" = "bbr" ]; then
        echo -e "拥塞控制: ${gl_lv}$actual_cc ✓${gl_bai}"
    else
        echo -e "拥塞控制: ${gl_huang}$actual_cc (期望: bbr) ⚠${gl_bai}"
    fi

    # 验证 BBR 版本（算法名在 v1/v3 下都是 bbr，需看内核模块版本）
    local actual_bbr_ver
    actual_bbr_ver=$(detect_bbr_module_version)
    if [ "$actual_cc" = "bbr" ]; then
        if [ "$actual_bbr_ver" = "3" ]; then
            echo -e "BBR 版本:   ${gl_lv}v3 ✓${gl_bai}"
        else
            echo -e "BBR 版本:   ${gl_huang}系统自带 BBR（未检测到 v3）${gl_bai}"
        fi
    fi

    # 验证缓冲区（动态）
    local actual_wmem_mb=$((actual_wmem / 1048576))
    local actual_rmem_mb=$((actual_rmem / 1048576))
    
    if [ "$actual_wmem" = "$buffer_bytes" ]; then
        echo -e "发送缓冲区: ${gl_lv}${buffer_mb}MB ✓${gl_bai}"
    else
        echo -e "发送缓冲区: ${gl_huang}${actual_wmem_mb}MB (期望: ${buffer_mb}MB) ⚠${gl_bai}"
    fi
    
    if [ "$actual_rmem" = "$buffer_bytes" ]; then
        echo -e "接收缓冲区: ${gl_lv}${buffer_mb}MB ✓${gl_bai}"
    else
        echo -e "接收缓冲区: ${gl_huang}${actual_rmem_mb}MB (期望: ${buffer_mb}MB) ⚠${gl_bai}"
    fi

    # 验证 TCP 全局内存（sysctl 输出以制表符分隔，统一成空格再比较）
    local actual_tcp_mem
    actual_tcp_mem=$(sysctl -n net.ipv4.tcp_mem 2>/dev/null | tr -s '[:space:]' ' ' | sed 's/ $//')
    if [ "$actual_tcp_mem" = "$tcp_mem" ]; then
        echo -e "TCP 全局内存: ${gl_lv}${tcp_mem} 页 ✓${gl_bai}"
    else
        echo -e "TCP 全局内存: ${gl_huang}${actual_tcp_mem} 页 (期望: ${tcp_mem}) ⚠${gl_bai}"
    fi

    # 验证 initcwnd
    local actual_initcwnd
    actual_initcwnd=$(ip route show default 2>/dev/null | head -1 | grep -oP 'initcwnd \K[0-9]+')
    if [ "$actual_initcwnd" = "32" ]; then
        echo -e "初始窗口:   ${gl_lv}initcwnd=$actual_initcwnd ✓${gl_bai}"
    elif [ -n "$actual_initcwnd" ]; then
        echo -e "初始窗口:   ${gl_huang}initcwnd=$actual_initcwnd (期望: 32) ⚠${gl_bai}"
    else
        echo -e "初始窗口:   ${gl_huang}未设置 (期望: initcwnd=32) ⚠${gl_bai}"
    fi

    # 验证 RPS
    if [ "$cpu_count" -gt 1 ]; then
        local expected_mask
        expected_mask=$(printf '%x' $((2**cpu_count - 1)))
        local rps_verify_devs=""
        local rps_all_ok=1
        for d in /sys/class/net/*; do
            [ -e "$d" ] || continue
            local vdev=$(basename "$d")
            case "$vdev" in
                lo|docker*|veth*|br-*|virbr*|zt*|tailscale*|wg*|tun*|tap*) continue;;
            esac
            [ -f "/sys/class/net/$vdev/queues/rx-0/rps_cpus" ] || continue
            local rps_val
            # rps_cpus 可能返回 "3" 或 "00000003" 或 "00000000,00000003"
            rps_val=$(cat /sys/class/net/$vdev/queues/rx-0/rps_cpus 2>/dev/null | tr -d ',' | sed 's/^0*//')
            [ -z "$rps_val" ] && rps_val="0"
            if [ "$rps_val" = "$expected_mask" ]; then
                rps_verify_devs="${rps_verify_devs} ${vdev}✓"
            else
                rps_verify_devs="${rps_verify_devs} ${vdev}✗"
                rps_all_ok=0
            fi
        done
        if [ -n "$rps_verify_devs" ]; then
            if [ $rps_all_ok -eq 1 ]; then
                echo -e "RPS/RFS:    ${gl_lv}${cpu_count}核分担 (0x${expected_mask})${rps_verify_devs} ✓${gl_bai}"
            else
                echo -e "RPS/RFS:    ${gl_huang}部分网卡未生效:${rps_verify_devs} ⚠${gl_bai}"
            fi
        else
            echo -e "RPS/RFS:    ${gl_huang}未检测到物理网卡 ⚠${gl_bai}"
        fi
    else
        echo -e "RPS/RFS:    ${gl_zi}单核跳过${gl_bai}"
    fi

    echo ""

    # 最终判断
    if [ "$actual_qdisc" = "fq" ] && [ "$actual_cc" = "bbr" ] && \
       [ "$actual_wmem" = "$buffer_bytes" ] && [ "$actual_rmem" = "$buffer_bytes" ]; then
        if [ "$actual_bbr_ver" = "3" ]; then
            echo -e "${gl_lv}✅ BBR v3 直连/落地优化配置完成并已生效！${gl_bai}"
        else
            # 参数已全部生效，但当前内核的 BBR 不是 v3：如实提示，不再显示“BBR v3 已生效”
            echo -e "${gl_lv}✅ BBR 直连/落地优化配置完成并已生效！${gl_bai}"
            if [ "$(uname -m)" = "aarch64" ]; then
                echo -e "${gl_huang}ℹ 当前为系统自带 BBR（ARM64 平台暂无官方 BBR v3 方案），以上优化参数均已生效${gl_bai}"
            else
                echo -e "${gl_huang}ℹ 当前为系统自带 BBR，不是 BBR v3；以上优化参数均已生效${gl_bai}"
                echo -e "${gl_huang}  如需 BBR v3：请执行功能 1 安装 XanMod 内核并重启${gl_bai}"
            fi
        fi
        echo -e "${gl_zi}配置说明: ${buffer_mb}MB 缓冲区（${detected_bandwidth} Mbps 带宽），适合直连/落地场景${gl_bai}"
    else
        echo -e "${gl_huang}⚠️ 配置已保存但部分参数未生效${gl_bai}"
        echo -e "${gl_huang}建议执行以下操作：${gl_bai}"
        echo "1. 检查是否有其他配置文件冲突"
        echo "2. 重启服务器使配置完全生效: reboot"
    fi
}

#=============================================================================
# 状态检查函数
#=============================================================================

check_bbr_status() {
    echo -e "${gl_kjlan}=== 当前系统状态 ===${gl_bai}"
    local kernel_release
    kernel_release=$(uname -r)
    echo "内核版本: $kernel_release"
    
    local congestion="未知"
    local qdisc="未知"
    local bbr_version=""
    local bbr_active=0
    
    if command -v sysctl &>/dev/null; then
        congestion=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "未知")
        qdisc=$(sysctl -n net.core.default_qdisc 2>/dev/null || echo "未知")
        echo "拥塞控制算法: $congestion"
        echo "队列调度算法: $qdisc"
        
        if command -v modinfo &>/dev/null; then
            bbr_version=$(modinfo tcp_bbr 2>/dev/null | awk '/^version:/ {print $2}')
            if [ -n "$bbr_version" ]; then
                if [ "$bbr_version" = "3" ]; then
                    echo -e "BBR 版本: ${gl_lv}v${bbr_version} ✓${gl_bai}"
                else
                    echo -e "BBR 版本: ${gl_huang}v${bbr_version} (不是 v3)${gl_bai}"
                fi
            fi
        fi
    fi
    
    if [ "$congestion" = "bbr" ] && [ "$bbr_version" = "3" ]; then
        bbr_active=1
    fi
    
    local xanmod_pkg_installed=0
    local dpkg_available=0
    if command -v dpkg &>/dev/null; then
        dpkg_available=1
        if dpkg -l 2>/dev/null | grep -qE '^ii\s+linux-.*xanmod'; then
            xanmod_pkg_installed=1
        fi
    fi
    
    local xanmod_running=0
    if echo "$kernel_release" | grep -qi 'xanmod'; then
        xanmod_running=1
    fi
    
    local status=1
    
    if [ $xanmod_pkg_installed -eq 1 ]; then
        echo -e "XanMod 内核: ${gl_lv}已安装 ✓${gl_bai}"
        status=0
    elif [ $xanmod_running -eq 1 ]; then
        echo -e "XanMod 内核: ${gl_huang}内核包已卸载，但当前运行版本仍为 ${kernel_release}，请重启系统使卸载完全生效${gl_bai}"
    else
        echo -e "XanMod 内核: ${gl_huang}未安装${gl_bai}"
    fi
    
    if [ $status -ne 0 ] && [ $bbr_active -eq 1 ]; then
        echo -e "${gl_kjlan}提示: 当前仍在运行 BBR v3 模块，重启后将恢复系统默认配置${gl_bai}"
    fi
    
    if [ $status -ne 0 ] && [ $dpkg_available -eq 0 ]; then
        # 非 Debian 系统：仅当内核名确实含 xanmod 时才认为已安装
        # BBR v3 活跃不等于 XanMod（用户可能自编译内核），避免误触发 update 流程
        if [ $xanmod_running -eq 1 ]; then
            status=0
        fi
    fi
    
    return $status
}

#=============================================================================
# XanMod 内核安装（官方源）
#=============================================================================

xanmod_get_repo_suite() {
    local suite=""

    if [ -r /etc/os-release ]; then
        suite=$( ( . /etc/os-release; printf '%s' "${VERSION_CODENAME:-${UBUNTU_CODENAME:-}}" ) )
    fi

    if [ -z "$suite" ] && command -v lsb_release &>/dev/null; then
        suite=$(lsb_release -sc 2>/dev/null)
    fi

    if [ -z "$suite" ]; then
        echo -e "${gl_hong}错误: 无法识别系统发行版 codename，不能添加 XanMod 软件源${gl_bai}" >&2
        return 1
    fi

    case "$suite" in
        bookworm|trixie|forky|sid|noble|plucky|questing|resolute|faye|gigi|wilma|xia|zara|zena)
            ;;
        *)
            echo -e "${gl_huang}警告: 当前发行版 codename 为 ${suite}，可能不在 XanMod 官方支持列表中${gl_bai}" >&2
            ;;
    esac

    echo "$suite"
}

xanmod_write_repo() {
    local gpg_key_file=$1
    local repo_file=$2
    local suite

    suite=$(xanmod_get_repo_suite) || return 1
    echo "deb [signed-by=${gpg_key_file}] https://deb.xanmod.org ${suite} main" | \
        tee "$repo_file" > /dev/null
    echo -e "${gl_lv}✅ XanMod 软件源: ${suite}${gl_bai}"
}

xanmod_select_kernel_package() {
    local version=$1
    local candidates=()

    case "$version" in
        1)
            candidates=("linux-xanmod-lts-x64v1")
            ;;
        2)
            candidates=("linux-xanmod-x64v2" "linux-xanmod-lts-x64v2")
            ;;
        3)
            candidates=("linux-xanmod-x64v3" "linux-xanmod-lts-x64v3")
            ;;
        4)
            # XanMod 官方 mainline 当前不提供 x64v4；v4 CPU 使用 x64v3 更稳妥。
            candidates=("linux-xanmod-x64v3" "linux-xanmod-lts-x64v3")
            ;;
        *)
            candidates=("linux-xanmod-x64v3" "linux-xanmod-lts-x64v3")
            ;;
    esac

    local pkg
    for pkg in "${candidates[@]}"; do
        if apt-cache show "$pkg" >/dev/null 2>&1; then
            echo "$pkg"
            return 0
        fi
    done

    return 1
}

install_xanmod_kernel() {
    clear
    echo -e "${gl_kjlan}=== 安装 XanMod 内核与 BBR v3 ===${gl_bai}"
    echo "视频教程: https://www.bilibili.com/video/BV14K421x7BS"
    echo "------------------------------------------------"

    # 先检测架构：ARM64 无可安装内容，不应先询问用户是否安装
    local cpu_arch
    cpu_arch=$(uname -m)

    if [ "$cpu_arch" = "aarch64" ]; then
        echo -e "检测到 CPU 架构: ${gl_huang}aarch64 (ARM64)${gl_bai}"
        echo ""
        echo -e "${gl_huang}⚠ ARM64 平台暂无官方 BBR v3 方案${gl_bai}"
        echo ""
        echo "原因：BBR v3 至今未合入 Linux 主线内核，必须使用打过补丁"
        echo "      重新编译的内核；而 XanMod 官方仅提供 x86-64 构建。"
        echo ""
        echo -e "${gl_lv}✅ 但你的 ARM 机器依然可以做网络优化：${gl_bai}"
        echo -e "   请直接使用【${gl_lv}功能 3 - BBR 直连/落地优化${gl_bai}】"
        echo ""
        echo "   ARM 内核自带 BBR + fq 队列算法，配合功能 3 的带宽检测"
        echo "   与缓冲区调优，同样能获得明显的网络性能提升。"
        echo ""
        echo "------------------------------------------------"
        break_end
        return 1
    fi

    echo "支持系统: Debian/Ubuntu x86_64（ARM64 请使用功能 3）"
    echo -e "${gl_huang}警告: 将升级 Linux 内核，请提前备份重要数据！${gl_bai}"
    echo "------------------------------------------------"
    read -e -p "确定继续安装吗？(Y/N): " choice

    case "$choice" in
        [Yy])
            ;;
        *)
            echo "已取消安装"
            return 1
            ;;
    esac

    # 显式检查 x86_64 架构（aarch64 已在前面提前返回，这里兜底其余架构）
    if [ "$cpu_arch" != "x86_64" ]; then
        echo -e "${gl_hong}错误: 不支持的 CPU 架构: ${cpu_arch}${gl_bai}"
        echo "XanMod 内核仅提供 x86_64 构建；其他架构可使用功能 3 做网络调优。"
        break_end
        return 1
    fi

    # x86_64 架构安装流程
    # 检查系统支持
    if [ -r /etc/os-release ]; then
        . /etc/os-release
        if [ "$ID" != "debian" ] && [ "$ID" != "ubuntu" ]; then
            echo -e "${gl_hong}错误: 仅支持 Debian 和 Ubuntu 系统${gl_bai}"
            return 1
        fi
    else
        echo -e "${gl_hong}错误: 无法确定操作系统类型${gl_bai}"
        return 1
    fi

    # 环境准备
    check_disk_space 3 || return 1
    install_package wget gnupg || { echo -e "${gl_hong}错误: 无法安装必要依赖 wget/gnupg${gl_bai}"; return 1; }

    # 添加 XanMod GPG 密钥（分步执行，避免管道 $? 只检查最后一条命令）
    echo "正在添加 XanMod 仓库密钥..."
    local gpg_key_file="/usr/share/keyrings/xanmod-archive-keyring.gpg"
    local key_tmp=$(mktemp)
    local gpg_ok=false

    # 尝试1: 从镜像源下载
    if wget -qO "$key_tmp" "${gh_proxy}raw.githubusercontent.com/kejilion/sh/main/archive.key" 2>/dev/null && \
       [ -s "$key_tmp" ]; then
        if gpg --dearmor -o "$gpg_key_file" --yes < "$key_tmp" 2>/dev/null; then
            gpg_ok=true
        fi
    fi

    # 尝试2: 从 XanMod 官方源下载
    if [ "$gpg_ok" = false ]; then
        echo -e "${gl_huang}镜像源失败，尝试 XanMod 官方源...${gl_bai}"
        if wget -qO "$key_tmp" "https://dl.xanmod.org/archive.key" 2>/dev/null && \
           [ -s "$key_tmp" ]; then
            if gpg --dearmor -o "$gpg_key_file" --yes < "$key_tmp" 2>/dev/null; then
                gpg_ok=true
            fi
        fi
    fi

    rm -f "$key_tmp"

    if [ "$gpg_ok" = false ]; then
        echo -e "${gl_hong}错误: GPG 密钥导入失败，无法继续安装${gl_bai}"
        echo "请检查网络连接后重试"
        return 1
    fi
    echo -e "${gl_lv}✅ GPG 密钥导入成功${gl_bai}"

    local xanmod_repo_file="/etc/apt/sources.list.d/xanmod-release.list"

    # 添加 XanMod 仓库（使用系统 codename；旧 releases suite 已为空）
    xanmod_write_repo "$gpg_key_file" "$xanmod_repo_file" || return 1

    # 检测 CPU 架构版本（使用安全临时目录）
    echo "正在检测 CPU 支持的最优内核版本..."
    local detect_dir=$(mktemp -d)
    local detect_script="${detect_dir}/check_x86-64_psabi.sh"
    local version=""

    if wget -qO "$detect_script" "${gh_proxy}raw.githubusercontent.com/kejilion/sh/main/check_x86-64_psabi.sh" 2>/dev/null && \
       [ -s "$detect_script" ]; then
        chmod +x "$detect_script"
        version=$("$detect_script" 2>/dev/null | sed -nE 's/.*x86-64-v([1-4]).*/\1/p' | head -1)
    fi
    rm -rf "$detect_dir"

    # 在线检测失败时，使用本地 /proc/cpuinfo 检测 CPU 支持的最高等级
    if ! [[ "$version" =~ ^[1-4]$ ]]; then
        echo -e "${gl_huang}在线检测脚本不可用，使用本地 CPU 特征检测...${gl_bai}"
        local cpu_flags=$(grep -m1 '^flags' /proc/cpuinfo 2>/dev/null)
        if echo "$cpu_flags" | grep -qw 'avx512f'; then
            version="4"
        elif echo "$cpu_flags" | grep -qw 'avx2'; then
            version="3"
        elif echo "$cpu_flags" | grep -qw 'sse4_2'; then
            version="2"
        else
            version="1"
        fi
        echo -e "${gl_lv}本地检测结果: CPU 支持 x86-64-v${version}${gl_bai}"
    fi

    # 安装 XanMod 内核
    echo "正在更新软件包列表..."
    if ! apt-get update; then
        echo -e "${gl_huang}⚠️  apt-get update 部分失败，尝试继续安装...${gl_bai}"
    fi

    local xanmod_package
    xanmod_package=$(xanmod_select_kernel_package "$version")
    if [ -z "$xanmod_package" ]; then
        echo -e "${gl_hong}错误: 未找到适合 x86-64-v${version} 的 XanMod 内核包${gl_bai}"
        echo -e "${gl_huang}可用包参考:${gl_bai}"
        apt-cache search '^linux-xanmod' 2>/dev/null | awk '{print "  - " $1}' | head -20
        rm -f "$xanmod_repo_file"
        return 1
    fi

    echo -e "${gl_lv}将安装: ${xanmod_package}${gl_bai}"
    if [ "$version" = "4" ] && echo "$xanmod_package" | grep -q 'x64v3'; then
        echo -e "${gl_huang}说明: XanMod 官方 mainline 当前不提供 x64v4，x86-64-v4 CPU 使用 x64v3 包${gl_bai}"
    elif [ "$version" = "1" ] && echo "$xanmod_package" | grep -q 'lts'; then
        echo -e "${gl_huang}说明: XanMod 官方 mainline 当前不提供 x64v1，x86-64-v1 CPU 使用 LTS 包${gl_bai}"
    fi

    apt-get install -y "$xanmod_package"

    if [ $? -ne 0 ]; then
        echo -e "${gl_hong}内核安装失败！${gl_bai}"
        rm -f "$xanmod_repo_file"
        return 1
    fi

    # 验证内核是否真正安装成功
    if ! dpkg -l 2>/dev/null | awk -v pkg="$xanmod_package" '$1 == "ii" && $2 == pkg { found=1 } END { exit !found }'; then
        echo -e "${gl_hong}内核包安装验证失败！${gl_bai}"
        rm -f "$xanmod_repo_file"
        return 1
    fi

    echo -e "${gl_lv}XanMod 内核安装成功！${gl_bai}"
    echo -e "${gl_huang}提示: 请先重启系统加载新内核，然后再配置 BBR${gl_bai}"
    echo ""
    echo -e "${gl_kjlan}━━━━━━━━━━ CPU 架构信息 ━━━━━━━━━━${gl_bai}"
    echo -e "  CPU 架构等级: ${gl_lv}x86-64-v${version}${gl_bai}"
    echo -e "  安装内核包: ${gl_lv}${xanmod_package}${gl_bai}"
    echo -e "  ${gl_huang}说明: 本机 CPU 最高支持 v${version}，已安装官方仓库中最匹配的内核包${gl_bai}"
    echo -e "  ${gl_huang}官方 mainline 当前提供 x64v2/x64v3；x64v1 使用 LTS，x64v4 使用 x64v3${gl_bai}"
    echo -e "${gl_kjlan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"
    echo ""
    echo -e "${gl_kjlan}后续更新: 再次运行选项1即可检查并安装最新内核${gl_bai}"

    rm -f "$xanmod_repo_file"
    echo -e "${gl_lv}已自动清理 XanMod 软件源（如需更新可再次运行选项1）${gl_bai}"

    return 0
}

#=============================================================================
# DNS净化与安全加固功能（NS论坛）- SSH安全增强版
#=============================================================================

# DNS净化 - 智能检测并修复 systemd-resolved
dns_purify_fix_systemd_resolved() {
    echo -e "${gl_kjlan}正在检测 systemd-resolved 服务状态...${gl_bai}"

    # 检查服务是否已启用且正在运行
    if systemctl is-enabled systemd-resolved &> /dev/null; then
        if systemctl is-active --quiet systemd-resolved; then
            echo -e "${gl_lv}✅ systemd-resolved 服务已启用且运行中${gl_bai}"
            return 0
        else
            # 已启用但未运行（可能 crash 或被手动停止）
            echo -e "${gl_huang}systemd-resolved 已启用但未运行，正在启动...${gl_bai}"
            systemctl start systemd-resolved 2>/dev/null || true
            sleep 2
            if systemctl is-active --quiet systemd-resolved; then
                echo -e "${gl_lv}✅ systemd-resolved 服务已成功启动${gl_bai}"
                return 0
            else
                echo -e "${gl_hong}启动失败，尝试重新启用...${gl_bai}"
                systemctl restart systemd-resolved 2>/dev/null || true
                sleep 2
                if systemctl is-active --quiet systemd-resolved; then
                    echo -e "${gl_lv}✅ systemd-resolved 服务已重启成功${gl_bai}"
                    return 0
                else
                    echo -e "${gl_hong}服务无法启动${gl_bai}"
                    systemctl status systemd-resolved --no-pager || true
                    return 1
                fi
            fi
        fi
    fi

    # 检查是否被 masked
    if systemctl status systemd-resolved 2>&1 | grep -q "masked"; then
        echo -e "${gl_huang}检测到 systemd-resolved 被屏蔽 (masked)，正在修复...${gl_bai}"

        # 解除屏蔽
        if systemctl unmask systemd-resolved 2>/dev/null; then
            echo -e "${gl_lv}✅ 已成功解除 systemd-resolved 的屏蔽状态${gl_bai}"
        else
            echo -e "${gl_hong}解除屏蔽失败，尝试手动修复...${gl_bai}"
            # 手动删除屏蔽链接
            rm -f /etc/systemd/system/systemd-resolved.service 2>/dev/null || true
            systemctl daemon-reload
            echo -e "${gl_lv}✅ 已手动移除屏蔽链接${gl_bai}"
        fi

        # 启用服务
        if systemctl enable systemd-resolved 2>/dev/null; then
            echo -e "${gl_lv}✅ 已启用 systemd-resolved 服务${gl_bai}"
        else
            echo -e "${gl_hong}启用服务失败${gl_bai}"
            return 1
        fi

        # 启动服务
        if systemctl start systemd-resolved 2>/dev/null; then
            echo -e "${gl_lv}✅ 已启动 systemd-resolved 服务${gl_bai}"
        else
            echo -e "${gl_hong}启动服务失败${gl_bai}"
            return 1
        fi

        # 等待服务完全启动
        sleep 2

        # 验证服务状态
        if systemctl is-active --quiet systemd-resolved; then
            echo -e "${gl_lv}✅ systemd-resolved 服务运行正常${gl_bai}"
            return 0
        else
            echo -e "${gl_hong}服务启动后状态异常${gl_bai}"
            systemctl status systemd-resolved --no-pager || true
            return 1
        fi
    else
        echo -e "${gl_huang}systemd-resolved 未启用，正在启用...${gl_bai}"
        systemctl enable systemd-resolved 2>/dev/null || true
        systemctl start systemd-resolved 2>/dev/null || true

        # 等待服务启动并验证
        sleep 2
        if systemctl is-active --quiet systemd-resolved; then
            echo -e "${gl_lv}✅ systemd-resolved 服务已启用并运行${gl_bai}"
            return 0
        else
            echo -e "${gl_hong}systemd-resolved 启动失败${gl_bai}"
            systemctl status systemd-resolved --no-pager || true
            return 1
        fi
    fi
}

# DNS净化 - 主执行函数（SSH安全版）
dns_purify_and_harden() {
    clear
    echo -e "${gl_kjlan}╔════════════════════════════════════════════════════════════╗${gl_bai}"
    echo -e "${gl_kjlan}║    DNS净化与安全加固脚本 - SSH安全增强版 v2.0             ║${gl_bai}"
    echo -e "${gl_kjlan}╚════════════════════════════════════════════════════════════╝${gl_bai}"
    echo ""

    # ==================== SSH安全检测 ====================
    local IS_SSH=false
    if [ -n "$SSH_CLIENT" ] || [ -n "$SSH_TTY" ]; then
        IS_SSH=true
        echo -e "${gl_hong}⚠️  检测到您正在通过SSH连接${gl_bai}"
        echo -e "${gl_lv}✅ SSH安全模式已启用：本脚本不会中断您的网络连接${gl_bai}"
        echo ""
    fi

    echo -e "${gl_kjlan}功能说明：${gl_bai}"
    echo "  ✓ 配置安全的DNS服务器（支持国外/国内模式）"
    echo "  ✓ 防止DHCP覆盖DNS配置"
    echo "  ✓ 清除厂商残留的DNS配置"
    echo "  ✓ 启用DNS安全功能（DNSSEC + DNS over TLS）"
    echo ""

    if [ "$IS_SSH" = true ]; then
        echo -e "${gl_lv}SSH安全保证：${gl_bai}"
        echo "  ✓ 不会停止或重启网络服务"
        echo "  ✓ 不会中断SSH连接"
        echo "  ✓ 所有配置立即生效，无需重启"
        echo "  ✓ 提供完整的回滚机制"
        echo ""
    fi

    # ==================== 已有配置检测 ====================
    local dns_has_config=false
    local dns_is_legacy=false
    local dns_all_healthy=true
    local current_mode_name=""
    local svc_file="/etc/systemd/system/dns-purify-persist.service"

    # 第一步：检测是否存在 DNS 净化配置（不管健不健康）
    if systemctl is-enabled --quiet dns-purify-persist.service 2>/dev/null \
       || [ -f "$svc_file" ] \
       || [ -x /usr/local/bin/dns-purify-apply.sh ]; then
        dns_has_config=true
    fi

    # 第二步：如果存在配置，立即检查是新版还是老版（独立于DNS健康状态）
    if [ "$dns_has_config" = true ]; then
        # 老版特征1: 服务文件用 Requires 而非 Wants
        if [ -f "$svc_file" ] && grep -q "Requires=systemd-resolved" "$svc_file" 2>/dev/null; then
            dns_is_legacy=true
        fi
        # 老版特征2: 持久化脚本缺少 resolvectl 可用性检查
        if [ -x /usr/local/bin/dns-purify-apply.sh ] && ! grep -q "command -v resolvectl\|NET_TCP_BOOT_RECOVERY_V1" /usr/local/bin/dns-purify-apply.sh 2>/dev/null; then
            dns_is_legacy=true
        fi
    fi

    # 第三步：健康检查（仅在有配置时执行）
    if [ "$dns_has_config" = true ]; then
        # 持久化服务已启用？
        if ! systemctl is-enabled --quiet dns-purify-persist.service 2>/dev/null; then
            dns_all_healthy=false
        fi
        # 持久化脚本存在？
        if [ ! -x /usr/local/bin/dns-purify-apply.sh ]; then
            dns_all_healthy=false
        fi
        # resolved 运行中？
        if ! systemctl is-active --quiet systemd-resolved 2>/dev/null; then
            dns_all_healthy=false
        fi
        # resolv.conf 指向 stub？
        if [ ! -L /etc/resolv.conf ] || [[ "$(readlink /etc/resolv.conf 2>/dev/null)" != *"stub-resolv.conf"* ]]; then
            dns_all_healthy=false
        fi
        # DNS 解析正常？
        if [ "$dns_all_healthy" = true ]; then
            local dns_resolve_ok=false
            if command -v getent >/dev/null 2>&1; then
                if getent hosts google.com >/dev/null 2>&1 || getent hosts baidu.com >/dev/null 2>&1; then
                    dns_resolve_ok=true
                fi
            fi
            if [ "$dns_resolve_ok" = false ]; then
                dns_all_healthy=false
            fi
        fi
    fi

    # 检测当前模式
    if [ "$dns_has_config" = true ] && [ -f /etc/systemd/resolved.conf ]; then
        local cur_dot
        cur_dot=$(sed -nE 's/^DNSOverTLS=(.+)/\1/p' /etc/systemd/resolved.conf 2>/dev/null)
        case "$cur_dot" in
            yes)           current_mode_name="纯国外模式（强制DoT）" ;;
            no)            current_mode_name="纯国内模式" ;;
            opportunistic) current_mode_name="混合模式（机会性DoT）" ;;
        esac
    fi

    # ==================== 显示检测结果 ====================
    if [ "$dns_has_config" = true ] && [ "$dns_is_legacy" = true ]; then
        # 老版配置（不管DNS当前是否健康，都必须警告）
        echo -e "${gl_hong}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"
        echo -e "${gl_hong}  ⚠️  检测到老版 DNS 净化配置，重启后可能导致 DNS 失效！${gl_bai}"
        echo -e "${gl_hong}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"
        echo ""
        [ -n "$current_mode_name" ] && echo -e "  当前模式:    ${gl_huang}${current_mode_name}${gl_bai}"
        if systemctl is-active --quiet systemd-resolved 2>/dev/null; then
            echo -e "  resolved:    ${gl_lv}✅ 运行中${gl_bai}"
        else
            echo -e "  resolved:    ${gl_hong}❌ 未运行${gl_bai}"
        fi
        if [ "$dns_all_healthy" = true ]; then
            echo -e "  DNS 解析:    ${gl_lv}✅ 当前正常${gl_bai}"
        else
            echo -e "  DNS 解析:    ${gl_hong}❌ 当前异常${gl_bai}"
        fi
        echo -e "  开机持久化:  ${gl_hong}⚠️  老版（重启有风险）${gl_bai}"
        echo ""
        echo -e "${gl_huang}原因：老版持久化服务存在已知bug，重启后可能导致DNS断连${gl_bai}"
        echo -e "${gl_lv}建议：继续执行功能5，新版会自动替换为安全的持久化机制${gl_bai}"
        echo ""

    elif [ "$dns_has_config" = true ] && [ "$dns_all_healthy" = true ]; then
        # 新版配置 + 全部健康：完美状态
        echo -e "${gl_lv}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"
        echo -e "${gl_lv}  ✅ DNS净化已完美配置，无需重复执行！${gl_bai}"
        echo -e "${gl_lv}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"
        echo ""
        echo -e "  当前模式:    ${gl_lv}${current_mode_name}${gl_bai}"
        echo -e "  resolved:    ${gl_lv}✅ 运行中${gl_bai}"
        echo -e "  resolv.conf: ${gl_lv}✅ 指向 stub（resolved 托管）${gl_bai}"
        echo -e "  开机持久化:  ${gl_lv}✅ dns-purify-persist 已启用（新版）${gl_bai}"
        echo -e "  DNS 解析:    ${gl_lv}✅ 正常${gl_bai}"
        echo ""
        echo -e "${gl_huang}提示：重启后 DNS 会自动恢复，无需担心${gl_bai}"
        echo ""
        if [ "$AUTO_MODE" = "1" ]; then
            return
        fi
        read -e -p "$(echo -e "${gl_huang}如需重新配置请输入 y，返回主菜单按回车: ${gl_bai}")" dns_reconfig
        if [[ ! "$dns_reconfig" =~ ^[Yy]$ ]]; then
            return
        fi
        echo ""
    fi

    # ==================== DNS模式选择 ====================
    echo -e "${gl_kjlan}请选择 DNS 配置模式：${gl_bai}"
    echo ""
    echo "  1. 🌍 纯国外模式（抗污染推荐）"
    echo "     首选：Google DNS + Cloudflare DNS"
    echo "     备用：无"
    echo "     加密：强制 DNS over TLS"
    echo ""
    echo "  2. 🇨🇳 纯国内模式（低延迟推荐）"
    echo "     首选：阿里云 DNS + 腾讯 DNSPod"
    echo "     备用：无"
    echo "     加密：无（国内DNS不支持DoT/DNSSEC）"
    echo ""
    if [ "$AUTO_MODE" = "1" ]; then
        dns_mode_choice=1
    else
        read -e -p "$(echo -e "${gl_huang}请选择 (1/2，默认1): ${gl_bai}")" dns_mode_choice
        dns_mode_choice=${dns_mode_choice:-1}
    fi

    # 验证输入
    if [[ ! "$dns_mode_choice" =~ ^[1-2]$ ]]; then
        dns_mode_choice=1
    fi

    echo ""

    if [ "$AUTO_MODE" = "1" ]; then
        confirm=y
    else
        read -e -p "$(echo -e "${gl_huang}是否继续执行？(y/n): ${gl_bai}")" confirm
    fi

    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo -e "${gl_huang}已取消操作${gl_bai}"
        return
    fi

    # ==================== 终极安全检查 ====================
    echo ""
    echo -e "${gl_kjlan}[安全检查] 正在验证系统环境...${gl_bai}"
    echo ""
    
    local pre_check_failed=false
    
    # 检查1: 磁盘空间（至少需要100MB）
    echo -n "  → 检查磁盘空间... "
    local available_space=$(df -m /etc | awk 'NR==2 {print $4}')
    if [ "$available_space" -lt 100 ]; then
        echo -e "${gl_hong}失败 (可用: ${available_space}MB, 需要: 100MB)${gl_bai}"
        pre_check_failed=true
    else
        echo -e "${gl_lv}通过 (可用: ${available_space}MB)${gl_bai}"
    fi
    
    # 检查2: 内存（至少需要50MB可用）
    echo -n "  → 检查可用内存... "
    local available_mem=$(free -m | awk 'NR==2 {print $7}')
    if [ "$available_mem" -lt 50 ]; then
        echo -e "${gl_hong}失败 (可用: ${available_mem}MB, 需要: 50MB)${gl_bai}"
        pre_check_failed=true
    else
        echo -e "${gl_lv}通过 (可用: ${available_mem}MB)${gl_bai}"
    fi
    
    # 检查3: systemd 是否正常工作
    echo -n "  → 检查 systemd 状态... "
    if ! systemctl --version > /dev/null 2>&1; then
        echo -e "${gl_hong}失败 (systemctl 命令无法执行)${gl_bai}"
        pre_check_failed=true
    else
        echo -e "${gl_lv}通过${gl_bai}"
    fi
    
    # 检查4: 是否有其他包管理器在运行
    echo -n "  → 检查包管理器锁... "
    if lsof /var/lib/dpkg/lock-frontend > /dev/null 2>&1 || \
       lsof /var/lib/apt/lists/lock > /dev/null 2>&1 || \
       lsof /var/cache/apt/archives/lock > /dev/null 2>&1; then
        echo -e "${gl_hong}失败 (其他包管理器正在运行)${gl_bai}"
        pre_check_failed=true
    else
        echo -e "${gl_lv}通过${gl_bai}"
    fi
    
    # 检查5: /run 目录是否可写
    echo -n "  → 检查 /run 目录权限... "
    if ! touch /run/.dns_test 2>/dev/null; then
        echo -e "${gl_hong}失败 (/run 目录不可写)${gl_bai}"
        pre_check_failed=true
    else
        rm -f /run/.dns_test
        echo -e "${gl_lv}通过${gl_bai}"
    fi
    
    # 检查6: 网络连通性（能否访问DNS服务器）
    echo -n "  → 检查网络连通性... "
    if ! ping -c 1 -W 2 8.8.8.8 > /dev/null 2>&1 && \
       ! ping -c 1 -W 2 1.1.1.1 > /dev/null 2>&1; then
        echo -e "${gl_huang}警告 (无法ping通DNS服务器，但继续执行)${gl_bai}"
    else
        echo -e "${gl_lv}通过${gl_bai}"
    fi
    
    echo ""
    
    # 如果有检查失败，拒绝执行
    if [ "$pre_check_failed" = true ]; then
        echo -e "${gl_hong}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"
        echo -e "${gl_hong}❌ 安全检查未通过！${gl_bai}"
        echo -e "${gl_hong}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"
        echo ""
        echo -e "${gl_huang}系统环境不满足安全执行条件，拒绝执行以避免风险。${gl_bai}"
        echo ""
        echo "请先解决上述问题，然后重试。"
        echo ""
        break_end
        return 1
    fi
    
    echo -e "${gl_lv}✅ 所有安全检查通过，可以安全执行${gl_bai}"
    echo ""

    # ==================== 创建备份 ====================
    command -v flock >/dev/null 2>&1 || { echo '缺少flock，DNS配置未继续。' >&2; return 1; }
    exec 208>/run/net-tcp-boot-repair.lock
    flock -n 208 || { exec 208>&-; echo '另一个启动恢复/DNS操作正在运行，DNS配置未继续。' >&2; return 1; }
    trap 'exec 208>&-' RETURN
    local BACKUP_DIR PRE_STATE_DIR
    mkdir -p /root/.dns_purify_backup || return 1
    BACKUP_DIR=$(mktemp -d "/root/.dns_purify_backup/$(date +%Y%m%d_%H%M%S).XXXXXXXX") || return 1
    PRE_STATE_DIR="$BACKUP_DIR/pre_state"
    mkdir -p "$PRE_STATE_DIR" || return 1
    echo ""
    echo -e "${gl_lv}✅ 创建备份目录：$BACKUP_DIR${gl_bai}"
    echo ""

    # 记录/恢复单个路径状态（文件、符号链接或不存在）
    backup_path_state() {
        local src="$1"
        local key="$2"
        if [[ -e "$src" || -L "$src" ]]; then
            cp -a "$src" "$PRE_STATE_DIR/$key" 2>/dev/null || true
        else
            : > "$PRE_STATE_DIR/$key.absent"
        fi
    }

    restore_path_state() {
        local dst="$1"
        local key="$2"
        rm -f "$dst" 2>/dev/null || true
        if [[ -e "$PRE_STATE_DIR/$key" || -L "$PRE_STATE_DIR/$key" ]]; then
            mkdir -p "$(dirname "$dst")"
            cp -a "$PRE_STATE_DIR/$key" "$dst" 2>/dev/null || true
        elif [[ -f "$PRE_STATE_DIR/$key.absent" ]]; then
            rm -f "$dst" 2>/dev/null || true
        fi
    }

    # 解析 DNS 地址中的 SNI 后缀（例如 1.1.1.1#cloudflare-dns.com -> 1.1.1.1）
    plain_dns_ip() {
        local dns_addr="$1"
        echo "${dns_addr%%#*}"
    }

    # 预先快照本次功能可能修改的关键文件
    backup_path_state "/etc/dhcp/dhclient.conf" "dhclient.conf"
    backup_path_state "/etc/network/interfaces" "interfaces"
    backup_path_state "/etc/systemd/resolved.conf" "resolved.conf"
    backup_path_state "/etc/resolv.conf" "resolv.conf"
    backup_path_state "/etc/systemd/system/dns-purify-persist.service" "dns-purify-persist.service"
    backup_path_state "/usr/local/bin/dns-purify-apply.sh" "dns-purify-apply.sh"
    backup_path_state "/etc/systemd/system/systemd-resolved.service.d/dbus-fix.conf" "dbus-fix.conf"
    backup_path_state "/etc/NetworkManager/conf.d/99-dns-purify.conf" "nm-99-dns-purify.conf"
    if ! boot_recovery_snapshot_dns_assets "$PRE_STATE_DIR"; then
        exec 208>&-
        echo '无法完整备份启动恢复组件，DNS配置未继续。' >&2
        return 1
    fi

    # 快照 if-up.d/resolved 执行权限状态
    local ifup_script="/etc/network/if-up.d/resolved"
    if [[ -e "$ifup_script" ]]; then
        if [[ -x "$ifup_script" ]]; then
            echo "executable" > "$PRE_STATE_DIR/ifup-resolved.exec"
        else
            echo "not_executable" > "$PRE_STATE_DIR/ifup-resolved.exec"
        fi
    else
        echo "absent" > "$PRE_STATE_DIR/ifup-resolved.exec"
    fi

    # 快照服务启用状态
    if systemctl is-enabled --quiet dns-purify-persist.service 2>/dev/null; then
        echo "true" > "$PRE_STATE_DIR/dns-persist.was-enabled"
    else
        echo "false" > "$PRE_STATE_DIR/dns-persist.was-enabled"
    fi

    # 用文本输出精确记录 enabled/static/disabled/masked 状态（is-enabled --quiet 对 static 也返回 0）
    local resolved_enable_state
    resolved_enable_state=$(systemctl is-enabled systemd-resolved 2>/dev/null || echo "unknown")
    echo "$resolved_enable_state" > "$PRE_STATE_DIR/resolved.enable-state"

    if [[ "$resolved_enable_state" == "masked" || "$resolved_enable_state" == "masked-runtime" ]]; then
        echo "true" > "$PRE_STATE_DIR/resolved.was-masked"
    else
        echo "false" > "$PRE_STATE_DIR/resolved.was-masked"
    fi

    if systemctl is-active --quiet systemd-resolved 2>/dev/null; then
        echo "true" > "$PRE_STATE_DIR/resolved.was-active"
    else
        echo "false" > "$PRE_STATE_DIR/resolved.was-active"
    fi

    # 快照 resolvconf 包状态（用于 Debian 11 回滚）
    if dpkg -s resolvconf >/dev/null 2>&1; then
        echo "true" > "$PRE_STATE_DIR/had-resolvconf.pkg"
    else
        echo "false" > "$PRE_STATE_DIR/had-resolvconf.pkg"
    fi

    local pre_dns_health="false"
    if command -v getent >/dev/null 2>&1; then
        if getent hosts google.com >/dev/null 2>&1 || getent hosts baidu.com >/dev/null 2>&1; then
            pre_dns_health="true"
        fi
    fi
    echo "$pre_dns_health" > "$PRE_STATE_DIR/pre-dns.health"

    # 快照现有 systemd-networkd DNS drop-in
    : > "$PRE_STATE_DIR/networkd-dropins.map"
    local existing_dropin
    for existing_dropin in /etc/systemd/network/*.network.d/dns-purify-override.conf; do
        [[ -f "$existing_dropin" ]] || continue
        local dropin_key="networkd-$(echo "$existing_dropin" | sed 's|/|__|g')"
        cp -a "$existing_dropin" "$PRE_STATE_DIR/$dropin_key" 2>/dev/null || true
        echo "$existing_dropin|$dropin_key" >> "$PRE_STATE_DIR/networkd-dropins.map"
    done

    # 退出函数时自动清理本函数内动态定义的 helper，避免影响其他功能
    trap 'exec 208>&-; unset -f backup_path_state restore_path_state plain_dns_ip auto_rollback_dns_purify dns_runtime_health_check can_connect_tcp >/dev/null 2>&1 || true' RETURN

    # 自动回滚函数（失败即恢复，避免遗留DNS隐患）
    auto_rollback_dns_purify() {
        bash "$PRE_STATE_DIR/boot-recovery-restore.sh" --lock-held || echo '启动恢复组件回滚未全部成功，请检查备份。' >&2
        # 恢复关键文件到执行前状态（注意：resolv.conf 延后恢复，避免悬空链接）
        restore_path_state "/etc/dhcp/dhclient.conf" "dhclient.conf"
        restore_path_state "/etc/network/interfaces" "interfaces"
        restore_path_state "/etc/systemd/resolved.conf" "resolved.conf"
        # resolv.conf 在服务状态恢复后再处理（见下方）
        restore_path_state "/etc/systemd/system/dns-purify-persist.service" "dns-purify-persist.service"
        restore_path_state "/usr/local/bin/dns-purify-apply.sh" "dns-purify-apply.sh"
        restore_path_state "/etc/systemd/system/systemd-resolved.service.d/dbus-fix.conf" "dbus-fix.conf"
        restore_path_state "/etc/NetworkManager/conf.d/99-dns-purify.conf" "nm-99-dns-purify.conf"

        # 恢复 if-up.d/resolved 执行权限
        if [[ -f "$PRE_STATE_DIR/ifup-resolved.exec" ]]; then
            case "$(cat "$PRE_STATE_DIR/ifup-resolved.exec" 2>/dev/null)" in
                executable)
                    [[ -e /etc/network/if-up.d/resolved ]] && chmod +x /etc/network/if-up.d/resolved 2>/dev/null || true
                    ;;
                not_executable)
                    [[ -e /etc/network/if-up.d/resolved ]] && chmod -x /etc/network/if-up.d/resolved 2>/dev/null || true
                    ;;
                absent)
                    rm -f /etc/network/if-up.d/resolved 2>/dev/null || true
                    ;;
            esac
        fi

        # 移除本次可能新增的 networkd drop-in（扩展搜索所有可能路径）
        local dropin_file search_dir
        for search_dir in /etc/systemd/network /run/systemd/network /usr/lib/systemd/network; do
            for dropin_file in "$search_dir"/*.network.d/dns-purify-override.conf; do
                [[ -f "$dropin_file" ]] || continue
                rm -f "$dropin_file"
                rmdir "$(dirname "$dropin_file")" 2>/dev/null || true
            done
        done

        # 恢复执行前已有的 networkd drop-in
        if [[ -f "$PRE_STATE_DIR/networkd-dropins.map" ]]; then
            local restore_path restore_key
            while IFS='|' read -r restore_path restore_key; do
                [[ -n "$restore_path" && -n "$restore_key" ]] || continue
                [[ -f "$PRE_STATE_DIR/$restore_key" ]] || continue
                mkdir -p "$(dirname "$restore_path")"
                cp -a "$PRE_STATE_DIR/$restore_key" "$restore_path" 2>/dev/null || true
            done < "$PRE_STATE_DIR/networkd-dropins.map"
        fi

        # 重载 systemd-networkd（使 drop-in 变更生效）
        if systemctl is-active --quiet systemd-networkd 2>/dev/null; then
            networkctl reload 2>/dev/null || systemctl reload systemd-networkd 2>/dev/null || true
        fi

        # 重载 NetworkManager（使配置文件变更生效）
        if systemctl is-active --quiet NetworkManager 2>/dev/null; then
            systemctl reload NetworkManager 2>/dev/null || true
        fi

        # 恢复 dns-purify 持久化服务启用状态
        local dns_persist_was_enabled="false"
        [[ -f "$PRE_STATE_DIR/dns-persist.was-enabled" ]] && dns_persist_was_enabled=$(cat "$PRE_STATE_DIR/dns-persist.was-enabled" 2>/dev/null || echo "false")

        systemctl daemon-reload 2>/dev/null || true
        if [[ -e "$PRE_STATE_DIR/dns-purify-persist.service" || -L "$PRE_STATE_DIR/dns-purify-persist.service" ]]; then
            if [[ "$dns_persist_was_enabled" == "true" ]]; then
                systemctl enable dns-purify-persist.service 2>/dev/null || true
            else
                systemctl disable dns-purify-persist.service 2>/dev/null || true
            fi
        else
            systemctl disable dns-purify-persist.service 2>/dev/null || true
        fi

        # 尝试恢复 resolvconf 包状态（Debian 11 场景）
        local had_resolvconf_pkg="false"
        [[ -f "$PRE_STATE_DIR/had-resolvconf.pkg" ]] && had_resolvconf_pkg=$(cat "$PRE_STATE_DIR/had-resolvconf.pkg" 2>/dev/null || echo "false")
        if [[ "$had_resolvconf_pkg" == "true" ]] && ! dpkg -s resolvconf >/dev/null 2>&1; then
            DEBIAN_FRONTEND=noninteractive apt-get install -y resolvconf >/dev/null 2>&1 || true
        fi

        # 恢复 systemd-resolved 启用/屏蔽/运行状态（在 resolv.conf 之前）
        local resolved_enable_state="unknown"
        local resolved_was_masked="false"
        local resolved_was_active="false"
        [[ -f "$PRE_STATE_DIR/resolved.enable-state" ]] && resolved_enable_state=$(cat "$PRE_STATE_DIR/resolved.enable-state" 2>/dev/null || echo "unknown")
        # 兼容旧版快照格式
        [[ "$resolved_enable_state" == "unknown" && -f "$PRE_STATE_DIR/resolved.was-enabled" ]] && {
            local old_enabled
            old_enabled=$(cat "$PRE_STATE_DIR/resolved.was-enabled" 2>/dev/null || echo "false")
            [[ "$old_enabled" == "true" ]] && resolved_enable_state="enabled" || resolved_enable_state="disabled"
        }
        [[ -f "$PRE_STATE_DIR/resolved.was-masked" ]] && resolved_was_masked=$(cat "$PRE_STATE_DIR/resolved.was-masked" 2>/dev/null || echo "false")
        [[ -f "$PRE_STATE_DIR/resolved.was-active" ]] && resolved_was_active=$(cat "$PRE_STATE_DIR/resolved.was-active" 2>/dev/null || echo "false")

        if [[ "$resolved_was_masked" == "true" ]]; then
            systemctl mask systemd-resolved 2>/dev/null || true
            systemctl stop systemd-resolved 2>/dev/null || true
        else
            systemctl unmask systemd-resolved 2>/dev/null || true
            case "$resolved_enable_state" in
                enabled|enabled-runtime)
                    systemctl enable systemd-resolved 2>/dev/null || true
                    ;;
                static|indirect|generated)
                    # static/indirect/generated 状态由包管理器控制，不改变
                    ;;
                *)
                    systemctl disable systemd-resolved 2>/dev/null || true
                    ;;
            esac

            if [[ "$resolved_was_active" == "true" ]]; then
                systemctl restart systemd-resolved 2>/dev/null || systemctl start systemd-resolved 2>/dev/null || true
                # 等待 resolved 完全启动，确保 stub 文件可用
                local wait_i
                for wait_i in $(seq 1 5); do
                    [[ -f /run/systemd/resolve/stub-resolv.conf ]] && break
                    sleep 1
                done
            else
                systemctl stop systemd-resolved 2>/dev/null || true
            fi
        fi

        # 最后恢复 resolv.conf（此时 resolved 已恢复运行状态，stub 文件可用）
        # 特殊处理：如果备份是指向 stub 的软链接但 resolved 未运行，则写静态文件
        if [[ -L "$PRE_STATE_DIR/resolv.conf" ]]; then
            local backup_link_target
            backup_link_target=$(readlink "$PRE_STATE_DIR/resolv.conf" 2>/dev/null || echo "")
            if [[ "$backup_link_target" == *"stub-resolv.conf"* ]] && [[ ! -f /run/systemd/resolve/stub-resolv.conf ]]; then
                # resolved 未运行，stub 不存在 — 写入静态 nameserver 避免悬空链接
                rm -f /etc/resolv.conf 2>/dev/null || true
                echo "nameserver 127.0.0.53" > /etc/resolv.conf 2>/dev/null || true
            else
                restore_path_state "/etc/resolv.conf" "resolv.conf"
            fi
        else
            restore_path_state "/etc/resolv.conf" "resolv.conf"
        fi

        # 回滚后验证 — 充分等待 resolved 初始化（最多15秒，每3秒重试）
        local rollback_ok=false
        local pre_dns_health="false"
        [[ -f "$PRE_STATE_DIR/pre-dns.health" ]] && pre_dns_health=$(cat "$PRE_STATE_DIR/pre-dns.health" 2>/dev/null || echo "false")

        local max_wait=5
        for i in $(seq 1 $max_wait); do
            if dns_runtime_health_check "global" || dns_runtime_health_check "cn"; then
                rollback_ok=true
                break
            fi
            sleep 3
        done

        if [ "$rollback_ok" = true ]; then
            echo -e "${gl_lv}  ✅ 回滚后DNS健康校验通过${gl_bai}"
        elif [ "$pre_dns_health" = "true" ]; then
            echo -e "${gl_huang}  ⚠️  回滚后DNS验证超时，但已恢复执行前配置，可能需要等待网络就绪${gl_bai}"
        else
            echo -e "${gl_huang}  ⚠️  执行前DNS即不可用，已恢复原始配置${gl_bai}"
        fi
    }

    # DNS运行时健康检查（多域名，多方法）
    dns_runtime_health_check() {
        local check_mode="${1:-global}"
        local domains=()
        if [[ "$check_mode" == "cn" ]]; then
            domains=("baidu.com" "qq.com" "aliyun.com")
        else
            domains=("google.com" "cloudflare.com" "github.com" "baidu.com")
        fi

        if command -v getent >/dev/null 2>&1; then
            local domain
            for domain in "${domains[@]}"; do
                if getent hosts "$domain" >/dev/null 2>&1; then
                    return 0
                fi
            done
        fi

        if command -v nslookup >/dev/null 2>&1; then
            local domain
            for domain in "${domains[@]}"; do
                if nslookup "$domain" >/dev/null 2>&1; then
                    return 0
                fi
            done
        fi

        local domain
        for domain in "${domains[@]}"; do
            if ping -c 1 -W 2 "$domain" >/dev/null 2>&1; then
                return 0
            fi
        done

        return 1
    }

    # TCP端口探测（用于DoT 853预检）
    can_connect_tcp() {
        local host="$1"
        local port="$2"
        if command -v timeout >/dev/null 2>&1; then
            timeout 3 bash -c "exec 3<>/dev/tcp/${host}/${port} && exec 3>&-" >/dev/null 2>&1
        else
            bash -c "exec 3<>/dev/tcp/${host}/${port} && exec 3>&-" >/dev/null 2>&1
        fi
    }

    # 目标DNS配置（根据用户选择的模式）
    local TARGET_DNS=""
    local FALLBACK_DNS=""
    local DNS_OVER_TLS=""
    local DNSSEC_MODE=""
    local MODE_NAME=""
    # 网卡级 DNS（用于 resolvectl）
    local INTERFACE_DNS_PRIMARY=""
    local INTERFACE_DNS_SECONDARY=""
    case "$dns_mode_choice" in
        1)
            # 纯国外模式
            TARGET_DNS="8.8.8.8#dns.google 1.1.1.1#cloudflare-dns.com"
            FALLBACK_DNS=""
            DNS_OVER_TLS="yes"
            DNSSEC_MODE="no"
            MODE_NAME="纯国外模式"
            # 网卡级使用纯IP，避免个别systemd/resolvectl版本对SNI参数兼容问题
            INTERFACE_DNS_PRIMARY="8.8.8.8"
            INTERFACE_DNS_SECONDARY="1.1.1.1"
            ;;
        2)
            # 纯国内模式（国内DNS和国内域名大多不支持DNSSEC，必须禁用）
            TARGET_DNS="223.5.5.5 119.29.29.29"
            FALLBACK_DNS=""
            DNS_OVER_TLS="no"
            DNSSEC_MODE="no"
            MODE_NAME="纯国内模式"
            INTERFACE_DNS_PRIMARY="223.5.5.5"
            INTERFACE_DNS_SECONDARY="119.29.29.29"
            ;;
    esac

    # strict DoT 预检：若目标机房到853不可达，直接中止（不自动降级）
    if [[ "$dns_mode_choice" == "1" ]]; then
        local dot_reachable_count=0
        can_connect_tcp "8.8.8.8" 853 && dot_reachable_count=$((dot_reachable_count + 1))
        can_connect_tcp "1.1.1.1" 853 && dot_reachable_count=$((dot_reachable_count + 1))

        if [[ "$dot_reachable_count" -eq 0 ]]; then
            echo -e "${gl_hong}❌ 预检失败：当前机房无法连通 DoT(853)，已终止执行（未做任何修改）${gl_bai}"
            echo -e "${gl_huang}建议：改用模式2，或放开到 8.8.8.8/1.1.1.1 的 853 出口后再执行模式1${gl_bai}"
            break_end
            return 1
        fi
    fi
    
    echo -e "${gl_lv}已选择：${MODE_NAME}${gl_bai}"
    echo ""
    
    # 构建配置（动态拼接，避免 FallbackDNS 为空时产生空行）
    local SECURE_RESOLVED_CONFIG="[Resolve]
DNS=${TARGET_DNS}"
    if [[ -n "$FALLBACK_DNS" ]]; then
        SECURE_RESOLVED_CONFIG="${SECURE_RESOLVED_CONFIG}
FallbackDNS=${FALLBACK_DNS}"
    fi
    SECURE_RESOLVED_CONFIG="${SECURE_RESOLVED_CONFIG}
LLMNR=no
MulticastDNS=no
DNSSEC=${DNSSEC_MODE}
DNSOverTLS=${DNS_OVER_TLS}
Cache=yes
DNSStubListener=yes
"

    echo "--- 开始执行DNS净化与安全加固流程 ---"
    echo ""

    local debian_version
    debian_version=$(grep "VERSION_ID" /etc/os-release | cut -d'=' -f2 | tr -d '"' || echo "unknown")

    # Only an exact, known legacy template is removed; customized files abort safely.
    if ! boot_recovery_install_assets ||
        ! /usr/local/libexec/net-tcp-boot-recovery --migrate-resolved ||
        ! systemctl daemon-reload; then
        echo -e "${gl_hong}❌ DNS依赖迁移失败，请检查自定义drop-in${gl_bai}"
        return 1
    fi

    # ==================== 阶段一：清除DNS冲突源 ====================
    echo -e "${gl_kjlan}[阶段 1/5] 清除DNS冲突源（安全操作）...${gl_bai}"
    echo ""

    # 1. 驯服 DHCP 客户端
    local dhclient_conf="/etc/dhcp/dhclient.conf"
    if [[ -f "$dhclient_conf" ]]; then
        # 备份
        cp "$dhclient_conf" "$BACKUP_DIR/dhclient.conf.bak" 2>/dev/null || true
        
        local dhclient_changed=false
        if ! grep -q "ignore domain-name-servers;" "$dhclient_conf"; then
            echo "" >> "$dhclient_conf"
            echo "# 由DNS净化脚本添加 - $(date)" >> "$dhclient_conf"
            echo "ignore domain-name-servers;" >> "$dhclient_conf"
            dhclient_changed=true
        fi
        if ! grep -q "ignore domain-search;" "$dhclient_conf"; then
            if [ "$dhclient_changed" = false ]; then
                echo "" >> "$dhclient_conf"
                echo "# 由DNS净化脚本添加 - $(date)" >> "$dhclient_conf"
            fi
            echo "ignore domain-search;" >> "$dhclient_conf"
            dhclient_changed=true
        fi
        if [ "$dhclient_changed" = true ]; then
            echo "  → 配置 dhclient 忽略DHCP提供的DNS..."
            echo -e "${gl_lv}  ✅ dhclient 配置完成${gl_bai}"
        else
            echo -e "${gl_lv}  ✅ dhclient 已配置（跳过）${gl_bai}"
        fi
    fi

    # 2. 禁用冲突的 if-up.d 脚本
    local ifup_script="/etc/network/if-up.d/resolved"
    if [[ -f "$ifup_script" ]] && [[ -x "$ifup_script" ]]; then
        echo "  → 禁用 if-up.d/resolved 脚本..."
        chmod -x "$ifup_script"
        echo -e "${gl_lv}  ✅ 已移除可执行权限${gl_bai}"
    fi

    # 3. 注释 /etc/network/interfaces 中的DNS配置
    local interfaces_file="/etc/network/interfaces"
    if [[ -f "$interfaces_file" ]]; then
        # 备份
        cp "$interfaces_file" "$BACKUP_DIR/interfaces.bak" 2>/dev/null || true
        
        if grep -qE '^[[:space:]]*dns-(nameservers|search|domain)' "$interfaces_file"; then
            echo "  → 清除 /etc/network/interfaces 中的DNS配置..."
            sed -i.bak -E 's/^([[:space:]]*dns-(nameservers|search|domain).*)/# \1 # 已被DNS净化脚本禁用/' "$interfaces_file"
            echo -e "${gl_lv}  ✅ 厂商DNS配置已注释${gl_bai}"
        else
            echo -e "${gl_lv}  ✅ /etc/network/interfaces 无DNS配置${gl_bai}"
        fi
    fi

    echo ""

    # ==================== 阶段二：配置 systemd-resolved ====================
    echo -e "${gl_kjlan}[阶段 2/5] 配置 systemd-resolved...${gl_bai}"
    echo ""

    # 检查是否已安装
    if ! command -v resolvectl &> /dev/null; then
        echo "  → 检测到未安装 systemd-resolved"
        echo "  → 安装 systemd-resolved..."
        apt-get update -y > /dev/null 2>&1
        DEBIAN_FRONTEND=noninteractive apt-get install -y systemd-resolved > /dev/null 2>&1
        echo -e "${gl_lv}  ✅ systemd-resolved 安装完成${gl_bai}"
    else
        echo -e "${gl_lv}  ✅ systemd-resolved 已安装${gl_bai}"
    fi

    # 处理 Debian 11 的 resolvconf 冲突
    if [[ "$debian_version" == "11" ]] && dpkg -s resolvconf &> /dev/null; then
        echo "  → 检测到 Debian 11 的 resolvconf 冲突"
        
        # 🛡️ 关键修复：在卸载前确保 systemd-resolved 完全就绪
        # 先启动 systemd-resolved
        echo "  → 启动 systemd-resolved（在卸载 resolvconf 之前）..."
        systemctl enable systemd-resolved 2>/dev/null || true
        systemctl start systemd-resolved 2>/dev/null || true
        
        # 等待服务启动
        sleep 2
        
        # 验证 systemd-resolved 正在运行
        if ! systemctl is-active --quiet systemd-resolved; then
            echo -e "${gl_hong}❌ 无法启动 systemd-resolved，中止操作${gl_bai}"
            auto_rollback_dns_purify
            break_end
            return 1
        fi
        
        # 验证 stub-resolv.conf 存在
        if [[ ! -f /run/systemd/resolve/stub-resolv.conf ]]; then
            echo -e "${gl_hong}❌ systemd-resolved stub 文件不存在，中止操作${gl_bai}"
            auto_rollback_dns_purify
            break_end
            return 1
        fi
        
        # 现在可以安全地卸载 resolvconf
        # 备份当前 resolv.conf
        [[ -f /etc/resolv.conf ]] && cp /etc/resolv.conf "$BACKUP_DIR/resolv.conf.pre_remove" 2>/dev/null || true
        
        # 创建临时DNS配置（避免卸载期间DNS中断）
        echo "nameserver $(plain_dns_ip "$INTERFACE_DNS_PRIMARY")" > /etc/resolv.conf.tmp
        echo "nameserver $(plain_dns_ip "$INTERFACE_DNS_SECONDARY")" >> /etc/resolv.conf.tmp
        
        # 使用临时DNS配置
        mv /etc/resolv.conf /etc/resolv.conf.old 2>/dev/null || true
        cp /etc/resolv.conf.tmp /etc/resolv.conf
        
        # 卸载 resolvconf
        echo "  → 卸载 resolvconf..."
        DEBIAN_FRONTEND=noninteractive apt-get remove -y resolvconf > /dev/null 2>&1
        
        # 清理临时文件
        rm -f /etc/resolv.conf.tmp /etc/resolv.conf.old
        
        echo -e "${gl_lv}  ✅ resolvconf 已安全卸载${gl_bai}"
    fi

    # 🔧 调用智能修复函数
    if ! dns_purify_fix_systemd_resolved; then
        echo -e "${gl_hong}❌ 无法修复 systemd-resolved 服务，脚本终止${gl_bai}"
        echo "检测到修复失败，正在自动回滚到执行前状态"
        auto_rollback_dns_purify
        break_end
        return 1
    fi

    # 备份并写入配置
    if [[ -f /etc/systemd/resolved.conf ]]; then
        cp /etc/systemd/resolved.conf "$BACKUP_DIR/resolved.conf.bak" 2>/dev/null || true
    fi

    echo "  → 配置 systemd-resolved..."
    echo -e "${SECURE_RESOLVED_CONFIG}" > /etc/systemd/resolved.conf
    
    echo ""

    # ==================== 阶段三：应用DNS配置（SSH安全方式）====================
    echo -e "${gl_kjlan}[阶段 3/5] 应用DNS配置（SSH安全模式）...${gl_bai}"
    echo ""

    # 先重新加载 systemd-resolved 配置
    echo "  → 重新加载 systemd-resolved 配置..."
    if ! systemctl reload-or-restart systemd-resolved; then
        echo -e "${gl_hong}❌ systemd-resolved 重启失败！${gl_bai}"
        echo "正在自动回滚配置..."
        auto_rollback_dns_purify
        break_end
        return 1
    fi
    
    # 等待服务完全启动
    echo "  → 等待 systemd-resolved 完全启动..."
    sleep 3
    
    # 验证服务状态
    if ! systemctl is-active --quiet systemd-resolved; then
        echo -e "${gl_hong}❌ systemd-resolved 未能正常运行！${gl_bai}"
        echo "正在自动回滚配置..."
        auto_rollback_dns_purify
        break_end
        return 1
    fi
    
    # 验证 stub-resolv.conf 文件存在
    if [[ ! -f /run/systemd/resolve/stub-resolv.conf ]]; then
        echo -e "${gl_hong}❌ systemd-resolved stub 文件不存在！${gl_bai}"
        echo "路径: /run/systemd/resolve/stub-resolv.conf"
        echo "正在自动回滚配置..."
        auto_rollback_dns_purify
        break_end
        return 1
    fi
    
    echo -e "${gl_lv}  ✅ systemd-resolved 配置已重新加载并验证${gl_bai}"

    # 🔧 确保服务开机自启动（修复 #11：某些 Debian 版本服务状态为 static 时不会自启）
    echo "  → 确保 systemd-resolved 开机自启动..."
    systemctl enable systemd-resolved >/dev/null 2>&1 || true
    echo -e "${gl_lv}  ✅ 已设置开机自启动${gl_bai}"

    # 🔒 检测 immutable 属性（云服务商保护机制）
    if [[ -e /etc/resolv.conf ]] && lsattr /etc/resolv.conf 2>/dev/null | grep -q 'i'; then
        echo ""
        echo -e "${gl_hong}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"
        echo -e "${gl_hong}⚠️  检测到 /etc/resolv.conf 被锁定保护${gl_bai}"
        echo -e "${gl_hong}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"
        echo ""
        echo "原因：您的服务器设置了不可变属性（通常是云服务商的保护机制）"
        echo ""
        echo "风险：强制修改可能导致机器失联或网络异常"
        echo ""
        echo "建议：如非必要，不建议继续修改"
        echo "      能正常执行的系统不会弹出此提示"
        echo ""
        echo -e "${gl_huang}状态：检测到锁定保护，正在恢复已修改的配置${gl_bai}"
        # 只回滚 resolved.conf（阶段二已修改），不做完整回滚
        # resolv.conf 尚未被修改（软链接替换在此检查之后），无需恢复
        restore_path_state "/etc/systemd/resolved.conf" "resolved.conf"
        systemctl reload-or-restart systemd-resolved 2>/dev/null || true
        echo ""
        break_end
        return 1
    fi
    
    # 🛡️ 关键修复：安全地创建 resolv.conf 链接
    # 备份并创建 resolv.conf 链接（只有在验证通过后才执行）
    if [[ -e /etc/resolv.conf ]] && [[ ! -L /etc/resolv.conf ]]; then
        # 如果是普通文件，备份它
        cp /etc/resolv.conf "$BACKUP_DIR/resolv.conf.bak" 2>/dev/null || true
    fi
    
    # 安全地创建链接
    rm -f /etc/resolv.conf
    ln -s /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
    
    # 验证链接创建成功
    if [[ ! -L /etc/resolv.conf ]] || [[ ! -e /etc/resolv.conf ]]; then
        echo -e "${gl_hong}❌ resolv.conf 链接创建失败！${gl_bai}"
        echo "正在自动回滚原始配置..."
        auto_rollback_dns_purify
        break_end
        return 1
    fi
    
    echo -e "${gl_lv}  ✅ resolv.conf 链接已安全创建${gl_bai}"
    
    # 🚫 完全移除 networking.service 重启（即使非SSH模式也危险）
    # 注意：不管是SSH还是本地连接，都不重启 networking.service
    # 因为重启网络服务在生产环境中极其危险
    echo -e "${gl_lv}  ✅ 网络服务未受影响（安全模式）${gl_bai}"

    echo ""
    
    # ==================== Debian 13特殊修复：D-Bus接口注册问题 ====================
    echo -e "${gl_kjlan}[特殊修复] 检测并修复 D-Bus 接口注册（Debian 13兼容）...${gl_bai}"
    echo ""
    
    # 检测是否需要修复D-Bus接口
    local need_dbus_fix=false
    # debian_version 已在阶段二前定义，此处直接使用

    echo "  → 检测系统版本：Debian ${debian_version:-未知}"
    
    # 检查resolvectl是否能正常通信
    echo "  → 测试 resolvectl 命令响应..."
    if ! timeout 3 resolvectl status >/dev/null 2>&1; then
        echo -e "${gl_huang}  ⚠️  resolvectl 命令无响应，需要修复 D-Bus 接口${gl_bai}"
        need_dbus_fix=true
    else
        echo -e "${gl_lv}  ✅ resolvectl 响应正常${gl_bai}"
    fi
    
    # 如果需要修复D-Bus接口
    if [ "$need_dbus_fix" = true ]; then
        echo ""
        echo -e "${gl_huang}检测到 D-Bus 接口注册问题（Debian 13已知问题），正在自动修复...${gl_bai}"
        echo ""
        
        # 🛡️ 安全措施：在重启前创建临时DNS配置，确保DNS始终可用
        echo "  → 创建临时DNS配置（防止修复期间DNS中断）..."
        
        # 备份当前resolv.conf
        if [[ -e /etc/resolv.conf ]]; then
            cp /etc/resolv.conf "$BACKUP_DIR/resolv.conf.before_dbus_fix" 2>/dev/null || true
        fi
        
        # 创建临时DNS配置文件
        cat > /etc/resolv.conf.dbus_fix_temp << TEMP_DNS
# 临时DNS配置（D-Bus修复期间使用）
nameserver $INTERFACE_DNS_PRIMARY
nameserver $INTERFACE_DNS_SECONDARY
TEMP_DNS
        
        # 使用临时DNS配置
        rm -f /etc/resolv.conf
        cp /etc/resolv.conf.dbus_fix_temp /etc/resolv.conf
        chmod 644 /etc/resolv.conf
        
        echo -e "${gl_lv}  ✅ 临时DNS配置已创建（确保修复期间DNS可用）${gl_bai}"
        
        # 1. 完全重启systemd-resolved，让它重新注册D-Bus接口
        echo "  → 重启 systemd-resolved 以重新注册 D-Bus 接口..."
        systemctl stop systemd-resolved 2>/dev/null || true
        sleep 2
        systemctl start systemd-resolved 2>/dev/null || true
        sleep 3
        
        # 🛡️ 恢复到 stub-resolv.conf 链接
        echo "  → 恢复 resolv.conf 链接到 stub-resolv.conf..."
        
        # 验证 stub-resolv.conf 存在
        if [[ -f /run/systemd/resolve/stub-resolv.conf ]]; then
            rm -f /etc/resolv.conf
            ln -s /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
            echo -e "${gl_lv}  ✅ resolv.conf 链接已恢复${gl_bai}"
        else
            echo -e "${gl_huang}  ⚠️  stub-resolv.conf 不存在，保持临时DNS配置${gl_bai}"
        fi
        
        # 清理临时文件
        rm -f /etc/resolv.conf.dbus_fix_temp
        
        # 2. 验证D-Bus接口是否注册成功
        if command -v busctl &>/dev/null; then
            local dbus_status=$(busctl list 2>/dev/null | grep "org.freedesktop.resolve1" | grep -v "activatable" || echo "")
            if [ -n "$dbus_status" ]; then
                echo -e "${gl_lv}  ✅ D-Bus 接口已成功注册${gl_bai}"
                
                # resolved participates in early boot before sysinit; ordering it after
                # dbus creates resolved -> sysinit -> dbus -> resolved. Never write that drop-in.
                echo "  → 使用发行版原生 D-Bus 依赖，不创建额外启动依赖"

                # 4. 再次测试resolvectl
                if timeout 3 resolvectl status >/dev/null 2>&1; then
                    echo -e "${gl_lv}  ✅ resolvectl 现在能正常工作了${gl_bai}"
                else
                    echo -e "${gl_huang}  ⚠️  resolvectl 仍无响应（但DNS配置已通过resolved.conf生效）${gl_bai}"
                fi
            else
                echo -e "${gl_huang}  ⚠️  D-Bus 接口注册可能失败${gl_bai}"
                echo -e "${gl_lv}  ✅ 但DNS配置已通过 /etc/systemd/resolved.conf 生效${gl_bai}"
            fi
        else
            echo -e "${gl_huang}  ⚠️  busctl 命令不可用，无法验证 D-Bus 状态${gl_bai}"
            echo -e "${gl_lv}  ✅ 但DNS配置已通过 /etc/systemd/resolved.conf 生效${gl_bai}"
        fi
        
        echo ""
    fi

    echo ""

    # ==================== 阶段四：配置网卡DNS ====================
    echo -e "${gl_kjlan}[阶段 4/5] 配置网卡DNS（立即生效）...${gl_bai}"
    echo ""
    
    # 🔥 强力保障：阶段4执行前二次验证resolvectl（确保100%成功）
    echo "  → 验证 resolvectl 命令状态..."
    local resolvectl_ready=true
    
    # 快速测试resolvectl是否响应（2秒超时）
    if ! timeout 2 resolvectl status >/dev/null 2>&1; then
        echo -e "${gl_huang}  ⚠️  resolvectl 仍无响应${gl_bai}"
        echo ""
        echo -e "${gl_huang}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"
        echo -e "${gl_huang}检测到 resolvectl 命令无法正常工作${gl_bai}"
        echo -e "${gl_huang}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"
        echo ""
        echo "这可能导致阶段4的网卡级DNS配置失败。"
        echo ""
        echo "你可以选择："
        echo "  1) 尝试强制修复（会重启systemd-resolved，有临时DNS保护）"
        echo "  2) 跳过网卡配置（安全，全局DNS已生效，推荐）"
        echo ""
        if [ "$AUTO_MODE" = "1" ]; then
            force_fix_choice=2
        else
            read -e -p "$(echo -e "${gl_huang}请选择 (1/2，默认2): ${gl_bai}")" force_fix_choice
            force_fix_choice=${force_fix_choice:-2}
        fi
        
        if [[ "$force_fix_choice" == "1" ]]; then
            echo ""
            echo -e "${gl_kjlan}正在执行强制修复...${gl_bai}"
            resolvectl_ready=false
            
            # 强制修复：重启systemd-resolved重新注册D-Bus
            echo "  → 创建临时DNS保护..."
            
            # 创建临时DNS保护
            cat > /etc/resolv.conf.stage4_temp << STAGE4_TEMP
nameserver $(plain_dns_ip "$INTERFACE_DNS_PRIMARY")
nameserver $(plain_dns_ip "$INTERFACE_DNS_SECONDARY")
STAGE4_TEMP
            cp /etc/resolv.conf /etc/resolv.conf.stage4_backup 2>/dev/null || true
            cp /etc/resolv.conf.stage4_temp /etc/resolv.conf
            
            echo "  → 强制重启 systemd-resolved..."
            # 完全重启服务
            systemctl stop systemd-resolved 2>/dev/null || true
            sleep 2
            systemctl start systemd-resolved 2>/dev/null || true
            sleep 3
            
            # 恢复链接
            echo "  → 恢复 resolv.conf 链接..."
            if [[ -f /run/systemd/resolve/stub-resolv.conf ]]; then
                rm -f /etc/resolv.conf
                ln -s /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
            fi
            
            # 清理临时文件
            rm -f /etc/resolv.conf.stage4_temp /etc/resolv.conf.stage4_backup
            
            # 再次验证
            echo "  → 验证修复结果..."
            if timeout 2 resolvectl status >/dev/null 2>&1; then
                echo -e "${gl_lv}  ✅ resolvectl 已修复，可以继续${gl_bai}"
                resolvectl_ready=true
            else
                echo -e "${gl_huang}  ⚠️  resolvectl 仍无法正常工作${gl_bai}"
                echo -e "${gl_lv}  ✅ 将跳过网卡级DNS配置（全局DNS已生效）${gl_bai}"
                resolvectl_ready=false
            fi
            echo ""
        else
            echo ""
            echo -e "${gl_lv}已选择跳过强制修复（安全选择）${gl_bai}"
            echo -e "${gl_lv}将跳过网卡级DNS配置，全局DNS配置已生效${gl_bai}"
            resolvectl_ready=false
            echo ""
        fi
    else
        echo -e "${gl_lv}  ✅ resolvectl 响应正常${gl_bai}"
    fi
    
    echo ""

    # 检测主网卡
    local main_interface=$(ip route | grep '^default' | awk '{print $5}' | head -n1)

    if [[ -n "$main_interface" ]] && command -v resolvectl &> /dev/null && [ "$resolvectl_ready" = true ]; then
        echo "  → 检测到主网卡: ${main_interface}"
        
        # 🛡️ 关键修复：检查timeout命令是否可用
        if ! command -v timeout &> /dev/null; then
            echo -e "${gl_huang}  ⚠️  timeout命令不可用，跳过网卡级DNS配置${gl_bai}"
            echo -e "${gl_lv}  ✅ DNS配置已通过 /etc/systemd/resolved.conf 生效${gl_bai}"
        else
            echo "  → 配置网卡 DNS（立即生效，无需重启）..."
            echo ""
            
            # 🛡️ 修复：添加超时机制防止resolvectl命令hang住
            local resolvectl_timeout=5  # 5秒超时
            local dns_config_success=true
            
            echo "    正在应用DNS服务器配置..."
            if timeout "$resolvectl_timeout" resolvectl dns "$main_interface" "$INTERFACE_DNS_PRIMARY" "$INTERFACE_DNS_SECONDARY" 2>/dev/null; then
                echo -e "    ${gl_lv}✅ DNS服务器配置成功${gl_bai}"
            else
                echo -e "    ${gl_huang}⚠️  DNS服务器配置超时或失败（配置已通过resolved.conf生效）${gl_bai}"
                dns_config_success=false
            fi
            
            echo "    正在应用DNS域配置..."
            if timeout "$resolvectl_timeout" resolvectl domain "$main_interface" ~. 2>/dev/null; then
                echo -e "    ${gl_lv}✅ DNS域配置成功${gl_bai}"
            else
                echo -e "    ${gl_huang}⚠️  DNS域配置超时或失败（配置已通过resolved.conf生效）${gl_bai}"
                dns_config_success=false
            fi
            
            echo "    正在应用默认路由配置..."
            if timeout "$resolvectl_timeout" resolvectl default-route "$main_interface" yes 2>/dev/null; then
                echo -e "    ${gl_lv}✅ 默认路由配置成功${gl_bai}"
            else
                echo -e "    ${gl_huang}⚠️  默认路由配置超时或失败（配置已通过resolved.conf生效）${gl_bai}"
                dns_config_success=false
            fi
            
            echo ""
            if [ "$dns_config_success" = true ]; then
                echo -e "${gl_lv}  ✅ 网卡DNS配置已全部应用${gl_bai}"
            else
                echo -e "${gl_huang}  ⚠️  部分网卡DNS配置未能通过resolvectl应用${gl_bai}"
                echo -e "${gl_lv}  ✅ 但DNS配置已通过 /etc/systemd/resolved.conf 生效${gl_bai}"
            fi
        fi
        echo -e "${gl_lv}  ✅ DNS配置立即生效，无需重启${gl_bai}"
    else
        if [[ -z "$main_interface" ]]; then
            echo -e "${gl_huang}  ⚠️  未检测到默认网卡${gl_bai}"
        else
            echo -e "${gl_huang}  ⚠️  resolvectl 命令不可用${gl_bai}"
        fi
        echo -e "${gl_lv}  ✅ DNS配置已通过 /etc/systemd/resolved.conf 生效${gl_bai}"
    fi

    # ==================== 阶段4.5：持久化前健康检查 ====================
    echo ""
    echo -e "${gl_kjlan}[阶段 4.5/5] 持久化前DNS健康检查...${gl_bai}"
    echo ""
    local precheck_dns_ok=false
    if [[ "$dns_mode_choice" == "2" ]]; then
        if dns_runtime_health_check "cn"; then
            precheck_dns_ok=true
        fi
    else
        if dns_runtime_health_check "global"; then
            precheck_dns_ok=true
        fi
    fi

    # strict 模式下绝不自动降级：解析失败立即回滚并退出
    if [ "$precheck_dns_ok" = false ] && [ "$DNS_OVER_TLS" = "yes" ]; then
        echo -e "${gl_hong}❌ strict DoT 健康检查失败，按严格策略中止并回滚（不降级）${gl_bai}"
        auto_rollback_dns_purify
        break_end
        return 1
    fi

    if [ "$precheck_dns_ok" = false ]; then
        echo -e "${gl_hong}❌ 持久化前DNS健康检查失败，正在自动回滚本次配置${gl_bai}"
        auto_rollback_dns_purify
        echo -e "${gl_huang}已自动回滚，请检查机房网络对上游DNS/DoT(853)连通性后重试${gl_bai}"
        break_end
        return 1
    else
        echo -e "${gl_lv}✅ 持久化前DNS健康检查通过${gl_bai}"
    fi

    # ==================== 阶段五：配置重启持久化 ====================
    echo ""
    echo -e "${gl_kjlan}[阶段 5/5] 配置重启持久化（确保重启后DNS不失效）...${gl_bai}"
    echo ""

    # Self-contained helper validates DNS, reports failure and lets systemd retry.
    if ! boot_recovery_install_assets ||
        ! /usr/local/libexec/net-tcp-boot-recovery --migrate-resolved ||
        ! boot_recovery_write_dns_service "$INTERFACE_DNS_PRIMARY" "$INTERFACE_DNS_SECONDARY" ||
        ! systemctl daemon-reload ||
        ! systemctl enable dns-purify-persist.service ||
        ! systemctl enable --now net-tcp-boot-watch.timer; then
        echo -e "${gl_hong}❌ DNS启动恢复配置失败，正在回滚DNS配置${gl_bai}"
        auto_rollback_dns_purify
        return 1
    fi

    # --- 5c: 阻止 systemd-networkd DHCP 覆盖DNS（最常见的重启失效原因）---
    if systemctl is-active --quiet systemd-networkd 2>/dev/null; then
        echo "  → 检测到 systemd-networkd，配置 DHCP DNS 阻断..."

        # 查找当前网卡对应的 .network 配置文件
        local networkd_file=""
        if command -v networkctl &>/dev/null; then
            networkd_file=$(networkctl status "$main_interface" 2>/dev/null | sed -nE 's/.*Network File:[[:space:]]*(.*)/\1/p' | head -1)
        fi

        if [[ -n "$networkd_file" ]] && [[ -f "$networkd_file" ]]; then
            # 安全方式：创建 drop-in 覆盖，不修改原文件
            local dropin_dir="${networkd_file}.d"
            mkdir -p "$dropin_dir"
            cat > "$dropin_dir/dns-purify-override.conf" << 'NETWORKD_DROPIN'
# DNS净化脚本 - 阻止DHCP覆盖DNS配置
# 仅禁用DHCP下发的DNS，不影响IP地址等其他DHCP功能
[DHCP]
UseDNS=false
UseDomains=false
NETWORKD_DROPIN
            echo -e "${gl_lv}  ✅ systemd-networkd DHCP DNS 阻断已配置（drop-in: ${dropin_dir}/）${gl_bai}"
            echo -e "${gl_lv}     仅阻止DNS覆盖，不影响IP/网关等DHCP功能${gl_bai}"
        else
            # 没找到现有配置文件，创建通用的 drop-in 目录
            echo -e "${gl_huang}  ⚠️  未找到 ${main_interface} 的 .network 文件${gl_bai}"
            echo -e "${gl_lv}  ✅ 已通过开机服务保障重启后DNS恢复${gl_bai}"
        fi
    else
        echo -e "${gl_lv}  ✅ 未使用 systemd-networkd（无需额外配置）${gl_bai}"
    fi

    # --- 5d: 处理 NetworkManager（如果存在）---
    if systemctl is-active --quiet NetworkManager 2>/dev/null; then
        echo "  → 检测到 NetworkManager，配置DNS保护..."
        mkdir -p /etc/NetworkManager/conf.d
        cat > /etc/NetworkManager/conf.d/99-dns-purify.conf << 'NM_CONF'
# DNS净化脚本 - 让 NetworkManager 使用 systemd-resolved
# 不直接管理 /etc/resolv.conf，交给 systemd-resolved
[main]
dns=systemd-resolved
NM_CONF
        echo -e "${gl_lv}  ✅ NetworkManager 已配置为使用 systemd-resolved${gl_bai}"
    fi

    echo ""
    echo -e "${gl_lv}  ✅ 重启持久化配置完成，重启后DNS不会失效${gl_bai}"

    echo ""
    echo -e "${gl_kjlan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"
    echo -e "${gl_lv}✅ DNS净化完成！${gl_bai}"
    echo -e "${gl_kjlan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"
    echo ""

    # 显示当前DNS状态
    echo -e "${gl_huang}当前DNS配置：${gl_bai}"
    echo "────────────────────────────────────────────────────────"
    if command -v resolvectl &> /dev/null; then
        resolvectl status 2>/dev/null | head -30 || cat /etc/resolv.conf
    else
        cat /etc/resolv.conf
    fi
    echo "────────────────────────────────────────────────────────"
    
    # ==================== 统一验证输出（兼容所有systemd版本）====================
    echo ""
    echo -e "${gl_kjlan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"
    echo -e "${gl_kjlan}[智能验证] 网卡DNS配置状态检测：${gl_bai}"
    echo -e "${gl_kjlan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"
    echo ""
    
    if command -v resolvectl &> /dev/null && [[ -n "$main_interface" ]]; then
        local verify_output=$(resolvectl status "$main_interface" 2>/dev/null || echo "")
        local verify_success=true
        
        # 检测1: Default Route（兼容不同systemd版本）
        if echo "$verify_output" | grep -q "Default Route: yes" || \
           echo "$verify_output" | grep -q "Protocols:.*+DefaultRoute"; then
            echo -e "  ${gl_lv}✅ Default Route: 已启用${gl_bai}"
        else
            echo -e "  ${gl_huang}⚠️  Default Route: 未启用或不支持${gl_bai}"
            verify_success=false
        fi
        
        # 检测2: DNS Servers（根据用户选择的模式动态验证）
        local escaped_dns_primary=$(echo "$INTERFACE_DNS_PRIMARY" | sed 's/\./\\./g')
        local escaped_dns_secondary=$(echo "$INTERFACE_DNS_SECONDARY" | sed 's/\./\\./g')
        if echo "$verify_output" | grep -q "DNS Servers:.*${escaped_dns_primary}" && \
           echo "$verify_output" | grep -q "DNS Servers:.*${escaped_dns_secondary}"; then
            echo -e "  ${gl_lv}✅ DNS Servers: ${INTERFACE_DNS_PRIMARY}, ${INTERFACE_DNS_SECONDARY}${gl_bai}"
        else
            echo -e "  ${gl_huang}⚠️  DNS Servers: 配置可能未完全生效${gl_bai}"
            verify_success=false
        fi
        
        # 检测3: DNS Domain
        if echo "$verify_output" | grep -q "DNS Domain:.*~\."; then
            echo -e "  ${gl_lv}✅ DNS Domain: ~. (所有域名)${gl_bai}"
        else
            echo -e "  ${gl_huang}⚠️  DNS Domain: 未配置${gl_bai}"
            verify_success=false
        fi
        
        echo ""
        
        # 最终判断
        if [ "$verify_success" = true ]; then
            echo -e "${gl_lv}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"
            echo -e "${gl_lv}💯 最终判断: 网卡DNS配置 100% 成功！${gl_bai}"
            echo -e "${gl_lv}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"
        else
            echo -e "${gl_huang}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"
            echo -e "${gl_huang}⚠️  网卡DNS配置部分未生效${gl_bai}"
            echo -e "${gl_lv}✅ 但全局DNS配置已生效，DNS解析正常工作${gl_bai}"
            echo -e "${gl_huang}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"
        fi
    else
        echo -e "${gl_huang}  ⚠️  resolvectl 不可用或未检测到网卡${gl_bai}"
        echo -e "${gl_lv}  ✅ 全局DNS配置已生效${gl_bai}"
        echo ""
        echo -e "${gl_kjlan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"
    fi
    
    echo ""

    # 测试DNS解析（等待配置生效）
    echo -e "${gl_huang}测试DNS解析：${gl_bai}"
    echo "  → 等待DNS配置生效（3秒）..."
    sleep 3
    
    local dns_test_passed=false
    if [[ "$dns_mode_choice" == "2" ]]; then
        if dns_runtime_health_check "cn"; then
            echo -e "${gl_lv}  ✅ DNS解析正常（国内链路）${gl_bai}"
            dns_test_passed=true
        fi
    else
        if dns_runtime_health_check "global"; then
            echo -e "${gl_lv}  ✅ DNS解析正常（国际链路）${gl_bai}"
            dns_test_passed=true
        fi
    fi
    
    # 如果所有测试都失败
    if [ "$dns_test_passed" = false ]; then
        echo -e "${gl_hong}  ❌ DNS测试未通过，触发自动回滚以避免遗留隐患${gl_bai}"
        auto_rollback_dns_purify
        # 回滚后再次校验，确保脚本退出时机器仍可解析
        local post_rollback_ok=false
        if dns_runtime_health_check "global" || dns_runtime_health_check "cn"; then
            post_rollback_ok=true
        fi
        if [ "$post_rollback_ok" = true ]; then
            echo -e "${gl_lv}  ✅ 回滚后DNS健康校验通过${gl_bai}"
        else
            echo -e "${gl_huang}  ⚠️  回滚后DNS仍异常，请检查上游网络/防火墙策略${gl_bai}"
        fi
        echo -e "${gl_huang}  已自动恢复执行前配置，请检查网络环境后重试${gl_bai}"
        break_end
        return 1
    fi
    echo ""

    # ==================== 生成回滚脚本 ====================
    cat > "$BACKUP_DIR/rollback.sh" << 'ROLLBACK_SCRIPT'
#!/bin/bash
# DNS配置回滚脚本
# 使用方法: bash rollback.sh

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  DNS配置回滚脚本"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

BACKUP_DIR="$(dirname "$0")"
PRE_STATE_DIR="$BACKUP_DIR/pre_state"
command -v flock >/dev/null 2>&1 || { echo '缺少flock，回滚未继续。' >&2; exit 1; }
exec 208>/run/net-tcp-boot-repair.lock
flock -n 208 || { echo '另一个启动恢复/DNS操作正在运行，回滚未继续。' >&2; exit 1; }

# 优先使用增强回滚（精确恢复执行前状态）
if [[ -d "$PRE_STATE_DIR" ]]; then
    echo "检测到增强备份元数据，正在精确恢复执行前状态..."
    if [[ -f "$PRE_STATE_DIR/boot-recovery-restore.sh" ]]; then
        bash "$PRE_STATE_DIR/boot-recovery-restore.sh" --lock-held || { echo '启动恢复组件回滚未全部成功，请检查备份。' >&2; exit 1; }
    elif [[ "$(cat "$PRE_STATE_DIR/boot-recovery.was-installed" 2>/dev/null)" == false ]] &&
        [[ -x /usr/local/libexec/net-tcp-boot-recovery ]]; then
        # Compatibility with backups made before per-asset snapshots existed.
        /usr/local/libexec/net-tcp-boot-recovery --remove-app-guards || true
    fi

    restore_path_state() {
        local dst="$1"
        local key="$2"
        rm -f "$dst" 2>/dev/null || true
        if [[ -e "$PRE_STATE_DIR/$key" || -L "$PRE_STATE_DIR/$key" ]]; then
            mkdir -p "$(dirname "$dst")"
            cp -a "$PRE_STATE_DIR/$key" "$dst" 2>/dev/null || true
        elif [[ -f "$PRE_STATE_DIR/$key.absent" ]]; then
            rm -f "$dst" 2>/dev/null || true
        fi
    }

    # 恢复配置文件（resolv.conf 延后，避免悬空链接）
    restore_path_state "/etc/dhcp/dhclient.conf" "dhclient.conf"
    restore_path_state "/etc/network/interfaces" "interfaces"
    restore_path_state "/etc/systemd/resolved.conf" "resolved.conf"
    restore_path_state "/etc/systemd/system/dns-purify-persist.service" "dns-purify-persist.service"
    restore_path_state "/usr/local/bin/dns-purify-apply.sh" "dns-purify-apply.sh"
    restore_path_state "/etc/systemd/system/systemd-resolved.service.d/dbus-fix.conf" "dbus-fix.conf"
    restore_path_state "/etc/NetworkManager/conf.d/99-dns-purify.conf" "nm-99-dns-purify.conf"

    if [[ -f "$PRE_STATE_DIR/ifup-resolved.exec" ]]; then
        case "$(cat "$PRE_STATE_DIR/ifup-resolved.exec" 2>/dev/null)" in
            executable)
                [[ -e /etc/network/if-up.d/resolved ]] && chmod +x /etc/network/if-up.d/resolved 2>/dev/null || true
                ;;
            not_executable)
                [[ -e /etc/network/if-up.d/resolved ]] && chmod -x /etc/network/if-up.d/resolved 2>/dev/null || true
                ;;
            absent)
                rm -f /etc/network/if-up.d/resolved 2>/dev/null || true
                ;;
        esac
    fi

    # 移除 networkd drop-in（扩展搜索所有可能路径）
    for search_dir in /etc/systemd/network /run/systemd/network /usr/lib/systemd/network; do
        for dropin_file in "$search_dir"/*.network.d/dns-purify-override.conf; do
            [[ -f "$dropin_file" ]] || continue
            rm -f "$dropin_file"
            rmdir "$(dirname "$dropin_file")" 2>/dev/null || true
        done
    done

    if [[ -f "$PRE_STATE_DIR/networkd-dropins.map" ]]; then
        while IFS='|' read -r restore_path restore_key; do
            [[ -n "$restore_path" && -n "$restore_key" ]] || continue
            [[ -f "$PRE_STATE_DIR/$restore_key" ]] || continue
            mkdir -p "$(dirname "$restore_path")"
            cp -a "$PRE_STATE_DIR/$restore_key" "$restore_path" 2>/dev/null || true
        done < "$PRE_STATE_DIR/networkd-dropins.map"
    fi

    # 重载 networkd/NM 使配置变更生效
    if systemctl is-active --quiet systemd-networkd 2>/dev/null; then
        networkctl reload 2>/dev/null || systemctl reload systemd-networkd 2>/dev/null || true
    fi
    if systemctl is-active --quiet NetworkManager 2>/dev/null; then
        systemctl reload NetworkManager 2>/dev/null || true
    fi

    systemctl daemon-reload 2>/dev/null || true

    dns_persist_was_enabled="false"
    [[ -f "$PRE_STATE_DIR/dns-persist.was-enabled" ]] && dns_persist_was_enabled=$(cat "$PRE_STATE_DIR/dns-persist.was-enabled" 2>/dev/null || echo "false")

    if [[ -e "$PRE_STATE_DIR/dns-purify-persist.service" || -L "$PRE_STATE_DIR/dns-purify-persist.service" ]]; then
        if [[ "$dns_persist_was_enabled" == "true" ]]; then
            systemctl enable dns-purify-persist.service 2>/dev/null || true
        else
            systemctl disable dns-purify-persist.service 2>/dev/null || true
        fi
    else
        systemctl disable dns-purify-persist.service 2>/dev/null || true
    fi

    had_resolvconf_pkg="false"
    [[ -f "$PRE_STATE_DIR/had-resolvconf.pkg" ]] && had_resolvconf_pkg=$(cat "$PRE_STATE_DIR/had-resolvconf.pkg" 2>/dev/null || echo "false")
    if [[ "$had_resolvconf_pkg" == "true" ]] && ! dpkg -s resolvconf >/dev/null 2>&1; then
        DEBIAN_FRONTEND=noninteractive apt-get install -y resolvconf >/dev/null 2>&1 || true
    fi

    # 先恢复 resolved 服务状态（在 resolv.conf 之前，避免悬空链接）
    resolved_enable_state="unknown"
    resolved_was_masked="false"
    resolved_was_active="false"
    [[ -f "$PRE_STATE_DIR/resolved.enable-state" ]] && resolved_enable_state=$(cat "$PRE_STATE_DIR/resolved.enable-state" 2>/dev/null || echo "unknown")
    # 兼容旧版快照
    if [[ "$resolved_enable_state" == "unknown" && -f "$PRE_STATE_DIR/resolved.was-enabled" ]]; then
        old_enabled=$(cat "$PRE_STATE_DIR/resolved.was-enabled" 2>/dev/null || echo "false")
        [[ "$old_enabled" == "true" ]] && resolved_enable_state="enabled" || resolved_enable_state="disabled"
    fi
    [[ -f "$PRE_STATE_DIR/resolved.was-masked" ]] && resolved_was_masked=$(cat "$PRE_STATE_DIR/resolved.was-masked" 2>/dev/null || echo "false")
    [[ -f "$PRE_STATE_DIR/resolved.was-active" ]] && resolved_was_active=$(cat "$PRE_STATE_DIR/resolved.was-active" 2>/dev/null || echo "false")

    if [[ "$resolved_was_masked" == "true" ]]; then
        systemctl mask systemd-resolved 2>/dev/null || true
        systemctl stop systemd-resolved 2>/dev/null || true
    else
        systemctl unmask systemd-resolved 2>/dev/null || true
        case "$resolved_enable_state" in
            enabled|enabled-runtime)
                systemctl enable systemd-resolved 2>/dev/null || true
                ;;
            static|indirect|generated)
                ;;
            *)
                systemctl disable systemd-resolved 2>/dev/null || true
                ;;
        esac

        if [[ "$resolved_was_active" == "true" ]]; then
            systemctl restart systemd-resolved 2>/dev/null || systemctl start systemd-resolved 2>/dev/null || true
            # 等待 stub 文件可用
            for wait_i in $(seq 1 5); do
                [[ -f /run/systemd/resolve/stub-resolv.conf ]] && break
                sleep 1
            done
        else
            systemctl stop systemd-resolved 2>/dev/null || true
        fi
    fi

    # 最后恢复 resolv.conf（此时 resolved 已恢复，stub 文件可用）
    if [[ -L "$PRE_STATE_DIR/resolv.conf" ]]; then
        backup_link=$(readlink "$PRE_STATE_DIR/resolv.conf" 2>/dev/null || echo "")
        if [[ "$backup_link" == *"stub-resolv.conf"* ]] && [[ ! -f /run/systemd/resolve/stub-resolv.conf ]]; then
            rm -f /etc/resolv.conf 2>/dev/null || true
            echo "nameserver 127.0.0.53" > /etc/resolv.conf 2>/dev/null || true
        else
            restore_path_state "/etc/resolv.conf" "resolv.conf"
        fi
    else
        restore_path_state "/etc/resolv.conf" "resolv.conf"
    fi

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "✅ 回滚完成（增强模式）！"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    exit 0
fi

# ===== 旧版回滚（无 pre_state 目录时的兼容模式）=====

# 恢复 dhclient.conf
if [[ -f "$BACKUP_DIR/dhclient.conf.bak" ]]; then
    echo "恢复 dhclient.conf..."
    cp "$BACKUP_DIR/dhclient.conf.bak" /etc/dhcp/dhclient.conf
    echo "✅ 已恢复 dhclient.conf"
fi

# 恢复 interfaces
if [[ -f "$BACKUP_DIR/interfaces.bak" ]]; then
    echo "恢复 interfaces..."
    cp "$BACKUP_DIR/interfaces.bak" /etc/network/interfaces
    echo "✅ 已恢复 interfaces"
fi

# 恢复 resolved.conf
if [[ -f "$BACKUP_DIR/resolved.conf.bak" ]]; then
    echo "恢复 resolved.conf..."
    cp "$BACKUP_DIR/resolved.conf.bak" /etc/systemd/resolved.conf
    echo "✅ 已恢复 resolved.conf"
fi

# 移除DNS持久化服务
if [[ -f /etc/systemd/system/dns-purify-persist.service ]]; then
    echo "移除 DNS持久化服务..."
    systemctl disable dns-purify-persist.service 2>/dev/null || true
    rm -f /etc/systemd/system/dns-purify-persist.service
    echo "✅ 已移除 dns-purify-persist.service"
fi

# 移除DNS持久化脚本
if [[ -f /usr/local/bin/dns-purify-apply.sh ]]; then
    rm -f /usr/local/bin/dns-purify-apply.sh
    echo "✅ 已移除 dns-purify-apply.sh"
fi

# 移除 D-Bus 修复配置（仅删除本脚本创建的文件，不删整个目录）
if [[ -f /etc/systemd/system/systemd-resolved.service.d/dbus-fix.conf ]]; then
    rm -f /etc/systemd/system/systemd-resolved.service.d/dbus-fix.conf
    rmdir /etc/systemd/system/systemd-resolved.service.d 2>/dev/null || true
    echo "✅ 已移除 D-Bus 修复配置"
fi

# 移除 systemd-networkd DNS阻断 drop-in（扩展搜索路径）
for search_dir in /etc/systemd/network /run/systemd/network /usr/lib/systemd/network; do
    for dropin_dir in "$search_dir"/*.network.d; do
        if [[ -f "$dropin_dir/dns-purify-override.conf" ]]; then
            rm -f "$dropin_dir/dns-purify-override.conf"
            rmdir "$dropin_dir" 2>/dev/null || true
            echo "✅ 已移除 systemd-networkd DNS阻断配置"
        fi
    done
done

# 移除 NetworkManager DNS配置
if [[ -f /etc/NetworkManager/conf.d/99-dns-purify.conf ]]; then
    rm -f /etc/NetworkManager/conf.d/99-dns-purify.conf
    echo "✅ 已移除 NetworkManager DNS配置"
fi

# 恢复 if-up.d/resolved 可执行权限
if [[ -f /etc/network/if-up.d/resolved ]] && [[ ! -x /etc/network/if-up.d/resolved ]]; then
    echo "恢复 if-up.d/resolved 可执行权限..."
    chmod +x /etc/network/if-up.d/resolved
    echo "✅ 已恢复 if-up.d/resolved 可执行权限"
fi

# 重新加载 systemd
systemctl daemon-reload 2>/dev/null || true

# 重载 networkd/NM
if systemctl is-active --quiet systemd-networkd 2>/dev/null; then
    networkctl reload 2>/dev/null || systemctl reload systemd-networkd 2>/dev/null || true
fi
if systemctl is-active --quiet NetworkManager 2>/dev/null; then
    systemctl reload NetworkManager 2>/dev/null || true
fi

# 重新加载 systemd-resolved
echo "重新加载 systemd-resolved..."
systemctl reload-or-restart systemd-resolved 2>/dev/null || true
echo "✅ systemd-resolved 已重新加载"

# 恢复 resolv.conf（在 resolved 重启之后，保留软链接特性）
if [[ -f "$BACKUP_DIR/resolv.conf.bak" ]]; then
    echo "恢复 resolv.conf..."
    rm -f /etc/resolv.conf
    cp -a "$BACKUP_DIR/resolv.conf.bak" /etc/resolv.conf
    echo "✅ 已恢复 resolv.conf"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ 回滚完成！"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
ROLLBACK_SCRIPT

    chmod +x "$BACKUP_DIR/rollback.sh"

    # 显示备份信息
    echo -e "${gl_kjlan}备份与回滚信息：${gl_bai}"
    echo "  所有原始配置已备份到："
    echo "  $BACKUP_DIR"
    echo ""
    echo -e "${gl_huang}如需回滚，执行：${gl_bai}"
    echo "  bash $BACKUP_DIR/rollback.sh"
    echo ""

    echo -e "${gl_lv}DNS净化脚本执行完成${gl_bai}"
    echo "原作者：NSdesk"
    echo "安全增强：SSH防断连优化"
    echo "更多信息：https://www.nodeseek.com/space/23129#/general"
    echo "════════════════════════════════════════════════════════"
    echo ""

    break_end
}

#=============================================================================
# Realm 转发首连超时修复（专项优化）
#=============================================================================

# 没有 IPv4 默认路由视为纯 IPv6 机器（禁用 IPv6 或改 IPv4 监听会断开 SSH/转发）
has_ipv4_default_route() {
    [ -n "$(ip -4 route show default 2>/dev/null)" ]
}

realm_fix_timeout() {
    clear
    echo -e "${gl_kjlan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"
    echo -e "${gl_kjlan}   Realm 转发首连超时修复（针对跨境线路优化）${gl_bai}"
    echo -e "${gl_kjlan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"
    echo ""
    echo -e "${gl_huang}功能说明：${gl_bai}"
    echo "  • 连接跟踪模块加载 + 容量扩展（转发必需）"
    echo "  • Realm 监听地址改为 IPv4（0.0.0.0）"
    echo "  • 提升 realm.service 文件句柄限制"
    echo ""
    echo -e "${gl_kjlan}已由其他功能覆盖（本功能不再重复设置）：${gl_bai}"
    echo "  • MSS 钳制 → 功能3/4已配置"
    echo "  • DNS 管理 → 功能5已配置"
    echo "  • tcp_fin_timeout / tcp_fastopen → 功能3已配置"
    echo ""
    if [ "$AUTO_MODE" = "1" ]; then
        confirm=y
    else
        read -e -p "是否继续执行修复？(y/n): " confirm
    fi

    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo -e "${gl_huang}已取消操作${gl_bai}"
        return
    fi

    # 检查 root 权限
    if [[ ${EUID:-0} -ne 0 ]]; then
        echo -e "${gl_hong}错误：请以 root 身份运行（sudo -i 或 sudo bash）${gl_bai}"
        return 1
    fi

    # 备份目录
    BACKUP_DIR="/root/.realm_fix_backup/$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$BACKUP_DIR"
    echo -e "${gl_lv}[1/4] 创建备份目录：$BACKUP_DIR${gl_bai}"

    # 加载并持久化 nf_conntrack
    echo -e "${gl_lv}[2/4] 加载/持久化 nf_conntrack（连接跟踪）${gl_bai}"
    if command -v modprobe >/dev/null 2>&1; then
        modprobe nf_conntrack 2>/dev/null || true
    fi
    mkdir -p /etc/modules-load.d
    if ! grep -q '^nf_conntrack$' /etc/modules-load.d/conntrack.conf 2>/dev/null; then
        echo nf_conntrack >> /etc/modules-load.d/conntrack.conf
    fi

    # 写入 Realm 专属 sysctl 配置（仅 conntrack_max，其余由功能3管理）
    cat >/etc/sysctl.d/60-realm-tune.conf <<'SYSC'
# Realm 转发专属优化（仅设置功能3未覆盖的参数）
# tcp_fin_timeout / tcp_fastopen 由功能3的配置文件统一管理

# 连接跟踪容量（转发必需）
net.netfilter.nf_conntrack_max = 262144
SYSC
    sysctl --system >/dev/null 2>&1
    echo -e "${gl_lv}  ✓ nf_conntrack_max = 262144 已生效${gl_bai}"

    # 修改 Realm 配置
    echo -e "${gl_lv}[3/4] 优化 Realm 配置（监听改为 IPv4）${gl_bai}"
    realm_cfg="/etc/realm/config.json"
    if [[ -f "$realm_cfg" ]]; then
        cp -a "$realm_cfg" "$BACKUP_DIR/"

        # 说明：旧版在此处向 config.json 顶层写入 resolve / nodelay / reuse_port 三个键，
        # 但它们不是 Realm 的配置项（Realm 顶层仅 log / dns / network / endpoints，未知键被忽略；
        # TCP_NODELAY 由 Realm 自身始终开启），从未生效，v5.4.10 起不再写入。
        # 已写入过的旧键保持原样（无害），不做删除。

        # 用文本替换确保 IPv6 监听改为 IPv4
        if has_ipv4_default_route; then
            sed -i.bak -E 's/"listen"\s*:\s*":::([0-9]+)"/"listen": "0.0.0.0:\1"/g' "$realm_cfg" 2>/dev/null || true
            sed -i.bak -E 's/"listen"\s*:\s*"\[::\]:([0-9]+)"/"listen": "0.0.0.0:\1"/g' "$realm_cfg" 2>/dev/null || true
            sed -i.bak 's/:::/0.0.0.0:/g' "$realm_cfg" 2>/dev/null || true
            echo -e "${gl_lv}  ✓ Realm 配置已优化${gl_bai}"
        else
            echo -e "${gl_huang}  检测到本机无 IPv4，保留 Realm 原监听地址${gl_bai}"
        fi
    else
        echo -e "${gl_huang}  未找到 $realm_cfg，跳过 Realm 配置修改${gl_bai}"
    fi

    # realm.service 文件句柄限制
    echo -e "${gl_lv}[4/4] 提升 realm.service 文件句柄限制${gl_bai}"
    if systemctl list-unit-files 2>/dev/null | grep -q '^realm\.service'; then
        mkdir -p /etc/systemd/system/realm.service.d
        cat >/etc/systemd/system/realm.service.d/override.conf <<'OVR'
[Service]
LimitNOFILE=1048576
OVR
        systemctl daemon-reload
        systemctl restart realm 2>/dev/null || echo -e "${gl_huang}  ⚠ realm 重启失败，请手动检查${gl_bai}"
        echo -e "${gl_lv}  ✓ LimitNOFILE=1048576 已生效${gl_bai}"
    else
        echo -e "${gl_huang}  未发现 realm.service，跳过${gl_bai}"
    fi

    echo ""
    echo -e "${gl_kjlan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"
    echo -e "${gl_lv}✅ Realm 优化完成！${gl_bai}"
    echo -e "${gl_kjlan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"
    echo ""
    echo -e "${gl_huang}📋 备份位置：${gl_bai}$BACKUP_DIR"
    echo ""
    echo -e "${gl_huang}🔍 快速验证：${gl_bai}"
    echo "  • Realm 监听：  ss -tlnp | grep realm"
    echo "  • conntrack：   sysctl net.netfilter.nf_conntrack_max"
    echo "  • Realm 配置：  grep '\"listen\"' /etc/realm/config.json"
    echo ""
    echo -e "${gl_lv}💯 重启服务器后所有配置依然生效，无需重复执行！${gl_bai}"
    echo ""
}

#=============================================================================
# 一键全自动优化
#=============================================================================

one_click_optimize() {
    clear
    echo -e "${gl_kjlan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"
    echo -e "${gl_kjlan}   ⭐ 一键全自动优化 (BBR v3 + 网络调优)${gl_bai}"
    echo -e "${gl_kjlan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"
    echo ""

    # 检测当前是否已运行 XanMod 内核
    local xanmod_running=0
    if uname -r | grep -qi 'xanmod'; then
        xanmod_running=1
    fi

    if [ $xanmod_running -eq 0 ]; then
        # ===== 阶段1：安装内核 =====
        echo -e "${gl_huang}▶ 阶段 1/2：安装 XanMod + BBR v3 内核${gl_bai}"
        echo ""
        echo "安装完成后需要重启服务器"
        echo "重启后再次执行 66 即可进入阶段2（全自动优化）"
        echo ""

        install_xanmod_kernel
        if [ $? -eq 0 ]; then
            echo ""
            echo -e "${gl_lv}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"
            echo -e "${gl_lv}  ✅ 内核安装完成！${gl_bai}"
            echo -e "${gl_lv}  重启后执行 66 继续自动优化${gl_bai}"
            echo -e "${gl_lv}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"
            echo ""
            server_reboot
        fi
    else
        # ===== 阶段2：全自动优化 =====
        echo -e "${gl_lv}✅ 检测到 XanMod 内核已运行：$(uname -r)${gl_bai}"
        echo ""
        echo -e "${gl_huang}▶ 阶段 2/2：全自动网络优化${gl_bai}"
        echo "将依次执行："
        echo "  [1/4] 功能3 - BBR 直连优化（自动检测带宽）"
        echo "  [2/4] 功能5 - DNS 净化（纯国外模式）"
        echo "  [3/4] 功能6 - Realm 转发修复"
        echo "  [4/4] 功能8 - 永久禁用 IPv6"
        echo ""
        sleep 3

        AUTO_MODE=1

        echo -e "${gl_kjlan}━━━━━━ [1/4] BBR 直连优化 ━━━━━━${gl_bai}"
        bbr_configure_direct

        echo ""
        echo -e "${gl_kjlan}━━━━━━ [2/4] DNS 净化 ━━━━━━${gl_bai}"
        dns_purify_and_harden

        echo ""
        echo -e "${gl_kjlan}━━━━━━ [3/4] Realm 转发修复 ━━━━━━${gl_bai}"
        realm_fix_timeout

        AUTO_MODE=""

        echo ""
        echo -e "${gl_kjlan}━━━━━━ [4/4] 禁用 IPv6（可选） ━━━━━━${gl_bai}"
        if ! has_ipv4_default_route; then
            echo -e "${gl_huang}检测到本机无 IPv4，已跳过禁用 IPv6（避免断开 SSH）${gl_bai}"
        else
            read -e -p "$(echo -e "${gl_huang}是否永久禁用 IPv6？(Y/N) [Y]: ${gl_bai}")" ipv6_choice
            ipv6_choice=${ipv6_choice:-Y}
            if [[ "$ipv6_choice" =~ ^[Yy]$ ]]; then
                AUTO_MODE=1
                disable_ipv6_permanent
                AUTO_MODE=""
            else
                echo -e "${gl_huang}已跳过 IPv6 禁用${gl_bai}"
            fi
        fi

        echo ""
        echo -e "${gl_lv}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"
        echo -e "${gl_lv}  ✅ 全部优化完成！${gl_bai}"
        echo -e "${gl_lv}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"
        echo ""
        break_end
    fi
}

# 主菜单
#=============================================================================

show_main_menu() {
    clear
    check_bbr_status
    local is_installed=$?

    echo ""
    local box_width=50
    local inner=$((box_width - 2))
    echo -e "${gl_zi}╔$(printf '═%.0s' $(seq 1 $inner))╗${gl_bai}"
    echo -e "${gl_zi}║ $(format_fixed_width "BBR v3 终极优化脚本 - Ultimate Edition" $((inner - 2))) ║${gl_bai}"
    echo -e "${gl_zi}║ $(format_fixed_width "version ${SCRIPT_VERSION}" $((inner - 2))) ║${gl_bai}"
    if [ -n "$SCRIPT_LAST_UPDATE" ]; then
        echo -e "${gl_zi}║ ${gl_huang}$(format_fixed_width "更新: ${SCRIPT_LAST_UPDATE}" $((inner - 2)))${gl_zi} ║${gl_bai}"
    fi
    echo -e "${gl_zi}╚$(printf '═%.0s' $(seq 1 $inner))╝${gl_bai}"
    echo ""
    echo -e "${gl_kjlan}━━━━━━━━━━━━ 核心功能 ━━━━━━━━━━━━${gl_bai}"
    echo -e "${gl_kjlan}[内核管理]${gl_bai}"
    echo "1. 安装/更新 XanMod 内核 + BBR v3 ⭐ 推荐"
    echo "2. 卸载 XanMod 内核"
    echo ""
    echo -e "${gl_kjlan}[BBR/网络优化]${gl_bai}"
    echo "3. BBR 直连/落地优化（智能带宽检测）⭐ 推荐"
    echo -e "4. ${gl_hui}清理旧版 MTU 残留（需明确确认）${gl_bai}"
    echo "5. NS论坛-DNS净化（抗污染/驯服DHCP）"
    echo "6. Realm转发timeout修复 ⭐ 推荐"
    echo ""
    echo -e "${gl_kjlan}━━━━━━━━━━━ 系统配置 ━━━━━━━━━━━${gl_bai}"
    echo "7. 设置IPv4/IPv6优先级"
    echo "8. IPv6管理（临时/永久禁用/取消）"
    echo ""
    echo -e "${gl_kjlan}━━━━━━━━━━ 代理部署 ━━━━━━━━━━${gl_bai}"
    echo "9. 一键反代 ⭐ 推荐"
    echo ""
    echo -e "${gl_kjlan}━━━━━━━━━ 一键优化 ━━━━━━━━━${gl_bai}"
    echo "66. ⭐ 一键全自动优化 (BBR v3 + 网络调优)"
    echo ""
    echo -e "${gl_kjlan}━━━━━━━━━ 脚本维护 ━━━━━━━━━${gl_bai}"
    echo "98. 更新脚本（从 GitHub 拉取最新版）"
    echo ""
    echo -e "${gl_hong}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"
    echo -e "${gl_hong}99. 完全卸载脚本（卸载所有内容）${gl_bai}"
    echo ""
    echo "0. 退出脚本"
    echo -e "${gl_kjlan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"
    read -e -p "请输入选择: " choice

    case $choice in
        1)
            if [ $is_installed -eq 0 ]; then
                update_xanmod_kernel
                # update 函数内部已有重启交互，无需再次调用 server_reboot
            else
                install_xanmod_kernel && server_reboot
            fi
            ;;
        2)
            if [ $is_installed -eq 0 ]; then
                uninstall_xanmod
            else
                echo -e "${gl_huang}当前未检测到 XanMod 内核，无需卸载${gl_bai}"
                break_end
            fi
            ;;
        3)
            bbr_configure_direct
            break_end
            ;;
        4)
            echo -e "${gl_huang}功能4仅用于清理旧版 MTU 残留，会恢复路由/链路 MTU。${gl_bai}"
            local mtu_cleanup_confirm
            if read -r -p "输入 清理MTU 才执行，其他输入取消: " mtu_cleanup_confirm && [ "$mtu_cleanup_confirm" = "清理MTU" ]; then
                auto_cleanup_legacy_mtu
            fi
            break_end
            ;;
        5)
            dns_purify_and_harden
            ;;
        6)
            realm_fix_timeout
            break_end
            ;;
        7)
            manage_ip_priority
            ;;
        8)
            manage_ipv6
            ;;
        9)
            manage_reverse_proxy
            ;;
        66)
            one_click_optimize
            ;;
        98)
            update_script_self
            ;;
        99)
            uninstall_all
            ;;
        0)
            echo "退出脚本"
            exit 0
            ;;
        *)
            echo "无效选择"
            sleep 2
            ;;
    esac
}

update_xanmod_kernel() {
    clear
    echo -e "${gl_kjlan}=== 更新 XanMod 内核 ===${gl_bai}"
    echo "------------------------------------------------"
    
    # 获取当前内核版本
    local current_kernel=$(uname -r)
    echo -e "当前内核版本: ${gl_huang}${current_kernel}${gl_bai}"
    echo ""
    
    # 检测 CPU 架构
    local cpu_arch=$(uname -m)
    
    # ARM 架构提示：XanMod 无 ARM64 构建，此处不存在可更新的内核
    if [ "$cpu_arch" = "aarch64" ]; then
        echo -e "${gl_huang}ARM64 平台无 XanMod 内核可更新${gl_bai}"
        echo "BBR v3 未合入主线内核，XanMod 官方仅提供 x86-64 构建。"
        echo -e "ARM 机器请使用【${gl_lv}功能 3 - BBR 直连/落地优化${gl_bai}】做网络调优。"
        break_end
        return 1
    fi
    
    # x86_64 架构更新流程
    echo "正在检查可用更新..."
    
    local xanmod_repo_file="/etc/apt/sources.list.d/xanmod-release.list"

    # 添加/修正 XanMod 仓库（旧 releases suite 已为空）
    if [ ! -f "$xanmod_repo_file" ] || grep -qE 'deb\.xanmod\.org[[:space:]]+releases[[:space:]]+' "$xanmod_repo_file" 2>/dev/null; then
        echo "正在添加 XanMod 仓库..."

        # 添加密钥（分步执行，避免管道 $? 问题）
        local gpg_key_file="/usr/share/keyrings/xanmod-archive-keyring.gpg"
        local key_tmp=$(mktemp)
        local gpg_ok=false

        if wget -qO "$key_tmp" "${gh_proxy}raw.githubusercontent.com/kejilion/sh/main/archive.key" 2>/dev/null && \
           [ -s "$key_tmp" ]; then
            if gpg --dearmor -o "$gpg_key_file" --yes < "$key_tmp" 2>/dev/null; then
                gpg_ok=true
            fi
        fi

        if [ "$gpg_ok" = false ]; then
            if wget -qO "$key_tmp" "https://dl.xanmod.org/archive.key" 2>/dev/null && \
               [ -s "$key_tmp" ]; then
                if gpg --dearmor -o "$gpg_key_file" --yes < "$key_tmp" 2>/dev/null; then
                    gpg_ok=true
                fi
            fi
        fi

        rm -f "$key_tmp"

        if [ "$gpg_ok" = false ]; then
            echo -e "${gl_hong}错误: GPG 密钥导入失败${gl_bai}"
            break_end
            return 1
        fi

        # 添加仓库（使用系统 codename；旧 releases suite 已为空）
        xanmod_write_repo "$gpg_key_file" "$xanmod_repo_file" || { break_end; return 1; }
    fi

    # 更新软件包列表
    echo "正在更新软件包列表..."
    if ! apt-get update > /dev/null 2>&1; then
        echo -e "${gl_huang}⚠️  apt-get update 部分失败，尝试继续...${gl_bai}"
    fi

    # 检查已安装的 XanMod 内核包（使用 ^ii 过滤，排除已卸载残留）
    local installed_packages=$(dpkg -l | grep -E '^ii\s+linux-.*xanmod' | awk '{print $2}')
    
    if [ -z "$installed_packages" ]; then
        echo -e "${gl_hong}错误: 未检测到已安装的 XanMod 内核${gl_bai}"
        break_end
        return 1
    fi
    
    echo -e "已安装的内核包:"
    echo "$installed_packages" | while read pkg; do
        echo "  - $pkg"
    done
    echo ""
    
    # 检查是否有可用更新
    local upgradable=$(apt list --upgradable 2>/dev/null | grep xanmod)
    
    if [ -z "$upgradable" ]; then
        local cpu_level
        cpu_level=$(echo "$installed_packages" | sed -nE 's/.*x64v([1-4]).*/\1/p' | head -1)
        [ -z "$cpu_level" ] && cpu_level="3"

        # 获取已安装的最新 XanMod 内核版本（从 linux-image 包名提取版本号并取最大值）
        local latest_installed
        latest_installed=$(echo "$installed_packages" \
            | sed -nE 's/^linux-image-([0-9]+\.[0-9]+\.[0-9]+-x64v[1-4]-xanmod[0-9]+)$/\1/p' \
            | sort -V | tail -1)

        local running_latest=0
        if [ -n "$latest_installed" ] && [ "$current_kernel" = "$latest_installed" ]; then
            running_latest=1
        fi

        if [ $running_latest -eq 1 ]; then
            echo -e "${gl_lv}✅ 当前运行内核已是最新版本！${gl_bai}"
        else
            echo -e "${gl_lv}✅ XanMod 内核包已是最新，但当前运行内核尚未切换！${gl_bai}"
            echo -e "  正在运行: ${gl_hong}${current_kernel}${gl_bai}"
            if [ -n "$latest_installed" ]; then
                echo -e "  最新已装: ${gl_lv}${latest_installed}${gl_bai}"
            else
                echo -e "  ${gl_huang}提示: 未能解析最新已装内核版本，请重启后再检查${gl_bai}"
            fi
            echo -e "  ${gl_huang}请重启系统 (reboot) 以切换到最新内核${gl_bai}"
        fi
        echo ""

        echo -e "${gl_kjlan}━━━━━━━━━━ CPU 架构信息 ━━━━━━━━━━${gl_bai}"
        echo -e "  CPU 架构等级: ${gl_lv}x86-64-v${cpu_level}${gl_bai}"
        echo -e "  当前运行内核: ${gl_lv}${current_kernel}${gl_bai}"
        if [ -n "$latest_installed" ] && [ $running_latest -ne 1 ]; then
            echo -e "  最新已装内核: ${gl_lv}${latest_installed}${gl_bai}"
        fi
        if [ $running_latest -eq 1 ]; then
            echo -e "  ${gl_huang}说明: 本机 CPU 最高支持 v${cpu_level}，当前已运行该等级最新内核${gl_bai}"
        else
            echo -e "  ${gl_huang}说明: 本机 CPU 最高支持 v${cpu_level}，最新内核已安装，重启后生效${gl_bai}"
        fi
        echo -e "  ${gl_huang}不同等级(v1-v4)的内核更新进度可能不同，以 XanMod 官方仓库为准${gl_bai}"
        echo -e "${gl_kjlan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"

        rm -f "$xanmod_repo_file"
        echo -e "${gl_lv}已自动清理 XanMod 软件源（如需更新可再次运行选项1）${gl_bai}"
        break_end
        return 0
    fi
    
    echo -e "${gl_huang}发现可用更新:${gl_bai}"
    echo "$upgradable"
    echo ""
    
    read -e -p "确定更新 XanMod 内核吗？(Y/N): " confirm
    
    case "$confirm" in
        [Yy])
            echo ""
            echo "正在更新内核..."
            echo "$installed_packages" | xargs -r apt install --only-upgrade -y
            
            if [ $? -eq 0 ]; then
                echo ""
                echo -e "${gl_lv}✅ XanMod 内核更新成功！${gl_bai}"
                echo -e "${gl_huang}⚠️  请重启系统以加载新内核${gl_bai}"
                echo ""
                local cpu_level
                cpu_level=$(echo "$installed_packages" | sed -nE 's/.*x64v([1-4]).*/\1/p' | head -1)
                [ -z "$cpu_level" ] && cpu_level="3"
                local latest_installed
                latest_installed=$(dpkg -l 2>/dev/null | awk '/^ii\s+linux-image-[0-9].*xanmod/ {print $2}' | sed 's/^linux-image-//' | sort -V | tail -1)
                echo -e "${gl_kjlan}━━━━━━━━━━ CPU 架构信息 ━━━━━━━━━━${gl_bai}"
                echo -e "  CPU 架构等级: ${gl_lv}x86-64-v${cpu_level}${gl_bai}"
                if [ -n "$latest_installed" ]; then
                    echo -e "  最新已装内核: ${gl_lv}${latest_installed}${gl_bai}"
                else
                    echo -e "  已更新内核包: ${gl_lv}$(echo "$installed_packages" | head -1)${gl_bai}"
                fi
                echo -e "  ${gl_huang}说明: 本机 CPU 最高支持 v${cpu_level}，已更新至该等级的最新内核${gl_bai}"
                echo -e "  ${gl_huang}不同等级(v1-v4)的内核更新进度可能不同，以 XanMod 官方仓库为准${gl_bai}"
                echo -e "${gl_kjlan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"
                echo ""
                echo -e "${gl_kjlan}后续更新: 再次运行选项1即可检查并安装最新内核${gl_bai}"

                rm -f "$xanmod_repo_file"
                echo -e "${gl_lv}已自动清理 XanMod 软件源（如需更新可再次运行选项1）${gl_bai}"
                return 0
            else
                echo ""
                echo -e "${gl_hong}❌ 内核更新失败${gl_bai}"
                break_end
                return 1
            fi
            ;;
        *)
            echo "已取消更新"
            break_end
            return 1
            ;;
    esac
}

uninstall_xanmod() {
    echo -e "${gl_huang}警告: 即将卸载 XanMod 内核${gl_bai}"
    echo ""

    # 安全检查：确认系统中有回退内核可用
    local non_xanmod_kernels=$(dpkg -l 2>/dev/null | grep '^ii' | grep 'linux-image-' | grep -v 'xanmod' | grep -v 'dbg' | wc -l)
    if [ "$non_xanmod_kernels" -eq 0 ]; then
        echo -e "${gl_hong}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"
        echo -e "${gl_hong}❌ 安全检查未通过：未检测到非 XanMod 的回退内核！${gl_bai}"
        echo -e "${gl_hong}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"
        echo ""
        echo "卸载 XanMod 内核后系统将没有可启动的内核，重启会导致 VPS 无法开机。"
        echo ""
        echo -e "${gl_lv}建议：先安装默认内核再卸载 XanMod${gl_bai}"
        echo "  apt install -y linux-image-amd64   # Debian"
        echo "  apt install -y linux-image-generic  # Ubuntu"
        echo ""
        break_end
        return 1
    fi
    echo -e "${gl_lv}✅ 检测到 ${non_xanmod_kernels} 个回退内核，可以安全卸载${gl_bai}"
    echo ""

    read -e -p "确定继续吗？(Y/N): " confirm

    case "$confirm" in
        [Yy])
            # 使用能匹配元包和内核包的模式
            echo "正在卸载 XanMod 相关包..."
            if apt purge -y 'linux-*xanmod*' 2>&1; then
                # 验证卸载结果
                if dpkg -l 2>/dev/null | grep -qE '^ii\s+linux-.*xanmod'; then
                    echo -e "${gl_hong}⚠️  部分 XanMod 包未能卸载，请手动检查：${gl_bai}"
                    dpkg -l | grep -E '^ii\s+linux-.*xanmod' | awk '{print "  - " $2}'
                else
                    echo -e "${gl_lv}✅ XanMod 内核包已全部卸载${gl_bai}"
                fi
                update-grub 2>/dev/null
            else
                echo -e "${gl_hong}❌ 卸载命令执行失败，请手动检查${gl_bai}"
                break_end
                return 1
            fi

            # 清理软件源和 GPG 密钥
            rm -f /etc/apt/sources.list.d/xanmod-release.list
            rm -f /usr/share/keyrings/xanmod-archive-keyring.gpg
            echo -e "${gl_lv}✅ XanMod 软件源已清理${gl_bai}"

            rm -f "$SYSCTL_CONF" "$SYSCTL_CONF_LEGACY"
            echo -e "${gl_lv}XanMod 内核已卸载${gl_bai}"
            server_reboot
            ;;
        *)
            echo "已取消"
            ;;
    esac
}

# 清理本脚本管理的 bbr 快捷别名，避免误删用户自己的 alias
strip_bbr_alias_blocks() {
    local file="$1"

    awk '
    function flush_pending(    i) {
        for (i = 1; i <= pending_count; i++) print pending[i]
        pending_count = 0
        candidate = 0
    }
    function add_pending(line) {
        pending[++pending_count] = line
    }
    function strip_unquoted_comment(line,    i, c, out, in_single, in_double, escaped) {
        out = ""
        in_single = 0
        in_double = 0
        escaped = 0
        for (i = 1; i <= length(line); i++) {
            c = substr(line, i, 1)
            if (escaped) {
                out = out c
                escaped = 0
                continue
            }
            if (c == "\\" && in_double) {
                out = out c
                escaped = 1
                continue
            }
            if (c == "'"'"'" && !in_double) in_single = !in_single
            if (c == "\"" && !in_single) in_double = !in_double
            if (c == "#" && !in_single && !in_double) break
            out = out c
        }
        return out
    }
    function is_project_alias(line,    body) {
        body = strip_unquoted_comment(line)
        return body ~ /^[[:space:]]*alias[[:space:]]+(bbr|dog)=/ &&
               (body ~ /(raw\.githubusercontent\.com|github\.com)\/(Eric86777\/vps-tcp-tune|flyto23\/bbr)\// ||
                body ~ /\/net-tcp-tune\.sh/) &&
               body ~ /net-tcp-tune\.sh/
    }
    function is_managed_comment(line) {
        return line ~ /^# >>> net-tcp-tune alias >>>/ ||
               line ~ /^# <<< net-tcp-tune alias <<</ ||
               line ~ /^# =+$/ ||
               line ~ /net-tcp-tune[[:space:]]+快捷别名/ ||
               line ~ /使用.*时间戳参数确保每次都获取最新版本/ ||
               line ~ /运行本地副本/ ||
               line ~ /每次运行自动从/
    }
    function is_end_marker(line) {
        return line ~ /^# <<< net-tcp-tune alias <<</
    }
    BEGIN {
        pending_count = 0
        drop_next_end_marker = 0
    }
    drop_next_end_marker && is_end_marker($0) {
        drop_next_end_marker = 0
        next
    }
    is_managed_comment($0) {
        add_pending($0)
        if (pending_count >= 12) flush_pending()
        next
    }
    pending_count > 0 {
        if (is_project_alias($0)) {
            pending_count = 0
            drop_next_end_marker = 1
            next
        }
        flush_pending()
    }
    is_project_alias($0) { drop_next_end_marker = 1; next }
    {
        print
    }
    END {
        flush_pending()
    }
    ' "$file"
}

rc_file_has_bbr_alias() {
    local rc_file="$1"
    [ -r "$rc_file" ] || return 2

    grep -qE '(^# >>> net-tcp-tune alias >>>|net-tcp-tune 快捷别名)' "$rc_file" 2>/dev/null && return 0

    awk '
    function strip_unquoted_comment(line,    i, c, out, in_single, in_double, escaped) {
        out = ""
        in_single = 0
        in_double = 0
        escaped = 0
        for (i = 1; i <= length(line); i++) {
            c = substr(line, i, 1)
            if (escaped) {
                out = out c
                escaped = 0
                continue
            }
            if (c == "\\" && in_double) {
                out = out c
                escaped = 1
                continue
            }
            if (c == "'"'"'" && !in_double) in_single = !in_single
            if (c == "\"" && !in_single) in_double = !in_double
            if (c == "#" && !in_single && !in_double) break
            out = out c
        }
        return out
    }
    function is_project_alias(line,    body) {
        body = strip_unquoted_comment(line)
        return body ~ /^[[:space:]]*alias[[:space:]]+(bbr|dog)=/ &&
               (body ~ /(raw\.githubusercontent\.com|github\.com)\/(Eric86777\/vps-tcp-tune|flyto23\/bbr)\// ||
                body ~ /\/net-tcp-tune\.sh/) &&
               body ~ /net-tcp-tune\.sh/
    }
    is_project_alias($0) { found = 1; exit }
    END { exit(found ? 0 : 1) }
    ' "$rc_file"
}

write_cleaned_rc_file() {
    local rc_file="$1"
    local new_content="$2"
    local backup_file="${rc_file}.bak.uninstall.$(date +%Y%m%d_%H%M%S).$$"

    if cmp -s "$rc_file" "$new_content"; then
        return 2
    fi

    if ! cp -p "$rc_file" "$backup_file" 2>/dev/null; then
        return 1
    fi

    if ! cat "$new_content" > "$rc_file"; then
        cat "$backup_file" > "$rc_file" 2>/dev/null || true
        return 1
    fi

    if ! cmp -s "$new_content" "$rc_file"; then
        cat "$backup_file" > "$rc_file" 2>/dev/null || true
        return 1
    fi

    return 0
}

#=============================================================================
# 脚本在线更新（从 GitHub 仓库拉取最新版）
#=============================================================================

# 写入指向本地副本的 bbr 别名
append_bbr_alias_block_local() {
    cat <<ALIAS_EOF
# >>> net-tcp-tune alias >>>
# ========================================
# net-tcp-tune 快捷别名 (自动添加)
# 运行本地副本，更新请执行 bbr 菜单 98
# ========================================
alias bbr="bash ${SCRIPT_LOCAL_PATH}"
# <<< net-tcp-tune alias <<<
ALIAS_EOF
}

# 把已存在的 bbr 别名改写为本地副本
ensure_local_bbr_alias() {
    local rc_file temp_file rc found=0 changed=0
    for rc_file in "$HOME/.bashrc" "$HOME/.bash_profile" "$HOME/.zshrc" "$HOME/.profile"; do
        [ -f "$rc_file" ] || continue
        rc_file_has_bbr_alias "$rc_file"
        [ $? -eq 0 ] || continue
        found=1
        temp_file=$(mktemp "${rc_file}.tmp.XXXXXX") || continue
        if ! strip_bbr_alias_blocks "$rc_file" > "$temp_file"; then
            rm -f "$temp_file"
            continue
        fi
        if [ -s "$temp_file" ] && [ "$(tail -c 1 "$temp_file" | wc -l | tr -d ' ')" -eq 0 ]; then
            printf '\n' >> "$temp_file"
        fi
        append_bbr_alias_block_local >> "$temp_file"
        write_cleaned_rc_file "$rc_file" "$temp_file"
        rc=$?
        rm -f "$temp_file"
        [ "$rc" -eq 0 ] && changed=1
    done
    if [ "$found" -eq 0 ]; then
        echo -e "  ${gl_huang}提示: 未找到 bbr 别名，可运行 install-alias.sh 安装${gl_bai}"
    elif [ "$changed" -eq 1 ]; then
        echo -e "  ${gl_lv}✅ bbr 别名已指向本地副本（source ~/.bashrc 或重新登录后生效）${gl_bai}"
    fi
}

update_script_self() {
    clear
    echo -e "${gl_kjlan}=== 更新脚本 ===${gl_bai}"
    echo ""
    echo -e "仓库地址: ${gl_zi}${SCRIPT_REPO_URL}${gl_bai}"
    echo -e "当前版本: ${gl_huang}v${SCRIPT_VERSION}${gl_bai} (${SCRIPT_LAST_UPDATE})"
    echo -e "安装路径: ${gl_zi}${SCRIPT_LOCAL_PATH}${gl_bai}"
    echo ""

    if ! command -v curl &>/dev/null && ! command -v wget &>/dev/null; then
        echo -e "${gl_hong}❌ 未找到 curl 或 wget，无法在线更新${gl_bai}"
        break_end
        return 1
    fi

    local tmp_file url ok=0
    tmp_file=$(mktemp /tmp/net-tcp-tune.update.XXXXXX) || {
        echo -e "${gl_hong}❌ 无法创建临时文件${gl_bai}"
        break_end
        return 1
    }
    url="${SCRIPT_RAW_BASE}/net-tcp-tune.sh?$(date +%s)"

    echo "正在从 GitHub 拉取最新版..."
    if command -v curl &>/dev/null; then
        curl -q -fsSL --connect-timeout 10 --max-time 180 "$url" -o "$tmp_file" && ok=1
    fi
    if [ "$ok" -ne 1 ] && command -v wget &>/dev/null; then
        wget -q --timeout=30 --tries=2 -O "$tmp_file" "$url" && ok=1
    fi
    if [ "$ok" -ne 1 ] || [ ! -s "$tmp_file" ]; then
        echo -e "${gl_hong}❌ 下载失败: ${url}${gl_bai}"
        rm -f "$tmp_file"
        break_end
        return 1
    fi

    if ! verify_downloaded_script "$tmp_file" || ! grep -q '^SCRIPT_VERSION=' "$tmp_file" || ! grep -q 'net-tcp-tune' "$tmp_file"; then
        echo -e "${gl_hong}❌ 下载内容校验失败（不是有效脚本），已取消，未修改任何文件${gl_bai}"
        rm -f "$tmp_file"
        break_end
        return 1
    fi
    if ! bash -n "$tmp_file"; then
        echo -e "${gl_hong}❌ 新脚本语法校验失败，已取消，未修改任何文件${gl_bai}"
        rm -f "$tmp_file"
        break_end
        return 1
    fi

    local new_version new_update
    new_version=$(sed -n 's/^SCRIPT_VERSION="\(.*\)"$/\1/p' "$tmp_file" | head -n 1)
    new_update=$(sed -n 's/^SCRIPT_LAST_UPDATE="\(.*\)"$/\1/p' "$tmp_file" | head -n 1)
    echo ""
    echo -e "最新版本: ${gl_lv}v${new_version}${gl_bai} (${new_update})"
    if [ "$new_version" = "$SCRIPT_VERSION" ]; then
        echo -e "${gl_huang}提示: 版本号与当前相同（可能已是最新，或仓库刚更新未改版本号）${gl_bai}"
    fi
    echo ""

    local confirm_update
    read -e -p "$(echo -e "${gl_huang}确认安装到 ${SCRIPT_LOCAL_PATH}？(Y/n): ${gl_bai}")" confirm_update
    case "${confirm_update:-Y}" in
        [Yy]) ;;
        *)
            echo "已取消"
            rm -f "$tmp_file"
            break_end
            return 1
            ;;
    esac

    local backup_file=""
    if [ -f "$SCRIPT_LOCAL_PATH" ]; then
        backup_file="${SCRIPT_LOCAL_PATH}.bak.$(date +%Y%m%d_%H%M%S)"
        if ! cp -p "$SCRIPT_LOCAL_PATH" "$backup_file"; then
            echo -e "${gl_hong}❌ 备份旧版本失败，已取消${gl_bai}"
            rm -f "$tmp_file"
            break_end
            return 1
        fi
        echo -e "  已备份旧版本: ${backup_file}"
    fi

    if ! install -m 755 "$tmp_file" "$SCRIPT_LOCAL_PATH"; then
        echo -e "${gl_hong}❌ 写入 ${SCRIPT_LOCAL_PATH} 失败${gl_bai}"
        [ -n "$backup_file" ] && cp -p "$backup_file" "$SCRIPT_LOCAL_PATH" 2>/dev/null
        rm -f "$tmp_file"
        break_end
        return 1
    fi
    rm -f "$tmp_file"
    echo -e "${gl_lv}✅ 已更新: ${SCRIPT_LOCAL_PATH}${gl_bai}"

    ensure_local_bbr_alias

    echo ""
    local run_now
    read -e -p "$(echo -e "${gl_huang}是否立即运行新版本？(Y/n): ${gl_bai}")" run_now
    case "${run_now:-Y}" in
        [Yy])
            echo ""
            echo "正在启动新版本..."
            exec bash "$SCRIPT_LOCAL_PATH"
            ;;
        *)
            echo "稍后运行 bbr 即可使用新版本"
            ;;
    esac
    break_end
}

# 完全卸载脚本所有内容
uninstall_all() {
    clear
    echo -e "${gl_hong}╔════════════════════════════════════════════╗${gl_bai}"
    echo -e "${gl_hong}║       完全卸载脚本 - 所有内容清理          ║${gl_bai}"
    echo -e "${gl_hong}╚════════════════════════════════════════════╝${gl_bai}"
    echo ""
    echo -e "${gl_huang}⚠️  警告：此操作将完全卸载脚本的所有内容，包括：${gl_bai}"
    echo ""
    echo "  • XanMod 内核（如果已安装）"
    echo "  • bbr 快捷别名"
    echo "  • 本地脚本副本（${SCRIPT_LOCAL_PATH}）"
    echo "  • 所有 BBR/网络优化配置"
    echo "  • 所有 sysctl 配置文件"
    echo "  • MTU优化和持久化服务"
    echo "  • DNS净化和持久化服务"
    echo "  • 其他相关配置文件和备份"
    echo ""
    echo -e "${gl_hong}此操作不可逆！${gl_bai}"
    echo ""
    
    read -e -p "确定要完全卸载吗？(输入 YES 确认): " confirm
    
    if [ "$confirm" != "YES" ]; then
        echo -e "${gl_huang}已取消卸载${gl_bai}"
        break_end
        return 1
    fi
    
    echo ""
    echo -e "${gl_kjlan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"
    echo -e "${gl_kjlan}开始完全卸载...${gl_bai}"
    echo ""
    
    local uninstall_count=0
    local xanmod_removed=0
    
    # 1. 卸载 XanMod 内核
    echo -e "${gl_huang}[1/8] 检查并卸载 XanMod 内核...${gl_bai}"
    if dpkg -l | grep -qE '^ii\s+linux-.*xanmod'; then
        # 安全检查：确认有回退内核
        local non_xanmod_kernels=$(dpkg -l 2>/dev/null | grep '^ii' | grep 'linux-image-' | grep -v 'xanmod' | grep -v 'dbg' | wc -l)
        if [ "$non_xanmod_kernels" -eq 0 ]; then
            echo -e "  ${gl_hong}❌ 未检测到回退内核，跳过卸载以防系统无法启动${gl_bai}"
            echo -e "  ${gl_huang}请先安装默认内核: apt install -y linux-image-amd64${gl_bai}"
        else
            echo "  正在卸载 XanMod 内核..."
            if apt purge -y 'linux-*xanmod*' > /dev/null 2>&1; then
                update-grub > /dev/null 2>&1
            else
                echo -e "  ${gl_hong}❌ XanMod 内核卸载命令执行失败，请手动检查${gl_bai}"
            fi
            if dpkg -l | grep -qE '^ii\s+linux-.*xanmod'; then
                echo -e "  ${gl_hong}❌ 仍检测到 XanMod 内核，请手动检查${gl_bai}"
            else
                echo -e "  ${gl_lv}✅ XanMod 内核已卸载${gl_bai}"
                uninstall_count=$((uninstall_count + 1))
                xanmod_removed=1
            fi
        fi
    else
        echo -e "  ${gl_huang}未检测到 XanMod 内核，跳过${gl_bai}"
    fi
    echo ""
    
    # 2. 卸载 bbr 快捷别名
    echo -e "${gl_huang}[2/8] 卸载 bbr 快捷别名...${gl_bai}"
    
    # 检查所有可能的配置文件
    local rc_files=("$HOME/.bashrc" "$HOME/.bash_profile" "$HOME/.zshrc" "$HOME/.profile")
    local alias_found=0
    local alias_removed=0
    
    for rc_file in "${rc_files[@]}"; do
        if [ ! -f "$rc_file" ]; then
            continue
        fi
        
        # 检查是否存在本脚本管理的别名（不清理用户自定义 bbr）
        rc_file_has_bbr_alias "$rc_file"
        local has_alias_rc=$?
        if [ "$has_alias_rc" -eq 2 ]; then
            echo -e "  ${gl_hong}❌ 无法读取 $(basename "$rc_file")，跳过${gl_bai}"
            continue
        fi
        if [ "$has_alias_rc" -eq 0 ]; then
            alias_found=1

            local temp_file
            temp_file=$(mktemp "${rc_file}.tmp.XXXXXX") || {
                echo -e "  ${gl_hong}❌ 无法创建临时文件，跳过 $(basename "$rc_file")${gl_bai}"
                continue
            }

            if ! strip_bbr_alias_blocks "$rc_file" > "$temp_file"; then
                rm -f "$temp_file"
                echo -e "  ${gl_hong}❌ 清理 $(basename "$rc_file") 失败${gl_bai}"
                continue
            fi

            write_cleaned_rc_file "$rc_file" "$temp_file"
            local clean_rc=$?
            rm -f "$temp_file"

            if [ $clean_rc -eq 0 ]; then
                alias_removed=1
                echo -e "  ${gl_lv}✅ 已从 $(basename "$rc_file") 中删除别名${gl_bai}"
            elif [ $clean_rc -ne 2 ]; then
                echo -e "  ${gl_hong}❌ 写回 $(basename "$rc_file") 失败，已尝试恢复备份${gl_bai}"
            fi
        fi
    done
    
    if [ $alias_removed -eq 1 ]; then
        # 立即尝试取消当前会话中的别名（对子 shell 有效）
        unalias bbr 2>/dev/null || true
        
        echo -e "  ${gl_lv}✅ bbr 快捷别名已卸载${gl_bai}"
        echo -e "  ${gl_huang}提示: 配置文件已清理。如当前终端仍可执行 bbr，请手动运行: ${gl_kjlan}unalias bbr${gl_huang}${gl_bai}"
        echo -e "  ${gl_huang}如需在新终端生效，请执行: ${gl_bai}source ~/.bashrc${gl_huang} 或 ${gl_bai}source ~/.zshrc${gl_bai}"
        uninstall_count=$((uninstall_count + 1))
    elif [ $alias_found -eq 1 ]; then
        # 即使删除失败，也尝试取消当前会话的别名
        unalias bbr 2>/dev/null || true
        echo -e "  ${gl_huang}警告: 检测到别名但删除失败，请手动检查配置文件${gl_bai}"
        echo -e "  ${gl_huang}已尝试取消当前会话的别名${gl_bai}"
    else
        # 以防万一，取消当前会话的别名
        unalias bbr 2>/dev/null || true
        echo -e "  ${gl_huang}未检测到 bbr 别名，跳过${gl_bai}"
    fi
    echo ""
    
    # 3. 清理 sysctl 配置文件
    echo -e "${gl_huang}[3/8] 清理 sysctl 配置文件...${gl_bai}"
    local sysctl_files=(
        "$SYSCTL_CONF"
        "$SYSCTL_CONF_LEGACY"
        "/etc/sysctl.d/99-sysctl.conf"
        "/etc/sysctl.d/999-net-bbr-fq.conf"
    )
    
    local sysctl_cleaned=0
    for file in "${sysctl_files[@]}"; do
        if [ -f "$file" ]; then
            rm -f "$file"
            sysctl_cleaned=$((sysctl_cleaned + 1))
        fi
    done
    
    # 清理 IPv6 管理相关配置
    if [ -f "/etc/sysctl.d/99-disable-ipv6.conf" ]; then
        rm -f "/etc/sysctl.d/99-disable-ipv6.conf"
        sysctl_cleaned=$((sysctl_cleaned + 1))
    fi
    if [ -f "/etc/sysctl.d/.ipv6-state-backup.conf" ]; then
        rm -f "/etc/sysctl.d/.ipv6-state-backup.conf"
        sysctl_cleaned=$((sysctl_cleaned + 1))
    fi
    
    # 恢复 sysctl.conf 原始配置（如果有备份）
    if [ -f "/etc/sysctl.conf.bak.original" ]; then
        cp /etc/sysctl.conf "/etc/sysctl.conf.bak.$(date +%Y%m%d_%H%M%S)" 2>/dev/null
        cp /etc/sysctl.conf.bak.original /etc/sysctl.conf 2>/dev/null
        rm -f /etc/sysctl.conf.bak.original
        sysctl_cleaned=$((sysctl_cleaned + 1))
    fi
    
    if [ $sysctl_cleaned -gt 0 ]; then
        echo -e "  ${gl_lv}✅ 已清理 $sysctl_cleaned 个配置文件${gl_bai}"
        uninstall_count=$((uninstall_count + 1))
    else
        echo -e "  ${gl_huang}未找到需要清理的配置文件${gl_bai}"
    fi
    echo ""
    
    # 4. 清理 XanMod 软件源
    echo -e "${gl_huang}[4/8] 清理 XanMod 软件源...${gl_bai}"
    local repo_files=(
        "/etc/apt/sources.list.d/xanmod-release.list"
        "/usr/share/keyrings/xanmod-archive-keyring.gpg"
    )
    
    local repo_cleaned=0
    for file in "${repo_files[@]}"; do
        if [ -f "$file" ]; then
            rm -f "$file"
            repo_cleaned=$((repo_cleaned + 1))
        fi
    done
    
    if [ $repo_cleaned -gt 0 ]; then
        echo -e "  ${gl_lv}✅ 已清理 XanMod 软件源${gl_bai}"
        uninstall_count=$((uninstall_count + 1))
    else
        echo -e "  ${gl_huang}未找到 XanMod 软件源${gl_bai}"
    fi
    echo ""
    
    # 5. 清理持久化服务和优化配置（功能3/4/5）
    echo -e "${gl_huang}[5/8] 清理持久化服务和优化配置...${gl_bai}"
    local persist_cleaned=0

    # 功能4: MTU优化 — 恢复路由/链路MTU + 清理服务
    if [ -f /usr/local/etc/mtu-optimize.conf ]; then
        . /usr/local/etc/mtu-optimize.conf 2>/dev/null
        # 恢复默认路由 MTU
        local def_rt
        def_rt=$(ip -4 route show default 2>/dev/null | head -1)
        if [ -n "$def_rt" ]; then
            local cl_rt
            cl_rt=$(echo "$def_rt" | sed 's/ mtu lock [0-9]*//;s/ mtu [0-9]*//')
            ip route replace $cl_rt 2>/dev/null || true
        fi
        # 恢复链路 MTU
        if [ -n "${DEFAULT_IFACE:-}" ] && [ -n "${ORIGINAL_MTU:-}" ]; then
            ip link set dev "$DEFAULT_IFACE" mtu "$ORIGINAL_MTU" 2>/dev/null || true
        fi
        rm -f /usr/local/etc/mtu-optimize.conf
        persist_cleaned=$((persist_cleaned + 1))
        echo -e "  ${gl_lv}✓ MTU优化已恢复${gl_bai}"
    fi
    if [ -f /etc/systemd/system/mtu-optimize-persist.service ]; then
        systemctl disable mtu-optimize-persist.service 2>/dev/null || true
        rm -f /etc/systemd/system/mtu-optimize-persist.service
        rm -f /usr/local/bin/mtu-optimize-apply.sh
        persist_cleaned=$((persist_cleaned + 1))
    fi

    # 功能3: BBR优化持久化
    if [ -f /etc/systemd/system/bbr-optimize-persist.service ]; then
        systemctl disable bbr-optimize-persist.service 2>/dev/null || true
        rm -f /etc/systemd/system/bbr-optimize-persist.service
        rm -f /usr/local/bin/bbr-optimize-apply.sh
        persist_cleaned=$((persist_cleaned + 1))
        echo -e "  ${gl_lv}✓ BBR持久化服务已移除${gl_bai}"
    fi

    # 功能5: DNS净化持久化
    if [ -f /etc/systemd/system/dns-purify-persist.service ]; then
        systemctl disable dns-purify-persist.service 2>/dev/null || true
        rm -f /etc/systemd/system/dns-purify-persist.service
        rm -f /usr/local/bin/dns-purify-apply.sh
        persist_cleaned=$((persist_cleaned + 1))
        echo -e "  ${gl_lv}✓ DNS持久化服务已移除${gl_bai}"
    fi

    if [ -x /usr/local/libexec/net-tcp-boot-recovery ] &&
        grep -q 'NET_TCP_BOOT_RECOVERY_V1' /usr/local/libexec/net-tcp-boot-recovery; then
        /usr/local/libexec/net-tcp-boot-recovery --remove-app-guards || echo '部分自定义启动保护已保留，请人工检查' >&2
    fi

    # 清理旧版 iptables set-mss 规则（功能4旧版兼容）
    if command -v iptables &>/dev/null; then
        local tag="net-tcp-tune-mss" del_v
        while read -r del_v; do
            [ -n "$del_v" ] || continue
            iptables -t mangle -D OUTPUT -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss "$del_v" -m comment --comment "$tag" 2>/dev/null || true
        done < <(iptables -t mangle -S OUTPUT 2>/dev/null | grep "$tag" | sed -n 's/.*--set-mss \([0-9]\+\).*/\1/p')
        while read -r del_v; do
            [ -n "$del_v" ] || continue
            iptables -t mangle -D POSTROUTING -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss "$del_v" -m comment --comment "$tag" 2>/dev/null || true
        done < <(iptables -t mangle -S POSTROUTING 2>/dev/null | grep "$tag" | sed -n 's/.*--set-mss \([0-9]\+\).*/\1/p')
    fi

    if [ $persist_cleaned -gt 0 ]; then
        systemctl daemon-reload 2>/dev/null || true
        echo -e "  ${gl_lv}✅ 已清理 $persist_cleaned 个持久化组件${gl_bai}"
        uninstall_count=$((uninstall_count + 1))
    else
        echo -e "  ${gl_huang}未找到持久化服务${gl_bai}"
    fi
    echo ""

    # 6. 清理其他临时文件和备份
    echo -e "${gl_huang}[6/8] 清理临时文件和备份...${gl_bai}"
    local temp_cleaned=0

    # 临时文件（glob 展开后逐个删除）
    local tmp_file
    for tmp_file in /tmp/socks5_proxy_*.sh; do
        if [ -f "$tmp_file" ]; then
            rm -f "$tmp_file" 2>/dev/null
            temp_cleaned=$((temp_cleaned + 1))
        fi
    done

    # 本地安装副本（菜单 98 更新到本地的脚本）
    if [ -f "$SCRIPT_LOCAL_PATH" ]; then
        rm -f "$SCRIPT_LOCAL_PATH" 2>/dev/null
        temp_cleaned=$((temp_cleaned + 1))
    fi
    for tmp_file in "${SCRIPT_LOCAL_PATH}.bak."*; do
        [ -f "$tmp_file" ] || continue
        rm -f "$tmp_file" 2>/dev/null
        temp_cleaned=$((temp_cleaned + 1))
    done

    # 备份目录（显式处理，不走 glob）
    if [ -d "/root/.realm_backup" ]; then
        rm -rf "/root/.realm_backup" 2>/dev/null
        temp_cleaned=$((temp_cleaned + 1))
    fi
    
    if [ $temp_cleaned -gt 0 ]; then
        echo -e "  ${gl_lv}✅ 已清理临时文件${gl_bai}"
    else
        echo -e "  ${gl_huang}未找到临时文件${gl_bai}"
    fi
    echo ""
    
    # 7. 应用 sysctl 更改
    echo -e "${gl_huang}[7/8] 应用系统配置更改...${gl_bai}"
    sysctl --system > /dev/null 2>&1
    echo -e "  ${gl_lv}✅ 系统配置已重置${gl_bai}"
    echo ""

    # 8. 清理功能5 DNS净化残留配置
    echo -e "${gl_huang}[8/8] 清理 DNS 净化残留配置...${gl_bai}"
    local dns_cleaned=0
    # NetworkManager DNS 委托配置
    if [ -f /etc/NetworkManager/conf.d/99-dns-purify.conf ]; then
        rm -f /etc/NetworkManager/conf.d/99-dns-purify.conf
        systemctl reload NetworkManager 2>/dev/null || true
        dns_cleaned=$((dns_cleaned + 1))
    fi
    # systemd-networkd drop-in
    local sd_dir
    for sd_dir in /etc/systemd/network /run/systemd/network /usr/lib/systemd/network; do
        local dropin_f
        for dropin_f in "$sd_dir"/*.network.d/dns-purify-override.conf; do
            [ -f "$dropin_f" ] || continue
            rm -f "$dropin_f"
            rmdir "$(dirname "$dropin_f")" 2>/dev/null || true
            dns_cleaned=$((dns_cleaned + 1))
        done
    done
    if [ $dns_cleaned -gt 0 ]; then
        echo -e "  ${gl_lv}✅ 已清理 DNS 净化残留配置${gl_bai}"
    else
        echo -e "  ${gl_huang}未找到 DNS 净化残留${gl_bai}"
    fi
    echo ""

    # 完成提示
    echo -e "${gl_kjlan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"
    echo -e "${gl_lv}✅ 完全卸载完成！${gl_bai}"
    echo ""
    echo -e "${gl_huang}卸载统计：${gl_bai}"
    echo "  • 已卸载 $uninstall_count 个主要组件"
    echo ""
    echo -e "${gl_huang}⚠️  重要提示：${gl_bai}"
    echo "  1. 如果卸载了内核，请重启系统以生效"
    echo "  2. 如果卸载了别名，请重新加载 Shell 配置："
    echo -e "     ${gl_kjlan}source ~/.bashrc${gl_bai} 或 ${gl_kjlan}source ~/.zshrc${gl_bai}"
    echo "  3. 如需重新安装，请重新运行脚本"
    echo ""
    
    # 询问是否重启
    if [ "$xanmod_removed" -eq 1 ]; then
        echo -e "${gl_huang}检测到已卸载内核，建议重启系统${gl_bai}"
        read -e -p "是否立即重启？(Y/n): " reboot_confirm
        case "${reboot_confirm:-Y}" in
            [Yy])
                echo ""
                echo -e "${gl_lv}✅ 完全卸载完成，正在重启系统...${gl_bai}"
                sleep 2
                server_reboot
                ;;
            *)
                echo ""
                echo -e "${gl_huang}请稍后手动重启系统${gl_bai}"
                echo -e "${gl_lv}✅ 完全卸载完成，脚本即将退出${gl_bai}"
                sleep 2
                exit 0
                ;;
        esac
    else
        if dpkg -l | grep -qE '^ii\s+linux-.*xanmod'; then
            echo ""
            echo -e "${gl_hong}❌ 检测到 XanMod 内核仍存在，请手动检查${gl_bai}"
            sleep 2
            exit 1
        else
            echo ""
            echo -e "${gl_lv}✅ 完全卸载完成，脚本即将退出${gl_bai}"
            sleep 2
            exit 0
        fi
    fi
}

#=============================================================================
# Cloudflare Tunnel 通用 Helper 函数族
# 供 一键反代 使用
# 统一目录规范:/etc/cloudflared/{cert.pem,credentials/,configs/}
#=============================================================================

# ---- 统一路径常量 ----
CF_HOME="/etc/cloudflared"
CF_CREDENTIALS_DIR="$CF_HOME/credentials"
CF_CONFIGS_DIR="$CF_HOME/configs"
CF_CERT_FILE="$CF_HOME/cert.pem"
CF_LEGACY_HOME="/root/.cloudflared"
CF_LEGACY_CERT="$CF_LEGACY_HOME/cert.pem"
CF_BINARY_PATH="/usr/local/bin/cloudflared"

# 初始化目录骨架
cf_helper_init_dirs() {
    mkdir -p "$CF_CREDENTIALS_DIR" "$CF_CONFIGS_DIR"
    chmod 700 "$CF_CREDENTIALS_DIR" 2>/dev/null
    chmod 755 "$CF_HOME" "$CF_CONFIGS_DIR" 2>/dev/null
    return 0
}

# 安装 cloudflared 二进制(支持 amd64/arm64/arm/386)
# 用法:cf_helper_install_binary [--force]
cf_helper_install_binary() {
    local force=false
    [ "$1" = "--force" ] && force=true

    if [ "$force" = false ] && command -v cloudflared &>/dev/null; then
        local current_ver
        current_ver=$(cloudflared --version 2>/dev/null | head -1)
        echo -e "${gl_lv}✅ cloudflared 已安装:${current_ver}${gl_bai}"
        return 0
    fi

    local arch
    arch=$(uname -m)
    local asset
    case "$arch" in
        x86_64|amd64)           asset="cloudflared-linux-amd64" ;;
        aarch64|arm64)          asset="cloudflared-linux-arm64" ;;
        armv7l|armv6l|armhf|arm) asset="cloudflared-linux-arm" ;;
        i386|i686)              asset="cloudflared-linux-386" ;;
        *)
            echo -e "${gl_hong}❌ 不支持的 CPU 架构:$arch${gl_bai}"
            return 1
            ;;
    esac

    local url="https://github.com/cloudflare/cloudflared/releases/latest/download/${asset}"
    echo "正在下载 cloudflared (${asset})..."

    # 安全：mktemp 随机后缀替代 PID 后缀；chmod 755 显式保持与原先 umask 结果一致
    local tmp
    tmp=$(mktemp "${CF_BINARY_PATH}.tmp.XXXXXX") || {
        echo -e "${gl_hong}❌ 创建临时文件失败${gl_bai}"
        return 1
    }
    if wget -q --show-progress -O "$tmp" "$url" && [ -s "$tmp" ]; then
        chmod 755 "$tmp"
        mv "$tmp" "$CF_BINARY_PATH"
        local ver
        ver=$("$CF_BINARY_PATH" --version 2>/dev/null | head -1)
        echo -e "${gl_lv}✅ 安装成功:${ver}${gl_bai}"
        return 0
    else
        rm -f "$tmp"
        echo -e "${gl_hong}❌ 下载 cloudflared 失败${gl_bai}"
        return 1
    fi
}

# 确保 CF 账户已授权(cert.pem 存在)
# 不存在则引导用户走 cloudflared tunnel login
cf_helper_ensure_auth() {
    cf_helper_init_dirs

    # 优先看新路径,再看老路径
    if [ -f "$CF_CERT_FILE" ] || [ -f "$CF_LEGACY_CERT" ]; then
        return 0
    fi

    echo ""
    echo -e "${gl_huang}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"
    echo -e "${gl_huang}  需要授权 Cloudflare 账户${gl_bai}"
    echo -e "${gl_huang}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"
    echo ""
    echo "使用前提:"
    echo "  1. 已拥有一个域名(任何注册商购买均可)"
    echo "  2. 该域名的 NS 已托管到 Cloudflare"
    echo "     (cloudflare.com → Add a site → 按指引改 NS → 状态 Active)"
    echo ""
    echo "按回车将输出一个授权 URL,用浏览器打开登录并选择 zone。"
    echo "若条件不满足,按 Ctrl+C 退出。"
    echo ""
    read -e -p "继续: "

    cloudflared tunnel login
    if [ $? -ne 0 ]; then
        echo -e "${gl_hong}❌ 授权失败${gl_bai}"
        return 1
    fi

    # cloudflared 登录默认把 cert.pem 写到 /root/.cloudflared,同步到新路径
    if [ -f "$CF_LEGACY_CERT" ] && [ ! -f "$CF_CERT_FILE" ]; then
        cp "$CF_LEGACY_CERT" "$CF_CERT_FILE"
        chmod 600 "$CF_CERT_FILE"
    fi

    echo -e "${gl_lv}✅ Cloudflare 账户授权成功${gl_bai}"
    return 0
}

# 查询隧道 UUID(按名字)
# stdout: tunnel_id 或空
cf_helper_get_tunnel_id() {
    local tunnel_name=$1
    [ -z "$tunnel_name" ] && return 1
    cloudflared tunnel list 2>/dev/null | awk -v name="$tunnel_name" '
        NR > 1 && $2 == name { print $1; exit }
    '
}

# 创建隧道,同名冲突按 mode 处理
# 用法:cf_helper_create_tunnel <tunnel_name> [interactive|reuse|recreate]
# stdout: tunnel_id,返回 0 成功
cf_helper_create_tunnel() {
    local tunnel_name=$1
    local mode=${2:-interactive}

    # 名字格式校验
    if ! [[ "$tunnel_name" =~ ^[_a-zA-Z0-9][-_.a-zA-Z0-9]{0,63}$ ]]; then
        echo -e "${gl_hong}❌ 隧道名不合法(只允许 a-z A-Z 0-9 _ - . 开头非 -/.)${gl_bai}" >&2
        return 1
    fi

    local existing_id
    existing_id=$(cf_helper_get_tunnel_id "$tunnel_name")

    if [ -n "$existing_id" ]; then
        case "$mode" in
            reuse)
                echo "$existing_id"
                return 0
                ;;
            recreate)
                local svc="cloudflared-$tunnel_name"
                systemctl stop "$svc" 2>/dev/null
                systemctl disable "$svc" 2>/dev/null
                rm -f "/etc/systemd/system/${svc}.service"
                systemctl daemon-reload 2>/dev/null
                rm -f "$CF_CREDENTIALS_DIR/$existing_id.json" \
                      "$CF_LEGACY_HOME/$existing_id.json"
                cloudflared tunnel cleanup "$tunnel_name" 2>/dev/null
                sleep 1
                cloudflared tunnel delete -f "$tunnel_name" 2>/dev/null
                sleep 1
                ;;
            *)
                echo -e "${gl_huang}同名隧道已存在(ID: $existing_id)${gl_bai}" >&2
                echo "" >&2
                echo -e "${gl_huang}⚠️  注意:选 1 复用会让新配置覆盖老 ingress(调用方会写新 yaml)${gl_bai}" >&2
                echo -e "${gl_huang}    如果你想往老隧道加新域名/规则,请选 0 取消后到 Cloudflare 控制台修改,或选 2 删除重建${gl_bai}" >&2
                echo "" >&2
                echo "1. 复用现有隧道(新配置覆盖老配置)" >&2
                echo "2. 删除后重建" >&2
                echo "3. 取消" >&2
                local choice
                read -e -p "请选择 [1-3]: " choice
                case "$choice" in
                    1) echo "$existing_id"; return 0 ;;
                    2) cf_helper_create_tunnel "$tunnel_name" recreate; return $? ;;
                    *) return 1 ;;
                esac
                ;;
        esac
    fi

    local output
    output=$(cloudflared tunnel create "$tunnel_name" 2>&1)
    local rc=$?

    if [ $rc -ne 0 ]; then
        echo -e "${gl_hong}❌ 创建隧道失败:${gl_bai}" >&2
        echo "$output" >&2
        if echo "$output" | grep -qi "already exists"; then
            echo -e "${gl_huang}提示:CF 控制面或本地凭证残留,请到 Dashboard 手动清理或换名${gl_bai}" >&2
        fi
        return 1
    fi

    # 解析 UUID
    local new_id
    new_id=$(echo "$output" | grep -oE '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' | head -1)
    [ -z "$new_id" ] && new_id=$(cf_helper_get_tunnel_id "$tunnel_name")

    if [ -z "$new_id" ]; then
        echo -e "${gl_hong}❌ 创建成功但无法解析 tunnel_id${gl_bai}" >&2
        return 1
    fi

    # 凭证 JSON 从默认位置同步到 /etc/cloudflared/credentials/
    cf_helper_init_dirs
    local default_cred="$CF_LEGACY_HOME/$new_id.json"
    local target_cred="$CF_CREDENTIALS_DIR/$new_id.json"
    if [ -f "$default_cred" ] && [ ! -f "$target_cred" ]; then
        cp "$default_cred" "$target_cred"
        chmod 600 "$target_cred"
    fi

    echo "$new_id"
    return 0
}

# 路由 DNS(支持预检提示)
# 用法:cf_helper_route_dns <tunnel_id> <hostname>
cf_helper_route_dns() {
    local tunnel_id=$1
    local hostname=$2

    local output
    output=$(cloudflared tunnel route dns "$tunnel_id" "$hostname" 2>&1)
    local rc=$?

    if [ $rc -ne 0 ]; then
        if echo "$output" | grep -qi "already exists"; then
            echo -e "${gl_huang}⚠️  域名 $hostname 已有冲突 DNS 记录${gl_bai}" >&2
            echo -e "${gl_huang}   请到 CF Dashboard 手动删除旧记录,或改用其他子域名${gl_bai}" >&2
        else
            echo -e "${gl_hong}❌ DNS 路由失败:${gl_bai}" >&2
            echo "$output" >&2
        fi
        return 1
    fi
    return 0
}

# 生成 config.yml(接受 ingress 规则数组,每项格式 hostname|path|service)
# 用法:
#   rules=("sub.example.com||http://127.0.0.1:3001")
#   cf_helper_write_config <config_file> <tunnel_id> <cred_file> "${rules[@]}"
cf_helper_write_config() {
    local config_file=$1
    local tunnel_id=$2
    local cred_file=$3
    shift 3
    local rules=("$@")

    local tmp
    tmp=$(mktemp)
    {
        echo "tunnel: $tunnel_id"
        echo "credentials-file: $cred_file"
        echo ""
        echo "ingress:"
        local rule host path svc
        for rule in "${rules[@]}"; do
            IFS='|' read -r host path svc <<< "$rule"
            echo "  - hostname: $host"
            if [ -n "$path" ]; then
                # path 前缀自动加 ^(Go 正则前缀匹配)
                [[ "$path" != ^* ]] && path="^${path}"
                echo "    path: $path"
            fi
            echo "    service: $svc"
        done
        echo "  - service: http_status:404"
    } > "$tmp"

    # ingress validate(预飞检查)
    if cloudflared tunnel --config "$tmp" ingress validate &>/dev/null; then
        mv "$tmp" "$config_file"
        chmod 644 "$config_file"
        return 0
    else
        echo -e "${gl_hong}❌ ingress 配置校验失败:${gl_bai}" >&2
        cloudflared tunnel --config "$tmp" ingress validate 2>&1 >&2
        rm -f "$tmp"
        return 1
    fi
}

# 写 systemd unit + enable + start + 活性校验
# 用法:cf_helper_write_systemd <tunnel_name> <config_file> [description]
cf_helper_write_systemd() {
    local tunnel_name=$1
    local config_file=$2
    local description=${3:-"Cloudflare Tunnel: $tunnel_name"}
    local service_name="cloudflared-$tunnel_name"
    local service_file="/etc/systemd/system/${service_name}.service"

    # 对 Description 做防御性转义:剥离可能被 systemd 解析的 $ ` " 等
    local safe_desc="${description//\$/}"
    safe_desc="${safe_desc//\`/}"
    safe_desc="${safe_desc//\"/}"

    cat > "$service_file" << SVCEOF
[Unit]
Description=$safe_desc
After=network-online.target
Wants=network-online.target

[Service]
Type=notify
ExecStart=$CF_BINARY_PATH --config "$config_file" --no-autoupdate tunnel run
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
SVCEOF

    systemctl daemon-reload
    systemctl enable "$service_name" 2>/dev/null
    systemctl start "$service_name"

    # 轮询最多 10 秒,慢 VPS 友好(原 sleep 3 对慢 VPS 不够)
    local i
    for i in 1 2 3 4 5 6 7 8 9 10; do
        sleep 1
        systemctl is-active --quiet "$service_name" && break
    done

    if systemctl is-active --quiet "$service_name"; then
        echo -e "${gl_lv}✅ 服务启动成功:$service_name${gl_bai}"
        return 0
    else
        echo -e "${gl_hong}❌ 服务启动失败,最近 20 行日志:${gl_bai}" >&2
        journalctl -u "$service_name" -n 20 --no-pager 2>/dev/null >&2
        return 1
    fi
}

# 从 systemd unit 解析 --config 路径
_cf_get_config_from_service() {
    local service=$1
    local unit="/etc/systemd/system/${service}.service"
    [ -f "$unit" ] || return 1

    local line config_arg
    line=$(grep -E 'ExecStart=.*--config([=[:space:]]|$)' "$unit" | head -1)
    [ -z "$line" ] && return 1

    config_arg="${line#*--config}"
    config_arg="${config_arg#=}"
    config_arg="${config_arg#"${config_arg%%[![:space:]]*}"}"

    case "$config_arg" in
        \"*) config_arg="${config_arg#\"}"; echo "${config_arg%%\"*}" ;;
        \'*) config_arg="${config_arg#\'}"; echo "${config_arg%%\'*}" ;;
        *) echo "${config_arg%%[[:space:]]*}" ;;
    esac
}

# 部署失败回滚:按已创建的资源逆序清理(解决 P0-3)
# 用法:_cf_rollback_partial_deploy <tunnel_name> <tunnel_id> [dns_domain] [config_file]
# 空字符串表示该步没完成,跳过对应清理
_cf_rollback_partial_deploy() {
    local tunnel_name=$1
    local tunnel_id=$2
    local dns_domain=$3
    local config_file=$4
    local service_name="cloudflared-$tunnel_name"

    echo ""
    echo -e "${gl_huang}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"
    echo -e "${gl_huang}  检测到部署失败,正在回滚...${gl_bai}"
    echo -e "${gl_huang}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"

    # 1. 停并删 systemd
    if [ -f "/etc/systemd/system/${service_name}.service" ]; then
        systemctl stop "$service_name" 2>/dev/null
        systemctl disable "$service_name" 2>/dev/null
        rm -f "/etc/systemd/system/${service_name}.service"
        systemctl daemon-reload 2>/dev/null
    fi

    # 2. 删 config yaml
    [ -n "$config_file" ] && [ -f "$config_file" ] && rm -f "$config_file"

    # 3. 删 CF 云端隧道 + 本地凭证
    if [ -n "$tunnel_id" ]; then
        # 先 soft delete,若有活跃连接 fallback force
        cloudflared tunnel delete "$tunnel_name" 2>/dev/null \
            || cloudflared tunnel delete -f "$tunnel_name" 2>/dev/null
        rm -f "$CF_CREDENTIALS_DIR/$tunnel_id.json" "$CF_LEGACY_HOME/$tunnel_id.json"
    fi

    # 4. DNS 记录需手动清(cloudflared 不支持自动删)
    if [ -n "$dns_domain" ]; then
        echo -e "${gl_huang}⚠️  DNS CNAME 需手动到 CF Dashboard 删除: $dns_domain${gl_bai}"
    fi

    echo -e "${gl_lv}✅ 已回滚,可重新尝试${gl_bai}"
}

# ---- [2] 添加新隧道(6 步向导) ----
cf_tunnel_add() {
    clear
    echo -e "${gl_kjlan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"
    echo -e "${gl_kjlan}  添加新隧道反代${gl_bai}"
    echo -e "${gl_kjlan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"
    echo ""

    # --- 前置检查 ---
    echo -e "${gl_zi}[前置检查]${gl_bai}"
    if ! command -v cloudflared &>/dev/null; then
        echo -e "  cloudflared: ${gl_huang}未安装${gl_bai}"
        local install_now
        read -e -p "  是否现在自动安装?(Y/n): " install_now
        if [[ ! "$install_now" =~ ^[Nn]$ ]]; then
            cf_helper_install_binary || { break_end; return 1; }
        else
            echo "已取消"; break_end; return 1
        fi
    else
        echo -e "  cloudflared: ${gl_lv}✅ 已安装${gl_bai}"
    fi

    if [ ! -f "$CF_CERT_FILE" ] && [ ! -f "$CF_LEGACY_CERT" ]; then
        echo -e "  CF 授权: ${gl_huang}未登录${gl_bai}"
        echo ""
        cf_helper_ensure_auth || { break_end; return 1; }
    else
        echo -e "  CF 授权: ${gl_lv}✅ 已登录${gl_bai}"
    fi
    echo ""

    # --- 步骤 1/6 ---
    echo -e "${gl_zi}[步骤 1/6] 隧道名称${gl_bai}"
    echo "  只允许 a-z A-Z 0-9 _ - .,开头非 -/.,长度 1-64"
    local default_name="tunnel-$(openssl rand -hex 4 2>/dev/null || echo $RANDOM)"
    echo "  留空使用随机: $default_name"
    echo ""
    local tunnel_name
    while true; do
        read -e -p "请输入: " tunnel_name
        [ -z "$tunnel_name" ] && tunnel_name="$default_name"
        if [[ ! "$tunnel_name" =~ ^[_a-zA-Z0-9][-_.a-zA-Z0-9]{0,63}$ ]]; then
            echo -e "${gl_hong}❌ 名字不合法${gl_bai}"
            continue
        fi
        # 防止和已存在服务重名
        if systemctl list-unit-files "cloudflared-${tunnel_name}.service" 2>/dev/null | grep -q "cloudflared-${tunnel_name}"; then
            echo -e "${gl_hong}❌ 已有同名隧道服务,换一个名字${gl_bai}"
            continue
        fi
        break
    done
    echo -e "${gl_lv}✅ $tunnel_name${gl_bai}"
    echo ""

    # --- 步骤 2/6 ---
    echo -e "${gl_zi}[步骤 2/6] 反代目标${gl_bai}"
    echo "  支持:端口号(如 3001,自动补 http://127.0.0.1:)或完整 URL(http(s)://host:port)"
    echo ""
    local backend
    while true; do
        read -e -p "请输入: " backend
        if [ -z "$backend" ]; then
            echo -e "${gl_hong}❌ 不能为空${gl_bai}"; continue
        fi
        if [[ "$backend" =~ ^[0-9]+$ ]]; then
            if [ "$backend" -lt 1 ] || [ "$backend" -gt 65535 ]; then
                echo -e "${gl_hong}❌ 端口超范围${gl_bai}"; continue
            fi
            local port=$backend
            backend="http://127.0.0.1:$backend"
            if ss -tuln 2>/dev/null | grep -q ":$port " || netstat -tuln 2>/dev/null | grep -q ":$port "; then
                echo -e "${gl_lv}  ✅ 端口 $port 监听中${gl_bai}"
            else
                echo -e "${gl_huang}  ⚠️  端口 $port 当前没有服务监听${gl_bai}"
                local cont
                read -e -p "  是否继续?(y/N): " cont
                [[ ! "$cont" =~ ^[Yy]$ ]] && continue
            fi
        elif [[ "$backend" =~ ^https?://.+ ]]; then
            :
        else
            echo -e "${gl_hong}❌ 格式不对,请输入端口号或 http(s):// URL${gl_bai}"; continue
        fi
        break
    done
    echo -e "${gl_lv}✅ $backend${gl_bai}"
    echo ""

    # --- 步骤 3/6 ---
    echo -e "${gl_zi}[步骤 3/6] 路由模式${gl_bai}"
    echo ""
    echo "  1. 整站反代(推荐) ← 域名所有请求转发到上面的地址"
    echo "  2. 按路径分流(高级) ← 不同 URL 路径分给不同后端"
    echo ""
    local route_mode
    read -e -p "请选择 [1/2](默认 1): " route_mode
    route_mode=${route_mode:-1}

    local -a extra_rules=()
    if [ "$route_mode" = "2" ]; then
        echo ""
        echo "开始添加路由规则(每条 = 一个「路径前缀 → 后端」)"
        local rule_num=1 rule_path rule_backend
        while true; do
            echo ""
            echo "第 $rule_num 条规则:"
            read -e -p "  路径前缀(如 /api): " rule_path
            if [ -z "$rule_path" ]; then
                echo -e "${gl_hong}  ❌ 路径不能为空${gl_bai}"; continue
            fi
            [[ "$rule_path" != /* ]] && rule_path="/$rule_path"
            read -e -p "  这些请求转给哪(端口号或完整地址): " rule_backend
            if [[ "$rule_backend" =~ ^[0-9]+$ ]]; then
                # P1-6 修复:端口号需在 1-65535 范围
                if [ "$rule_backend" -lt 1 ] || [ "$rule_backend" -gt 65535 ]; then
                    echo -e "${gl_hong}  ❌ 端口超范围(1-65535)${gl_bai}"; continue
                fi
                rule_backend="http://127.0.0.1:$rule_backend"
            elif [[ ! "$rule_backend" =~ ^https?:// ]]; then
                echo -e "${gl_hong}  ❌ 后端格式错${gl_bai}"; continue
            fi
            # 路径长度防御:超长路径(>256)拒绝
            if [ ${#rule_path} -gt 256 ]; then
                echo -e "${gl_hong}  ❌ 路径过长${gl_bai}"; continue
            fi
            extra_rules+=("$rule_path|$rule_backend")
            echo -e "${gl_lv}  ✅ $rule_path → $rule_backend${gl_bai}"
            rule_num=$((rule_num + 1))
            local more
            read -e -p "继续加一条?(y/N): " more
            [[ ! "$more" =~ ^[Yy]$ ]] && break
        done
        echo ""
        echo -e "${gl_huang}兜底规则将自动加:其他所有路径 → $backend${gl_bai}"
    fi
    echo ""

    # --- 步骤 4/6 ---
    echo -e "${gl_zi}[步骤 4/6] 域名${gl_bai}"
    echo "  必须已托管到 Cloudflare(否则 DNS 路由会失败)"
    echo ""
    local domain
    while true; do
        read -e -p "请输入 FQDN (如 sub.example.com): " domain
        if [ -z "$domain" ]; then
            echo -e "${gl_hong}❌ 域名不能为空${gl_bai}"; continue
        fi
        if ! [[ "$domain" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)+$ ]]; then
            echo -e "${gl_hong}❌ 域名格式不对${gl_bai}"; continue
        fi
        break
    done
    echo -e "${gl_lv}✅ $domain${gl_bai}"
    echo ""

    # 生成 ingress 规则
    local -a rules=()
    if [ "$route_mode" = "2" ]; then
        local ex
        for ex in "${extra_rules[@]}"; do
            rules+=("$domain|${ex%%|*}|${ex#*|}")
        done
        rules+=("$domain||$backend")
    else
        rules+=("$domain||$backend")
    fi

    # --- 步骤 5/6 ---
    echo -e "${gl_zi}[步骤 5/6] 确认${gl_bai}"
    echo ""
    echo "  隧道名称: $tunnel_name"
    echo "  域名:     https://$domain"
    echo "  ingress 规则:"
    local r host path svc
    for r in "${rules[@]}"; do
        IFS='|' read -r host path svc <<< "$r"
        if [ -n "$path" ]; then
            echo "    $path → $svc"
        else
            echo "    * (兜底) → $svc"
        fi
    done
    echo ""
    local confirm
    read -e -p "确认开始部署?(Y/n): " confirm
    if [[ "$confirm" =~ ^[Nn]$ ]]; then
        echo "已取消"; break_end; return 1
    fi
    echo ""

    # --- 步骤 6/6:执行 ---
    echo -e "${gl_zi}[步骤 6/6] 部署中${gl_bai}"
    echo ""

    echo "  [1/5] 创建隧道..."
    local tunnel_id
    tunnel_id=$(cf_helper_create_tunnel "$tunnel_name")
    if [ -z "$tunnel_id" ]; then
        echo -e "${gl_hong}    ❌ 失败${gl_bai}"; break_end; return 1
    fi
    echo -e "${gl_lv}    ✅ Tunnel ID: $tunnel_id${gl_bai}"

    echo "  [2/5] 路由 DNS..."
    if ! cf_helper_route_dns "$tunnel_id" "$domain"; then
        # P0-3 修复:回滚已创建的隧道
        _cf_rollback_partial_deploy "$tunnel_name" "$tunnel_id" "" ""
        break_end; return 1
    fi
    echo -e "${gl_lv}    ✅ CNAME: $domain → ${tunnel_id}.cfargotunnel.com${gl_bai}"

    echo "  [3/5] 写 config yaml..."
    local config_file="$CF_CONFIGS_DIR/$tunnel_name.yml"
    # P1-8 修复:严格校验 cred_file 必须存在,否则 systemd 启动必然失败
    local cred_file="$CF_CREDENTIALS_DIR/$tunnel_id.json"
    [ ! -f "$cred_file" ] && cred_file="$CF_LEGACY_HOME/$tunnel_id.json"
    if [ ! -f "$cred_file" ]; then
        echo -e "${gl_hong}    ❌ 凭证文件丢失:$CF_CREDENTIALS_DIR/$tunnel_id.json${gl_bai}"
        _cf_rollback_partial_deploy "$tunnel_name" "$tunnel_id" "$domain" ""
        break_end; return 1
    fi
    if ! cf_helper_write_config "$config_file" "$tunnel_id" "$cred_file" "${rules[@]}"; then
        _cf_rollback_partial_deploy "$tunnel_name" "$tunnel_id" "$domain" ""
        break_end; return 1
    fi
    echo -e "${gl_lv}    ✅ $config_file${gl_bai}"

    echo "  [4/5] 写 systemd + 启动..."
    if ! cf_helper_write_systemd "$tunnel_name" "$config_file" "Cloudflare Tunnel: $tunnel_name → $domain"; then
        _cf_rollback_partial_deploy "$tunnel_name" "$tunnel_id" "$domain" "$config_file"
        break_end; return 1
    fi

    echo "  [5/5] 探测访问..."
    sleep 2
    local http_code
    http_code=$(curl -sSk --max-time 10 -o /dev/null -w "%{http_code}" "https://$domain/" 2>/dev/null)
    if [[ "$http_code" =~ ^[234] ]]; then
        echo -e "${gl_lv}    ✅ https://$domain 响应 HTTP $http_code${gl_bai}"
    else
        # P1-9:探测失败不阻塞部署完成,但提示更明确
        echo -e "${gl_huang}    ⚠️  探测返回 HTTP '$http_code'${gl_bai}"
        echo -e "${gl_huang}        DNS 记录可能刚加还没生效(一般 1-2 分钟),也可能后端 $backend 此刻没响应${gl_bai}"
        echo -e "${gl_huang}        服务已启动,自行验证:curl -v https://$domain${gl_bai}"
    fi

    echo ""
    echo -e "${gl_kjlan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"
    echo -e "${gl_lv}🎉 部署完成${gl_bai}"
    echo -e "${gl_kjlan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"
    echo ""
    echo "访问地址: https://$domain"
    echo ""
    echo "管理命令:"
    echo "  systemctl status/restart/stop cloudflared-$tunnel_name"
    echo "  journalctl -u cloudflared-$tunnel_name -f"
    break_end
}

#=============================================================================
# 一键反代功能 - 通用反向代理管理
#=============================================================================

# 配置文件路径
REVERSE_PROXY_CONFIG_DIR="/root/reverse-proxy-configs"
REVERSE_PROXY_CONFIG_FILE="$REVERSE_PROXY_CONFIG_DIR/config.json"

# 初始化配置目录
init_reverse_proxy_config() {
    if [ ! -d "$REVERSE_PROXY_CONFIG_DIR" ]; then
        mkdir -p "$REVERSE_PROXY_CONFIG_DIR"
        mkdir -p "$REVERSE_PROXY_CONFIG_DIR/cf-tunnel"
    fi

    if [ ! -f "$REVERSE_PROXY_CONFIG_FILE" ]; then
        echo '{"proxies":[]}' > "$REVERSE_PROXY_CONFIG_FILE"
    fi
}

# 快速部署 - Cloudflare Tunnel
# P0-4 修复(split-brain):转发到新统一向导 cf_tunnel_add,避免老路径 /root/reverse-proxy-configs
quick_deploy_cf_tunnel() {
    cf_tunnel_add
}

# 查看所有反代配置
list_reverse_proxies() {
    clear
    echo -e "${gl_kjlan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"
    echo -e "${gl_kjlan}  已部署的反向代理${gl_bai}"
    echo -e "${gl_kjlan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"
    echo ""

    init_reverse_proxy_config

    # 列出所有 cloudflared 服务
    # Bug 修复:grep "cloudflared-tunnel" 会漏掉所有 tunnel_name 中不含 "tunnel" 的服务
    # 改成匹配 "cloudflared-" 前缀的所有服务
    local services=$(systemctl list-units --type=service --all 2>/dev/null | grep -oE '^[[:space:]]*cloudflared-[^[:space:]]+\.service' | awk '{print $1}')

    if [ -z "$services" ]; then
        echo -e "${gl_huang}暂无已部署的反向代理${gl_bai}"
        echo ""
        break_end
        return 0
    fi

    local count=0
    for service in $services; do
        count=$((count + 1))
        local tunnel_name=$(echo "$service" | sed 's/cloudflared-//' | sed 's/.service//')

        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "[$count] $tunnel_name"

        # 检查服务状态
        if systemctl is-active --quiet "$service"; then
            echo -e "  状态: ${gl_lv}运行中${gl_bai}"
        else
            echo -e "  状态: ${gl_hong}已停止${gl_bai}"
        fi

        # 读取配置文件(优先从 systemd unit 解析,fallback 到老路径)
        # P0-4/I-2 修复:migrate 后配置已搬到 /etc/cloudflared/configs/,不能硬编码老路径
        local config_file
        config_file=$(_cf_get_config_from_service "$service" 2>/dev/null)
        [ -z "$config_file" ] && config_file="$REVERSE_PROXY_CONFIG_DIR/cf-tunnel/$tunnel_name.yaml"
        if [ -f "$config_file" ]; then
            local domain=$(grep "hostname:" "$config_file" | head -1 | awk '{print $3}')
            local port=$(grep "service:" "$config_file" | head -1 | sed -nE 's/.*:([0-9]+).*/\1/p')

            echo "  域名: https://$domain"
            echo "  端口: $port"
            echo "  配置: $config_file"
        fi

        echo "  服务: $service"
        echo ""
    done

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "总计: $count 个反向代理"
    echo ""

    break_end
}

# 删除反代配置
delete_reverse_proxy() {
    clear
    echo -e "${gl_kjlan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"
    echo -e "${gl_kjlan}  删除反向代理${gl_bai}"
    echo -e "${gl_kjlan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"
    echo ""

    # 列出所有服务
    # Bug 修复:grep "cloudflared-tunnel" 会漏掉所有 tunnel_name 中不含 "tunnel" 的服务
    # 改成匹配 "cloudflared-" 前缀的所有服务
    local services=$(systemctl list-units --type=service --all 2>/dev/null | grep -oE '^[[:space:]]*cloudflared-[^[:space:]]+\.service' | awk '{print $1}')

    if [ -z "$services" ]; then
        echo -e "${gl_huang}暂无已部署的反向代理${gl_bai}"
        break_end
        return 0
    fi

    local services_array=()
    mapfile -t services_array <<< "$services"
    local count=0

    for service in "${services_array[@]}"; do
        count=$((count + 1))
        local tunnel_name=$(echo "$service" | sed 's/cloudflared-//' | sed 's/.service//')

        if systemctl is-active --quiet "$service"; then
            echo -e "  $count. $tunnel_name ${gl_lv}[运行中]${gl_bai}"
        else
            echo -e "  $count. $tunnel_name ${gl_hong}[已停止]${gl_bai}"
        fi
    done

    echo ""
    read -e -p "请选择要删除的反代编号 (1-$count, 0取消): " choice

    if [ "$choice" = "0" ]; then
        return 0
    fi

    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt $count ]; then
        echo -e "${gl_hong}无效的选择${gl_bai}"
        break_end
        return 1
    fi

    local selected_service="${services_array[$((choice-1))]}"
    local tunnel_name=$(echo "$selected_service" | sed 's/cloudflared-//' | sed 's/.service//')

    echo ""
    echo -e "${gl_huang}将要删除: $tunnel_name${gl_bai}"
    echo ""
    read -e -p "确认删除？(y/n): " confirm

    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo "已取消"
        break_end
        return 0
    fi

    echo ""
    echo "正在停止服务..."
    systemctl stop "$selected_service"
    systemctl disable "$selected_service"

    echo "正在删除服务文件..."
    rm -f "/etc/systemd/system/$selected_service"
    systemctl daemon-reload

    echo "正在删除配置文件..."
    rm -f "$REVERSE_PROXY_CONFIG_DIR/cf-tunnel/$tunnel_name.yaml"

    # 删除隧道（可选）
    read -e -p "是否同时删除 Cloudflare Tunnel？(y/n): " delete_tunnel
    if [[ "$delete_tunnel" =~ ^[Yy]$ ]]; then
        echo "正在删除隧道..."
        cloudflared tunnel delete "$tunnel_name" 2>/dev/null || true
    fi

    echo ""
    echo -e "${gl_lv}✅ 删除完成${gl_bai}"

    break_end
}

# 一键反代主菜单
manage_reverse_proxy() {
    while true; do
        clear
        echo -e "${gl_kjlan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"
        echo -e "${gl_kjlan}  一键反代 🎯${gl_bai}"
        echo -e "${gl_kjlan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"
        echo ""
        echo "1. 快速部署（输入端口+域名）"
        echo "2. 查看已部署的反代"
        echo "3. 删除反代配置"
        echo "0. 返回主菜单"
        echo ""
        echo -e "${gl_kjlan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"
        read -e -p "请选择操作 [0-3]: " choice

        case $choice in
            1)
                quick_deploy_cf_tunnel
                ;;
            2)
                list_reverse_proxies
                ;;
            3)
                delete_reverse_proxy
                ;;
            0)
                return
                ;;
            *)
                echo "无效的选择"
                sleep 2
                ;;
        esac
    done
}

# 显示帮助信息
show_help() {
    cat << EOF
BBR v3 终极优化脚本 v${SCRIPT_VERSION}

用法: $0 [选项]

选项:
  -h, --help      显示此帮助信息
  -v, --version   显示版本号
  -i, --install   直接安装 XanMod 内核（非交互）
  --repair-boot-recovery  仅迁移DNS启动保护及检查IPv6冲突，不重启机器/网络
  --debug         启用调试模式（详细日志）
  -q, --quiet     静默模式（仅显示错误）

示例:
  $0              启动交互式菜单
  $0 -i           直接安装 BBR v3 内核
  $0 --debug      调试模式运行

日志文件: ${LOG_FILE}
配置文件: ~/.net-tcp-tune.conf 或 /etc/net-tcp-tune.conf
EOF
}

# 解析命令行参数
parse_args() {
    NET_TCP_PARSED_ARGS=()
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                show_help
                exit 0
                ;;
            -v|--version)
                echo "net-tcp-tune.sh v${SCRIPT_VERSION}"
                exit 0
                ;;
            -i|--install)
                check_root
                install_xanmod_kernel
                if [ $? -eq 0 ]; then
                    echo ""
                    echo "安装完成后，请重启系统以加载新内核"
                fi
                exit 0
                ;;
            --debug)
                LOG_LEVEL="DEBUG"
                log_debug "调试模式已启用"
                shift
                ;;
            -q|--quiet)
                LOG_LEVEL="ERROR"
                shift
                ;;
            --repair-boot-recovery)
                break
                ;;
            -*)
                echo "未知选项: $1"
                echo "使用 -h 或 --help 查看帮助"
                exit 1
                ;;
            *)
                # 无参数时继续
                break
                ;;
        esac
    done
    NET_TCP_PARSED_ARGS=("$@")
}

main() {
    # 先解析参数
    parse_args "$@"
    set -- "${NET_TCP_PARSED_ARGS[@]}"

    # 检查 root 权限
    check_root

    # 卸载专用入口必须在配置 source 和任何维护动作之前分流。
    case "${1:-}" in
        --repair-boot-recovery) shift; run_boot_recovery_repair "$@"; return $? ;;
    esac
    # Existing project installations migrate once per normal invocation. Content
    # checks keep later invocations quiet and repair missing assets/new instances.
    local boot_recovery_rc=0
    boot_recovery_migrate auto || boot_recovery_rc=$?
    if [ "$boot_recovery_rc" -ne 0 ]; then
        echo '启动恢复自动迁移仍有未完成项（详见上方）；菜单可继续用于检查和处理，未自动重启业务或网络。' >&2
    fi
    # 启动菜单不自动改 MTU 或迁移 CF；迁移留在 CF 管理入口。

    # 加载用户配置（如果存在）
    [ -f "/etc/net-tcp-tune.conf" ] && source "/etc/net-tcp-tune.conf"
    [ -f "$HOME/.net-tcp-tune.conf" ] && source "$HOME/.net-tcp-tune.conf"

    # 交互式菜单
    while true; do
        show_main_menu
    done
}

# 执行主函数
main "$@"
