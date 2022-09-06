# KVM虚拟机（Windows 10）单显卡直通笔记

> 本仓库是用来记录操作步骤的，基本上是按照ledis大神的单[显卡直通教程](https://github.com/ledisthebest/LEDs-single-gpu-passthrough/blob/main/README-cn.md)一步一步来的。  

更新日期：2022年8月25日  

---  

## 我的电脑配置  

> - 处理器: AMD 锐龙 5800X  
> - 显卡: Radeon RX 6500XT  
> - 主版：TUF GAMING B550M  
> - 内存: 32GB 3600Mhz 双通道  
> - 系统: Arch Linux 5.19  
> - 桌面环境: XFCE4 X11

---  

## 主要步骤

### 一、配置一个简单的KVM（前提是硬件条件已具备,安装的内核是ArchLinux默认版本.自定义版本需要确认是否开启KVM相关选项,不会....）

(一)修改相关启动参数,准备一个可以安装虚拟机的软件环境(BIOS已提前开启硬件虚拟化)  

```shell
终端粘贴运行以下代码,找到VGA compatible行后面的[1002:743f]以及Audio device行后面的[1002:ab28],分别填写到下一步中的ids后面","隔开.
#
shopt -s nullglob
for g in `find /sys/kernel/iommu_groups/* -maxdepth 0 -type d | sort -V`; do
    echo "IOMMU Group ${g##*/}:"
    for d in $g/devices/*; do
        echo -e "\t$(lspci -nns ${d##*/})"
    done;
done;

#
sudo vim /etc/modules-load.d/virtio.conf

virtio-net
virtio-blk
virtio-scsi
virtio-serial
virtio-balloon
options vfio-pci ids=1002:743f,1002:ab28
options vfio-pci disable_idle_d3=1
options vfio-pci disable_vga=1
#
sudo vim /etc/modprobe.d/kvm_amd.conf

options kvm_amd nested=1
#
sudo vim /boot/loader/entries/2022-06-28_14-30-36_linux.conf
# Created by: archinstall
# Created on: 2022-06-28_14-30-36
title Arch Linux (linux)
linux /vmlinuz-linux
initrd /amd-ucode.img
initrd /initramfs-linux.img
options root=PARTUUID=62471b94-63c3-4b88-8771-53a860099dbf zswap.enabled=0 rootflags=subvol=/@ rw intel_pstate=no_hwp rootfstype=btrfs amd_iommu=on iommu=pt
#安装qemu相关
paru -S qemu-full libvirt edk2-ovmf virt-manager dnsmasq ebtables iptables bridge-utils gnu-netcat
#
sudo systemctl enable libvirtd

sudo systemctl enable virtlogd.socket

sudo virsh net-start default

sudo virsh net-autostart default
#重启,然后检查iommu
sudo dmesg | grep -e DMAR -e IOMMU
#应该输出:
[    0.645469] pci 0000:00:00.2: AMD-Vi: IOMMU performance counters supported
[    0.649231] pci 0000:00:00.2: AMD-Vi: Found IOMMU cap 0x40
[    0.649445] perf/amd_iommu: Detected AMD IOMMU #0 (2 banks, 4 counters/bank).
[    0.682474] AMD-Vi: AMD IOMMUv2 loaded and initialized
#KVM环境准备完毕
```

(二)安装Windows 10虚拟机  

1.打开Virtaul Machine Manager  

创建一个新虚拟机,选择[下载](https://www.microsoft.com/zh-cn/software-download/windows10ISO)好的本地Windows10.iso镜像,自动识别类型为win10(或者手动找到win10),内存大小8192(根据实际情况),CPU默认待会修改,磁盘类型默认,大小100G(根据实际情况),确认名字是否为win10,勾选启动前配置,点击完成  

2.修改虚拟机配置

- Overview:修改Name为:win10,Chipset为Q35,Firmware为OVMF_CODE.fd,每一项修改完记得应用.
- CPUs:去掉Configration下的Copy勾选,将Model修改为host-model,点开Topology,手动设置CPU拓扑,1x4x2.
- Boot Options:选择刚才的CDROM(win10镜像).
- DIsk,NIC:类型可以选择VirtIO(需提前准备红帽的[VirtIO驱动](https://github.com/virtio-win/virtio-win-pkg-scripts/blob/master/README.md))
- 如果选择了virtio类型的磁盘格式,还需要添加一个硬件,找到Storage,浏览找到virtio驱动,类型为CDROM,添加.

3.启动完成虚拟机的安装

### 二、Libvirt 钩子、QEMU和Libvirt的配置

```shell
#配置libvirt钩子
sudo mkdir /etc/libvirt/hooks
sudo vim /etc/libvirt/hooks/qemu
#内容:
#!/bin/bash

OBJECT="$1"
OPERATION="$2"

if [[ $OBJECT == "win10" ]]; then
        case "$OPERATION" in
                "prepare")
                systemctl start libvirt-nosleep@"$OBJECT"  2>&1 | tee -a /var/log/libvirt/custom_hooks.log
                /bin/vfio-startup.sh 2>&1 | tee -a /var/log/libvirt/custom_hooks.log
                ;;

            "release")
                systemctl stop libvirt-nosleep@"$OBJECT"  2>&1 | tee -a /var/log/libvirt/custom_hooks.log  
                /bin/vfio-teardown.sh 2>&1 | tee -a /var/log/libvirt/custom_hooks.log
                ;;
        esac
#

sudo vim /etc/libvirt/hooks/vfio-startup.sh
#内容:
#注意:我的显示管理器用的是sddm,pci后面的数字为第一步得到的两行的开头数字,原格式为09:00.0和09:00.1,写成下面的格式,参考着替换.
#下一个文件也是同样的:
set -x
systemctl stop sddm
echo 0 > /sys/class/vtconsole/vtcon0/bind
echo 0 > /sys/class/vtconsole/vtcon1/bind
echo efi-framebuffer.0 > /sys/bus/platform/drivers/efi-framebuffer/unbind
sleep 10
modprobe -r amdgpu
modprobe -r radeon
virsh nodedev-detach pci_0000_09_00_0
virsh nodedev-detach pci_0000_09_00_1
modprobe vfio_pci
modprobe vfio
modprobe vfio_iommu_type1
modprobe vfio_virqfd

#
sudo vim /etc/libvirt/hooks/vfio-teardown.sh
#内容:
set -x
sleep 10
modprobe -r vfio_pci
modprobe -r vfio
modprobe -r vfio_iommu_type1
modprobe -r vfio_virqfd
virsh nodedev-reattach pci_0000_09_00_0
virsh nodedev-reattach pci_0000_09_00_1
echo 1 > /sys/class/vtconsole/vtcon0/bind
echo 1 > /sys/class/vtconsole/vtcon1/bind
echo efi-framebuffer.0 > /sys/bus/platform/drivers/efi-framebuffer/bind
modprobe amdgpu
modprobe radeon
sleep 5
systemctl start sddm

#
sudo chmod +x /etc/libvirt/hooks/*
sudo ln -s /etc/libvirt/hooks/vfio-startup.sh /bin/vfio-startup.sh
sudo ln -s /etc/libvirt/hooks/vfio-teardown.sh /bin/vfio-teardown.sh

sudo vim /etc/systemd/system/libvirt-nosleep@.service
#内容:
[Unit]
Description=Preventing sleep while libvirt domain "%i" is running
[Service]
Type=simple
ExecStart=/usr/bin/systemd-inhibit --what=sleep --why="Libvirt domain \"%i\" is running" --who=%U --mode=block sleep infinity

#
sudo chmod 644 -R /etc/systemd/system/libvirt-nosleep@.service
sudo chown root:root /etc/systemd/system/libvirt-nosleep@.service

sudo vim /etc/libvirt/libvirtd.conf
#编辑这两行,把注释去掉,
unix_sock_group = "libvirt"
unix_sock_rw_perms = "0770"
#文件最后面加上
log_filters="1:qemu"
log_outputs="1:file:/var/log/libvirt/libvirtd.log"

#
sudo vim /etc/libvirt/qemu.conf
#把 user = "root" 改成 user = "现在你的用户名",
#group = "root" 改成 group = "libvirt"

sudo usermod -aG libvirt,storage,power ${USER}

sudo systemctl restart libvirtd.service

sudo systemctl restart virtlogd.socket

```

### 三、显卡直通  

保险起见还是用cpu-z吧,不用双系统的话pe好多都带cpu-z的估计也可以,我是根据[ArchWiki](https://wiki.archlinux.org/index.php/PCI_passthrough_via_OVMF#UEFI_(OVMF)_compatibility_in_VBIOS)导出显卡固件,我不太确定我的步骤有没有问题,根据上面提到的数字id自行替换,有转义符是我用Tab补全命令时候出来的  

```shell
git clone https://github.com/awilliam/rom-parser

cd rom-parser && make

mkdir -p /home/你的用户名/kvm

su

echo 1 > /sys/bus/pci/devices/0000\:09\:00.0/rom

cat /sys/bus/pci/devices/0000\:09\:00.0/rom > /home/你的用户名/kvm/GPU.rom

echo 0 > /sys/bus/pci/devices/0000\:09\:00.0/rom

./rom-parser /home/你的用户名/kvm/GPU.rom

exit

cd /home/你的用户名/kvm
sudo chmod -R 660 GPU.rom
sudo chown 你的用户名:users GPU.rom
```

打开Virtual Machine Manager,编辑win10虚拟机,添加最开始的两个PCI device,添加自己的USB设备,键盘鼠标是必要的,其他比如USB耳机音箱啥的根据实际情况添加,删除能删除的不需要的,按原教程我删不掉Display Spide,只能把Video改成none.注意启动项(Boot Options)不要在勾选CDROM了,应该只勾选已经装上系统的Disk.  

别急还需要几个步骤:  

先从最开始的管理窗口的菜单栏里找到Edit->Preferences,启用XML编辑.  

回到正在编辑的虚拟机窗口  

在Overview的XML里面:

```xml
#找到</hyperv>关键字,他的前面和后面应该分别加上两个内容并应用:
 <vendor_id state="on" value="randomid"/>
    </hyperv>
    <kvm>
      <hidden state="on"/>
    </kvm>

#找到</cpu>,在他的前面加上:
<feature policy="require" name="topoext"/>
</cpu>

#
```

在之前添加的**两个**PCI device的XML里面:

```xml
#找到</source>关键字,在后面加上相应内容,注意CPU.rom的位置,同样的内容两个XML文件里都要加.
</sourece>
<rom bar="on" file="/home/你的用户名/kvm/GPU.rom"/>
```

到这里不出意外应该就可以开启虚拟机了,然后自己到官网下载驱动,安装后才能识别显卡,至少我的电脑就这样成功了,感谢LEDs大大,因为没有看到amd的hooks,参考nvidia的改了下,稀里糊涂的就进去了,特此记录一下步骤
