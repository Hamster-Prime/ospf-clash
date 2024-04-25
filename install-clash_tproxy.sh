#!/bin/bash

apt update
apt install curl wget gzip sudo -y

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

echo "开始下载 mihomo"

# 检测系统架构
architecture=$(uname -m)

echo "当前架构为: $architecture"

# 定义文件下载链接
if [ "$architecture" == "x86_64" ]; then
    file_url="https://github.com/Hamster-Prime/ospf-clash/releases/download/1.0.0/mihomo-linux-amd64-compatible-alpha.gz"
elif [ "$architecture" == "aarch64" ]; then
    file_url="https://github.com/Hamster-Prime/ospf-clash/releases/download/1.0.0/mihomo-linux-arm64-alpha.gz"
else
    echo "不支持您的系统架构 目前只支持x86_64与arm64 当前架构为: $architecture"
    exit 1
fi

# 下载文件
wget "$file_url" || {
    echo "文件下载失败"
    exit 1
}

echo "mihomo 下载完成"

# 解压文件

echo "开始解压"

for file in mihomo*; do
    if [ -f "$file" ]; then
        echo "解压 $file ..."
        gunzip "$file"
    fi
done

echo "解压完成"

# 重命名文件

echo "开始重命名"

for file in mihomo*; do
    if [ -f "$file" ]; then
        echo "重命名 $file 为 clash ..."
        mv "$file" clash
    fi
done

echo "重命名完成"

echo "开始添加执行权限"
chmod u+x clash
echo "执行权限添加完成"

echo "开始创建 /etc/clash 目录"
mkdir /etc/clash
echo "/etc/clash 目录创建完成"

echo "开始复制 clash 到 /usr/local/bin"
cp clash /usr/local/bin
echo "复制完成"

echo "开始设置 转发"
echo 'net.ipv4.ip_forward = 1' | tee -a /etc/sysctl.conf
echo "转发设置完成"

echo "开始创建 systemd 服务"

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

echo "请输入内网DNS服务器地址(无内网dns请输入网关地址)"

read dnsip

echo "请输入机场订阅地址"

read proxyurl

tee /etc/clash/config.yaml <<EOF
mode: rule
ipv6: false
log-level: info
allow-lan: true
mixed-port: 7890
tproxy-port: 7896
unified-delay: false
tcp-concurrent: true
external-controller: 0.0.0.0:9090
external-ui: /etc/clash/ui/metacubexd

geodata-mode: true
geox-url:
  geoip: "https://fastly.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@release/geoip.dat"
  geosite: "https://fastly.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@release/geosite.dat"
  mmdb: "https://fastly.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@release/country.mmdb"

profile:
  store-selected: true
  store-fake-ip: true
  tracing: true

sniffer:
  enable: true
  sniff:
    TLS:
      ports: [443, 8443]
    HTTP:
      ports: [80, 8080-8880]
      override-destination: true
interface-name: $selected_interface
tun:
  device: utun
  enable: false
  stack: system
  auto-route: true
  auto-detect-interface: false

dns:
  enable: true
  listen: :1053
  ipv6: false
  enhanced-mode: redir-host
  fake-ip-range: 28.0.0.1/8
  fake-ip-filter:
    - '*'
    - '+.lan'
    - '+.local'
  default-nameserver:
    - ${dnsip}
  nameserver:
    - ${dnsip}
  proxy-server-nameserver:
    - ${dnsip}
  nameserver-policy:
    "geosite:cn,private":
      - ${dnsip}
proxies:
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
    use:
      - 机场
    proxies:
    url: "https://www.gstatic.com/generate_204"
    interval: 10
  - name: 故障自动转移
    type: fallback
    use:
      - 机场
    proxies:
    url: "https://www.gstatic.com/generate_204"
    interval: 10
rules:
  - MATCH,PROXY
EOF

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
		meta l4proto { tcp, udp } meta mark set 1 tproxy to :7896 accept
	}

#	chain clash-mark {
#		fib daddr type { unspec, local, anycast, multicast } return
#		ip daddr @local_ipv4 return
#		ip6 daddr @local_ipv6 return
#		udp dport { 123 } return
#		meta mark set 1
#	}
#
#	chain mangle-output {
#		type route hook output priority mangle; policy accept;
#		meta l4proto { tcp, udp } skgid != 997 ct direction original jump clash-mark
#	}

	chain mangle-prerouting {
		type filter hook prerouting priority mangle; policy accept;
		iifname { lo, $selected_interface } meta l4proto { tcp, udp } ct direction original jump clash-tproxy
	}
}" >> /etc/nftables.conf

nft -f /etc/nftables.conf

echo "开始下载并设置metacubexd面板"

# 下载文件
wget https://github.com/MetaCubeX/metacubexd/releases/download/v1.138.1/compressed-dist.tgz

# 创建目标文件夹
sudo mkdir -p /etc/clash/ui/metacubexd

# 解压缩到目标文件夹
sudo tar -xzvf compressed-dist.tgz -C /etc/clash/ui/metacubexd

# 清理下载的压缩文件
rm compressed-dist.tgz

echo "重启 clash"

systemctl enable clash
systemctl restart clash

echo "安装完成"

echo "请访问 http://$ip_address:9090/ui 进入管理面板后填入 http://$ip_address:9090"
