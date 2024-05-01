#!/bin/bash
set -e

main(){
    . ./common

    rootcheck
    nbdcheck

    _TSTAMP="$(date '+%Y%m%d_%H%M%S')"
    _IMGDIR="/mnt/mss/stuff/techy-bits/images"

    if [ ! -d "${_IMGDIR}" ]; then mkdir -pv "${_IMGDIR}"; fi

    iterate_xmls
}

iterate_xmls(){
    for volume in ./xml/vol_*.xml; do
        volname="$(echo "${volume}" | sed 's/\.\/xml\/vol_//g;s/\.xml$//g')"
        path_to_vol="$(virsh vol-key --pool setboxes --vol ${volname}.qcow2)"

        pinfo "processing ${volname}"
        pinfo "(${path_to_vol})"

        virsh destroy --graceful --domain "${volname}" >/dev/null 2>&1 || true
        qemu-nbd --connect=/dev/nbd1 "${path_to_vol}" >/dev/null 2>&1

        e2fsck -fy /dev/nbd1p2 >/dev/null 2>&1 || true

        partclone.fat32 -q -c -s /dev/nbd1p1 -o - \
            | zstd -T`nproc` -19 -o \
                "${_IMGDIR}"/"${_TSTAMP}"-setboxes-"${volname}"-p1.img.zst

        partclone.ext4 -q -c -s /dev/nbd1p2 -o - \
            | zstd -T`nproc` -19 -o \
                "${_IMGDIR}"/"${_TSTAMP}"-setboxes-"${volname}"-p2.img.zst

        qemu-nbd --disconnect /dev/nbd1 >/dev/null 2>&1
    done
}
