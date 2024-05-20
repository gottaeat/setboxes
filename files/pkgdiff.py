#!/usr/bin/python3
# pylint: disable=missing-module-docstring,missing-class-docstring
# pylint: disable=missing-function-docstring
# pylint: disable=too-many-instance-attributes

import subprocess
import json
import socket

import yaml


class PkgDiff:
    _REPODIR = "/mss/repo"

    def __init__(self):
        self.local_pkglist = []
        self.ansible_pkglist = []

        self.local_hostname = None
        self.local_metaname = None

        self.ansible_inventory = None
        self.ansible_hosts = None

        self.main_pkgs_base = None
        self.main_pkgs_multimedia = None
        self.main_pkgs_desktop_extra = None
        self.main_pkgs_router = None
        self.main_pkgs_bios = None
        self.main_pkgs_wlan_tools = None

        self.user_pkgs_base = None
        self.user_pkgs_multimedia = None

        self.main_pkgs_extra = None
        self.user_pkgs_extra = None

    @staticmethod
    def runcmd(string):
        cmdline = string.split(" ")

        try:
            proc = subprocess.run(cmdline, check=True, capture_output=True)
        except subprocess.CalledProcessError as except_obj:
            raise ValueError(except_obj.stderr.decode("utf-8")) from except_obj

        return proc.stdout.decode("utf-8")

    def get_local_pkglist(self):
        pacman_out = self.runcmd("pacman -Qe").split()

        pkg_iter, local_pkglist = 0, []
        while pkg_iter < len(pacman_out):
            local_pkglist.append(pacman_out[pkg_iter])
            pkg_iter += 2

        self.local_pkglist = sorted(set(local_pkglist))

    def parse_ansible(self):
        # - - inventory + hosts - - #
        self.ansible_inventory = json.loads(
            self.runcmd(f"{self._REPODIR}/inventory.py")
        )
        self.ansible_hosts = self.ansible_inventory["_meta"]["hostvars"]

        self.local_hostname = socket.gethostname()

        for key, val in self.ansible_hosts.items():
            if val["ansible_host"] == self.local_hostname:
                self.local_metaname = key
                break

        if self.local_metaname is None:
            raise ValueError(f"{self.local_hostname} is not in the inventory.")

        # - - packages - - #
        # main
        with open(
            f"{self._REPODIR}/files/pkglist/main.yml", "r", encoding="utf-8"
        ) as yaml_file:
            main_pkgs = yaml.load(yaml_file.read(), Loader=yaml.Loader)

        self.main_pkgs_base = main_pkgs["main_pkgs_base"]
        self.main_pkgs_multimedia = main_pkgs["main_pkgs_multimedia"]
        self.main_pkgs_desktop_extra = main_pkgs["main_pkgs_desktop_extra"]
        self.main_pkgs_router = main_pkgs["main_pkgs_router"]
        self.main_pkgs_bios = main_pkgs["main_pkgs_bios"]
        self.main_pkgs_wlan_tools = main_pkgs["main_pkgs_wlan_tools"]

        # aur
        with open(
            f"{self._REPODIR}/files/pkglist/user.yml", "r", encoding="utf-8"
        ) as yaml_file:
            user_pkgs = yaml.load(yaml_file.read(), Loader=yaml.Loader)

        self.user_pkgs_base = user_pkgs["user_pkgs_base"]
        self.user_pkgs_multimedia = user_pkgs["user_pkgs_multimedia"]

        # user requested
        with open(
            f"{self._REPODIR}/host_vars/{self.local_metaname}.yml",
            "r",
            encoding="utf-8",
        ) as yaml_file:
            host_vars = yaml.load(yaml_file.read(), Loader=yaml.Loader)

        self.main_pkgs_extra = host_vars["main_pkgs_extra"]
        self.user_pkgs_extra = host_vars["user_pkgs_extra"]

    def mkpkglist(self):
        # pkglist groups
        base = [
            self.main_pkgs_base,
            self.user_pkgs_base,
            self.main_pkgs_extra,
            self.user_pkgs_extra,
        ]

        desktop = [
            self.main_pkgs_multimedia,
            self.user_pkgs_multimedia,
            self.main_pkgs_desktop_extra,
            self.main_pkgs_wlan_tools,
        ]

        router = [
            self.main_pkgs_router,
        ]

        bios = [
            self.main_pkgs_bios,
        ]

        # base
        ansible_pkglist = []

        for pkglist in base:
            ansible_pkglist.extend(pkglist)

        # desktop
        if self.local_metaname in self.ansible_inventory["desktops"]["hosts"]:
            for pkglist in desktop:
                ansible_pkglist.extend(pkglist)

        # router
        if self.local_metaname in self.ansible_inventory["routers"]["hosts"]:
            for pkglist in router:
                ansible_pkglist.extend(pkglist)

        # mbr
        if self.local_metaname in self.ansible_inventory["bios"]["hosts"]:
            for pkglist in bios:
                ansible_pkglist.extend(pkglist)

        self.ansible_pkglist = sorted(set(ansible_pkglist))

    def compare(self):
        local_v_ansible = [
            item for item in self.ansible_pkglist if item not in self.local_pkglist
        ]

        ansible_v_local = [
            item for item in self.local_pkglist if item not in self.ansible_pkglist
        ]

        msg = ""
        if len(local_v_ansible) != 0:
            msg = "present in ansible but not on the local machine:\n"
            for i in local_v_ansible:
                msg += f" - {i}\n"

        if len(ansible_v_local) != 0:
            msg += "\n"

            msg += "present on the local machine but not in Ansible:\n"
            for i in ansible_v_local:
                msg += f" - {i}\n"

            msg = msg.rstrip("\n")

        if len(msg) == 0:
            msg = "there are no differences."

        print(msg)

    def run(self):
        self.get_local_pkglist()
        self.parse_ansible()
        self.mkpkglist()
        self.compare()


if __name__ == "__main__":
    pd = PkgDiff()
    pd.run()
