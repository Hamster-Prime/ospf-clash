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

mv /root/nchnroutes/produce.py /root/nchnroutes/produce.py.orig

tee /etc/bird/bird.conf <<EOF
#!/usr/bin/env python3
import argparse
import csv
from ipaddress import IPv4Network, IPv6Network
import math

parser = argparse.ArgumentParser(description='Generate non-China routes for BIRD.')
parser.add_argument('--exclude', metavar='CIDR', type=str, nargs='*',
                    help='IPv4 ranges to exclude in CIDR format')
parser.add_argument('--next', default="$selected_interface", metavar = "INTERFACE OR IP",
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

make -C /root/nchnroutes

echo "安装完成"

echo "请执行 crontab -e 在末尾添加 0 5 * * * cd /root/nchnroutes && make"
