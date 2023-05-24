#!/bin/bash

octo_deploy_update() {
    sudo -u $user git -C $SCRIPTDIR pull
    exit
}

replace_id() {
    echo "PLEASE NOTE, this will only work in replacing an existing serial number with another serial number"
    echo "or an existing USB port with another USB port. You cannot mix and match."
    PS3='Select instance to change serial ID: '
    readarray -t options < <(cat /etc/octoprint_instances | sed -n -e 's/^instance:\([[:graph:]]*\) .*/\1/p')
    options+=("Quit")
    unset 'options[0]'
    select opt in "${options[@]}"
    do
        if [ "$opt" == Quit ]; then
            main_menu
        fi
        
        echo "Selected $opt to replace serial ID" | log
        #Serial number or KERNELS? Not doing any error checking yet
        KERN=$(grep octo_$opt /etc/udev/rules.d/99-octoprint.rules | sed -n -e 's/KERNELS==\"\([[:graph:]]*[[:digit:]]\)\".*/\1/p')
        detect_printer
        if [ -z "$KERN" ]; then
            sed -i -e "s/\(ATTRS{serial}==\)\"\([[:alnum:]]*\)\"\(.*\)\(\"octo_$opt\"\)/\1\"$UDEV\"\2\3/" /etc/udev/rules.d/99-octoprint.rules
            echo "Serial number replaced with: $UDEV"
        else
            sed -i -e "s/\(KERNELS==\)\"$KERN\"\(.*\)\(\"octo_$opt\"\)/\1\"$USB\"\2\3/"  /etc/udev/rules.d/99-octoprint.rules
            echo "USB port replaced with: $USB"
        fi
        udevadm control --reload-rules
        udevadm trigger
        exit 0
    done
}

back_up() {
    INSTANCE=$1
    echo "Creating backup of $INSTANCE...."
    if [ "$INSTANCE" == generic ]; then
        INSTANCE="octoprint"
    fi
    d=$(date '+%Y-%m-%d')
    sudo -p $user tar -czf ${INSTANCE}_${d}_backup.tar.gz -C /home/$user/ .${INSTANCE}
    echo "Tarred and gzipped backup created in /home/$user"
}


restore() {
    INSTANCE=$1
    TAR=$2
    echo "Restoring backup of $INSTANCE...."
    systemctl stop $INSTANCE
    sudo -p $user tar -xvf $TAR
    systemctl start $INSTANCE
    
}

back_up_all() {
    get_settings
    readarray -t instances < <(cat /etc/octoprint_instances | sed -n -e 's/^instance:\([[:graph:]]*\) .*/\1/p')
    unset 'instances[0]'
    for instance in "${instances[@]}"; do
        echo $instance
        back_up $instance
    done
    
}

sync_users() {
    echo
    echo
    echo "This will sync all the users from one instance to all the other instances."
    PS3='Select instance that contains current user list: '
    readarray -t options < <(cat /etc/octoprint_instances | sed -n -e 's/^instance:\([[:graph:]]*\) .*/\1/p')
    options+=("Quit")
    select opt in "${options[@]}"
    do
        if [ "$opt" == Quit ]; then
            main_menu
        fi
        
        if prompt_confirm "Copy users from instance $opt to all other instances?"; then
            if [ "$opt" == generic ]; then
                userfile=/home/$user/.octoprint/users.yaml
            else
                userfile=/home/$user/.$opt/users.yaml
            fi
            #re-read to avoid the Quit
            readarray -t instances < <(cat /etc/octoprint_instances | sed -n -e 's/^instance:\([[:graph:]]*\) .*/\1/p')
            for instance in "${instances[@]}"; do
                if [ "$instance" == "$opt" ]; then
                    continue
                fi
                if [ "$instance" == generic ]; then
                    sudo -u $user cp $userfile /home/$user/.octoprint/
                else
                    sudo -u $user cp $userfile /home/$user/.$instance/
                fi
            done
            
            if prompt_confirm "Restart all instances now for changes to take effect?"; then
                restart_all
            fi
        fi
        
        main_menu
    done
}

share_uploads() {
    get_settings
    echo
    echo
    echo "This option will make all your uploads go to a single instance."
    echo "This will mean all gcode files be available for all your instances."
    echo "Use this option only if you understand the implications."
    echo "This can be adjusted later in the Folders settings of OctoPrint."
    PS3='Select instance where uploads will be stored: '
    readarray -t options < <(cat /etc/octoprint_instances | sed -n -e 's/^instance:\([[:graph:]]*\) port:.*/\1/p')
    options+=("Custom" "Quit")
    unset 'options[0]'
    select opt in "${options[@]}"
    do
        if [ "$opt" == Quit ]; then
            main_menu
            break
        fi
        
        if [ "$opt" == "Custom" ]; then
            echo "Enter full path (should start /home/$user/):"
            read ULPATH
            if [ -d "$ULPATH" ]; then
                #echo "This folder already exists. Are you sure you want to use it?"
                if prompt_confirm "This folder already exists. Are you sure you want to use it?"; then
                    opt=$ULPATH
                else
                    echo "Restart the option if you change your mind"
                    main_menu
                    break
                fi
            else
                sudo -u $user mkdir $ULPATH
                opt=$ULPATH
            fi
            
        else
            opt=/home/$user/.$opt/uploads
        fi
        echo $opt
        echo
        #Remove Quit and Custom from array, is there a cleaner way?
        unset 'options[-1]'
        unset 'options[-1]'
        for instance in "${options[@]}"; do
            $OCTOEXEC --basedir /home/$user/.$instance config set folder.uploads "$opt"
        done
        break
    done
    echo "Instances must be restarted for changes to take effect."
    main_menu
}

instance_status() {
    echo
    echo "*******************************************"
    readarray -t instances < <(cat /etc/octoprint_instances | sed -n -e 's/^instance:\([[:graph:]]*\) .*/\1/p')
    unset 'instances[0]'
    echo "Instance - Status:"
    echo "------------------"
    for instance in "${instances[@]}"; do
        status=$(systemctl status $instance | sed -n -e 's/Active: \([[:graph:]]*\) .*/\1/p')
        echo "$instance - $status"
    done
    echo "*******************************************"
    main_menu
}

remove_everything() {
    get_settings
    if prompt_confirm "Remove everything?"; then
        readarray -t instances < <(cat /etc/octoprint_instances | sed -n -e 's/^instance:\([[:graph:]]*\) .*/\1/p')
        unset 'instances[0]'
        readarray -t cameras < <(ls -1 /etc/systemd/system/cam*.service | sed -n -e 's/^.*\/\(.*\).service/\1/p')
        for instance in "${instances[@]}"; do
            remove_instance $instance
        done
        
        for camera in "${cameras[@]}"; do
            remove_camera $camera
        done
        
        echo "Removing system stuff"
        rm /etc/systemd/system/octoprint_default.service
        rm /etc/octoprint_streamer
        rm /etc/octoprint_deploy
        rm /etc/octoprint_instances
        rm /etc/camera_ports
        rm /etc/udev/rules.d/99-octoprint.rules
        rm /etc/sudoers.d/octoprint_reboot
        rm /etc/sudoers.d/octoprint_systemctl
        echo "Removing template"
        rm -rf /home/$user/.octoprint
        rm -rf /home/$user/OctoPrint
        rm -rf /home/$user/ustreamer
        rm -rf /home/$user/mjpg-streamer
        systemctl restart haproxy.service
        systemctl daemon-reload
        
        #if using OctoPi, restart template
        if [ "$TYPE" == octopi ]; then
            systemctl restart octoprint.service
        fi
    fi
}

restart_all() {
    get_settings
    readarray -t instances < <(cat /etc/octoprint_instances | sed -n -e 's/^instance:\([[:graph:]]*\) .*/\1/p')
    unset 'instances[0]'
    for instance in "${instances[@]}"; do
        if [ "$instance" == generic ]; then
            continue
        fi
        echo "Trying to restart instance $instance"
        systemctl restart $instance
    done
    exit 0
}

check_sn() {
    if [ -f "/etc/udev/rules.d/99-octoprint.rules" ]; then
        if grep -q $1 /etc/udev/rules.d/99-octoprint.rules; then
            echo "An identical serial number has been detected in the udev rules. Please be warned, this will likely cause instability!" | log
        else
            echo "No duplicate serial number detected" | log
        fi
    fi
}


usb_testing() {
    echo
    echo
    echo "Testing printer USB" | log
    detect_printer
    echo "Detected device at $TEMPUSB" | log
    echo "Serial Number detected: $UDEV" | log
    main_menu
}