#!/bin/bash
#=============================================================================
# 脚本名称: install-alias.sh
# 功能描述: 安装/卸载 net-tcp-tune 脚本及 bbr 快捷命令
# 使用方法: 
#   安装: bash install-alias.sh [install]
#   卸载: bash install-alias.sh uninstall
#=============================================================================

YELLOW='\033[1;33m'
GREEN='\033[1;32m'
CYAN='\033[1;36m'
RED='\033[1;31m'
NC='\033[0m' # No Color

# 仓库与安装路径
REPO_URL="https://github.com/flyto23/bbr"
REPO_RAW="https://raw.githubusercontent.com/flyto23/bbr/refs/heads/main"
SCRIPT_URL="${REPO_RAW}/net-tcp-tune.sh"
SCRIPT_LOCAL_PATH="/usr/local/bin/net-tcp-tune.sh"

# 检测操作模式（安装或卸载）
MODE="${1:-install}"
if [ "$MODE" != "install" ] && [ "$MODE" != "uninstall" ]; then
    echo -e "${RED}错误: 未知参数 '$MODE'${NC}"
    echo "使用方法:"
    echo "  安装: bash install-alias.sh [install]"
    echo "  卸载: bash install-alias.sh uninstall"
    exit 1
fi

# 检测当前使用的 shell
CURRENT_SHELL=$(basename "$SHELL")

# 根据不同的 shell 设置配置文件（检查多个可能的配置文件）
detect_rc_file() {
    if [ "$CURRENT_SHELL" = "zsh" ]; then
        RC_FILE="$HOME/.zshrc"
    elif [ "$CURRENT_SHELL" = "bash" ]; then
        RC_FILE="$HOME/.bashrc"
        # 如果 .bashrc 不存在，使用 .bash_profile
        if [ ! -f "$RC_FILE" ]; then
            RC_FILE="$HOME/.bash_profile"
        fi
    else
        RC_FILE="$HOME/.bashrc"
    fi
    
    # 如果文件不存在，创建它
    if [ ! -f "$RC_FILE" ]; then
        if ! touch "$RC_FILE"; then
            echo -e "${RED}错误: 无法创建配置文件 ${RC_FILE}${NC}"
            exit 1
        fi
    fi
}

detect_rc_file

# 下载最新脚本到本地，成功时设置 SCRIPT_LOCAL_PATH
download_script_copy() {
    local dest
    if [ "$(id -u)" -eq 0 ] && [ -d /usr/local/bin ] && [ -w /usr/local/bin ]; then
        dest="/usr/local/bin/net-tcp-tune.sh"
    else
        mkdir -p "$HOME/.local/bin" 2>/dev/null || return 1
        [ -w "$HOME/.local/bin" ] || return 1
        dest="$HOME/.local/bin/net-tcp-tune.sh"
    fi

    if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
        echo -e "${YELLOW}未找到 curl 或 wget，跳过脚本下载${NC}"
        return 1
    fi

    local tmp
    tmp=$(mktemp "${dest}.download.XXXXXX") || return 1

    local downloaded=0
    if command -v curl >/dev/null 2>&1; then
        if curl -q -fsSL --connect-timeout 10 --max-time 180 "${SCRIPT_URL}?$(date +%s)" -o "$tmp"; then
            downloaded=1
        fi
    fi
    if [ "$downloaded" -ne 1 ] && command -v wget >/dev/null 2>&1; then
        if wget -q --timeout=30 --tries=2 -O "$tmp" "${SCRIPT_URL}?$(date +%s)"; then
            downloaded=1
        fi
    fi

    if [ "$downloaded" -ne 1 ] || [ ! -s "$tmp" ]; then
        rm -f "$tmp"
        return 1
    fi

    # 校验下载内容，避免把错误页/半截文件装进去
    local first_line
    first_line=$(head -n 1 "$tmp" 2>/dev/null)
    if ! printf '%s' "$first_line" | grep -q '^#!.*bash'; then
        rm -f "$tmp"
        return 1
    fi
    if ! grep -q '^SCRIPT_VERSION=' "$tmp" 2>/dev/null || ! grep -q 'net-tcp-tune' "$tmp" 2>/dev/null; then
        rm -f "$tmp"
        return 1
    fi
    if ! bash -n "$tmp" 2>/dev/null; then
        rm -f "$tmp"
        return 1
    fi

    chmod 755 "$tmp" 2>/dev/null
    if ! mv -f "$tmp" "$dest"; then
        rm -f "$tmp"
        return 1
    fi

    SCRIPT_LOCAL_PATH="$dest"
    return 0
}

alias_block_exists() {
    if [ ! -r "$RC_FILE" ]; then
        echo -e "${RED}错误: 无法读取配置文件 ${RC_FILE}${NC}" >&2
        return 2
    fi

    grep -qE '(^# >>> net-tcp-tune alias >>>|net-tcp-tune 快捷别名)' "$RC_FILE" 2>/dev/null && return 0

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
    ' "$RC_FILE"
}

append_alias_block() {
    local alias_line note
    if [ "${USE_LOCAL_SCRIPT:-0}" = "1" ]; then
        note="运行本地副本，更新请执行 bbr 菜单 98"
        alias_line='alias bbr="bash '"${SCRIPT_LOCAL_PATH}"'"'
    else
        note="每次运行自动从 ${REPO_URL} 获取最新版本"
        alias_line='alias bbr="bash <(curl -q -fsSL \"'"${SCRIPT_URL}"'?\$(date +%s)\")"'
    fi

    {
        echo '# >>> net-tcp-tune alias >>>'
        echo '# ========================================'
        echo '# net-tcp-tune 快捷别名 (自动添加)'
        echo "# ${note}"
        echo '# ========================================'
        echo "$alias_line"
        echo '# <<< net-tcp-tune alias <<<'
    }
}

strip_alias_blocks() {
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

write_rc_safely() {
    local new_content="$1"
    local backup_file="${RC_FILE}.bak.$(date +%Y%m%d_%H%M%S).$$"

    if cmp -s "$RC_FILE" "$new_content"; then
        LAST_BACKUP_FILE=""
        return 2
    fi

    if ! cp -p "$RC_FILE" "$backup_file"; then
        echo -e "${RED}错误: 无法备份 ${RC_FILE}${NC}" >&2
        return 1
    fi

    if ! cat "$new_content" > "$RC_FILE"; then
        echo -e "${RED}错误: 写入 ${RC_FILE} 失败，正在尝试恢复备份${NC}" >&2
        cat "$backup_file" > "$RC_FILE" 2>/dev/null || true
        return 1
    fi

    if ! cmp -s "$new_content" "$RC_FILE"; then
        echo -e "${RED}错误: 写入校验失败，正在尝试恢复备份${NC}" >&2
        cat "$backup_file" > "$RC_FILE" 2>/dev/null || true
        return 1
    fi

    LAST_BACKUP_FILE="$backup_file"
    return 0
}

# 卸载功能
uninstall_alias() {
    echo -e "${CYAN}=== 卸载 net-tcp-tune 快捷别名 ===${NC}"
    echo ""
    echo -e "检测到 Shell: ${GREEN}${CURRENT_SHELL}${NC}"
    echo -e "配置文件: ${GREEN}${RC_FILE}${NC}"
    echo ""
    
    # 检查别名是否已存在
    alias_block_exists
    local exists_rc=$?
    if [ "$exists_rc" -eq 2 ]; then
        echo -e "${RED}❌ 无法读取配置文件，卸载别名失败${NC}"
        echo ""
        return 1
    fi
    if [ "$exists_rc" -ne 0 ]; then
        echo -e "${YELLOW}未找到已安装的别名，无需卸载${NC}"
        echo ""
        return 0
    fi

    local temp_file
    temp_file=$(mktemp "${RC_FILE}.tmp.XXXXXX") || {
        echo -e "${RED}错误: 无法创建临时文件${NC}"
        return 1
    }

    if ! strip_alias_blocks "$RC_FILE" > "$temp_file"; then
        rm -f "$temp_file"
        echo -e "${RED}错误: 清理别名内容失败${NC}"
        return 1
    fi

    write_rc_safely "$temp_file"
    local write_rc=$?
    rm -f "$temp_file"

    case "$write_rc" in
        0)
        echo -e "${GREEN}✅ 别名已从 ${RC_FILE} 中移除${NC}"
        echo ""
            [ -n "$LAST_BACKUP_FILE" ] && echo -e "${YELLOW}提示: 原配置文件已备份为 ${LAST_BACKUP_FILE}${NC}"
        echo ""
        echo -e "${CYAN}=== 现在生效（执行以下命令）===${NC}"
        echo ""
        echo -e "${YELLOW}source ${RC_FILE}${NC}"
        echo ""
        echo "或者关闭终端重新打开，卸载即生效。"
        echo ""
        [ -f "$SCRIPT_LOCAL_PATH" ] && echo -e "${YELLOW}提示: 本地脚本仍在 ${SCRIPT_LOCAL_PATH}，如需删除请手动执行 rm -f${NC}"
        echo ""
            ;;
        2)
            echo -e "${YELLOW}未找到需要删除的内容${NC}"
            echo ""
            ;;
        *)
            echo -e "${RED}❌ 卸载别名失败${NC}"
            echo ""
            return 1
            ;;
    esac
}

# 安装功能
install_alias() {
    echo -e "${CYAN}=== 安装 net-tcp-tune 快捷命令 ===${NC}"
    echo ""
    echo -e "检测到 Shell: ${GREEN}${CURRENT_SHELL}${NC}"
    echo ""
    echo -e "配置文件: ${GREEN}${RC_FILE}${NC}"
    echo -e "脚本仓库: ${GREEN}${REPO_URL}${NC}"
    echo ""

    # 先下载脚本本体，别名指向本地副本（菜单 98 可更新）
    local installed_version=""
    if download_script_copy; then
        USE_LOCAL_SCRIPT=1
        installed_version=$(sed -n 's/^SCRIPT_VERSION="\(.*\)"$/\1/p' "$SCRIPT_LOCAL_PATH" 2>/dev/null | head -n 1)
        echo -e "脚本已安装: ${GREEN}${SCRIPT_LOCAL_PATH}${NC} (v${installed_version:-unknown})"
    else
        USE_LOCAL_SCRIPT=0
        echo -e "${YELLOW}⚠️  脚本下载失败，改用在线模式（每次运行从 GitHub 拉取最新版）${NC}"
    fi
    echo ""

    local had_alias=0
    alias_block_exists
    local exists_rc=$?
    if [ "$exists_rc" -eq 2 ]; then
        echo -e "${RED}❌ 无法读取配置文件，安装别名失败${NC}"
        return 1
    fi
    if [ "$exists_rc" -eq 0 ]; then
        had_alias=1
        echo -e "${YELLOW}配置已存在，正在更新...${NC}"
    fi

    local temp_file
    temp_file=$(mktemp "${RC_FILE}.tmp.XXXXXX") || {
        echo -e "${RED}错误: 无法创建临时文件${NC}"
        return 1
    }

    if ! strip_alias_blocks "$RC_FILE" > "$temp_file"; then
        rm -f "$temp_file"
        echo -e "${RED}错误: 清理旧别名内容失败${NC}"
        return 1
    fi

    if [ -s "$temp_file" ] && [ "$(tail -c 1 "$temp_file" | wc -l | tr -d ' ')" -eq 0 ]; then
        printf '\n' >> "$temp_file"
    fi
    append_alias_block >> "$temp_file"

    write_rc_safely "$temp_file"
    local write_rc=$?
    rm -f "$temp_file"

    if [ "$write_rc" -eq 1 ]; then
        echo -e "${RED}❌ 写入别名失败${NC}"
        return 1
    fi

    if [ "$had_alias" -eq 1 ]; then
        echo -e "${GREEN}✅ 别名已更新到 ${RC_FILE}${NC}"
        echo ""
    else
        echo -e "${GREEN}✅ 别名已添加到 ${RC_FILE}${NC}"
        echo ""
    fi
    
    echo -e "${CYAN}=== 快捷命令 ===${NC}"
    echo ""
    echo -e "  ${GREEN}bbr${NC}   - 一键运行系统优化脚本"
    echo ""
    echo -e "${CYAN}=== 使用方法 ===${NC}"
    echo ""
    echo "1. 重新加载配置："
    echo -e "   ${YELLOW}source ${RC_FILE}${NC}"
    echo ""
    echo "2. 或者关闭终端重新打开"
    echo ""
    echo "3. 然后直接输入快捷命令："
    echo -e "   ${GREEN}bbr${NC}  (系统优化)"
    echo ""
    echo -e "${CYAN}=== 更新方法 ===${NC}"
    echo ""
    echo -e "  运行 ${GREEN}bbr${NC} 后选择 ${GREEN}98. 更新脚本${NC} 即可从 GitHub 拉取最新版"
    echo ""
    echo -e "${CYAN}=== 卸载方法 ===${NC}"
    echo ""
    echo "如需卸载别名，请运行："
    echo -e "   ${YELLOW}bash <(curl -q -fsSL ${REPO_RAW}/install-alias.sh) uninstall${NC}"
    echo ""
    echo -e "${CYAN}=== 现在就生效（执行以下命令）===${NC}"
    echo ""
    echo -e "${YELLOW}source ${RC_FILE}${NC}"
    echo ""
}

# 根据模式执行相应操作
case "$MODE" in
    install)
        install_alias
        ;;
    uninstall)
        uninstall_alias
        ;;
esac
