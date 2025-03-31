#!/usr/bin/python
import json

no_libvirt = False

try:
    import libvirt
except:
    no_libvirt = True


class GenInventory:
    _BOXES = ["gat", "solitude"]

    def __init__(self):
        self.conn = None
        self.libvirt_is_up = None
        self.in_vm = None

    def _get_libvirt_state(self):
        # try to connect to libvirtd, if cannot, assume on baremetal
        try:
            self.conn = libvirt.open("qemu:///system")
        except libvirt.libvirtError:
            # cannot connect to libvirt, assume on baremetal
            self.in_vm = False
            return

        self.libvirt_is_up = True

    def _check_domains(self):
        if self.libvirt_is_up:
            alivedoms = 0
            try:
                for domain in self._BOXES:
                    if self.conn.lookupByName(domain).isActive() == 1:
                        alivedoms += 1
            # except libvirt.libvirtError:
            except:
                # one of the specified domains are not up, assume on baremetal
                self.in_vm = False
                return

            # some are up some are down, error out
            if alivedoms >= 1 and alivedoms < len(self._BOXES):
                msg = "only some of the domains are up, cannot determine state"
                raise ValueError(msg)

            # libvirt is up, domains are up, we are operating on VMs
            self.in_vm = True

    def _dump_jayson(self):
        inventory_json = {
            "_meta": {
                "hostvars": {
                    "desk1": {
                        "ansible_host": "192.168.199.2" if self.in_vm else "gat",
                        "in_vm": self.in_vm,
                    },
                    "x230": {
                        "ansible_host": "192.168.199.3" if self.in_vm else "solitude",
                        "in_vm": self.in_vm,
                    },
                }
            },
            "crib": {"hosts": ["desk1", "x230"]},
        }

        print(json.dumps(inventory_json, indent=4))

    @staticmethod
    def libvirt_callback(userdata, err):
        pass

    def run(self):
        if no_libvirt:
            self.in_vm = False
        else:
            # libvirt exceptions, even when they are caught, print out the error
            # message for some reason, hijack the handler instead
            libvirt.registerErrorHandler(f=self.libvirt_callback, ctx=None)

            self._get_libvirt_state()

        self._check_domains()
        self._dump_jayson()


if __name__ == "__main__":
    gi = GenInventory()
    gi.run()
