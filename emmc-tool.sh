#!/bin/bash
# EMMC寿命检测脚本
# 功能：安装、卸载、检测EMMC寿命

SCRIPT_NAME="emmc"
INSTALL_PATH="/usr/local/bin/$SCRIPT_NAME"
SERVICE_FILE="/etc/systemd/system/emmc-info.service"

# 颜色定义
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
MAGENTA='\033[1;35m'
CYAN='\033[1;36m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color
BOLD='\033[1m'
UNDERLINE='\033[4m'

# 进度条字符
BAR_CHAR="█"
EMPTY_CHAR="░"

# 显示帮助信息
show_help() {
    echo -e "${GREEN}EMMC寿命检测工具${NC}"
    echo -e "使用方法:"
    echo -e "  $0 install     - 安装工具"
    echo -e "  $0 uninstall   - 卸载工具"
    echo -e "  $0 run         - 运行检测"
    echo -e "  直接输入 'emmc'  - 运行检测(安装后可用)"
    echo
    echo -e "注意: 需要root权限执行安装和卸载"
}

# 获取当前用户的shell配置文件
get_user_shell_files() {
    local user_home="$1"
    local shell_configs=()
    
    # 检查不同shell的配置文件
    if [ -f "$user_home/.bashrc" ]; then
        shell_configs+=("$user_home/.bashrc")
    fi
    
    if [ -f "$user_home/.bash_profile" ]; then
        shell_configs+=("$user_home/.bash_profile")
    fi
    
    if [ -f "$user_home/.profile" ]; then
        shell_configs+=("$user_home/.profile")
    fi
    
    if [ -f "$user_home/.zshrc" ]; then
        shell_configs+=("$user_home/.zshrc")
    fi
    
    echo "${shell_configs[@]}"
}

# 自动重新加载用户shell配置
reload_shell_config() {
    local user_home="$1"
    
    echo -e "${YELLOW}正在自动重新加载shell配置...${NC}"
    
    # 获取所有可能的shell配置文件
    IFS=' ' read -r -a config_files <<< "$(get_user_shell_files "$user_home")"
    
    for config_file in "${config_files[@]}"; do
        if [ -f "$config_file" ]; then
            echo -e "${BLUE}加载配置文件: $config_file${NC}"
            # 尝试重新加载配置文件
            if [[ "$config_file" == *.bashrc ]] || [[ "$config_file" == *.bash_profile ]] || [[ "$config_file" == *.profile ]]; then
                # 对于当前shell重新加载
                if [ -n "$BASH_VERSION" ]; then
                    # 如果是bash shell，则重新加载
                    source "$config_file" 2>/dev/null && echo -e "${GREEN}✓ 已重新加载 $config_file${NC}"
                fi
            elif [[ "$config_file" == *.zshrc ]]; then
                # 对于zsh shell
                if [ -n "$ZSH_VERSION" ]; then
                    source "$config_file" 2>/dev/null && echo -e "${GREEN}✓ 已重新加载 $config_file${NC}"
                fi
            fi
        fi
    done
    
    # 设置立即生效的别名（对当前会话有效）
    alias emmc="sudo $INSTALL_PATH run" 2>/dev/null
    
    echo -e "${GREEN}✓ Shell配置已自动重新加载${NC}"
    echo -e "${CYAN}您现在可以直接在终端输入 'emmc' 运行检测工具${NC}"
}

# 检查root权限
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}错误: 此操作需要root权限${NC}"
        echo "请使用 sudo $0 $1"
        exit 1
    fi
}

# 安装脚本
install_script() {
    check_root "install"
    
    echo -e "${GREEN}正在安装EMMC检测工具...${NC}"
    
    # 复制脚本到系统路径
    cp "$0" "$INSTALL_PATH"
    chmod +x "$INSTALL_PATH"
    
    # 获取当前用户（可能是通过sudo执行）
    if [ -n "$SUDO_USER" ]; then
        CURRENT_USER="$SUDO_USER"
    else
        CURRENT_USER="$USER"
    fi
    
    # 获取用户家目录
    USER_HOME=$(getent passwd "$CURRENT_USER" | cut -d: -f6)
    
    if [ -z "$USER_HOME" ]; then
        USER_HOME="$HOME"
    fi
    
    echo -e "${BLUE}为用户 $CURRENT_USER ($USER_HOME) 安装...${NC}"
    
    # 检查用户的默认shell
    USER_SHELL=$(getent passwd "$CURRENT_USER" | cut -d: -f7)
    echo -e "${BLUE}用户默认shell: $USER_SHELL${NC}"
    
    # 创建别名（如果bashrc中不存在）
    BASHRC="$USER_HOME/.bashrc"
    
    if [ -f "$BASHRC" ]; then
        if ! grep -q "alias $SCRIPT_NAME" "$BASHRC"; then
            echo "" >> "$BASHRC"
            echo "# EMMC寿命检测工具别名" >> "$BASHRC"
            echo "alias $SCRIPT_NAME='sudo $INSTALL_PATH run'" >> "$BASHRC"
            echo -e "${GREEN}✓ 已添加别名到 $BASHRC${NC}"
        else
            echo -e "${YELLOW}✓ 别名已存在于 $BASHRC${NC}"
        fi
    else
        # 如果.bashrc不存在，创建它
        echo "# EMMC寿命检测工具别名" > "$BASHRC"
        echo "alias $SCRIPT_NAME='sudo $INSTALL_PATH run'" >> "$BASHRC"
        chown "$CURRENT_USER:$CURRENT_USER" "$BASHRC"
        echo -e "${GREEN}✓ 已创建 $BASHRC 并添加别名${NC}"
    fi
    
    # 也添加到.bash_profile（如果存在）
    BASH_PROFILE="$USER_HOME/.bash_profile"
    if [ -f "$BASH_PROFILE" ]; then
        if ! grep -q "alias $SCRIPT_NAME" "$BASH_PROFILE"; then
            echo "" >> "$BASH_PROFILE"
            echo "# EMMC寿命检测工具别名" >> "$BASH_PROFILE"
            echo "alias $SCRIPT_NAME='sudo $INSTALL_PATH run'" >> "$BASH_PROFILE"
            echo -e "${GREEN}✓ 已添加别名到 $BASH_PROFILE${NC}"
        fi
    fi
    
    # 也添加到.profile（如果存在）
    PROFILE="$USER_HOME/.profile"
    if [ -f "$PROFILE" ] && [ ! -f "$BASH_PROFILE" ]; then
        if ! grep -q "alias $SCRIPT_NAME" "$PROFILE"; then
            echo "" >> "$PROFILE"
            echo "# EMMC寿命检测工具别名" >> "$PROFILE"
            echo "alias $SCRIPT_NAME='sudo $INSTALL_PATH run'" >> "$PROFILE"
            echo -e "${GREEN}✓ 已添加别名到 $PROFILE${NC}"
        fi
    fi
    
    # 创建全局符号链接（可选）
    if [ ! -f "/usr/bin/$SCRIPT_NAME" ]; then
        ln -sf "$INSTALL_PATH" "/usr/bin/$SCRIPT_NAME" 2>/dev/null
        echo -e "${GREEN}✓ 已创建全局符号链接${NC}"
    fi
    
    echo -e "${GREEN}安装完成!${NC}"
    
    # 自动重新加载shell配置
    reload_shell_config "$USER_HOME"
    
    # 显示使用方法
    echo -e "\n${CYAN}════════════ 使用方法 ════════════${NC}"
    echo -e "${WHITE}1. 在当前终端直接输入: ${GREEN}emmc${NC}"
    echo -e "${WHITE}2. 或运行: ${GREEN}sudo $INSTALL_PATH run${NC}"
    echo -e "${WHITE}3. 关闭终端重新打开后，输入 ${GREEN}emmc${NC} 也可以使用"
    echo -e "${CYAN}═══════════════════════════════════${NC}"
}

# 卸载脚本
uninstall_script() {
    check_root "uninstall"
    
    echo -e "${YELLOW}正在卸载EMMC检测工具...${NC}"
    
    # 获取当前用户
    if [ -n "$SUDO_USER" ]; then
        CURRENT_USER="$SUDO_USER"
    else
        CURRENT_USER="$USER"
    fi
    
    # 获取用户家目录
    USER_HOME=$(getent passwd "$CURRENT_USER" | cut -d: -f6)
    if [ -z "$USER_HOME" ]; then
        USER_HOME="$HOME"
    fi
    
    # 删除安装的文件
    if [ -f "$INSTALL_PATH" ]; then
        rm -f "$INSTALL_PATH"
        echo -e "${GREEN}✓ 已删除: $INSTALL_PATH${NC}"
    fi
    
    # 删除全局符号链接
    if [ -f "/usr/bin/$SCRIPT_NAME" ]; then
        rm -f "/usr/bin/$SCRIPT_NAME"
        echo -e "${GREEN}✓ 已删除全局符号链接${NC}"
    fi
    
    # 从用户配置文件中删除别名
    for config_file in "$USER_HOME/.bashrc" "$USER_HOME/.bash_profile" "$USER_HOME/.profile" "$USER_HOME/.zshrc"; do
        if [ -f "$config_file" ]; then
            if grep -q "alias $SCRIPT_NAME" "$config_file"; then
                # 删除别名行
                sed -i "/alias $SCRIPT_NAME/d" "$config_file"
                # 删除空行和注释
                sed -i "/^# EMMC寿命检测工具别名$/d" "$config_file"
                echo -e "${GREEN}✓ 已从 $config_file 中移除别名${NC}"
            fi
        fi
    done
    
    # 自动重新加载shell配置
    reload_shell_config "$USER_HOME"
    
    echo -e "\n${GREEN}卸载完成!${NC}"
    echo -e "${YELLOW}注意: 您可能需要关闭并重新打开终端以使更改完全生效${NC}"
}

# 获取设备信息
get_device_info() {
    local info=()
    
    # 制造商
    if [ -f "/sys/block/mmcblk0/device/manfid" ]; then
        manfid=$(cat /sys/block/mmcblk0/device/manfid 2>/dev/null | tr -d '\n')
        info+=("制造商: 0x$manfid")
    fi
    
    # 设备名称
    if [ -f "/sys/block/mmcblk0/device/name" ]; then
        name=$(cat /sys/block/mmcblk0/device/name 2>/dev/null | tr -d '\n')
        info+=("设备名称: $name")
    fi
    
    # 序列号
    if [ -f "/sys/block/mmcblk0/device/serial" ]; then
        serial=$(cat /sys/block/mmcblk0/device/serial 2>/dev/null | tr -d '\n')
        info+=("序列号: 0x$serial")
    fi
    
    # 固件版本
    if [ -f "/sys/block/mmcblk0/device/fwrev" ]; then
        fwrev=$(cat /sys/block/mmcblk0/device/fwrev 2>/dev/null | tr -d '\n')
        info+=("固件版本: $fwrev")
    fi
    
    # 容量
    if [ -f "/sys/block/mmcblk0/size" ]; then
        size=$(cat /sys/block/mmcblk0/size 2>/dev/null)
        if [ -n "$size" ]; then
            capacity_gb=$((size * 512 / 1000000000))
            info+=("容量: ${capacity_gb}GB")
        fi
    fi
    
    echo "${info[@]}"
}

# 解析寿命值
parse_life_time() {
    local life_time="$1"
    local -A life_map=(
        ["0x01"]="0-10%"
        ["0x02"]="10-20%"
        ["0x03"]="20-30%"
        ["0x04"]="30-40%"
        ["0x05"]="40-50%"
        ["0x06"]="50-60%"
        ["0x07"]="60-70%"
        ["0x08"]="70-80%"
        ["0x09"]="80-90%"
        ["0x0A"]="90-100%"
        ["0x0B"]="≥100%"
    )
    
    local -A status_map=(
        ["0x01"]="正常"
        ["0x02"]="正常"
        ["0x03"]="正常"
        ["0x04"]="正常"
        ["0x05"]="正常"
        ["0x06"]="一般"
        ["0x07"]="注意"
        ["0x08"]="需关注"
        ["0x09"]="高风险"
        ["0x0A"]="即将耗尽"
        ["0x0B"]="寿命已耗尽"
    )
    
    local -A percent_map=(
        ["0x01"]=5
        ["0x02"]=15
        ["0x03"]=25
        ["0x04"]=35
        ["0x05"]=45
        ["0x06"]=55
        ["0x07"]=65
        ["0x08"]=75
        ["0x09"]=85
        ["0x0A"]=95
        ["0x0B"]=100
    )
    
    echo "${life_map[$life_time]}:${status_map[$life_time]}:${percent_map[$life_time]}"
}

# 显示进度条
show_progress_bar() {
    local percent=$1
    local status=$2
    local bar_width=50
    local filled=$((percent * bar_width / 100))
    local empty=$((bar_width - filled))
    
    # 根据状态设置颜色
    local bar_color=$GREEN
    if [[ $percent -ge 50 && $percent -lt 70 ]]; then
        bar_color=$YELLOW
    elif [[ $percent -ge 70 && $percent -lt 90 ]]; then
        bar_color=$RED
    elif [[ $percent -ge 90 ]]; then
        bar_color=$RED
    fi
    
    echo -e "\n${CYAN}寿命状态: ${bar_color}$status${NC}"
    echo -ne "${BLUE}使用率: ${WHITE}[${bar_color}"
    
    # 填充部分
    for ((i=0; i<filled; i++)); do
        echo -ne "$BAR_CHAR"
    done
    
    # 空白部分
    for ((i=0; i<empty; i++)); do
        echo -ne "$EMPTY_CHAR"
    done
    
    echo -ne "${WHITE}] ${percent}%${NC}\n"
}

# 显示寿命表格
show_life_table() {
    echo -e "\n${CYAN}┌─────────────────────────────────────────────┐${NC}"
    echo -e "${CYAN}│${WHITE}        EMMC寿命参考表                     ${CYAN}│${NC}"
    echo -e "${CYAN}├─────────┬──────────┬─────────────────────┤${NC}"
    echo -e "${CYAN}│${WHITE}  值     ${CYAN}│${WHITE}  使用率   ${CYAN}│${WHITE}       状态         ${CYAN}│${NC}"
    echo -e "${CYAN}├─────────┼──────────┼─────────────────────┤${NC}"
    
    local -A table=(
        ["0x01"]="0-10%      正常"
        ["0x02"]="10-20%     正常"
        ["0x03"]="20-30%     正常"
        ["0x04"]="30-40%     正常"
        ["0x05"]="40-50%     正常"
        ["0x06"]="50-60%     一般"
        ["0x07"]="60-70%     注意"
        ["0x08"]="70-80%     需关注"
        ["0x09"]="80-90%     高风险"
        ["0x0A"]="90-100%    即将耗尽"
        ["0x0B"]="≥100%      寿命已耗尽"
    )
    
    for key in "${!table[@]}"; do
        IFS=' ' read -r -a parts <<< "${table[$key]}"
        echo -e "${CYAN}│${WHITE} $key     ${CYAN}│${WHITE} ${parts[0]}   ${CYAN}│${WHITE} ${parts[1]}     ${CYAN}│${NC}"
    done
    
    echo -e "${CYAN}└─────────┴──────────┴─────────────────────┘${NC}"
}

# 运行检测
run_detection() {
    clear
    echo -e "${BOLD}${CYAN}╔═══════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${CYAN}║     EMMC 寿命检测工具 v1.0               ║${NC}"
    echo -e "${BOLD}${CYAN}╚═══════════════════════════════════════════╝${NC}"
    
    # 检查设备是否存在
    if [ ! -d "/sys/block/mmcblk0" ]; then
        echo -e "\n${RED}错误: 未找到EMMC设备 /dev/mmcblk0${NC}"
        echo -e "${YELLOW}请检查:${NC}"
        echo -e "1. 设备是否正确连接"
        echo -e "2. 是否是EMMC设备"
        echo -e "3. 查看可用设备: ls /sys/block/"
        exit 1
    fi
    
    # 检查寿命文件是否存在
    if [ ! -f "/sys/block/mmcblk0/device/life_time" ]; then
        echo -e "\n${RED}错误: 无法读取寿命信息${NC}"
        echo -e "${YELLOW}可能原因:${NC}"
        echo -e "1. 设备不支持寿命检测"
        echo -e "2. 内核版本不兼容"
        echo -e "3. 权限不足(请使用sudo)"
        echo -e "\n${YELLOW}尝试查看其他信息:${NC}"
        ls -la /sys/block/mmcblk0/device/ 2>/dev/null | head -10
        exit 1
    fi
    
    # 获取设备信息
    echo -e "\n${GREEN}════════════ 设备信息 ═════════════${NC}"
    IFS=$'\n' read -r -d '' -a device_info < <(get_device_info)
    for info in "${device_info[@]}"; do
        echo -e "${WHITE}  ${info}${NC}"
    done
    
    # 读取寿命信息
    echo -e "\n${GREEN}════════════ 寿命检测 ═════════════${NC}"
    life_time=$(cat /sys/block/mmcblk0/device/life_time 2>/dev/null)
    
    if [ -z "$life_time" ]; then
        echo -e "${RED}无法读取寿命数据${NC}"
        exit 1
    fi
    
    echo -e "${WHITE}读取到的值: ${YELLOW}$life_time${NC}"
    
    # 解析寿命值
    IFS=' ' read -r used_life total_life <<< "$life_time"
    
    if [ -z "$used_life" ] || [ -z "$total_life" ]; then
        echo -e "${RED}寿命数据格式错误${NC}"
        exit 1
    fi
    
    # 解析已使用寿命
    used_info=$(parse_life_time "$used_life")
    IFS=':' read -r used_range used_status used_percent <<< "$used_info"
    
    # 解析总寿命
    total_info=$(parse_life_time "$total_life")
    IFS=':' read -r total_range total_status total_percent <<< "$total_info"
    
    # 显示已使用寿命
    echo -e "\n${WHITE}已使用寿命:${NC}"
    echo -e "  值: $used_life"
    echo -e "  使用率: $used_range"
    echo -e "  状态: ${YELLOW}$used_status${NC}"
    
    # 显示进度条
    show_progress_bar "$used_percent" "$used_status"
    
    # 显示参考表
    show_life_table
    
    echo -e "\n${GREEN}════════════ 检测完成 ═════════════${NC}"
    echo -e "${WHITE}当前状态: ${YELLOW}$used_status${NC}"
    
    # 建议
    if [[ "$used_life" == "0x0A" ]] || [[ "$used_life" == "0x0B" ]]; then
        echo -e "${RED}⚠️  警告: EMMC寿命即将耗尽，建议备份数据并更换设备${NC}"
    elif [[ "$used_life" == "0x08" ]] || [[ "$used_life" == "0x09" ]]; then
        echo -e "${YELLOW}⚠️  注意: EMMC寿命已消耗较多，建议关注设备健康${NC}"
    fi
    
    echo -e "\n${WHITE}按Enter键继续...${NC}"
    read -r
}

# 主程序
main() {
    case "$1" in
        "install")
            install_script
            ;;
        "uninstall")
            uninstall_script
            ;;
        "run")
            run_detection
            ;;
        *)
            # 如果脚本是通过emmc命令运行的
            if [ "$(basename "$0")" = "$SCRIPT_NAME" ]; then
                run_detection
            else
                show_help
            fi
            ;;
    esac
}

# 运行主程序
main "$1"