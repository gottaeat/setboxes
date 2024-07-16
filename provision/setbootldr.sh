#!/bin/bash
set -e

calc_resume(){
    _SWAPUUID="$(blkid -o export "$(mount | grep "${_SWAPMOUNT}" \
        | awk '{print $1}')" \
        | awk '/UUID/{print}')"

    _SWAPOFFS="$(filefrag -v "${_SWAPPATH}" \
        | awk '$1=="0:" {print substr($4, 1, length($4)-2)}')"

    _CMDLINE="${_CMDLINE} resume=${_SWAPUUID} resume_offset=${_SWAPOFFS}"
}

print_info(){
    pinfo "swap mount   → ${_SWAPMOUNT}"
    pinfo "swap path    → ${_SWAPPATH} "
    pinfo "swap uuid    → ${_SWAPUUID} "
    pinfo "swap offset  → ${_SWAPOFFS} "
    pinfo "full cmdline → ${_CMDLINE}  "
}

call_efiboot(){
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
}

call_mkinitcpio(){
    pinfo "calling mkinitcpio"
    mkinitcpio -P >/dev/null 2>&1
}

call_grub(){
    pinfo "calling grub"

    grub-install --target=i386-pc /dev/sda
    grub-mkconfig -o /boot/grub/grub.cfg
}

main(){
    . ./common

    rootcheck

    # - - get device cmdline opts - - #
    if [ -z "${1}" ]; then
        perr "specify a device in as \$1."
    fi

    . "./cmdline/${1}" >/dev/null 2>&1 || perr "failed importing ${1}"

    calc_resume
    print_info
    call_mkinitcpio

    if [ "${EFI}" -eq 1 ]
        then
            call_efiboot
            echo
            pinfo "boot order is now:"
            efibootmgr -u
        else
            cat ./misc/grub_template \
                | sed "s|REPLACEMECMDLINE|${_CMDLINE}|g" \
            > /etc/default/grub

            call_grub
    fi
}

main "${1}"
