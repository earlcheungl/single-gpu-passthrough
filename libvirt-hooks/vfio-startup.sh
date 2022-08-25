set -x

systemctl stop sddm

echo 0 > /etc/class/vtconsole/vtcon0/bind
echo 0 > /etc/class/vtconsole/vtcon1/bind

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

