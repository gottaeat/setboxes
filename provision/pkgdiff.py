#!/usr/bin/python3
# pylint: disable=missing-module-docstring,missing-class-docstring
# pylint: disable=missing-function-docstring
# pylint: disable=too-many-instance-attributes,too-few-public-methods

import json
import socket
import subprocess
import logging
import sys

import yaml


class ANSIColors:
    RES = "\033[0;39m"

    LBLK = "\033[0;30m"
    LRED = "\033[0;31m"
    LGRN = "\033[0;32m"
    LYEL = "\033[0;33m"
    LBLU = "\033[0;34m"
    LMGN = "\033[0;35m"
    LCYN = "\033[0;36m"
    LWHI = "\033[0;37m"

    BBLK = "\033[1;30m"
    BRED = "\033[1;31m"
    BGRN = "\033[1;32m"
    BYEL = "\033[1;33m"
    BBLU = "\033[1;34m"
    BMGN = "\033[1;35m"
    BCYN = "\033[1;36m"
    BWHI = "\033[1;37m"

    def __init__(self):
        pass


_c = ANSIColors()


class ShutdownHandler(logging.StreamHandler):
    def emit(self, record):
        if record.levelno >= logging.ERROR:
            sys.exit(1)


class PkgDiffFormatter(logging.Formatter):
    _FMT_BEGIN = f"{_c.BBLK}["
    _FMT_END = f"{_c.BBLK}]{_c.BWHI}"

    _FORMATS = {
        logging.NOTSET: _c.LCYN,
        logging.DEBUG: _c.BWHI,
        logging.INFO: _c.BBLU,
        logging.WARNING: _c.LGRN,
        logging.ERROR: _c.LRED,
        logging.CRITICAL: _c.LRED,
    }

    def format(self, record):
        finfmt = f"{self._FMT_BEGIN}{self._FORMATS.get(record.levelno)}"
        finfmt += f"%(levelname)-.1s{self._FMT_END} %(message)s{_c.RES}"

        return logging.Formatter(fmt=finfmt, validate=True).format(record)


class PkgDiff:
    _REPODIR = "/opt/mss/repo"

    def __init__(self):
        self.logger = None

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
            if "pacman" in cmdline[0]:
                return (except_obj.returncode, except_obj.stderr.decode("utf-8"))
            raise ValueError(except_obj.stderr.decode("utf-8")) from except_obj
        return (proc.returncode, proc.stdout.decode("utf-8"))

    def get_local_pkglist(self):
        pacman_out = self.runcmd("pacman -Qe")[1].split()

        pkg_iter, local_pkglist = 0, []
        while pkg_iter < len(pacman_out):
            local_pkglist.append(pacman_out[pkg_iter])
            pkg_iter += 2

        self.local_pkglist = sorted(set(local_pkglist))

    def parse_ansible(self):
        # - - inventory + hosts - - #
        self.ansible_inventory = json.loads(
            self.runcmd(f"{self._REPODIR}/inventory.py")[1]
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
        with open(
            f"{self._REPODIR}/group_vars/crib/packages.yml", "r", encoding="utf-8"
        ) as yaml_file:
            pkgs = yaml.load(yaml_file.read(), Loader=yaml.Loader)

        # main
        self.main_pkgs_base = pkgs["main_pkgs_base"]
        self.main_pkgs_multimedia = pkgs["main_pkgs_multimedia"]
        self.main_pkgs_desktop_extra = pkgs["main_pkgs_desktop_extra"]
        self.main_pkgs_router = pkgs["main_pkgs_router"]
        self.main_pkgs_bios = pkgs["main_pkgs_bios"]
        self.main_pkgs_wlan_tools = pkgs["main_pkgs_wlan_tools"]

        # user
        self.user_pkgs_base = pkgs["user_pkgs_base"]
        self.user_pkgs_multimedia = pkgs["user_pkgs_multimedia"]

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

    def diff(self):
        local_v_ansible = [
            item for item in self.ansible_pkglist if item not in self.local_pkglist
        ]

        ansible_v_local = [
            item for item in self.local_pkglist if item not in self.ansible_pkglist
        ]

        # packages installed during mkbaseimg.sh, init.yml and
        # pre-package-handling
        handled_outside_of_pkg_handling = [
            "base",
            "base-devel",
            "dosfstools",
            "efibootmgr",
            "git",
            "go",
            "grub",
            "linux-zen",
            "openssh",
            "python3",
            "sudo",
            "yay",
        ]

        local_v_ansible = [
            item
            for item in local_v_ansible
            if item not in handled_outside_of_pkg_handling
        ]

        ansible_v_local = [
            item
            for item in ansible_v_local
            if item not in handled_outside_of_pkg_handling
        ]

        # exist but as a dep, not as explicit
        pkg_exists_but_not_explicit = []
        for pkg in local_v_ansible:
            pkg_exists = self.runcmd(f"pacman -Q {pkg}")[0]
            if pkg_exists == 0:
                pkg_exists_but_not_explicit.append(pkg)

        pkg_exists_but_not_explicit = [
            item
            for item in pkg_exists_but_not_explicit
            if item not in handled_outside_of_pkg_handling
        ]

        if len(pkg_exists_but_not_explicit) != 0:
            local_v_ansible = [
                item
                for item in local_v_ansible
                if item not in pkg_exists_but_not_explicit
            ]

        # prompts
        if len(pkg_exists_but_not_explicit) != 0:
            msg = "explicit in ansible spec, dep on local machine:\n"

            pkg_msg = ""
            for i in pkg_exists_but_not_explicit:
                pkg_msg += f" - {_c.BYEL}{i}{_c.RES}\n"

            msg += pkg_msg
            msg = msg.rstrip("\n")

            for line in msg.split("\n"):
                self.logger.warning(line)

        if len(local_v_ansible) != 0:
            msg = "present in ansible spec but not on the local machine:\n"

            pkg_msg = ""
            for i in local_v_ansible:
                pkg_msg += f" - {_c.BYEL}{i}\n"

            msg += pkg_msg
            msg = msg.rstrip("\n")

            for line in msg.split("\n"):
                self.logger.info(line)

        if len(ansible_v_local) != 0:
            msg = "present on local machine but not in ansible spec:\n"

            pkg_msg = ""
            for i in ansible_v_local:
                pkg_msg += f" - {_c.BYEL}{i}\n"

            msg += pkg_msg
            msg = msg.rstrip("\n")

            for line in msg.split("\n"):
                self.logger.info(line)

    def run(self):
        self.logger = logging.getLogger("PkgDiff")
        self.logger.setLevel(logging.DEBUG)

        handler = logging.StreamHandler()
        handler.setLevel(logging.DEBUG)

        handler.setFormatter(PkgDiffFormatter())

        self.logger.addHandler(handler)
        self.logger.addHandler(ShutdownHandler())

        self.get_local_pkglist()
        self.parse_ansible()
        self.mkpkglist()
        self.diff()


if __name__ == "__main__":
    pd = PkgDiff()
    pd.run()
