#!/bin/bash
while true; do
    # 提示用户选择操作
    echo ""
    echo "1. OSPF + Clash TUN"
    echo ""
    echo "2. OSPF + Clash TProxy"
    echo ""
    echo "3. 仅OSPF"
    echo ""
    echo "4. 退出"
    echo ""
    read -p "请输入操作编号： " option

    case "$option" in
        1)  wget https://raw.githubusercontent.com/Hamster-Prime/ospf-clash/main/install-ospf-clash_tun.sh && chmod +x install-ospf-clash_tun.sh && ./install-ospf-clash_tun.sh
            ;;
        2)  wget https://raw.githubusercontent.com/Hamster-Prime/ospf-clash/main/install-ospf-clash_tproxy.sh && chmod +x install-ospf-clash_tproxy.sh && ./install-ospf-clash_tproxy.sh
            ;;
        3)  wget https://raw.githubusercontent.com/Hamster-Prime/ospf-clash/main/install-ospf.sh && chmod +x install-ospf.sh && ./install-ospf.sh
            ;;
        4)  echo "退出脚本"
            exit 0
            ;;
        *)  echo "无效选项，请重新选择"
            continue
            ;;
    esac
done
