#!/usr/bin/python
import os
import re

import yaml


class GenThinkfanConf:
    _IBMFAN_PATH = "/proc/acpi/ibm/fan"
    _HWMON_DIR = "/sys/class/hwmon/"
    _LABELS = ["Tctl", "Package", "Core 0"]

    def __init__(self):
        self._tempfile = None

    def _get_tempfile(self):
        tempfile_list = []
        for d in os.listdir(self._HWMON_DIR):
            for file in os.listdir(self._HWMON_DIR + d):
                fullpath = f"{self._HWMON_DIR}{d}/{file}"
                if "_label" in fullpath:
                    tempfile_list.append(fullpath)

        for _, file in enumerate(tempfile_list):
            with open(file, "r", encoding="utf-8") as f:
                f_contents = re.sub(r"\n", "", f.read())
            if any(label in f_contents for label in self._LABELS):
                self._tempfile = re.sub(r"label", "input", file)
                break

        if not self._tempfile:
            raise ValueError("no hwmon temp file matching the criteria was found")

    def _gen_yaml(self):
        if not os.path.isfile(self._IBMFAN_PATH):
            raise ValueError("procfs ibm fan path does not exist.")

        thinkfanconf = {
            "sensors": [{"hwmon": f"{self._tempfile}"}],
            "fans": [{"tpacpi": f"{self._IBMFAN_PATH}"}],
            "levels": [
                ["level 0", 0, 50],
                ["level 1", 50, 65],
                ["level 3", 65, 80],
                ["level disengaged", 80, 255],
            ],
        }

        yaml_str = yaml.dump(thinkfanconf, sort_keys=False)

        with open("/etc/thinkfan.conf", "w", encoding="utf-8") as yaml_file:
            yaml_file.write(yaml_str)

    def run(self):
        self._get_tempfile()
        self._gen_yaml()


if __name__ == "__main__":
    t = GenThinkfanConf()
    t.run()
