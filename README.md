# 这是一个基于OSPF路由协议的RouterOS分流方案
### 特别感谢
> [孔昊天的折腾日记](https://www.youtube.com/@user-ek1qg7ti5r)  
> [allanchen2019](https://github.com/allanchen2019)  
> [dndx](https://github.com/dndx)  
> [Nathan](https://nathanyu.me/author/nathanyu/)
### 本项目相关知识引用自
> [haotianlPM/rosrbgprouter](https://github.com/haotianlPM/rosrbgprouter)  
> [allanchen2019/ospf-over-wireguard](https://github.com/allanchen2019/ospf-over-wireguard)  
> [dndx/nchnroutes](https://github.com/dndx/nchnroutes)  
> [使用Clash在Debian系统上用TProxy模式搭建透明代理](https://nathanyu.me/clash-transparent-proxy-on-debian/)
---
# LXC容器配置部分
### 1. 模板下载
**https://github.com/Hamster-Prime/ospf-clash/releases/download/1.0.0/ubuntu-22.04.tar.zst**
### 2. 容器创建
取消特权容器勾选
其他配置根据自己实际情况设定
### 3. 容器完善
创建完成后容器，不要开机，进入对应容器的选项
勾选一下选项
- 嵌套
- nfs
- smb
- fuse
### 4. 容器配置文件
进入pve控制台，进入/etc/pve/lxc文件夹，修改对应的配置文件，添加以下内容
```
lxc.apparmor.profile: unconfined
lxc.cgroup.devices.allow: a
lxc.cap.drop: 
lxc.cgroup2.devices.allow: c 10:200 rwm
lxc.mount.entry: /dev/net/tun dev/net/tun none bind,create=file
```
启动容器并进入控制台
### 5. 安装Clash与OSPF服务
#### * 选择你喜欢的方式并根据脚本提示完成设置
OSPF + Clash TUN
```
wget https://raw.githubusercontent.com/Hamster-Prime/ospf-clash/main/installospfclash.sh && chmod +x installospfclash.sh && ./installospfclash.sh
```
OSPF + Clash TProxy + MosDNS
```
wget https://raw.githubusercontent.com/Hamster-Prime/ospf-clash/main/install.sh && chmod +x install.sh && ./install.sh
```
# RouterOS配置部分
### 1. 创建 Routing Table
```
/routing table add name=Clash_VPN fib
```
### 2. OSPF 设置
```
/routing ospf instance add name=Clash router-id="RouterOS的IP" routing-table=Clash_VPN
/routing ospf area add instance=Clash name=OSPF-Area-Clash
/routing ospf interface-template add area=OSPF-Area-Clash hello-interval=10s cost=10 priority=1 interfaces="LAN网桥名字或者网卡名字" type=broadcast networks="内网网段,比如10.0.0.0/24"
```
### 3. Firewall Mangle 设置
```
/ip firewall mangle add action=accept chain=prerouting src-address="安装Clash服务器的IP" protocol=!ospf
/ip firewall mangle add action=mark-routing new-routing-mark=Clash_VPN dst-address-type=!local chain=prerouting src-address-list=!No_Proxy
```
### 4. 跳过代理
```
/ip firewall address-list add address="不想代理的主机IP地址" list=No_Proxy
```
