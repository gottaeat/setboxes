# setboxes

### before ansible
replicate an arch cloudimg but with an ext4 rootfs and cruft removed, provision
dummy VMs.
```sh
cd provision/
sudo ./mkbaseimg.sh
sudo ./setlibvirt.sh
cd ../
```

### initial ansible in VM
```sh
# install collections and roles
ansible-galaxy collection install -r requirements.yml

# run the playbooks against the VMs
time ansible-playbook -i \
    inventory.yml \
    --flush-cache \
    --ask-become-pass \
    01-initial_setup.yml 02-system_config.yml 03-mss_wares.yml 04-services.yml
```
