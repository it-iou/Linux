#!/bin/bash

# 函数：检查错误并退出
# 参数 $1: 错误消息
check_error() {
    if [ $? -ne 0 ]; then
        echo "发生错误： $1"
        exit 1
    fi
}

# 函数：检查是否具有 root 权限
check_root() {
    if [ "$(id -u)" != "0" ]; then
        echo "需要 root 权限来运行此脚本。请使用 sudo 或以 root 用户身份运行。"
        exit 1
    fi
}

# 函数：安装 openssl
install_openssl() {
    echo "正在安装 openssl..."
    if [ "$OS" = "centos" ]; then
        sudo yum install openssl -y
    elif [ "$OS" = "debian" ] || [ "$OS" = "ubuntu" ]; then
        sudo apt-get install openssl -y
    else
        echo "无法识别的操作系统，请手动安装 openssl。"
        exit 1
    fi
    check_error "安装 openssl 时出错"
}

# 函数：检查并安装 openssl
check_and_install_openssl() {
    if ! command -v openssl &> /dev/null; then
        echo "openssl 未安装，正在安装..."
        install_openssl
    fi
}

# 函数：生成随机密码
generate_random_password() {
    random_password=$(openssl rand -base64 12 | tr -dc 'a-zA-Z0-9!@#$%^&*()_-')
    echo "root:$random_password" | sudo chpasswd
    check_error "生成随机密码时出错"
    echo "$random_password" # 输出密码
}

# 函数：生成随机端口，避免常用端口
generate_random_port() {
    local common_ports=(22 80 443 8080 3306 5432 6379 27017 25 21 23)
    local random_port
    while true; do
        random_port=$((1024 + RANDOM % 64511))
        if ! [[ " ${common_ports[*]} " =~ " $random_port " ]] && ! ss -ltn | grep -q ":$random_port "; then
            echo "$random_port"
            break
        fi
    done
}

# 函数：安装 SELinux 管理工具
install_selinux_utils() {
    if ! command -v semanage &> /dev/null; then
        echo "SELinux 管理工具未安装，正在安装..."
        sudo yum install -y policycoreutils-python
        check_error "安装 SELinux 管理工具时出错"
    fi
}

# 全局变量存储旧端口
old_port=$(grep '^Port' /etc/ssh/sshd_config | awk '{print $2}')

# 函数：修改 sshd_config 文件以更改 SSH 端口
modify_sshd_config_for_port() {
    local new_port=$1
    install_selinux_utils  # 确保 SELinux 工具已安装

    # 删除旧端口的 SELinux 和防火墙规则
    if [ ! -z "$old_port" ]; then
        semanage port -d -t ssh_port_t -p tcp $old_port
        if command -v firewall-cmd &>/dev/null; then
            firewall-cmd --permanent --remove-port=${old_port}/tcp
            firewall-cmd --reload
        elif command -v iptables &>/dev/null; then
            iptables -D INPUT -p tcp --dport $old_port -j ACCEPT
            service iptables save
        fi
    fi

    # 更新 SELinux 策略，允许新端口
    semanage port -a -t ssh_port_t -p tcp $new_port 2>/dev/null || semanage port -m -t ssh_port_t -p tcp $new_port
    check_error "更新 SELinux 端口策略时出错"

    # 更新防火墙规则
    if command -v firewall-cmd &>/dev/null; then
        firewall-cmd --permanent --add-port=${new_port}/tcp
        firewall-cmd --reload
    elif command -v iptables &>/dev/null; then
        iptables -A INPUT -p tcp --dport $new_port -j ACCEPT
        service iptables save
    fi

    # 修改 sshd_config
    sudo sed -i "s/^Port .*/Port $new_port/" /etc/ssh/sshd_config || echo "Port $new_port" | sudo tee -a /etc/ssh/sshd_config
    check_error "修改 SSH 端口时出错"
}

# 函数：重启 SSHD 服务
restart_sshd_service() {
    sudo systemctl restart sshd
    check_error "重启 SSHD 服务时出错"
}

# 函数：检测操作系统
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
    elif [ -f /etc/centos-release ]; then
        OS=centos
    elif [ -f /etc/debian_version ]; then
        OS=debian
    else
        OS=$(uname -s)
    fi
}

# 主函数
main() {
    check_root
    detect_os
    echo "检测到的操作系统: $OS"
    check_and_install_openssl

    echo "请选择密码选项："
    echo "1. 生成密码"
    echo "2. 输入密码"
    read -p "请输入选项编号：" password_option

    case $password_option in
        1)
            password=$(generate_random_password) # 保存生成的密码
            ;;
        2)
            read -p "请输入更改密码：" custom_password
            echo "root:$custom_password" | sudo chpasswd
            check_error "修改密码时出错"
            password=$custom_password # 保存输入的密码
            ;;
        *)
            echo "无效选项，退出..."
            exit 1
            ;;
    esac

    echo "密码已成功更改：$password" # 输出密码

    echo "是否要修改SSH端口？[y/N]"
    read change_port
    if [[ "$change_port" = "y" || "$change_port" = "Y" ]]; then
        echo "请选择端口选项："
        echo "1. 生成随机端口"
        echo "2. 输入自定义端口"
        read -p "请输入选项编号：" port_option

        case $port_option in
            1)
                new_port=$(generate_random_port)
                ;;
            2)
                read -p "请输入新的SSH端口：" new_port
                ;;
            *)
                echo "无效选项，退出..."
                exit 1
                ;;
        esac

        modify_sshd_config_for_port $new_port
        restart_sshd_service

        echo "SSH端口已成功更改为：$new_port" # 输出新的端口
    fi

    # 删除下载的脚本
    rm -f "$0"
}

# 执行主函数
main
