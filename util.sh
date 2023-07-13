#!/bin/bash

# from stackoverflow.com/questions/3231804
prompt_confirm() {
    while true; do
        read -r -n 1 -p "${green}${1:-Continue?}${white} ${yellow}[y/n]${white}: " REPLY
        case $REPLY in
            [yY]) echo ; return 0 ;;
            [nN]) echo ; return 1 ;;
            *) printf " \033[31m %s \n\033[0m" "invalid input"
        esac
    done
}
# from unix.stackexchange.com/questions/391293
log () {
    if [ -z "$1" ]; then
        cat
    else
        printf '%s\n' "$@"
    fi | tee -a "$logfile"
}

#https://gist.github.com/wellsie/56a468a1d53527fec827
has-space () {
    [[ "$1" != "${1%[[:space:]]*}" ]] && return 0 || return 1
}

get_settings() {
    #Get octoprint_deploy settings, all of which are written on system prepare
    if [ -f /etc/octoprint_deploy ]; then
        OCTOEXEC=$(cat /etc/octoprint_deploy | sed -n -e 's/^octoexec: \(\.*\)/\1/p')
        OCTOPIP=$(cat /etc/octoprint_deploy | sed -n -e 's/^octopip: \(\.*\)/\1/p')
        STREAMER=$(cat /etc/octoprint_deploy | sed -n -e 's/^streamer: \(\.*\)/\1/p')
        HAPROXY=$(cat /etc/octoprint_deploy | sed -n -e 's/^haproxy: \(\.*\)/\1/p')
    fi
}

global_config() {
    echo "This utility allows you to modify OctoPrint settings for indivdual or all instances."
    echo "There is no error checking so it is critical to set the input parameters correctly."
    echo "See the Wiki for more details."
    echo "Enter the config and parameter"
    read -p $GC
    get_instances true
    select opt in "${INSTANCE_ARR[@]}"
    do
        if [ "$opt" == Quit ]; then
            main_menu
        fi
        echo "Sorry this doesn't do anything yet"
    done
    
}

octo_deploy_update() {
    sudo -u $user git -C $SCRIPTDIR pull
    exit
}

back_up() {
    INSTANCE=$1
    echo "Creating backup of $INSTANCE...."
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
    get_instances false
    for instance in "${instances[@]}"; do
        echo $instance
        back_up $instance
    done
    
}

get_instances() {
    addquit=$1
    readarray -t INSTANCE_ARR < <(cat /etc/octoprint_instances | sed -n -e 's/^instance:\([[:graph:]]*\) .*/\1/p')
    if [ "$addquit" == true ]; then
        INSTANCE_ARR+=("Quit")
    fi
}

get_cameras() {
    addquit=$1
    readarray -t CAMERA_ARR < <(cat /etc/octoprint_cameras | sed -n -e 's/^camera:\([[:graph:]]*\) .*/\1/p')
    if [ "$addquit" == true ]; then
        CAMERA_ARR+=("Quit")
    fi
}

sync_users() {
    echo
    echo
    echo "This will sync all the users from one instance to all the other instances."
    PS3="${green}Select instance that contains current user list: ${white}"
    get_instances true
    select opt in "${INSTANCE_ARR[@]}"
    do
        if [ "$opt" == Quit ]; then
            main_menu
        fi
        
        if prompt_confirm "Copy users from instance $opt to all other instances?"; then
            userfile=/home/$user/.$opt/users.yaml
            #re-read to avoid the Quit
            get_instances false
            for instance in "${INSTANCE_ARR[@]}"; do
                if [ "$instance" == "$opt" ]; then
                    continue
                fi
                sudo -u $user cp $userfile /home/$user/.$instance/
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
    PS3="${green}Select instance where uploads will be stored: ${white}"
    get_instances false
    INSTANCE_ARR+=("Custom" "Quit")
    select opt in "${INSTANCE_ARR[@]}"
    do
        if [ "$opt" == Quit ]; then
            main_menu
            break
        fi
        
        if [ "$opt" == "Custom" ]; then
            echo "Enter full path (should start /home/$user/):"
            read ULPATH
            if [ -d "$ULPATH" ]; then
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
        echo
        #Remove Quit and Custom from array, is there a cleaner way?
        unset 'options[-1]'
        unset 'options[-1]'
        for instance in "${options[@]}"; do
            $OCTOEXEC --basedir /home/$user/.$instance config set folder.uploads "$opt"
        done
        break
    done
    echo "${cyan}Instances must be restarted for changes to take effect.${white}"
    main_menu
}

add_udev() {
    #get instances that don't have a udev rule
    PS3="${green}Select instance to add udev rule: ${white}"
    readarray -t noudev < <(fgrep "udev:false" /etc/octoprint_instances 2> /dev/null | sed -n -e 's/^instance:\([[:graph:]]*\) .*/\1/p')
    noudev+=("Quit")
    select opt in "${noudev[@]}"
    do
        if [ "$opt" == Quit ]; then
            main_menu
        fi
        INSTANCE=$opt
        detect_printer
        printer_udev false
        printer_udev true
        #this needs more thought
        sed -i "s/^\(instance:$INSTANCE port:.* udev:\)false/\1true/" /etc/octoprint_instances
        break
    done
    udevadm control --reload-rules
    udevadm trigger
    echo "${cyan}udev rule has been added${white}"
    main_menu
}

remove_udev() {
    PS3="${green}Select udev rule to remove: ${white}"
    readarray -t udevs < <(fgrep "udev:true" /etc/octoprint_instances 2> /dev/null | sed -n -e 's/^instance:\([[:graph:]]*\) .*/\1/p')
    udevs+=("Quit")
    select opt in "${udevs[@]}"
    do
        if [ "$opt" == Quit ]; then
            main_menu
        fi
        sed -i "/$opt/d" /etc/udev/rules.d/99-octoprint.rules
        sed -i "s/^\(instance:$opt port:.* udev:\)true/\1false/" /etc/octoprint_instances
        break
    done
    echo "${cyan}udev rule has been removed${white}"
    udevadm control --reload-rules
    udevadm trigger
    main_menu
}

add_udev_camera() {
    PS3="${green}Select camera to add udev rule: ${white}"
    readarray -t noudev < <(fgrep "udev:false" /etc/octoprint_cameras 2> /dev/null | sed -n -e 's/^camera:\([[:graph:]]*\) .*/\1/p')
    noudev+=("Quit")
    select opt in "${noudev[@]}"
    do
        if [ "$opt" == Quit ]; then
            main_menu
        fi
        INSTANCE=$opt
        detect_camera
        write_cam_udev
        sed -i "s/^\(camera:$opt port:.* udev:\)false/\1true/" /etc/octoprint_instances
        break
    done
    udevadm control --reload-rules
    udevadm trigger
    echo "${cyan}Camera udev rule has been added${white}"
    main_menu
}

remove_udev_camera() {
    PS3="${green}Select udev rule to remove: ${white}"
    readarray -t udevs < <(fgrep "udev:true" /etc/octoprint_cameras 2> /dev/null | sed -n -e 's/^camera:\([[:graph:]]*\) .*/\1/p')
    udevs+=("Quit")
    select opt in "${udevs[@]}"
    do
        if [ "$opt" == Quit ]; then
            main_menu
        fi
        sed -i "/$opt/d" /etc/udev/rules.d/99-octoprint.rules
        sed -i "s/^\(camera:$opt port:.* udev:\)true/\1false/" /etc/octoprint_cameras
        break
    done
    echo "${cyan}Camera udev rule has been removed${white}"
    udevadm control --reload-rules
    udevadm trigger
    main_menu
}

instance_status() {
    clear
    echo
    echo "${cyan}*******************************************${white}"
    get_instances false
    readarray -t cameras < <(ls -1 /etc/systemd/system/cam*.service 2> /dev/null | sed -n -e 's/^.*\/\(.*\).service/\1/p')
    #combine instances and cameras
    INSTANCE_ARR+=(${cameras[@]})
    echo "Service - Status:"
    echo "------------------"
    for instance in "${INSTANCE_ARR[@]}"; do
        status=$(systemctl status $instance | sed -n -e 's/Active: \([[:graph:]]*\) .*/\1/p')
        if [ $status = "active" ]; then
            status="${green}$status${white}"
            elif [ $status = "failed" ]; then
            status="${red}$status${white}"
        fi
        echo "$instance - $status"
    done
    echo "${cyan}*******************************************${white}"
    echo "Only instances and cameras made with octoprint_deploy are shown"
    echo
    main_menu
}

change_streamer() {
    echo
    echo "${cyan}This allows you to change the default webcam streamer."
    echo "Please note, it DOES NOT change the streamer for existing cameras."
    echo "You will need to delete and reinstall those cameras for changes to take effect.${white}"
    echo
    streamer_install
}

remove_everything() {
    get_settings
    if prompt_confirm "Remove everything?"; then
        get_instances false
        get_cameras false
        
        for instance in "${INSTANCE_ARR[@]}"; do
            remove_instance $instance
        done
        
        for camera in "${CAMERA_ARR[@]}"; do
            remove_camera $camera
        done
        
        echo "Removing system stuff"
        rm /etc/systemd/system/octoprint.service 2>/dev/null
        rm /etc/octoprint_streamer 2>/dev/null
        rm /etc/octoprint_deploy 2>/dev/null
        rm /etc/octoprint_instances 2>/dev/null
        rm /etc/octoprint_cameras 2>/dev/null
        rm /etc/udev/rules.d/99-octoprint.rules 2>/dev/null
        rm /etc/sudoers.d/octoprint_reboot 2>/dev/null
        rm /etc/sudoers.d/octoprint_systemctl 2>/dev/null
        rm -rf /home/$user/.octoprint 2>/dev/null
        rm -rf /home/$user/OctoPrint 2>/dev/null
        rm -rf /home/$user/ustreamer 2>/dev/null
        rm -rf /home/$user/mjpg-streamer 2>/dev/null
        rm -rf /home/$user/camera-streamer 2>/dev/null
        systemctl restart haproxy.service
        systemctl daemon-reload
        
    fi
}

restart_all() {
    get_settings
    get_instances false
    for instance in "${INSTANCE_ARR[@]}"; do
        echo "Trying to restart instance $instance"
        systemctl restart $instance
    done
    main_menu
}

check_sn() {
    if [ -f "/etc/udev/rules.d/99-octoprint.rules" ]; then
        if grep -q $1 /etc/udev/rules.d/99-octoprint.rules; then
            echo "${red}An identical serial number has been detected in the udev rules. Please be warned, this will likely cause instability!${white}"
        else
            echo "${cyan}No duplicate serial number detected.${white}"
        fi
    fi
}

usb_testing() {
    echo
    echo
    echo "Testing printer USB"
    detect_printer
    echo "Detected device at $TEMPUSB"
    echo "Serial Number detected: $UDEV"
    main_menu
}

diagnostic_output() {
    echo "**************************************"
    echo "$1"
    echo "**************************************"
    cat $1

}

diagnostics() {
    get_settings
    logfile='octoprint_deploy_diagnostic.log'
    echo "octoprint_deploy diagnostic information. Please provide ALL output for support help"
    diagnostic_output /etc/octoprint_deploy | log
    diagnostic_output /etc/octoprint_instances | log
    diagnostic_output /etc/octoprint_cameras | log
    diagnostic_output /etc/udev/rules.d/99-octoprint.rules | log
    ls -la /dev/octo* | log
    ls -la /dev/cam* | log
    #get all instance status
    get_instances false
    for instance in "${INSTANCE_ARR[@]}"; do
        echo "**************************************" | log
        systemctl status $instance -l --no-pager | log
        #get needed config info
        sudo -u $user $OCTOEXEC --basedir=/home/$user/.$INSTANCE config get plugins.classicwebcam | log
        sudo -u $user $OCTOEXEC --basedir=/home/$user/.$INSTANCE config get webcam | log
    done
    #get all cam status
    get_cameras false
    for camera in "${CAMERA_ARR[@]}"; do
        echo "**************************************" | log
        systemctl status $camera -l --no-pager | log
    done
    #get haproxy status
    echo "**************************************" | log
    systemctl status haproxy -l --no-pager | log
    logfile='octoprint_deploy.log'
    main_menu
}