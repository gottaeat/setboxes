#!/bin/bash
set +e

# - - check for root - - #
if [ "$(id -u)" -ne 0 ]; then
    echo "E: need root big man."
    exit 1
fi

# - - enter tmpdir - - #
TMPDIR="$(mktemp -d ./my_temp_dir_XXXXXX)"
cd "${TMPDIR}"

# - - variables - - #
POOLDIR="/mnt/mss/stuff/techy-bits/pools/setboxes"
MOUNT="${PWD}/nbdmount"
NBDDEV="/dev/nbd0"
IMGNAME="loggedin.qcow2"
IMGSIZE="10752M" # 10G + 512M
MIRROR='https://geo.mirror.pkgbuild.com/$repo/os/$arch'

# - - create image and partitions - - #
modprobe nbd

qemu-img create -f qcow2 "${IMGNAME}" "${IMGSIZE}"
qemu-nbd --connect="${NBDDEV}" "${IMGNAME}"

sgdisk --zap-all "${NBDDEV}"
sgdisk -n1:0:+512M "${NBDDEV}"
sgdisk -n2:0:0 "${NBDDEV}"

mkfs.fat -F 32 "${NBDDEV}"p1
mkfs.ext4 "${NBDDEV}"p2 -L arch-rootfs

# - - mounts - - #
mkdir "${MOUNT}"
mount "${NBDDEV}"p2 "${MOUNT}"
mkdir "${MOUNT}"/boot/
mount "${NBDDEV}"p1 "${MOUNT}"/boot/

# - - boostrap arch - - #
cat << EOF > pacman.conf
[options]
Architecture = auto

[core]
Include = mirrorlist

[extra]
Include = mirrorlist
EOF

echo "Server = ${MIRROR}" > mirrorlist

pacstrap -c -C ./pacman.conf -K -M "${MOUNT}" \
    base linux-zen openssh python3 sudo grub dosfstools efibootmgr

# - - larp as first boot - - #
rm -rfv "${MOUNT}"/etc/machine-id

arch-chroot "${MOUNT}" \
    /usr/bin/systemd-firstboot \
    --locale=C.UTF-8 \
    --timezone=UTC \
    --hostname=loggedin \
    --keymap=us

# - - root passwd - - #
echo -e "loggedin\nloggedin" | arch-chroot "${MOUNT}" /usr/bin/passwd "root"

# - - resolv - - #
echo "1.1.1.1" > "${MOUNT}"/etc/resolv.conf

# - - pacman - - #
rm -rfv "${MOUNT}/etc/pacman.d/gnupg/"

cat << EOF > "${MOUNT}"/etc/systemd/system/pacman-init.service
[Unit]
Description=Initializes Pacman keyring
Before=sshd.service cloud-final.service archlinux-keyring-wkd-sync.service
After=time-sync.target
ConditionFirstBoot=yes

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/bin/pacman-key --init
ExecStart=/usr/bin/pacman-key --populate

[Install]
WantedBy=multi-user.target
EOF

cat <<EOF > "${MOUNT}"/etc/pacman.d/mirrorlist
Server = https://geo.mirror.pkgbuild.com/\$repo/os/\$arch
Server = https://mirror.rackspace.com/archlinux/\$repo/os/\$arch
Server = https://mirror.leaseweb.net/archlinux/\$repo/os/\$arch
EOF

# - - services - - #
arch-chroot "${MOUNT}" \
    /bin/bash -e << EOF
source /etc/profile
systemctl enable sshd
systemctl enable systemd-networkd
systemctl enable pacman-init.service
EOF

# - - setup networking - - #
cat <<EOF >"${MOUNT}/etc/systemd/network/80-dhcp.network"
[Match]
Name=eth0

[Network]
DHCP=yes
EOF

# - - grub - - #
cp -rfv "${MOUNT}/boot/"{initramfs-linux-zen-fallback.img,initramfs-linux-zen.img}

sed -i 's/^GRUB_TIMEOUT=.*$/GRUB_TIMEOUT=1/' "${MOUNT}/etc/default/grub"
sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT=.*/GRUB_CMDLINE_LINUX_DEFAULT=\"net.ifnames=0\"/' "${MOUNT}/etc/default/grub"
arch-chroot "${MOUNT}" /usr/bin/grub-install --target=x86_64-efi --efi-directory=/boot --removable
arch-chroot "${MOUNT}" /usr/bin/grub-mkconfig -o /boot/grub/grub.cfg

# - - cleanup image - - #
sync -f "${MOUNT}/etc/os-release"
fstrim --verbose "${MOUNT}"
fstrim --verbose "${MOUNT}/boot"

# - - unmount - - #
pkill gpg-agent
umount --recursive "${MOUNT}"
qemu-nbd --disconnect "${NBDDEV}"

# - - send to pool - - #
mv "${IMGNAME}" "${POOLDIR}"

# - - cleanup - - #
cd ../
rm -rfv "${TMPDIR}"
