# LXC容器部分

# 创建lxc容器模板
## 乌班图下载
```
/var/lib/vz/template/cache
#上传文件夹
```
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
### 开启第三方登录
```
nano /etc/ssh/sshd_config
service ssh restart
```
### 设置东八区与中文
```
timedatectl set-timezone Asia/Shanghai
# 追加本地语言配置
echo "zh_CN.UTF-8 UTF-8" >> /etc/locale.gen
# 重新配置本地语言
dpkg-reconfigure locales
# 指定本地语言
export LC_ALL="zh_CN.UTF-8"
#中文的设置
```
### 常用软件安装
```
apt install zsh git vim curl -y
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
```
### 添加未知命令提示工具
```
nano ~/.zshrc

. /etc/zsh_command_not_found
#在文件末尾添加以上内容

source ~/.zshrc
#配置生效
```
### 安装Clash与OSPF服务

`wget https://raw.githubusercontent.com/Hamster-Prime/ospf-clash/main/installospfclash.sh && chmod +x installospfclash.sh && ./installospfclash.sh`

#### 根据脚本提示完成设置

# RouterOS设置部分

#### OSPF设置(全局)

`/routing ospf instance add name=Clash router-id="本设备IP"`

`/routing ospf area add instance=Clash name=OSPF-Area-Clash`

`/routing ospf interface-template add area=OSPF-Area-Clash hello-interval=10s cost=10 priority=1 interfaces="你的网桥名字或者网卡名字" type=ptp`
