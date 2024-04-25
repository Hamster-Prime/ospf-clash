#!/bin/bash

while true; do
    # 提示用户选择操作
    PS3="请选择要执行的操作： "
options=("安装Clash_TUN" "安装Clash_TProxy" "安装Bird并配置OSPF" "退出")
select opt in "${options[@]}"; do
    case "$REPLY" in
        1)  # 复制文件
            wget https://raw.githubusercontent.com/Hamster-Prime/ospf-clash/main/install-clash_tun.sh && chmod +x install-clash_tun.sh && ./install-clash_tun.sh
            ;;
        2)  # 移动文件
            wget https://raw.githubusercontent.com/Hamster-Prime/ospf-clash/main/install-clash_tproxy.sh && chmod +x install-clash_tproxy.sh && ./install-clash_tproxy.sh
            ;;
        3)  # 删除文件
            wget https://raw.githubusercontent.com/Hamster-Prime/ospf-clash/main/install-ospf.sh && chmod +x install-ospf.sh && ./install-ospf.sh
            ;;
        4)  # 退出
            echo "退出脚本"
            exit 0
            ;;
        *)  # 对于无效选项，显示提示信息
            echo "无效选项，请重新选择"
            ;;
        esac
    done
done
