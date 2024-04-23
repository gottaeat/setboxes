#!/bin/bash
set_network(){
    # create network
    if ! virsh net-list --name | grep "${ORG_NAME}" >/dev/null 2>&1; then
        virsh net-define --file ./xml/net_"${ORG_NAME}".xml
    fi

    # populate network info
    netinfo="$(virsh net-info --network "${ORG_NAME}")"

    # start network
    if [ "$(echo "${netinfo}" | awk '/^Active/{print $2}')" != "yes" ]; then
        virsh net-start --network "${ORG_NAME}"
    fi

    # set network to autostart
    if [ "$(echo "${netinfo}" | awk '/^Autostart/{print $2}')" != "yes" ]; then
        virsh net-autostart --network "${ORG_NAME}"
    fi
}

set_pool(){
    # create pool 
    if ! virsh pool-list --name | grep "${ORG_NAME}" >/dev/null 2>&1; then
        virsh pool-define --file ./xml/pool_"${ORG_NAME}".xml
    fi

    # populate pool info
    poolinfo="$(virsh pool-info --pool "${ORG_NAME}")"

    # start pool
    if [ "$(echo "${poolinfo}" | awk '/^State/{print $2}')" != "running" ]; then
        virsh pool-start --pool "${ORG_NAME}"
    fi

    # set pool to autostart
    if [ "$(echo "${poolinfo}" | awk '/^Autostart/{print $2}')" != "yes" ]; then
        virsh pool-autostart --pool "${ORG_NAME}"
    fi

    # refresh pool
    virsh pool-refresh --pool "${ORG_NAME}"
}

set_volumes(){
    # populate vol info
    volinfo="$(virsh vol-list --pool "${ORG_NAME}" \
                | awk '/^ /{print $1}' | grep -v ^Name)"

    for volume in ./xml/vol_*.xml; do
        volname="$(echo "${volume}" | sed 's/\.\/xml\/vol_//g;s/\.xml$//g')"

        # gat
        if ! echo "${volinfo}" | grep "${volname}" >/dev/null 2>&1; then
            virsh vol-create --pool "${ORG_NAME}" --file "${volume}"
        fi
    done

    # refresh pool
    virsh pool-refresh --pool "${ORG_NAME}"
}

set_doms(){
    # populate dom info
    dominfo="$(virsh list --name --all)"

    for domain in ./xml/dom_*.xml; do
        domname="$(echo "${domain}" | sed 's/\.\/xml\/dom_//g;s/\.xml$//g')"

        if ! echo "${dominfo}" | grep "${domname}" >/dev/null 2>&1; then
            virsh define --file "${domain}"
            virsh start "${domname}"
        fi
    done
}

main(){
    ORG_NAME="setboxes"

    set_network
    set_pool
    set_volumes
    set_doms
}

main
