#!/bin/bash
. ./common

set -e

if [ "$(id -u)" -ne 0 ]; then
    perr "need root big man"
fi

if [ -z "${1}" ]; then
    perr "specify a device in as \$1."
fi

# - - source device file - - #
. "./cmdline/${1}" || perr "failed importing ${1}"

# - - calculate resume cmdline - - #
_SWAPUUID="$(blkid -o export "$(mount | grep "${_SWAPMOUNT}" \
    | awk '{print $1}')" \
    | awk '/UUID/{sub(/UUID=/,""); print}')"

_SWAPOFFS="$(filefrag -v "${_SWAPPATH}" \
    | awk '$1=="0:" {print substr($4, 1, length($4)-2)}')"

_CMDLINE="${_CMDLINE} resume=${_SWAPUUID} resume_offset=${_SWAPOFFS}"

# - - prints - - #
pinfo "swap mount   → ${_SWAPMOUNT}"
pinfo "swap path    → ${_SWAPPATH} "
pinfo "swap uuid    → ${_SWAPUUID} "
pinfo "swap offset  → ${_SWAPOFFS} "
pinfo "full cmdline → ${_CMDLINE}  "

# - - mkinitcpio - - #
pinfo "calling mkinitcpio"
mkinitcpio -P

# - - efibootmgr - - #
pinfo "calling efibootmgr"

_EFIENTRIES="$(efibootmgr -u \
    | awk '/Boot[0-9][0-9][0-9][0-9]. arch/{gsub(/Boot|\*/,"");print $1}')"

for i in ${_EFIENTRIES}; do
    efibootmgr -b "${i}" -B "${i}" >/dev/null 2>&1
done

efibootmgr \
    -c                      \
    -d "/dev/sda" -p 1      \
    -L "arch"               \
    -l "\vmlinuz-linux-zen" \
    -u "${_CMDLINE}" >/dev/null 2>&1

echo
pinfo "boot order is now:"
efibootmgr -u
