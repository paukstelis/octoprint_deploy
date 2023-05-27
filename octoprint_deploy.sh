#!/bin/bash

#all operations must be with root/sudo
if (( $EUID != 0 )); then
    echo "Please run with sudo"
    exit
fi

#this is a weak check, but will catch most cases
if [ $SUDO_USER ]; then
    user=$SUDO_USER
else
    echo "You should not run this script as root. Use sudo as a normal user"
    exit
fi

if [ "$user" == root ]; then
    echo "You should not run this script as root. Use sudo as a normal user"
    exit
fi

#Get abbreviated architecture
ARCH=$(arch)
ARCH=${ARCH:0:3}




# initiate logging
logfile='octoprint_deploy.log'
SCRIPTDIR=$(dirname $(readlink -f $0))
source $SCRIPTDIR/plugins.sh
source $SCRIPTDIR/prepare.sh
source $SCRIPTDIR/instance.sh
source $SCRIPTDIR/util.sh
source $SCRIPTDIR/menu.sh

# gather info and write /etc/octoprint_deploy if missing
if [ ! -f /etc/octoprint_deploy ] && [ -f /etc/octoprint_instances ]; then
    echo "/etc/octoprint_deploy is missing. You may have prepared the system with an older vesion."
    echo "The file will be created now."
    streamer_type=("mjpg-streamer" "ustreamer")
    haproxy_bool=("true" "false")
    if [ -f /etc/octopi_version ]; then
        echo "type: octopi" >> /etc/octoprint_deploy
        apt-get -y install uuid-runtime
    else
        echo "type: linux" >> /etc/octoprint_deploy
    fi
    PS3='Select streamer type: '
    select str in "${streamer_type[@]}"; do
        echo "streamer: $str" >> /etc/octoprint_deploy
        break
    done
    PS3='Using haproxy (select true if using octopi): '
    select prox in "${haproxy_bool[@]}"; do
        echo "haproxy: $prox" >> /etc/octoprint_deploy
        break
    done
    
fi

get_settings

#02/17/23 - This will upgrade haproxy so it will no longer require the trailling slash
if [ "$HAPROXYNEW" == false ] && [ "$HAPROXY" == true ]; then
    #Update haproxy entries
    echo "Detected older version of haproxy entries. Updating those now."
    readarray -t instances < <(cat /etc/octoprint_instances | sed -n -e 's/^instance:\([[:graph:]]*\) .*/\1/p')
    unset 'instances[0]'
    for instance in "${instances[@]}"; do
        sed -i "/use_backend $instance/d" /etc/haproxy/haproxy.cfg
        SEDREPLACE="#$instance start\n\
        acl is_$instance url_beg /$instance\n\
        http-request redirect scheme http drop-query append-slash  if is_$instance ! { path_beg /$instance/ }\n\
        use_backend $instance if { path_beg /$instance/ }\n\
        #$instance stop"
        sed -i "/option forwardfor except 127.0.0.1/a $SEDREPLACE" /etc/haproxy/haproxy.cfg
    done
    echo 'haproxynew: true' >> /etc/octoprint_deploy
    systemctl restart haproxy
fi


#command line arguments
if [ "$1" == remove ]; then
    remove_everything
fi

if [ "$1" == restart_all ]; then
    restart_all
fi

if [ "$1" == backup ]; then
    back_up_all
fi

if [ "$1" == replace ]; then
    replace_id
fi

if [ "$1" == picam ]; then
    add_camera true
fi

if [ "$1" == noserial ]; then
    NOSERIAL=1
fi
main_menu
