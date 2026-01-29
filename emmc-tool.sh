#!/bin/bash
# eMMC寿命检测脚本
# 功能：安装/卸载脚本，检测eMMC寿命并显示进度条

SCRIPT_NAME="emmc"
SCRIPT_PATH="/usr/local/bin/$SCRIPT_NAME"
CONFIG_PATH="/etc/emmc_check.conf"
VERSION="1.0"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 寿命值映射表
declare -A LIFE_MAP
LIFE_MAP[0x01]="0-10%    正常"
LIFE_MAP[0x02]="10-20%   正常"
LIFE_MAP[0x03]="20-30%   正常"
LIFE_MAP[0x04]="30-40%   正常"
LIFE_MAP[0x05]="40-50%   正常"
LIFE_MAP[0x06]="50-60%   一般"
LIFE_MAP[0x07]="60-70%   注意"
LIFE_MAP[0x08]="70-80%   需关注"
LIFE_MAP[0x09]="80-90%   高风险"
LIFE_MAP[0x0A]="90-100%  即将耗尽"
LIFE_MAP[0x0B]="≥100%   寿命已耗尽"

# 显示帮助信息
show_help() {
    echo -e "${GREEN}eMMC寿命检测脚本 v$VERSION${NC}"
    echo "用法: $0 [选项]"
    echo
    echo "选项:"
    echo "  install     安装脚本到系统"
    echo "  uninstall   从系统卸载脚本"
    echo "  check      检测eMMC寿命（默认选项）"
    echo "  help        显示此帮助信息"
    echo
    echo "安装后，可以直接在终端输入 'emmc' 来运行脚本"
    echo
}

# 绘制进度条
draw_progress_bar() {
    local value=$1
    local max=100
    local width=50
    
    # 从映射表中获取百分比范围的最低值
    local percent_range=$(echo "${LIFE_MAP[$value]}" | awk '{print $1}' | tr -d '%')
    local min_percent=$(echo "$percent_range" | cut -d'-' -f1)
    
    # 计算进度条长度
    local filled=$((min_percent * width / max))
    local empty=$((width - filled))
    
    # 根据状态选择颜色
    local status_color=$GREEN
    if [[ $value == "0x06" ]]; then
        status_color=$YELLOW
    elif [[ $value == "0x07" ]]; then
        status_color=$PURPLE
    elif [[ $value == "0x08" ]]; then
        status_color=$YELLOW
    elif [[ $value == "0x09" ]]; then
        status_color=$RED
    elif [[ $value == "0x0A" ]]; then
        status_color=$RED
    elif [[ $value == "0x0B" ]]; then
        status_color=$RED
    fi
    
    echo -n "["
    for ((i=0; i<filled; i++)); do
        echo -ne "${status_color}█${NC}"
    done
    for ((i=0; i<empty; i++)); do
        echo -n " "
    done
    echo -n "]"
}

# 显示eMMC寿命信息
show_emmc_life() {
    echo -e "${CYAN}=========================================${NC}"
    echo -e "${GREEN}        eMMC 寿命检测工具${NC}"
    echo -e "${CYAN}=========================================${NC}"
    echo
    
    # 检查是否存在eMMC设备
    if [ ! -d "/sys/block/mmcblk0" ]; then
        echo -e "${RED}错误: 未找到eMMC设备 (mmcblk0)${NC}"
        echo "请确认系统使用eMMC存储设备"
        exit 1
    fi
    
    # 检查寿命文件
    if [ ! -f "/sys/block/mmcblk0/device/life_time" ]; then
        echo -e "${RED}错误: 无法读取寿命信息${NC}"
        echo "寿命文件不存在: /sys/block/mmcblk0/device/life_time"
        echo "可能原因:"
        echo "1. 设备不支持寿命报告"
        echo "2. 需要root权限"
        exit 1
    fi
    
    # 读取寿命值
    local life_time=$(cat /sys/block/mmcblk0/device/life_time 2>/dev/null)
    if [ -z "$life_time" ]; then
        echo -e "${RED}错误: 无法读取寿命值${NC}"
        echo "请尝试使用sudo运行: sudo $0"
        exit 1
    fi
    
    # 获取第一个值（通常是eMMC A）
    local life_value=$(echo $life_time | awk '{print $1}' | tr '[:lower:]' '[:upper:]')
    
    echo -e "${BLUE}eMMC设备信息:${NC}"
    echo "设备路径: /dev/mmcblk0"
    echo "制造商: $(cat /sys/block/mmcblk0/device/manf 2>/dev/null || echo "未知")"
    echo "名称: $(cat /sys/block/mmcblk0/device/name 2>/dev/null || echo "未知")"
    echo "序列号: $(cat /sys/block/mmcblk0/device/serial 2>/dev/null || echo "未知")"
    echo "固件版本: $(cat /sys/block/mmcblk0/device/fwrev 2>/dev/null || echo "未知")"
    echo
    
    echo -e "${BLUE}寿命检测结果:${NC}"
    echo -e "原始寿命值: ${YELLOW}$life_time${NC}"
    echo -e "解析值: ${YELLOW}$life_value${NC}"
    
    # 检查值是否有效
    if [[ -z "${LIFE_MAP[$life_value]}" ]]; then
        echo -e "${RED}警告: 未知的寿命值${NC}"
        echo "可能的值范围: 0x01 到 0x0B"
        exit 1
    fi
    
    # 显示状态信息
    local status_info="${LIFE_MAP[$life_value]}"
    local percent_range=$(echo "$status_info" | awk '{print $1}')
    local status=$(echo "$status_info" | awk '{print $2}')
    
    echo -e "寿命状态: ${YELLOW}$status${NC}"
    echo -e "使用百分比: ${GREEN}$percent_range${NC}"
    echo
    
    # 显示进度条
    echo -e "${BLUE}寿命进度:${NC}"
    draw_progress_bar $life_value
    echo -e " ${percent_range}"
    echo
    
    # 显示详细信息
    echo -e "${BLUE}状态说明:${NC}"
    case $life_value in
        0x01|0x02|0x03|0x04|0x05)
            echo -e "${GREEN}✓ 寿命状态良好，正常使用${NC}"
            ;;
        0x06)
            echo -e "${YELLOW}⚠ 寿命消耗过半，建议关注${NC}"
            ;;
        0x07)
            echo -e "${PURPLE}⚠ 寿命消耗较多，注意备份重要数据${NC}"
            ;;
        0x08)
            echo -e "${YELLOW}⚠ 寿命消耗显著，需密切关注${NC}"
            ;;
        0x09)
            echo -e "${RED}⚠ 寿命即将耗尽，高风险，请准备更换${NC}"
            ;;
        0x0A)
            echo -e "${RED}⚠ 寿命即将耗尽，请立即备份数据并准备更换${NC}"
            ;;
        0x0B)
            echo -e "${RED}✗ 寿命已耗尽，强烈建议立即更换存储设备${NC}"
            ;;
    esac
    
    echo
    echo -e "${CYAN}=========================================${NC}"
    echo -e "${GREEN}检测完成于: $(date)${NC}"
    echo
}

# 安装脚本
install_script() {
    echo -e "${GREEN}开始安装eMMC寿命检测工具...${NC}"
    
    # 检查root权限
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}需要root权限进行安装${NC}"
        echo "请使用: sudo $0 install"
        exit 1
    fi
    
    # 检查是否已安装
    if [[ -f "$SCRIPT_PATH" ]]; then
        echo -e "${YELLOW}警告: 脚本已存在于 $SCRIPT_PATH${NC}"
        read -p "是否重新安装? (y/N): " reinstall
        if [[ ! $reinstall =~ ^[Yy]$ ]]; then
            echo "安装已取消"
            exit 0
        fi
    fi
    
    # 获取当前脚本路径
    SCRIPT_SOURCE="$(realpath "$0")"
    
    # 复制脚本到系统目录
    echo -e "复制脚本到 $SCRIPT_PATH"
    cp "$SCRIPT_SOURCE" "$SCRIPT_PATH"
    
    # 设置可执行权限
    chmod +x "$SCRIPT_PATH"
    
    # 创建配置目录
    mkdir -p "$(dirname "$CONFIG_PATH")"
    
    # 保存安装信息
    echo "# eMMC寿命检测工具安装信息" > "$CONFIG_PATH"
    echo "INSTALL_DATE=$(date)" >> "$CONFIG_PATH"
    echo "VERSION=$VERSION" >> "$CONFIG_PATH"
    echo "SOURCE_SCRIPT=$SCRIPT_SOURCE" >> "$CONFIG_PATH"
    
    echo -e "${GREEN}安装完成!${NC}"
    echo
    echo -e "现在您可以通过以下方式使用:"
    echo -e "1. 直接运行: ${CYAN}emmc${NC}"
    echo -e "2. 或: ${CYAN}emmc check${NC}"
    echo
    echo -e "要卸载工具，请运行: ${CYAN}sudo $SCRIPT_PATH uninstall${NC}"
    echo
}

# 卸载脚本
uninstall_script() {
    echo -e "${YELLOW}开始卸载eMMC寿命检测工具...${NC}"
    
    # 检查root权限
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}需要root权限进行卸载${NC}"
        echo "请使用: sudo $0 uninstall"
        exit 1
    fi
    
    # 检查是否已安装
    if [[ ! -f "$SCRIPT_PATH" ]]; then
        echo -e "${RED}错误: 未找到已安装的脚本${NC}"
        echo "可能未安装或已卸载"
        exit 1
    fi
    
    # 确认卸载
    read -p "确认要卸载eMMC寿命检测工具? (y/N): " confirm
    if [[ ! $confirm =~ ^[Yy]$ ]]; then
        echo "卸载已取消"
        exit 0
    fi
    
    # 删除脚本
    echo -e "删除脚本文件: $SCRIPT_PATH"
    rm -f "$SCRIPT_PATH"
    
    # 删除配置文件
    if [[ -f "$CONFIG_PATH" ]]; then
        echo -e "删除配置文件: $CONFIG_PATH"
        rm -f "$CONFIG_PATH"
    fi
    
    echo -e "${GREEN}卸载完成!${NC}"
    echo
    echo -e "注意: 已删除的脚本可以从原始位置重新安装:"
    echo -e "$(realpath "$0")"
    echo
}

# 主函数
main() {
    case "$1" in
        install)
            install_script
            ;;
        uninstall)
            uninstall_script
            ;;
        help|--help|-h)
            show_help
            ;;
        check|"")
            show_emmc_life
            ;;
        *)
            echo -e "${RED}错误: 未知参数 '$1'${NC}"
            echo
            show_help
            exit 1
            ;;
    esac
}

# 运行主函数
main "$1"