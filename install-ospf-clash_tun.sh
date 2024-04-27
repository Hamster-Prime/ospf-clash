#!/bin/bash
apt update
apt install bird git make curl wget gzip sudo -y

# 检测eth0的IP
ip_address=$(ip addr show eth0 | grep -oP 'inet \K[\d.]+')

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

echo "systemd 服务创建完成"

echo "开始创建 bird 配置文件"

mv /etc/bird/bird.conf bird.conf.orig

echo "请输入路由ID(无特殊要求请输入本机内网IP $ip_address )"

read routerid

tee /etc/bird/bird.conf <<EOF
router id ${routerid};

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

echo "bird 配置文件创建完成"

git clone https://github.com/Hamster-Prime/nchnroutes.git

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

systemctl restart clash

# 最大循环次数
max_attempts=60
attempt=1

# 检查Clash服务状态是否为active，最多尝试60次
while [[ "$(systemctl is-active clash)" != "active" && $attempt -le $max_attempts ]]; do
    echo "正在等待Clash服务启动"
    sleep 1
done

# 如果循环次数达到上限仍未检测到Clash运行状态为active，则输出错误信息
if [[ "$(systemctl is-active clash)" != "active" ]]; then
    echo "Clash运行失败请检查配置文件是否正确"
else
    echo "Clash 已启动"
    # 继续执行后续命令
    cd /root/nchnroutes && make
fi

systemctl enable clash

echo "请执行 crontab -e 在末尾添加 0 5 * * * cd /root/nchnroutes && make"

echo "请访问 http://$ip_address:9090/ui 进入管理面板后填入 http://$ip_address:9090"
