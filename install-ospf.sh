#!/bin/bash

#升级并安装依赖
apt update
apt install bird git make curl wget sudo -y

# 检测eth0的IP
ip_address=$(ip addr show eth0 | grep -oP 'inet \K[\d.]+')

#配置bird
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
        interface "eth0" {
        };
    };
}
EOF

#拉取路由表
git clone https://github.com/Hamster-Prime/nchnroutes.git
make -C /root/nchnroutes

echo "请执行 crontab -e 在末尾添加 0 5 * * * make -C /root/nchnroutes"
