#!/bin/bash
apt update
apt install bird git make curl wget gzip sudo -y

#获取架构类型
architecture=$(uname -m)

# 检测eth0的IP
ip_address=$(ip addr show eth0 | grep -oP 'inet \K[\d.]+')

#获取DNS地址
echo "请输入内网DNS服务器地址(无内网dns请输入网关地址)"
read dnsip

#获取订阅链接地址
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
echo "开始解压"
for file in mihomo*; do
    if [ -f "$file" ]; then
        echo "解压 $file ..."
        gunzip "$file"
    fi
done
for file in mihomo*; do
    if [ -f "$file" ]; then
        echo "重命名 $file 为 clash ..."
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

#写入clash配置文件
tee /etc/clash/config.yaml <<EOF
mode: rule
ipv6: false
log-level: info
allow-lan: true
mixed-port: 7890
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
interface-name: eth0
tun:
  device: utun
  enable: true
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

#安装metacubexd面板
wget https://github.com/MetaCubeX/metacubexd/releases/download/v1.138.1/compressed-dist.tgz
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
echo "请执行 crontab -e 在末尾添加 0 5 * * * cd make -C /root/nchnroutes"
echo "请访问 http://$ip_address:9090/ui 进入管理面板后填入 http://$ip_address:9090"
