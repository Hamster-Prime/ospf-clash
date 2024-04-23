#!/bin/bash
apt update
apt install bird make curl wget gzip sudo -y

echo "开始下载 mohomo"

# 检测系统架构
architecture=$(uname -m)

# 定义文件下载链接
if [ "$architecture" == "x86_64" ]; then
    file_url="https://github.com/MetaCubeX/mihomo/releases/download/Prerelease-Alpha/mihomo-linux-amd64-compatible-alpha-002b8af.gz"
elif [ "$architecture" == "aarch64" ]; then
    file_url="https://github.com/MetaCubeX/mihomo/releases/download/Prerelease-Alpha/mihomo-linux-arm64-alpha-002b8af.gz"
else
    echo "不支持您的系统架构 目前只支持x86_64与arm64 当前架构为: $architecture"
    exit 1
fi

# 下载文件
wget "$file_url" || {
    echo "文件下载失败"
    exit 1
}

echo "mohomo 下载完成"

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
        echo "重命名 $file 为 $new_name ..."
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

echo "开始安装docker"
apt install docker.io -y
echo "docker安装完成"

echo "开始安装ui界面"
docker run -d --restart always -p 80:80 --name metacubexd mrxianyu/metacubexd-ui
echo "ui界面安装完成"

echo "开始设置 转发"
echo 'net.ipv4.ip_forward = 1' | tee -a /etc/sysctl.conf
echo 'net.ipv6.conf.all.forwarding = 1' | tee -a /etc/sysctl.conf
echo "转发设置完成"

echo "开始创建 systemd 服务"

sudo tee /etc/systemd/system/clash.service > /dev/null <<EOF
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

echo "请输入路由ID"

read routerid

tee /etc/bird/bird.conf <<EOF
router id ${routerid};

# The Kernel protocol is not a real routing protocol. Instead of communicating
# with other routers in the network, it performs synchronization of BIRD's
# routing tables with the OS kernel.
protocol kernel {
	scan time 60;
	import none;
	export all;   # Actually insert routes into the kernel routing table
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

git clone https://github.com/dndx/nchnroutes.git

mv /root/nchnroutes/Makefile Makefile.orig

tee /root/nchnroutes/Makefile <<EOF
produce:
	git pull
	curl -o delegated-apnic-latest https://ftp.apnic.net/stats/apnic/delegated-apnic-latest
	curl -o china_ip_list.txt https://raw.githubusercontent.com/17mon/china_ip_list/master/china_ip_list.txt
	python3 produce.py
	mv routes4.conf /etc/bird/routes4.conf
	# sudo mv routes6.conf /etc/bird/routes6.conf
	birdc c
	# sudo birdc6 configure
EOF

mv /root/nchnroutes/produce.py produce.py.orig

tee /root/nchnroutes/produce.py <<EOF
#!/usr/bin/env python3
import argparse
import csv
from ipaddress import IPv4Network, IPv6Network
import math

parser = argparse.ArgumentParser(description='Generate non-China routes for BIRD.')
parser.add_argument('--exclude', metavar='CIDR', type=str, nargs='*',
                    help='IPv4 ranges to exclude in CIDR format')
parser.add_argument('--next', default="utun", metavar = "INTERFACE OR IP",
                    help='next hop for where non-China IP address, this is usually the tunnel interface')
parser.add_argument('--ipv4-list', choices=['apnic', 'ipip'], default=['apnic', 'ipip'], nargs='*',
                    help='IPv4 lists to use when subtracting China based IP, multiple lists can be used at the same time (default: apnic ipip)')

args = parser.parse_args()

class Node:
    def __init__(self, cidr, parent=None):
        self.cidr = cidr
        self.child = []
        self.dead = False
        self.parent = parent

    def __repr__(self):
        return "<Node %s>" % self.cidr

def dump_tree(lst, ident=0):
    for n in lst:
        print("+" * ident + str(n))
        dump_tree(n.child, ident + 1)

def dump_bird(lst, f):
    for n in lst:
        if n.dead:
            continue

        if len(n.child) > 0:
            dump_bird(n.child, f)

        elif not n.dead:
            f.write('route %s via "%s";\n' % (n.cidr, args.next))

RESERVED = [
    IPv4Network('0.0.0.0/8'),
    IPv4Network('10.0.0.0/8'),
    IPv4Network('127.0.0.0/8'),
    IPv4Network('169.254.0.0/16'),
    IPv4Network('172.16.0.0/12'),
    IPv4Network('192.0.0.0/29'),
    IPv4Network('192.0.0.170/31'),
    IPv4Network('192.0.2.0/24'),
    IPv4Network('192.168.0.0/16'),
    IPv4Network('198.18.0.0/15'),
    IPv4Network('198.51.100.0/24'),
    IPv4Network('203.0.113.0/24'),
    IPv4Network('240.0.0.0/4'),
    IPv4Network('255.255.255.255/32'),
    IPv4Network('169.254.0.0/16'),
    IPv4Network('127.0.0.0/8'),
    IPv4Network('224.0.0.0/4'),
    IPv4Network('100.64.0.0/10'),
]
RESERVED_V6 = []
if args.exclude:
    for e in args.exclude:
        if ":" in e:
            RESERVED_V6.append(IPv6Network(e))

        else:
            RESERVED.append(IPv4Network(e))

IPV6_UNICAST = IPv6Network('2000::/3')

def subtract_cidr(sub_from, sub_by):
    for cidr_to_sub in sub_by:
        for n in sub_from:
            if n.cidr == cidr_to_sub:
                n.dead = True
                break

            if n.cidr.supernet_of(cidr_to_sub):
                if len(n.child) > 0:
                    subtract_cidr(n.child, sub_by)

                else:
                    n.child = [Node(b, n) for b in n.cidr.address_exclude(cidr_to_sub)]

                break

root = []
root_v6 = [Node(IPV6_UNICAST)]

with open("ipv4-address-space.csv", newline='') as f:
    f.readline() # skip the title

    reader = csv.reader(f, quoting=csv.QUOTE_MINIMAL)
    for cidr in reader:
        if cidr[5] == "ALLOCATED" or cidr[5] == "LEGACY":
            block = cidr[0]
            cidr = "%s.0.0.0%s" % (block[:3].lstrip("0"), block[-2:], )
            root.append(Node(IPv4Network(cidr)))

with open("delegated-apnic-latest") as f:
    for line in f:
        if 'apnic' in args.ipv4_list and "apnic|CN|ipv4|" in line:
            line = line.split("|")
            a = "%s/%d" % (line[3], 32 - math.log(int(line[4]), 2), )
            a = IPv4Network(a)
            subtract_cidr(root, (a,))

        elif "apnic|CN|ipv6|" in line:
            line = line.split("|")
            a = "%s/%s" % (line[3], line[4])
            a = IPv6Network(a)
            subtract_cidr(root_v6, (a,))

if 'ipip' in args.ipv4_list:
    with open("china_ip_list.txt") as f:
        for line in f:
            line = line.strip('\n')
            a = IPv4Network(line)
            subtract_cidr(root, (a,))

# get rid of reserved addresses
subtract_cidr(root, RESERVED)
# get rid of reserved addresses
subtract_cidr(root_v6, RESERVED_V6)

with open("routes4.conf", "w") as f:
    dump_bird(root, f)

with open("routes6.conf", "w") as f:
    dump_bird(root_v6, f)
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
unified-delay: false
tcp-concurrent: true
external-controller: 0.0.0.0:9090
secret: '123456789'

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

echo "重启 clash"

systemctl restart clash

echo "重启 bird"

cd /root/nchnroutes && make

echo "请执行 crontab -e 在末尾添加 0 5 * * * cd /root/nchnroutes && make"
