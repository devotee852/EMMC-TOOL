#!/bin/bash
# EMMC寿命检测脚本
# 功能：安装、卸载、检测EMMC寿命

SCRIPT_NAME="emmc"
INSTALL_PATH="/usr/local/bin/$SCRIPT_NAME"

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

# 自动检测EMMC设备
find_emmc_device() {
    local found_device=""
    
    echo -e "${CYAN}正在扫描EMMC设备...${NC}" >&2
    
    # 查找/sys/block下所有块设备
    for device in /sys/block/mmcblk*; do
        if [ -d "$device" ]; then
            device_name=$(basename "$device")
            
            # 检查是否是EMMC设备（通过检查是否有life_time文件或通过设备类型判断）
            if [ -f "$device/device/life_time" ] || [ -f "$device/device/type" ]; then
                # 如果找到life_time文件，则直接使用
                if [ -f "$device/device/life_time" ]; then
                    found_device="$device_name"
                    echo -e "${GREEN}✓ 找到EMMC设备: /dev/$device_name${NC}" >&2
                    # 已去除路径显示
                    break
                else
                    # 如果没有life_time文件，但可能是EMMC设备，检查设备类型
                    if [ -f "$device/device/type" ]; then
                        device_type=$(cat "$device/device/type" 2>/dev/null)
                        if [ "$device_type" = "MMC" ] || [ "$device_type" = "SD" ] || [[ "$device_name" == mmcblk* ]]; then
                            echo -e "${YELLOW}⚠ 找到可能设备: /dev/$device_name (类型: ${device_type:-未知})${NC}" >&2
                            echo -e "${YELLOW}  但未找到life_time文件，继续搜索...${NC}" >&2
                            # 不设置found_device，继续查找
                        fi
                    fi
                fi
            fi
        fi
    done
    
    # 如果没有找到任何mmcblk设备，尝试其他可能的EMMC设备路径
    if [ -z "$found_device" ]; then
        # 检查是否是SD卡设备
        for device in /sys/block/sd*; do
            if [ -d "$device" ]; then
                device_name=$(basename "$device")
                echo -e "${YELLOW}找到存储设备: /dev/$device_name (可能是SD卡或USB设备)${NC}" >&2
            fi
        done
        
        # 列出所有可用的块设备
        echo -e "\n${CYAN}可用的块设备列表:${NC}" >&2
        ls -la /sys/block/ 2>/dev/null | grep -E "^(d|l)" | awk '{print "  " $9}' >&2
        
        echo -e "\n${RED}错误: 未找到支持寿命检测的EMMC设备${NC}" >&2
        echo -e "${YELLOW}可能的原因:${NC}" >&2
        echo -e "1. 系统中没有EMMC设备" >&2
        echo -e "2. 设备不支持寿命检测功能" >&2
        echo -e "3. 内核版本过旧，不支持life_time接口" >&2
        echo -e "4. 设备驱动不支持此功能" >&2
        
        echo -e "\n${YELLOW}您可以尝试:${NC}" >&2
        echo -e "1. 检查设备是否正确连接" >&2
        echo -e "2. 检查内核是否支持EMMC寿命检测" >&2
        echo -e "3. 查看是否有其他mmc设备: ls /dev/mmc*" >&2
        echo -e "4. 尝试手动指定设备路径" >&2
        
        # 提示用户手动输入设备路径
        echo -e "\n${CYAN}是否要手动指定设备路径? (y/N)${NC}" >&2
        read -r response
        
        if [[ "$response" =~ ^[Yy]$ ]]; then
            echo -e "${CYAN}请输入设备名称 (如: mmcblk0, mmcblk1):${NC}" >&2
            read -r manual_device
            
            if [[ "$manual_device" =~ ^mmcblk[0-9]+$ ]] && [ -d "/sys/block/$manual_device" ]; then
                found_device="$manual_device"
                echo -e "${GREEN}✓ 使用手动指定的设备: /dev/$found_device${NC}" >&2
            else
                echo -e "${RED}错误: 设备 '$manual_device' 不存在或格式不正确${NC}" >&2
                echo -e "${YELLOW}设备名称应该类似于: mmcblk0, mmcblk1${NC}" >&2
                exit 1
            fi
        else
            exit 1
        fi
    fi
    
    echo "$found_device"
}

# 获取设备信息
get_device_info() {
    local device="$1"
    local info=()
    
    if [ -z "$device" ]; then
        device="mmcblk0"  # 默认值
    fi
    
    # 制造商
    if [ -f "/sys/block/$device/device/manfid" ]; then
        manfid=$(cat "/sys/block/$device/device/manfid" 2>/dev/null | tr -d '\n')
        info+=("制造商: 0x$manfid")
    fi
    
    # 设备名称
    if [ -f "/sys/block/$device/device/name" ]; then
        name=$(cat "/sys/block/$device/device/name" 2>/dev/null | tr -d '\n')
        info+=("设备名称: $name")
    fi
    
    # 序列号
    if [ -f "/sys/block/$device/device/serial" ]; then
        serial=$(cat "/sys/block/$device/device/serial" 2>/dev/null | tr -d '\n')
        info+=("序列号: 0x$serial")
    fi
    
    # 固件版本
    if [ -f "/sys/block/$device/device/fwrev" ]; then
        fwrev=$(cat "/sys/block/$device/device/fwrev" 2>/dev/null | tr -d '\n')
        info+=("固件版本: $fwrev")
    fi
    
    # 容量
    if [ -f "/sys/block/$device/size" ]; then
        size=$(cat "/sys/block/$device/size" 2>/dev/null)
        if [ -n "$size" ]; then
            capacity_gb=$((size * 512 / 1000000000))
            info+=("容量: ${capacity_gb}GB")
        fi
    fi
    
    # 设备类型
    if [ -f "/sys/block/$device/device/type" ]; then
        device_type=$(cat "/sys/block/$device/device/type" 2>/dev/null | tr -d '\n')
        info+=("设备类型: $device_type")
    fi
    
    # 硬件版本
    if [ -f "/sys/block/$device/device/hwrev" ]; then
        hwrev=$(cat "/sys/block/$device/device/hwrev" 2>/dev/null | tr -d '\n')
        info+=("硬件版本: 0x$hwrev")
    fi
    
    echo "${info[@]}"
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
    
    echo -e "${YELLOW}正在自动重新加载shell配置...${NC}" >&2
    
    # 获取所有可能的shell配置文件
    IFS=' ' read -r -a config_files <<< "$(get_user_shell_files "$user_home")"
    
    for config_file in "${config_files[@]}"; do
        if [ -f "$config_file" ]; then
            echo -e "${BLUE}加载配置文件: $config_file${NC}" >&2
            # 尝试重新加载配置文件
            if [[ "$config_file" == *.bashrc ]] || [[ "$config_file" == *.bash_profile ]] || [[ "$config_file" == *.profile ]]; then
                # 对于当前shell重新加载
                if [ -n "$BASH_VERSION" ]; then
                    # 如果是bash shell，则重新加载
                    source "$config_file" 2>/dev/null && echo -e "${GREEN}✓ 已重新加载 $config_file${NC}" >&2
                fi
            elif [[ "$config_file" == *.zshrc ]]; then
                # 对于zsh shell
                if [ -n "$ZSH_VERSION" ]; then
                    source "$config_file" 2>/dev/null && echo -e "${GREEN}✓ 已重新加载 $config_file${NC}" >&2
                fi
            fi
        fi
    done
    
    # 设置立即生效的别名（对当前会话有效）
    alias emmc="sudo $INSTALL_PATH run" 2>/dev/null
    
    echo -e "${GREEN}✓ Shell配置已自动重新加载${NC}" >&2
    echo -e "${CYAN}您现在可以直接在终端输入 'emmc' 运行检测工具${NC}" >&2
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

# 运行检测
run_detection() {
    clear
    echo -e "${BOLD}${CYAN}╔═══════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${CYAN}║     EMMC 寿命检测工具 v1.0               ║${NC}"
    echo -e "${BOLD}${CYAN}╚═══════════════════════════════════════════╝${NC}"
    
    # 自动检测EMMC设备
    echo -e "\n${GREEN}════════════ 设备检测 ═════════════${NC}"
    
    # 调用函数获取设备名称
    EMMC_DEVICE=$(find_emmc_device)
    
    if [ -z "$EMMC_DEVICE" ]; then
        echo -e "${RED}错误: 未找到可用的EMMC设备${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}✓ 使用EMMC设备: /dev/$EMMC_DEVICE${NC}"
    
    # 检查寿命文件是否存在
    if [ ! -f "/sys/block/$EMMC_DEVICE/device/life_time" ]; then
        echo -e "\n${RED}错误: 设备 /dev/$EMMC_DEVICE 不支持寿命检测${NC}"
        echo -e "${YELLOW}可能原因:${NC}"
        echo -e "1. 设备不支持寿命检测功能"
        echo -e "2. 内核版本不兼容"
        echo -e "3. 设备驱动不支持此功能"
        echo -e "\n${YELLOW}可用的设备信息文件:${NC}"
        ls -la "/sys/block/$EMMC_DEVICE/device/" 2>/dev/null | head -10
        exit 1
    fi
    
    # 获取设备信息
    echo -e "\n${GREEN}════════════ 设备信息 ═════════════${NC}"
    # 已去除设备路径显示
    
    IFS=$'\n' read -r -d '' -a device_info < <(get_device_info "$EMMC_DEVICE")
    for info in "${device_info[@]}"; do
        echo -e "${WHITE}  ${info}${NC}"
    done
    
    # 读取寿命信息
    echo -e "\n${GREEN}════════════ 寿命检测 ═════════════${NC}"
    life_time=$(cat "/sys/block/$EMMC_DEVICE/device/life_time" 2>/dev/null)
    
    if [ -z "$life_time" ]; then
        echo -e "${RED}无法读取寿命数据${NC}"
        echo -e "${YELLOW}请检查文件权限或设备状态${NC}"
        exit 1
    fi
    
    # 已去除读取到的值显示
    
    # 解析寿命值
    IFS=' ' read -r used_life total_life <<< "$life_time"
    
    if [ -z "$used_life" ] || [ -z "$total_life" ]; then
        echo -e "${RED}寿命数据格式错误${NC}"
        echo -e "${YELLOW}预期格式: 0x01 0x01 (实际值: $life_time)${NC}"
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
    
    # 显示总寿命
    echo -e "\n${WHITE}总寿命指示:${NC}"
    echo -e "  值: $total_life"
    echo -e "  范围: $total_range"
    
    # 显示进度条
    show_progress_bar "$used_percent" "$used_status"
    
    echo -e "\n${GREEN}════════════ 检测完成 ═════════════${NC}"
    # 已去除设备显示
    echo -e "${WHITE}当前状态: ${YELLOW}$used_status${NC}"
    
    # 建议
    if [[ "$used_life" == "0x0A" ]] || [[ "$used_life" == "0x0B" ]]; then
        echo -e "${RED}⚠️  警告: EMMC寿命即将耗尽，建议立即备份重要数据并更换设备${NC}"
    elif [[ "$used_life" == "0x08" ]] || [[ "$used_life" == "0x09" ]]; then
        echo -e "${YELLOW}⚠️  注意: EMMC寿命已消耗较多，建议关注设备健康并定期备份数据${NC}"
    elif [[ "$used_life" == "0x07" ]]; then
        echo -e "${YELLOW}⚠️  提示: EMMC寿命消耗较多，建议关注设备使用情况${NC}"
    elif [[ "$used_life" == "0x06" ]]; then
        echo -e "${BLUE}提示: EMMC寿命使用过半，建议适当关注${NC}"
    else
        echo -e "${GREEN}✓ EMMC寿命状态良好${NC}"
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