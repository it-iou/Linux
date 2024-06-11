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
    if [ "$OS" = "centos" ] || [ "$OS" = "rhel" ]; then
        sudo yum install -y openssl
    elif [ "$OS" = "debian" ] || [ "$OS" = "ubuntu" ]; then
        sudo apt-get install -y openssl
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

# 函数：获取当前 SSH 端口
get_current_ssh_port() {
    local current_port=$(grep "^Port " /etc/ssh/sshd_config | awk '{print $2}')
    if [ -z "$current_port" ]; then
        current_port=22  # 默认端口是 22
    fi
    echo $current_port
}

# 函数：安装 SELinux 管理工具
install_selinux_utils() {
    if [ "$OS" = "centos" ] || [ "$OS" = "rhel" ]; then
        if ! command -v semanage &> /dev/null; then
            echo "SELinux 管理工具未安装，正在安装..."
            sudo yum install -y policycoreutils-python-utils || sudo yum install -y policycoreutils-python
            check_error "安装 SELinux 管理工具时出错"
        fi
    fi
}

# 函数：修改 sshd_config 文件以更改 SSH 端口和允许登录设置
modify_sshd_config_for_port() {
    local new_port=$1
    if [ "$OS" = "centos" ] || [ "$OS" = "rhel" ]; then
        install_selinux_utils  # 确保 SELinux 工具已安装
        # 更新 SELinux 策略，允许新端口
        semanage port -a -t ssh_port_t -p tcp $new_port 2>/dev/null || semanage port -m -t ssh_port_t -p tcp $new_port
        check_error "更新 SELinux 端口策略时出错"
    fi

    # 确保删除所有现有的“Port”行，并正确设置新的端口
    sudo sed -i "/^#*Port /c\Port $new_port" /etc/ssh/sshd_config

    check_error "修改 SSH 配置时出错"
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
    echo "检测到的操作系统: $OS"
}

# 主函数
main() {
    check_root
    detect_os
    check_and_install_openssl
    new_port=$(get_current_ssh_port)

    modify_sshd_config_for_port $new_port # 先设置默认配置，防止用户中途退出导致设置丢失

    read -p "是否更改 root 密码？[y/N]" change_password

    if [[ "$change_password" = "y" || "$change_password" = "Y" ]]; then
        read -p "请输入新密码（留空自动生成）：" custom_password
        if [ -z "$custom_password" ]; then
            password=$(generate_random_password)
            echo "密码自动生成并更改成功，新密码为：$password"
        else
            echo "root:$custom_password" | sudo chpasswd
            check_error "修改密码时出错"
            password=$custom_password
            echo "密码已成功更改，新密码为：$password"
        fi
    fi

    read -p "请输入新的 SSH 端口（留空保持当前端口）：" custom_port
    if [ ! -z "$custom_port" ]; then
        modify_sshd_config_for_port $custom_port
        echo "SSH端口已成功更改，新端口为：$custom_port"
    else
        echo "SSH端口未更改，当前端口为：$new_port"
    fi

    restart_sshd_service

    echo "配置已完成。"

    # 删除下载的脚本
    rm -f "$0"
}

# 执行主函数
main
