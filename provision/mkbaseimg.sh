#!/bin/bash
. ./common

rootcheck

# - - enter tmpdir - - #
TMPDIR="$(mktemp -d ./my_temp_dir_XXXXXX)"
cd "${TMPDIR}"

# - - variables - - #
POOLDIR="/mnt/mss/stuff/techy-bits/pools/setboxes"
MOUNT="${PWD}/nbdmount"
NBDDEV="/dev/nbd0"
IMGNAME="loggedin.qcow2"
IMGSIZE="10G"
MIRROR='https://geo.mirror.pkgbuild.com/$repo/os/$arch'

# - - create image and partitions - - #
nbdcheck

qemu-img create -f qcow2 "${IMGNAME}" "${IMGSIZE}"
qemu-nbd --connect="${NBDDEV}" "${IMGNAME}"

sgdisk \
    --zap-all \
    --new=1:0:+512M \
    --new=2:0:0     \
    "${NBDDEV}"

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
echo "nameserver 1.1.1.1" > "${MOUNT}"/etc/resolv.conf

# - - mounts - - #
cat << EOF > "${MOUNT}"/etc/fstab
/dev/vda2 / ext4 defaults,noatime 0 1
/dev/vda1 /boot vfat defaults 0 0"
EOF

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

# - - allow ssh as root w/ passwd - - #
sed -i \
    -e 's/#PermitRootLogin .*/PermitRootLogin yes/' \
    -e 's/#PasswordAuthentication .*/PasswordAuthentication yes/' \
    "${MOUNT}"/etc/ssh/sshd_config

# - - setup networking - - #
cat <<EOF >"${MOUNT}/etc/systemd/network/80-dhcp.network"
[Match]
Name=eth0

[Network]
DHCP=yes
EOF

# - - grub - - #
cp -rfv "${MOUNT}/boot/"{initramfs-linux-zen-fallback.img,initramfs-linux-zen.img}

sed -i \
    -e 's/^GRUB_TIMEOUT=.*$/GRUB_TIMEOUT=1/' \
    -e 's/^GRUB_CMDLINE_LINUX_DEFAULT=.*/GRUB_CMDLINE_LINUX_DEFAULT=\"net.ifnames=0\"/' \
    "${MOUNT}/etc/default/grub"

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
