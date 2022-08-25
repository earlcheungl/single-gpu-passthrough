set -x

sleep 10

modprobe -r vfio_pci
modprobe -r vfio
modprobe -r vfio_iommu_type1
modprobe -r vfio_virqfd

virsh nodedev-reattach pci_0000_09_00_0
virsh nodedev-reattach pci_0000_09_00_1

echo 1 > /etc/class/vtconsole/vtcon0/bind
echo 1 > /etc/class/vtconsole/vtcon1/bind

echo efi-framebuffer.0 > /sys/bus/platform/drivers/efi-framebuffer/bind

modprobe amdgpu
modprobe radeon

sleep 5

systemctl start sddm
