#!/bin/bash
apt update
apt install bird unzip git nftables make curl wget gzip redis-server vim sudo -y

#获取架构类型
architecture=$(uname -m)

# 检测eth0的IP
ip_address=$(ip addr show eth0 | grep -oP 'inet \K[\d.]+')

#获取机场订阅地址
echo "请输入机场订阅地址"
read proxyurl

#安装clash
if [ "$architecture" == "x86_64" ]; then
    file_url="https://github.com/Hamster-Prime/ospf-clash/releases/download/1.0.0/mihomo-linux-amd64-compatible-alpha.gz"
elif [ "$architecture" == "aarch64" ]; then
    file_url="https://github.com/Hamster-Prime/ospf-clash/releases/download/1.0.0/mihomo-linux-arm64-alpha.gz"
else
    echo "不支持您的系统架构 目前只支持x86_64与arm64 当前架构为: $architecture"
    exit 1
fi
wget "$file_url" || {
    echo "文件下载失败"
    exit 1
}
for file in mihomo*; do
    if [ -f "$file" ]; then
        gunzip "$file"
    fi
done
for file in mihomo*; do
    if [ -f "$file" ]; then
        mv "$file" clash
    fi
done
chmod u+x clash
mkdir /etc/clash
cp clash /usr/local/bin
echo 'net.ipv4.ip_forward = 1' | tee -a /etc/sysctl.conf
tee /etc/systemd/system/clash.service > /dev/null <<EOF
[Unit]
Description=Clash daemon, A rule-based proxy in Go.
After=network.target

[Service]
Type=simple
Restart=always
ExecStart=/usr/local/bin/clash -d /etc/clash

[Install]
WantedBy=multi-user.target
EOF

#配置bird服务
mv /etc/bird/bird.conf /etc/bird/bird.conf.orig
mv /etc/bird/bird6.conf /etc/bird/bird6.conf.orig

#IPv4
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

#IPv6
tee /etc/bird/bird6.conf <<EOF
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
    include "routes6.conf";
}

protocol ospf {
    export all;

    area 0.0.0.0 {
        interface "eth0" {
        };
    };
}
EOF

#写入clash配置文件
tee /etc/clash/config.yaml <<EOF
mode: rule
ipv6: true
log-level: silent
allow-lan: true
tproxy-port: 7899
unified-delay: true
tcp-concurrent: true
find-process-mode: off
global-client-fingerprint: chrome
external-controller: 0.0.0.0:9090
external-ui: /etc/clash/ui/metacubexd
interface-name: eth0
profile:
  store-selected: true
proxy-providers:
  机场:
   type: http
   path: /etc/clash/proxies/jijicloud.yaml
   url: ${proxyurl}
   interval: 3600 
   filter: ''
   health-check:
     enable: true
     url: https://www.gstatic.com/generate_204
     interval: 300
proxy-groups:  
  - name: PROXY
    type: select
    use:
      - 机场
    proxies:
      - 自动选择
      - 故障自动转移
      - DIRECT
  - name: 自动选择
    type: url-test
    proxies:
      - 机场
    url: "https://www.gstatic.com/generate_204"
    interval: 10
  - name: 故障自动转移
    type: fallback
    proxies:
      - 机场
    url: "https://www.gstatic.com/generate_204"
    interval: 10
  - name: 机场
    type: fallback
    use:
      - 机场
    proxies:
    url: "https://www.gstatic.com/generate_204"
    interval: 10
rules:
  - MATCH,PROXY
EOF

#写入nftables配置文件
echo "table inet clash {
	set local_ipv4 {
		type ipv4_addr
		flags interval
		elements = {
			10.0.0.0/8,
			127.0.0.0/8,
			169.254.0.0/16,
			172.16.0.0/12,
			192.168.0.0/16,
			240.0.0.0/4
		}
	}

	set local_ipv6 {
		type ipv6_addr
		flags interval
		elements = {
			::ffff:0.0.0.0/96,
			64:ff9b::/96,
			100::/64,
			2001::/32,
			2001:10::/28,
			2001:20::/28,
			2001:db8::/32,
			2002::/16,
			fc00::/7,
			fe80::/10
		}
	}

	chain clash-tproxy {
		fib daddr type { unspec, local, anycast, multicast } return
		ip daddr @local_ipv4 return
		ip6 daddr @local_ipv6 return
		udp dport { 123 } return
		meta l4proto { tcp, udp } meta mark set 1 tproxy to :7899 accept
	}

	chain clash-mark {
		fib daddr type { unspec, local, anycast, multicast } return
		ip daddr @local_ipv4 return
		ip6 daddr @local_ipv6 return
		udp dport { 123 } return
		meta mark set 1
	}

	chain mangle-output {
		type route hook output priority mangle; policy accept;
		meta l4proto { tcp, udp } skgid != 997 ct direction original jump clash-mark
	}

	chain mangle-prerouting {
		type filter hook prerouting priority mangle; policy accept;
		iifname { lo, eth0 } meta l4proto { tcp, udp } ct direction original jump clash-tproxy
	}
}" >> /etc/nftables.conf

#重启nftables
nft -f /etc/nftables.conf
systemctl enable nftables

#创建clash-route服务
touch /etc/systemd/system/clash-route.service
echo "[Unit]
Description=Clash TProxy Rules
After=network.target
Wants=network.target

[Service]
User=root
Type=oneshot
RemainAfterExit=yes
# there must be spaces before and after semicolons
ExecStart=/sbin/ip rule add fwmark 1 table 100 ; /sbin/ip route add local default dev lo table 100 ; /sbin/ip -6 rule add fwmark 1 table 101 ; /sbin/ip -6 route add local ::/0 dev lo table 101
ExecStop=/sbin/ip rule del fwmark 1 table 100 ; /sbin/ip route del local default dev lo table 100 ; /sbin/ip -6 rule del fwmark 1 table 101 ; /sbin/ip -6 route del local ::/0 dev lo table 101

[Install]
WantedBy=multi-user.target" >> /etc/systemd/system/clash-route.service

#重启clash-route服务
systemctl enable clash-route

#安装metacubexd面板
wget https://github.com/MetaCubeX/metacubexd/releases/download/v1.176.1/compressed-dist.tgz
mkdir -p /etc/clash/ui/metacubexd
tar -xzvf compressed-dist.tgz -C /etc/clash/ui/metacubexd
rm compressed-dist.tgz

#重启clash
systemctl restart clash

#拉取路由表
git clone https://github.com/Hamster-Prime/nchnroutes.git
make -C /root/nchnroutes

#clash设置开机自启
systemctl enable clash

#完成安装
echo "安装完成"
echo "请执行 crontab -e 并在末尾添加 0 5 * * * make -C /root/nchnroutes"
echo "请访问 http://$ip_address:9090/ui 进入管理面板后填入 http://$ip_address:9090"
