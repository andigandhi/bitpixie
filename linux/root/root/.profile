alias get-vmk="su bitpix -c exploit"
echo ""
echo -e "\e[33;1m[+]\e[0m \e[33mThe BitLocker partition may be the following\e[0m" >&2
fdisk -l | grep "Microsoft basic data" | cut -d' ' -f0
echo ""
