#!/bin/bash

apt update
apt install bird git make curl wget sudo -y

#检测网卡
interfaces=$(ip -o link show | awk -F': ' '{print $2}')

    # 输出物理网卡名称
    for interface in $interfaces; do
        # 检查是否为物理网卡（不包含虚拟、回环等），并排除@符号及其后面的内容
        if [[ $interface =~ ^(en|eth).* ]]; then
            interface_name=$(echo "$interface" | awk -F'@' '{print $1}')  # 去掉@符号及其后面的内容
            echo "您的网卡是：$interface_name"
            valid_interfaces+=("$interface_name")  # 存储有效的网卡名称
        fi
    done
    # 提示用户选择
    read -p "脚本自行检测的是否是您要的网卡？(y/n): " confirm_interface
    if [ "$confirm_interface" = "y" ]; then
        selected_interface="$interface_name"
        echo "您选择的网卡是: $selected_interface"
    elif [ "$confirm_interface" = "n" ]; then
        read -p "请自行输入您的网卡名称: " selected_interface
        echo "您输入的网卡名称是: $selected_interface"
    else
        echo "无效的选择"
    fi

# 检测eth0的IP
ip_address=$(ip addr show $selected_interface | grep -oP 'inet \K[\d.]+')

echo "开始创建 bird 配置文件"

mv /etc/bird/bird.conf /etc/bird/bird.conf.orig

tee /etc/bird/bird.conf <<EOF
router id $ip_address;

# The Kernel protocol is not a real routing protocol. Instead of communicating
# with other routers in the network, it performs synchronization of BIRD's
# routing tables with the OS kernel.
protocol kernel {
	scan time 60;
	import none;
#	export all;   # Actually insert routes into the kernel routing table
}

# The Device protocol is not a real routing protocol. It doesn't generate any
# routes and it only serves as a module for getting information about network
# interfaces from the kernel. 
protocol device {
	scan time 60;
}

protocol static {
    include "routes4.conf";
}

protocol ospf {
    export all;

    area 0.0.0.0 {
        interface "$selected_interface" {
        };
    };
}
EOF

echo "bird 配置文件创建完成"

git clone https://github.com/Hamster-Prime/nchnroutes.git

sed -i 's/eth0/$selected_interface/g' /root/nchnroutes/produce.py

make -C /root/nchnroutes

echo "安装完成"

echo "请执行 crontab -e 在末尾添加 0 5 * * * cd /root/nchnroutes && make"
