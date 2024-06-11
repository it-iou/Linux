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
        echo "需要 root 权限来运行此脚本。"
        exit 1
    fi
}

# 函数：安装 openssl
install_openssl() {
    echo "正在安装 openssl..."
    if [ "$OS" = "centos" ] || [ "$OS" = "rhel" ]; then
        yum install -y openssl
    elif [ "$OS" = "debian" ] || [ "$OS" = "ubuntu" ]; then
        apt-get install -y openssl
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
    local random_password=$(openssl rand -base64 12 | tr -dc 'a-zA-Z0-9!@#$%^&*()_-')
    echo "root:$random_password" | chpasswd
    check_error "生成随机密码时出错"
    echo "$random_password" # 返回生成的密码给调用者
}

# 函数：获取当前 SSH 端口
get_current_ssh_port() {
    local current_port=$(grep "^Port " /etc/ssh/sshd_config | awk '{print $2}')
    if [ -z "$current_port" ]; then
        current_port=22  # 默认端口是 22
    fi
    echo $current_port
}

# 函数：修改 sshd_config 文件以更改 SSH 端口和允许登录设置
modify_sshd_config_for_port() {
    local new_port=$1
    local current_port=$(get_current_ssh_port)

    if [ "$new_port" != "$current_port" ]; then
        sed -i "/^Port /c\Port $new_port" /etc/ssh/sshd_config
        sed -i "/^PermitRootLogin /c\PermitRootLogin yes" /etc/ssh/sshd_config
        sed -i "/^PasswordAuthentication /c\PasswordAuthentication yes" /etc/ssh/sshd_config
        check_error "修改 SSH 配置时出错"
        echo "changed"
    else
        echo "unchanged"
    fi
}

# 函数：重启 SSHD 服务
restart_sshd_service() {
    systemctl restart sshd
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
    password_changed=0
    port_changed=0
    new_password=""
    new_port=$(get_current_ssh_port)
	
	# 开启密码认证 root 登录
    sed -i "/^PermitRootLogin /c\PermitRootLogin yes" /etc/ssh/sshd_config
    sed -i "/^PasswordAuthentication /c\PasswordAuthentication yes" /etc/ssh/sshd_config
    restart_sshd_service

    read -p "是否更改 root 密码？[y/N]" change_password

    if [[ "$change_password" = "y" || "$change_password" = "Y" ]]; then
        read -p "请输入新密码（留空自动生成）：" custom_password
        if [ -z "$custom_password" ]; then
            new_password=$(generate_random_password)
            echo "密码自动生成并更改成功，新密码为：$new_password。"
        else
            echo "root:$custom_password" | chpasswd
            check_error "修改密码时出错"
            new_password=$custom_password
            echo "密码已成功更改，新密码为：$new_password。"
        fi
        password_changed=1
    fi

    read -p "请输入新的 SSH 端口（留空保持当前端口）：" custom_port
    if [ ! -z "$custom_port" ]; then
        port_status=$(modify_sshd_config_for_port $custom_port)
        if [ "$port_status" = "changed" ]; then
            echo "SSH端口已成功更改，新端口为：$custom_port。"
            new_port=$custom_port
            port_changed=1
        else
            echo "SSH端口未更改，当前端口为：$new_port。"
        fi
    else
        echo "SSH端口未更改，当前端口为：$new_port。"
    fi

    restart_sshd_service

    if [ $password_changed -eq 1 ] && [ $port_changed -eq 1 ]; then
        echo "密码和SSH端口均已更改。新密码为：$new_password，新端口为：$new_port。"
    elif [ $password_changed -eq 1 ]; then
        echo "仅密码已更改，新密码为：$new_password。当前SSH端口为：$new_port。"
    elif [ $port_changed -eq 1 ]; then
        echo "仅SSH端口已更改，新端口为：$new_port。密码未更改。"
    else
        echo "未进行任何更改。"
    fi

    # 删除下载的脚本
    rm -f "$0"
}

# 执行主函数
main

