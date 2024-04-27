#!/bin/bash
while true; do
    # 提示用户选择操作
    echo "请选择要执行的操作："
    echo "1. 安装 OSPF + Clash_TUN"
    echo "2. 安装 OSPF + Clash_TProxy"
    echo "3. 安装Bird并配置OSPF"
    echo "4. 退出"
    read -p "请输入操作编号： " option

    # 根据用户输入执行相应操作
    case "$option" in
        1)  # 安装 OSPF + Clash_TUN
            wget https://raw.githubusercontent.com/Hamster-Prime/ospf-clash/main/install-ospf-clash_tun.sh && chmod +x install-ospf-clash_tun.sh && ./install-ospf-clash_tun.sh
            ;;
        2)  # 安装 OSPF + Clash_TProxy
            wget https://raw.githubusercontent.com/Hamster-Prime/ospf-clash/main/install-ospf-clash_tproxy.sh && chmod +x install-ospf-clash_tproxy.sh && ./install-ospf-clash_tproxy.sh
            ;;
        3)  # 仅安装OSPF
            wget https://raw.githubusercontent.com/Hamster-Prime/ospf-clash/main/install-ospf.sh && chmod +x install-ospf.sh && ./install-ospf.sh
            ;;
        4)  # 退出
            echo "退出脚本"
            exit 0
            ;;
        *)  # 对于无效选项，显示提示信息
            echo "无效选项，请重新选择"
            continue
            ;;
    esac
done
