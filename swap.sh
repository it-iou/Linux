#!/usr/bin/env bash

Green="\033[32m"
Font="\033[0m"
Red="\033[31m"
Yellow="\033[33m"

# 检查是否以root权限运行
root_need() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${Red}Error: This script must be run as root!${Font}"
        exit 1
    fi
}

# 检测虚拟化环境
check_virtualization() {
    virt=$(systemd-detect-virt 2>/dev/null || echo "unknown")
    case "$virt" in
    kvm)
        echo -e "${Green}您的VPS运行在KVM环境，完全支持Swap操作。${Font}"
        ;;
    openvz)
        echo -e "${Yellow}您的VPS运行在OpenVZ环境，支持Swap操作，但性能可能受限。${Font}"
        ;;
    *)
        echo -e "${Yellow}您的虚拟化环境检测为：${virt}，可能需要自行确认支持情况。${Font}"
        ;;
    esac
}

# 添加Swap
add_swap() {
    local swapsize=$1
    if [[ -z "$swapsize" ]]; then
        echo -e "${Green}请输入需要添加的Swap大小（单位：MB），建议为内存的2倍！${Font}"
        read -p "请输入Swap大小: " swapsize
    fi

    # 验证用户输入是否为数字
    if ! [[ "$swapsize" =~ ^[0-9]+$ ]]; then
        echo -e "${Red}输入错误！请输入一个有效的数字。${Font}"
        return
    fi

    # 检查是否已经存在Swap文件
    grep -q "swapfile" /etc/fstab
    if [ $? -ne 0 ]; then
        echo -e "${Green}未发现Swap文件，正在创建Swap文件...${Font}"

        # 优先使用fallocate命令
        if command -v fallocate > /dev/null; then
            fallocate -l ${swapsize}M /swapfile
        else
            echo -e "${Yellow}fallocate命令不可用，正在使用dd命令创建Swap文件...${Font}"
            dd if=/dev/zero of=/swapfile bs=1M count=${swapsize} status=progress
        fi

        chmod 600 /swapfile
        mkswap /swapfile
        swapon /swapfile
        echo '/swapfile none swap defaults 0 0' >> /etc/fstab

        echo -e "${Green}Swap创建成功，当前信息如下：${Font}"
        cat /proc/swaps
        cat /proc/meminfo | grep Swap
    else
        echo -e "${Red}Swap文件已存在，请先删除现有的Swap文件后再尝试！${Font}"
    fi
}

# 删除Swap
del_swap() {
    # 检查是否存在Swap文件
    grep -q "swapfile" /etc/fstab
    if [ $? -eq 0 ]; then
        echo -e "${Green}发现Swap文件，正在删除...${Font}"
        sed -i '/swapfile/d' /etc/fstab
        swapoff /swapfile
        rm -f /swapfile
        echo "3" > /proc/sys/vm/drop_caches
        echo -e "${Green}Swap已成功删除！${Font}"
    else
        echo -e "${Red}未发现Swap文件，无法删除！${Font}"
    fi
}

# 调整Swap大小
resize_swap() {
    local newsize=$1
    # 检查是否存在Swap文件
    grep -q "swapfile" /etc/fstab
    if [ $? -eq 0 ]; then
        echo -e "${Green}检测到已有Swap文件，当前Swap大小如下：${Font}"
        cat /proc/swaps

        if [[ -z "$newsize" ]]; then
            echo -e "${Green}请输入新的Swap大小（单位：MB）：${Font}"
            read -p "请输入新的Swap大小: " newsize
        fi

        # 验证用户输入是否为数字
        if ! [[ "$newsize" =~ ^[0-9]+$ ]]; then
            echo -e "${Red}输入错误！请输入一个有效的数字。${Font}"
            return
        fi

        echo -e "${Green}正在调整Swap大小...${Font}"
        swapoff /swapfile
        rm -f /swapfile

        # 使用适当方式重新创建Swap文件
        if command -v fallocate > /dev/null; then
            fallocate -l ${newsize}M /swapfile
        else
            dd if=/dev/zero of=/swapfile bs=1M count=${newsize} status=progress
        fi

        chmod 600 /swapfile
        mkswap /swapfile
        swapon /swapfile

        echo '/swapfile none swap defaults 0 0' >> /etc/fstab
        echo -e "${Green}Swap大小调整成功，当前信息如下：${Font}"
        cat /proc/swaps
        cat /proc/meminfo | grep Swap
    else
        echo -e "${Red}未发现Swap文件，无法调整大小，请先创建Swap文件！${Font}"
    fi
}

# 显示帮助信息
show_help() {
    echo -e "${Green}Usage: $0 [option] [size]${Font}"
    echo -e "${Green}Options:${Font}"
    echo -e "  add [size]    添加指定大小的Swap（单位：MB）"
    echo -e "  del           删除现有的Swap"
    echo -e "  resize [size] 调整现有Swap大小（单位：MB）"
    echo -e "  help          显示此帮助信息"
}

# 主逻辑，根据参数执行对应操作
main() {
    root_need
    case "$1" in
    add)
        add_swap "$2"
        ;;
    del)
        del_swap
        ;;
    resize)
        resize_swap "$2"
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        echo -e "${Red}无效的选项！请使用 'help' 查看正确用法。${Font}"
        show_help
        ;;
    esac
}

main "$@"
