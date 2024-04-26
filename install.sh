#!/bin/bash
apt update
apt install bird unzip git nftables make curl wget gzip redis-server vim sudo -y

# 检测eth0的IP
ip_address=$(ip addr show eth0 | grep -oP 'inet \K[\d.]+')

#安装clash
architecture=$(uname -m)
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

# 安装mosdns
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
echo "开始解压"
for file in mihomo*; do
    if [ -f "$file" ]; then
        echo "解压 $file ..."
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
tee /etc/mosdns/config.yaml <<EOF
# EasyMosdns v3.0(Final Release)
# https://apad.pro/easymosdns
log:
    file: "./mosdns.log"
    level: error

data_providers:
  - tag: chinalist
    file: ./rules/china_domain_list.txt
    auto_reload: true
  - tag: gfwlist
    file: ./rules/gfw_domain_list.txt
    auto_reload: true
  - tag: cdncn
    file: ./rules/cdn_domain_list.txt
    auto_reload: true
  - tag: chinaip
    file: ./rules/china_ip_list.txt
    auto_reload: true
  - tag: gfwip
    file: ./rules/gfw_ip_list.txt
    auto_reload: true
  - tag: adlist
    file: ./rules/ad_domain_list.txt
    auto_reload: true
  - tag: ecscn
    file: ./ecs_cn_domain.txt
    auto_reload: true
  - tag: ecsnoncn
    file: ./ecs_noncn_domain.txt
    auto_reload: true
  - tag: hosts
    file: ./hosts.txt
    auto_reload: true

plugins:
  # 缓存的插件
  # [lan|wan]
  - tag: cache_lan
    type: cache
    args:
      size: 8192
      redis: "redis://127.0.0.1:6379/0"
      lazy_cache_ttl: 86400
      cache_everything: true
      lazy_cache_reply_ttl: 1
  - tag: cache_wan
    type: cache
    args:
      size: 131072
      compress_resp: true
      redis: "redis://127.0.0.1:6379/0"
      lazy_cache_ttl: 86400
      cache_everything: true
      lazy_cache_reply_ttl: 5

  # 统计插件
  - tag: met
    type: "metrics_collector" 
    
  # Hosts的插件
  - tag: hosts
    type: hosts
    args:
      hosts:
        - "provider:hosts"

  # 获取ECS的插件
  - tag: ecs_auto
    type: ecs
    args:
      auto: true
      force_overwrite: false
      
  # 指定ECS的插件
  - tag: ecs_global
    type: ecs
    args:
      auto: false
      ipv4: "168.95.1.0"
      ipv6: "2001:b000:168::"
      force_overwrite: false

  # 匹配ECS的插件
  - tag: ecs_is_lan
    type: query_matcher
    args:
      ecs: 
        - "0.0.0.0/8"
        - "10.0.0.0/8"
        - "100.64.0.0/10"
        - "127.0.0.0/8"
        - "169.254.0.0/16"
        - "172.16.0.0/12"
        - "192.0.0.0/24"
        - "192.0.2.0/24"
        - "198.18.0.0/15"
        - "192.88.99.0/24"
        - "192.168.0.0/16"
        - "198.51.100.0/24"
        - "203.0.113.0/24"
        - "224.0.0.0/3"
        - "::1/128"
        - "fc00::/7"
        - "fe80::/10"
  - tag: ecs_is_cn
    type: query_matcher
    args:
      ecs: 
        - "provider:chinaip"

  # 调整TTL的插件
  # [1m|5m|1h]
  - tag: ttl_1m
    type: ttl
    args:
      minimal_ttl: 60
      maximum_ttl: 3600
  - tag: ttl_5m
    type: ttl
    args:
      minimal_ttl: 300
      maximum_ttl: 86400
  - tag: ttl_1h
    type: ttl
    args:
      minimal_ttl: 3600
      maximum_ttl: 86400

  # 匹配TYPE12类型请求的插件
  - tag: qtype12
    type: query_matcher
    args:
      qtype: [12]

  # 匹配TYPE65类型请求的插件
  - tag: qtype65
    type: query_matcher
    args:
      qtype: [65]

  # 匹配TYPE255类型请求的插件
  - tag: qtype255
    type: query_matcher
    args:
      qtype: [255]

  # 匹配RCODE2的插件
  - tag: response_server_failed
    type: response_matcher
    args:
      rcode: [2]

  # 屏蔽请求的插件
  - tag: black_hole
    type: blackhole
    args:
      rcode: 0
      ipv4: "0.0.0.0"
      ipv6: "::"

  # 匹配无效域名的插件
  - tag: query_is_non_domain
    type: query_matcher
    args:
      domain:
        - "keyword::"

  # 匹配本地域名的插件
  - tag: query_is_local_domain
    type: query_matcher
    args:
      domain:
        - "provider:chinalist"

  # 匹配污染域名的插件
  - tag: query_is_non_local_domain
    type: query_matcher
    args:
      domain:
        - "provider:gfwlist"

  # 匹配CDN域名的插件
  - tag: query_is_cdn_cn_domain
    type: query_matcher
    args:
      domain:
        - "provider:cdncn"

  # 匹配广告域名的插件
  - tag: query_is_ad_domain
    type: query_matcher
    args:
      domain:
        - "provider:adlist"

  # 匹配强制本地解析域名的插件
  - tag: query_is_cn_domain
    type: query_matcher
    args:
      domain:
        - "provider:ecscn"

  # 匹配强制非本地解析域名的插件
  - tag: query_is_noncn_domain
    type: query_matcher
    args:
      domain:
        - "provider:ecsnoncn"

  # 匹配本地IP的插件
  - tag: response_has_local_ip
    type: response_matcher
    args:
      ip:
        - "provider:chinaip"

  # 匹配污染IP的插件
  - tag: response_has_gfw_ip
    type: response_matcher
    args:
      ip:
        - "provider:gfwip"

  # 转发至本地服务器的插件
  - tag: forward_local
    type: fast_forward
    args:
      upstream:
        - addr: "223.5.5.5"
        - addr: "tls://120.53.53.53:853"
          enable_pipeline: true

  # 转发至远程服务器的插件
  - tag: forward_remote
    type: fast_forward
    args:
      upstream:
        - addr: "tcp://208.67.220.220:5353"
          enable_pipeline: true
          #socks5: "127.0.0.1:1080"
        - addr: "tls://8.8.4.4"
          enable_pipeline: true
          #socks5: "127.0.0.1:1080"

  # 转发至分流服务器的插件
  - tag: forward_easymosdns
    type: fast_forward
    args:
      upstream:
        - addr: "https://doh.apad.pro/dns-query"
          bootstrap: "119.29.29.29"
          #dial_addr: "ip:port"
          #enable_http3: true

  # 主要的运行逻辑插件
  # sequence 插件中调用的插件 tag 必须在 sequence 前定义
  # 否则 sequence 找不到对应插件
  - tag: main_sequence
    type: sequence
    args:
      exec:
        # met统计插件
        - met

        # 详细记录显示插件
        - _query_summary
        
        # 域名映射IP
        - hosts

        # 屏蔽TYPE65与无效类型请求
        - if: "[qtype65] || (query_is_non_domain)"
          exec:
            - black_hole
            - ttl_1h
            - _return

        # 优化PRT与ANY类型请求
        - if: "[qtype12] || [qtype255]"
          exec:
            - _no_ecs
            - forward_local
            - ttl_1h
            - _return

        # 缓存ECS
        - ecs_auto
        - _edns0_filter_ecs_only
        - if: ecs_is_lan
          exec:
            - cache_lan
            - _no_ecs
          else_exec:
            - cache_wan

        # 强制用本地服务器解析
        - if: query_is_cn_domain
          exec:
            - forward_local
            - ttl_5m
            - _return

        # 强制用非本地服务器解析
        - if: query_is_noncn_domain
          exec:
            # 优先返回ipv4结果
            - _prefer_ipv4
            - ecs_global
            - primary:
                # 默认用分流服务器
                - forward_easymosdns
              secondary:
                # 超时用远程服务器
                - forward_remote
              fast_fallback: 2500
              always_standby: false
            - ttl_5m
            - _return

        # 屏蔽广告域名
        - if: query_is_ad_domain
          exec:
          - black_hole
          - ttl_1h
          - _return

        # 已知的本地域名或CDN域名用本地服务器解析
        - if: "(query_is_local_domain) || (query_is_cdn_cn_domain)"
          exec:
            - primary:
                # 默认用本地服务器
                - forward_local
                - ttl_1m
              secondary:
                # 超时用分流服务器
                - forward_easymosdns
                - ttl_5m
              fast_fallback: 25
              always_standby: false
            # 预防已知的本地域名临时污染
            - if: "(! response_has_gfw_ip)"
              exec:
                - _return

        # 已知的污染域名用分流服务器或远程服务器解析
        - if: query_is_non_local_domain
          exec:
            # 优先返回ipv4结果
            - _prefer_ipv4
            - ecs_global
            - primary:
                # 默认用分流服务器
                - forward_easymosdns
              secondary:
                # 超时用远程服务器
                - forward_remote
              fast_fallback: 2500
              always_standby: false
            - ttl_5m
            - _return

        # 剩下的未知域名用IP分流
        # 优先返回ipv4结果
        - _prefer_ipv4
        - primary:
            # 默认用分流服务器
            - forward_easymosdns
            - if: response_server_failed
              exec:
                - forward_local
                - _return
            - ecs_global
            - if: "(! ecs_is_cn) && (! response_has_local_ip) && [_response_valid_answer]"
              exec:
                - forward_easymosdns
          secondary:
            # 超时用本地分流器
            - forward_remote
            - if: response_has_local_ip
              exec:
                - forward_local
                - _return
            - ecs_global
            - if: "(! ecs_is_cn) && [_response_valid_answer]"
              exec:
                - forward_remote
          fast_fallback: 2500
          always_standby: false
        - ttl_5m

servers:
  - exec: main_sequence
    timeout: 6
    listeners:
      - protocol: udp
        addr: "0.0.0.0:53"
      - protocol: tcp
        addr: "0.0.0.0:53"
      #- protocol: http
      #  addr: "127.0.0.1:9053"
      #  url_path: "/dns-query"
      #  get_user_ip_from_header: "X-Forwarded-For"
      #- protocol: tls             
      #  addr: "0.0.0.0:853"
      #  cert: "/etc/mosdns/yourdomain.cert"  # TLS 所需证书文件。
      #  key: "/etc/mosdns/yourdomain.key"    # TLS 所需密钥文件。

api:
    http: "127.0.0.1:9080"
EOF
mosdns service restart

#配置bird服务
echo "systemd 服务创建完成"
echo "开始创建 bird 配置文件"
mv /etc/bird/bird.conf /etc/bird/bird.conf.orig
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

#写入clash配置文件
echo "请输入机场订阅地址"
read proxyurl
tee /etc/clash/config.yaml <<EOF
mode: rule
ipv6: false
log-level: info
allow-lan: true
mixed-port: 7890
tproxy-port: 7899
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
    - 127.0.0.1
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

	chain clash-tproxy {
		fib daddr type { unspec, local, anycast, multicast } return
		ip daddr @local_ipv4 return
		udp dport { 123 } return
		meta l4proto { tcp, udp } meta mark set 1 tproxy to :7899 accept
	}

	chain mangle-prerouting {
		type filter hook prerouting priority mangle; policy accept;
		iifname { lo, eth0 } meta l4proto { tcp, udp } ct direction original jump clash-tproxy
	}
}" >> /etc/nftables.conf

#重启nftables
nft -f /etc/nftables.conf

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
echo "请执行 crontab -e 在末尾添加 0 5 * * * make -C /root/nchnroutes"
echo "请访问 http://$ip_address:9090/ui 进入管理面板后填入 http://$ip_address:9090"
