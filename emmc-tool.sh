#!/bin/bash
# EMMC健康监测脚本
# 支持安装、卸载、使用功能
# 需要root权限运行

set -e

SCRIPT_NAME="emmc_health"
INSTALL_PATH="/usr/local/bin/$SCRIPT_NAME"
VERSION="1.0"

# 颜色定义（用于其他部分，进度条不使用颜色）
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
MAGENTA='\033[1;35m'
CYAN='\033[1;36m'
WHITE='\033[1;37m'
NC='\033[0m' # 无颜色

# 进度条字符
BAR_CHAR_FILL="█"
BAR_CHAR_EMPTY="░"

# 设备路径
DEVICE_PATH="/sys/block/mmcblk0/device"

# 状态映射表
declare -A STATUS_MAP=(
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

# 状态颜色映射
declare -A STATUS_COLOR=(
    ["正常"]="$GREEN"
    ["一般"]="$CYAN"
    ["注意"]="$YELLOW"
    ["需关注"]="$YELLOW"
    ["高风险"]="$RED"
    ["即将耗尽"]="$RED"
    ["寿命已耗尽"]="$RED"
)

# 打印带颜色的文本
print_color() {
    echo -e "${2}${1}${NC}"
}

# 打印分隔线
print_separator() {
    echo "════════════════════════════════════════════════════════════"
}

# 检查root权限
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_color "此脚本需要root权限运行！" "$RED"
        print_color "请使用: sudo $0 $1" "$YELLOW"
        exit 1
    fi
}

# 检查是否支持EMMC
check_emmc() {
    if [[ ! -d "$DEVICE_PATH" ]]; then
        print_color "未找到EMMC设备！" "$RED"
        print_color "请确认系统中有mmcblk0设备" "$YELLOW"
        exit 1
    fi
}

# 解析16进制寿命值
parse_life_time() {
    local life_time_raw=$1
    local used_hex=$(echo $life_time_raw | awk '{print $1}')
    local total_hex=$(echo $life_time_raw | awk '{print $2}')
    
    # 转换为十进制
    local used_dec=$((16#${used_hex#0x}))
    local total_dec=$((16#${total_hex#0x}))
    
    # 计算百分比（四舍五入到整数）
    if [[ $total_dec -gt 0 ]]; then
        local percentage=$(( (used_dec * 100 + total_dec/2) / total_dec ))
    else
        local percentage=0
    fi
    
    # 确保不超过100%
    if [[ $percentage -gt 100 ]]; then
        percentage=100
    fi
    
    # 获取状态
    local status_key
    if [[ $percentage -ge 100 ]]; then
        status_key="0x0B"
    elif [[ $percentage -ge 90 ]]; then
        status_key="0x0A"
    elif [[ $percentage -ge 80 ]]; then
        status_key="0x09"
    elif [[ $percentage -ge 70 ]]; then
        status_key="0x08"
    elif [[ $percentage -ge 60 ]]; then
        status_key="0x07"
    elif [[ $percentage -ge 50 ]]; then
        status_key="0x06"
    elif [[ $percentage -ge 40 ]]; then
        status_key="0x05"
    elif [[ $percentage -ge 30 ]]; then
        status_key="0x04"
    elif [[ $percentage -ge 20 ]]; then
        status_key="0x03"
    elif [[ $percentage -ge 10 ]]; then
        status_key="0x02"
    else
        status_key="0x01"
    fi
    
    echo "$used_hex $total_hex $used_dec $total_dec $percentage $status_key"
}

# 显示进度条（无颜色）
show_progress_bar() {
    local percentage=$1
    local bar_width=50
    local filled=$((percentage * bar_width / 100))
    local empty=$((bar_width - filled))
    
    # 构建进度条
    local bar="["
    for ((i=0; i<filled; i++)); do
        bar+="$BAR_CHAR_FILL"
    done
    for ((i=0; i<empty; i++)); do
        bar+="$BAR_CHAR_EMPTY"
    done
    bar+="]"
    
    # 显示进度条，无颜色代码
    echo "健康度: $bar ${percentage}%"
}

# 显示EMMC信息
show_emmc_info() {
    print_separator
    print_color "┌──────────────────────────────────────────────────────┐" "$CYAN"
    print_color "│             EMMC 健康状态检测工具 v$VERSION             │" "$CYAN"
    print_color "└──────────────────────────────────────────────────────┘" "$CYAN"
    echo ""
    
    # 检查设备
    check_emmc
    
    # 读取基本信息
    if [[ -f "$DEVICE_PATH/manfid" ]]; then
        local manufacturer="0x$(cat $DEVICE_PATH/manfid | head -c2)"
        print_color "├─ 制造商:   $manufacturer" "$WHITE"
    fi
    
    if [[ -f "$DEVICE_PATH/name" ]]; then
        local name=$(cat $DEVICE_PATH/name 2>/dev/null | tr -d '\n')
        print_color "├─ 名称:     $name" "$WHITE"
    fi
    
    if [[ -f "$DEVICE_PATH/serial" ]]; then
        local serial=$(cat $DEVICE_PATH/serial 2>/dev/null | tr -d '\n')
        print_color "├─ 序列号:   $serial" "$WHITE"
    fi
    
    if [[ -f "$DEVICE_PATH/fwrev" ]]; then
        local fwrev=$(cat $DEVICE_PATH/fwrev 2>/dev/null | tr -d '\n')
        print_color "├─ 固件版本: $fwrev" "$WHITE"
    fi
    
    print_separator
    
    # 读取寿命信息
    if [[ -f "$DEVICE_PATH/life_time" ]]; then
        local life_time_raw=$(cat $DEVICE_PATH/life_time 2>/dev/null)
        
        if [[ -z "$life_time_raw" ]]; then
            print_color "无法读取EMMC寿命信息！" "$RED"
            exit 1
        fi
        
        # 解析寿命值
        local parsed=$(parse_life_time "$life_time_raw")
        local used_hex=$(echo $parsed | awk '{print $1}')
        local total_hex=$(echo $parsed | awk '{print $2}')
        local used_dec=$(echo $parsed | awk '{print $3}')
        local total_dec=$(echo $parsed | awk '{print $4}')
        local percentage=$(echo $parsed | awk '{print $5}')
        local status_key=$(echo $parsed | awk '{print $6}')
        
        # 显示原始值
        print_color "寿命原始值: $life_time_raw" "$MAGENTA"
        print_color "已用寿命:   $used_hex (十进制: $used_dec)" "$MAGENTA"
        print_color "总寿命:     $total_hex (十进制: $total_dec)" "$MAGENTA"
        
        print_separator
        
        # 显示健康状态
        local status=${STATUS_MAP[$status_key]}
        local status_color=${STATUS_COLOR[$status]}
        
        # 修复健康状态显示，确保颜色正确
        echo -n "健康状态:   [$status_key] "
        echo -e "${status_color}${status}${NC}"
        
        # 显示进度条（无颜色）
        echo ""
        show_progress_bar $percentage
        echo ""
        
        # 显示百分比
        if [[ $percentage -lt 50 ]]; then
            print_color "✓ EMMC健康状况良好" "$GREEN"
        elif [[ $percentage -lt 80 ]]; then
            print_color "⚠ EMMC健康度一般，建议关注" "$YELLOW"
        else
            print_color "⚠ EMMC健康度较差，建议备份数据并考虑更换" "$RED"
        fi
        
    else
        print_color "未找到寿命信息文件！" "$RED"
        print_color "可能此EMMC不支持寿命检测" "$YELLOW"
    fi
    
    print_separator
    echo ""
    print_color "提示: 可以定期运行此脚本监控EMMC健康状态" "$CYAN"
}

# 安装脚本
install_script() {
    check_root "install"
    
    print_color "开始安装EMMC健康检测工具..." "$CYAN"
    
    # 复制脚本
    cp "$0" "$INSTALL_PATH"
    chmod +x "$INSTALL_PATH"
    
    # 创建软链接（可选）
    ln -sf "$INSTALL_PATH" "/usr/bin/emmc" 2>/dev/null || true
    
    print_color "✓ 安装完成！" "$GREEN"
    echo ""
    print_color "使用方法:" "$YELLOW"
    print_color "  1. 在终端输入: $SCRIPT_NAME" "$WHITE"
    print_color "  2. 或输入: emmc" "$WHITE"
    echo ""
    print_color "卸载方法:" "$YELLOW"
    print_color "  sudo $INSTALL_PATH uninstall" "$WHITE"
    
    # 测试运行
    echo ""
    read -p "是否现在运行一次检测？[y/N]: " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        "$INSTALL_PATH"
    fi
}

# 卸载脚本
uninstall_script() {
    check_root "uninstall"
    
    print_color "开始卸载EMMC健康检测工具..." "$CYAN"
    
    # 删除安装的文件
    if [[ -f "$INSTALL_PATH" ]]; then
        rm -f "$INSTALL_PATH"
        print_color "✓ 已删除: $INSTALL_PATH" "$GREEN"
    fi
    
    # 删除软链接
    if [[ -L "/usr/bin/emmc" ]]; then
        rm -f "/usr/bin/emmc"
        print_color "✓ 已删除软链接: /usr/bin/emmc" "$GREEN"
    fi
    
    print_color "✓ 卸载完成！" "$GREEN"
}

# 显示帮助
show_help() {
    print_color "EMMC健康检测工具 v$VERSION" "$CYAN"
    echo ""
    print_color "使用方法:" "$YELLOW"
    print_color "  $0 [选项]" "$WHITE"
    echo ""
    print_color "选项:" "$YELLOW"
    print_color "  install    安装脚本到系统" "$WHITE"
    print_color "  uninstall  卸载脚本" "$WHITE"
    print_color "  help       显示此帮助信息" "$WHITE"
    print_color "  (无参数)   直接运行检测" "$WHITE"
    echo ""
    print_color "安装后，可以直接输入 'emmc' 运行检测" "$GREEN"
}

# 主函数
main() {
    # 检查参数
    case "${1:-}" in
        "install")
            install_script
            ;;
        "uninstall")
            uninstall_script
            ;;
        "help"|"-h"|"--help")
            show_help
            ;;
        "")
            # 无参数，直接运行检测
            check_root
            show_emmc_info
            ;;
        *)
            print_color "错误: 未知参数 '$1'" "$RED"
            echo ""
            show_help
            exit 1
            ;;
    esac
}

# 运行主函数
main "$@"