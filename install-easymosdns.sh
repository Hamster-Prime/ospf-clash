#!/bin/bash
apt update
echo "软件库升级完成"

# 安装所需软件
apt install unzip wget curl redis-server vim -y

#获取架构类型
architecture=$(uname -m)

#安装mosdns
if [ "$architecture" == "x86_64" ]; then
    file_url="https://github.com/Hamster-Prime/ospf-clash/releases/download/1.0.0/mosdns-linux-amd64.zip"
elif [ "$architecture" == "aarch64" ]; then
    file_url="https://github.com/Hamster-Prime/ospf-clash/releases/download/1.0.0/mosdns-linux-arm64.zip"
else
    echo "不支持您的系统架构 目前只支持x86_64与arm64 当前架构为: $architecture"
    exit 1
fi
wget "$file_url" || {
    echo "文件下载失败"
    exit 1
}
for file in mosdns*; do
    if [ -f "$file" ]; then
        unzip "$file" "mosdns" -d /usr/local/bin
    fi
done
wget https://github.com/Hamster-Prime/ospf-clash/releases/download/1.0.0/easymosdns.zip
chmod +x /usr/local/bin/mosdns
unzip easymosdns.zip
mv easymosdns-k-main /etc/mosdns
mkdir -p /etc/systemd/resolved.conf.d
tee /etc/systemd/resolved.conf.d/dns.conf <<EOF
[Resolve]
DNS=127.0.0.1
DNSStubListener=no
EOF
mv /etc/resolv.conf /etc/resolv.conf.backup
ln -s /run/systemd/resolve/resolv.conf /etc/resolv.conf
systemctl reload-or-restart systemd-resolved
mosdns service install -d /etc/mosdns -c config.yaml
mosdns service start
mv /etc/mosdns/config.yaml /etc/mosdns/config.yaml.orig
touch /etc/mosdns/config.yaml
wget -O /etc/mosdns/config.yaml https://raw.githubusercontent.com/Hamster-Prime/ospf-clash/main/easymosdnsconfig.yaml
mosdns service restart

#完成