#!/bin/bash
. ./common

set -e

if [ "$(id -u)" -ne 0 ]; then
    perr "need root big man"
fi

_TSTAMP="$(date '+%Y%m%d_%H%M%S')"
_IMGDIR="/mnt/mss/stuff/techy-bits/images"

if [ ! -d "${_IMGDIR}" ]; then mkdir -pv "${_IMGDIR}"; fi

for volume in ./xml/vol_*.xml; do
    volname="$(echo "${volume}" | sed 's/\.\/xml\/vol_//g;s/\.xml$//g')"
    path_to_vol="$(virsh vol-key --pool setboxes --vol ${volname}.qcow2)"

    virsh destroy --graceful --domain "${volname}" || true
    qemu-nbd --connect=/dev/nbd1 "${path_to_vol}"

    e2fsck -fy /dev/nbd1p2 || true

    partclone.fat32 -q -c -s /dev/nbd1p1 -o - \
        | zstd -T`nproc` -19 -o \
            "${_IMGDIR}"/"${_TSTAMP}"-setboxes-"${volname}"-p1.img.zst

    partclone.ext4 -q -c -s /dev/nbd1p2 -o - \
        | zstd -T`nproc` -19 -o \
            "${_IMGDIR}"/"${_TSTAMP}"-setboxes-"${volname}"-p2.img.zst

    qemu-nbd --disconnect /dev/nbd1
done
