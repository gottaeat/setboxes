# setboxes
setboxes does the following:
1. creates a backingStore qcow2 image that mimicks the arch cloud images
   - differences are that we target only EFI, our rootfs is ext4 and do not
     handle for cloud-init etc.
2. spins up a libVirt pool and network, creates volumes that overlay the base
   image, resizes these volumes to byte-perfectly fit the partitions in the
   baremetal targets, and spins up the domains.
3. these domains get configured once using both the `init.yml`, which performs
   one-off tasks for ansible to be ran proper such as the sshd configuration and
   the creation of the `ansible_user`, and by `site.yml`, which is the actual
   state of these baremetal targets that we aim for.
4. once the VMs get configured, they are shut off and with the help of
   `partclone` and `qemu-nbd`, these corresponding partitions for the targets
   are imaged.
5. targets get booted up using iPXE, the resulting images get written and inside
   a `chroot` the initramfs and efi bootloader entries are generated.
6. once rebooted, the `site.yml` playbook is called on them once again to
   finalize configuration.
7. from then on, the baremetal targets can be configured fully using ansible.

## stages
```sh
# 1. provision the backingStore image and deploy the VMs (as root)
cd provision/
pacman -Syyuu # base img creation requires an arch host as it uses pacstrap
./mkbaseimg.sh
./setlibvirt.sh
cd ../

# 2. install the ansible requirements
ansible-galaxy install -r requirements.yml

# 3. init the configuration of the VMs
ansible-playbook --flush-cache init.yml site.yml

# 4. cut the qcow2's to compressed partclone images
cd provision/
./mkimg.sh

# 5. restore partclone images in baremetal with:
#    unzstd --stdout -k $image \
#       | partclone.$fstype -r -s - -o $part
#
#    then chroot to rootfs and call:
#    ./provision/setbootmgr.sh $machine

# 6. handle baremetal targets once the images are written
ansible-playbook --flush-cache site.yml
```
