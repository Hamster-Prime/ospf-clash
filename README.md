# LXC容器部分:

#### 推荐使用pve中的debian-11-standard_11.7-1_amd64.tar.zst模板

`wget https://raw.githubusercontent.com/Hamster-Prime/ospf-clash/main/installospfclash.sh && chmod +x installospfclash.sh && ./installospfclash.sh`

#### 根据脚本提示完成设置

# RouterOS设置部分:

#### OSPF设置(全局)

`/routing ospf instance add name=Clash router-id="本设备IP"`

`/routing ospf area add instance=Clash name=OSPF-Area-Clash`

`/routing ospf interface-template add area=OSPF-Area-Clash hello-interval=10s interfaces="你的网桥名字或者网卡名字" type=ptp`
