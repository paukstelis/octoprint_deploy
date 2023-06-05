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


get_settings

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
