# LXC容器部分
## 模板下载
**https://github.com/Hamster-Prime/ospf-clash/releases/download/1.0.0/ubuntu-22.04.tar.zst**
## 容器创建
取消特权容器勾选
其他配置根据自己实际情况设定
## 容器优化
### 容器完善
创建完成后容器，不要开机，进入对应容器的选项
勾选一下选项
- 嵌套
- nfs
- smb
- fuse
### 容器配置文件
进入pve控制台，进入/etc/pve/lxc文件夹，修改对应的配置文件，添加以下内容
```
lxc.apparmor.profile: unconfined
lxc.cgroup.devices.allow: a
lxc.cap.drop: 
lxc.cgroup2.devices.allow: c 10:200 rwm
lxc.mount.entry: /dev/net/tun dev/net/tun none bind,create=file
```
### 安装Clash与OSPF服务
```
wget https://raw.githubusercontent.com/Hamster-Prime/ospf-clash/main/installospfclash.sh && chmod +x installospfclash.sh && ./installospfclash.sh
```
#### 根据脚本提示完成设置
# RouterOS设置部分
#### OSPF设置(全局)
```
/routing ospf instance add name=Clash router-id="本设备IP"
```
```
/routing ospf area add instance=Clash name=OSPF-Area-Clash
```
```
/routing ospf interface-template add area=OSPF-Area-Clash hello-interval=10s cost=10 priority=1 interfaces="你的网桥名字或者网卡名字" type=ptp
```
