#!/bin/bash
source $SCRIPTDIR/prepare.sh
white=$(echo -en "\e[39m")
green=$(echo -en "\e[92m")
red=$(echo -en "\e[91m")
magenta=$(echo -en "\e[35m")
cyan=$(echo -en "\e[96m")
yellow=$(echo -en "\e[93m") 

main_menu() {
    VERSION=1.0.7
    #reset
    UDEV=''
    TEMPUSB=''
    CAM=''
    TEMPUSBCAM=''
    INSTANCE=''
    INSTALL=''
    CAMHAPROXY=''
    echo
    echo
    echo "${cyan}*************************${white}"
    echo "${green}octoprint_deploy${white} $VERSION"
    echo "${cyan}*************************${white}"
    echo
    PS3="${green}Select operation: ${white}"
    if [ -f "/etc/octoprint_deploy" ]; then
        options=("Add instance" "Delete instance" "Add Camera" "Delete Camera" "Utilities" "Backup Menu" "Update" "Quit")
    else
        options=("Prepare system" "Update" "Quit")
    fi
    
    select opt in "${options[@]}"
    do
        case $opt in
            "Prepare system")
                detect_installs
                break
            ;;
            "Add instance")
                new_instance
                break
            ;;
            "Delete instance")
                remove_instance_menu
                break
            ;;
            "Add Camera")
                add_camera
                break
            ;;
            "Delete Camera")
                remove_camera_menu
                break
            ;;
            "Utilities")
                utility_menu
                break
            ;;
            "Backup Menu")
                backup_menu
                break
            ;;
            "Update")
                octo_deploy_update
                break
            ;;
            "Quit")
                exit 1
            ;;
            *) echo "invalid option $REPLY";;
        esac
    done
}

remove_instance_menu() {
    echo
    echo
    get_settings
    if [ $SUDO_USER ]; then user=$SUDO_USER; fi
    if [ -f "/etc/octoprint_instances" ]; then
        
        PS3="${green}Select instance number to remove: ${white}"
        get_instances true
        select opt in "${INSTANCE_ARR[@]}"
        do
            if [ "$opt" == Quit ]; then
                main_menu
            fi
            echo "Selected instance to remove: $opt"
            break
        done
        
        if prompt_confirm "Do you want to remove everything associated with this instance?"; then
            remove_instance $opt
        fi
    fi
    main_menu
}

remove_camera_menu() {
    get_settings
    PS3="${green}Select camera number to remove: ${white}"
    get_cameras true
    
    select camera in "${CAMERA_ARR[@]}"
    do
        if [ "$camera" == Quit ]; then
            main_menu
        fi
        
        echo "Removing udev, service files, and haproxy entry for $camera"
        remove_camera $camera
        main_menu
    done
}

utility_menu() {
    echo
    echo
    PS3="${green}Select an option: ${white}"
    options=("Instance Status" "USB Port Testing" "Sync Users" "Share Uploads" "Change Streamer" "Set Global Config" "Udev Menu" "Diagnostic Output" "Quit")
    select opt in "${options[@]}"
    do
        case $opt in
            "Instance Status")
                instance_status
                break
            ;;
            "USB Port Testing")
                usb_testing
                break
            ;;
            "Sync Users")
                sync_users
                break
            ;;
            "Share Uploads")
                share_uploads
                break
            ;;
            "Set Global Config")
                global_config
                break
            ;;
            "Udev Menu")
                udev_menu
                break
            ;;
            "Change Streamer")
                change_streamer
                break
            ;;
            "Diagnostic Output")
                diagnostics
                break
            ;;
            "Quit")
                main_menu
                break
                ;;*) echo "invalid option $REPLY";;
        esac
    done
}

udev_menu() {
    echo
    echo
    PS3="${green}Select an option: ${white}"
    options=("Add printer udev rule" "Remove printer udev rule" "Add camera udev rule" "Remove camera udev rule" "Quit")
    select opt in "${options[@]}"
    do
        case $opt in
            "Add printer udev rule")
                add_udev
                break
            ;;
            "Remove printer udev rule")
                remove_udev
                break
            ;;
            "Add camera udev rule")
                add_udev_camera
                break
            ;;
            "Remove camera udev rule")
                remove_udev_camera
                break
            ;;
            "Quit")
                main_menu
                break
                ;;*) echo "invalid option $REPLY";;
        esac
    done

}

backup_menu() {
    echo
    echo
    PS3="${green}Select an option: ${white}"
    options=("Create Backup" "Restore Backup" "Quit")
    select opt in "${options[@]}"
    do
        case $opt in
            "Create Backup")
                create_menu
                break
            ;;
            "Restore Backup")
                restore_menu
                break
                break
            ;;
            "Quit")
                main_menu
                break
                ;;*) echo "invalid option $REPLY";;
        esac
    done
}

create_menu() {
    echo
    echo
    PS3="${green}Select instance number to backup: ${white}"
    get_instances true
    select opt in "${INSTANCE_ARR[@]}"
    do
        if [ "$opt" == Quit ]; then
            main_menu
        fi
        
        echo "Selected instance to backup: $opt"
        back_up $opt
        main_menu
    done
}

restore_menu() {
    echo
    echo "${magenta}You must have already created an instance in order to restore it.${white}"
    PS3="${green}Select instance to restore: ${white}"
    get_instances true
    select opt in "${INSTANCE_ARR[@]}"
    do
        if [ "$opt" == Quit ]; then
            main_menu
        fi
        
        echo "Selected instance to restore: $opt"
    done
    
    PS3="${green}Select backup to restore: ${white}"
    readarray -t options < <(ls /home/$user/instance_backup/$opt-backup-*.zip)
    options+=("Quit")
    select zipfile in "${options[@]}"
    do
        if [ "$zipfile" == Quit ]; then
            main_menu
        fi
        
        echo "Selected $opt to restore"
        restore $opt /home/$user/instance_backup/$zipfile
        main_menu
    done
}
