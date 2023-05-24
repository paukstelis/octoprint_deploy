#!/bin/bash


detect_camera() {
    dmesg -C
    echo "Plug your camera in via USB now (detection time-out in 1 min)"
    counter=0
    while [[ -z "$CAM" ]] && [[ $counter -lt 60 ]]; do
        CAM=$(dmesg | sed -n -e 's/^.*SerialNumber: //p')
        TEMPUSBCAM=$(dmesg | sed -n -e 's|^.*input:.*/\(.*\)/input/input.*|\1|p')
        counter=$(( $counter + 1 ))
        if [[ -n "$TEMPUSBCAM" ]] && [[ -z "$CAM" ]]; then
            break
        fi
        sleep 1
    done
    dmesg -C
}


remove_camera() {
    systemctl stop $1.service
    systemctl disable $1.service
    rm /etc/systemd/system/$1.service
    sed -i "/$1/d" /etc/udev/rules.d/99-octoprint.rules
    if [ "$HAPROXY" == true ]; then
        sed -i "/use_backend $1/d" /etc/haproxy/haproxy.cfg
        sed -i "/#$1 start/,/#$1 stop/d" /etc/haproxy/haproxy.cfg
        systemctl restart haproxy
    fi
}

write_camera() {
    
    get_settings
    if [ -z "$STREAMER" ]; then
        STREAMER="mjpg-streamer"
    fi
    
    #mjpg-streamer
    if [ "$STREAMER" == mjpg-streamer ]; then
        cat $SCRIPTDIR/octocam_mjpg.service | \
        sed -e "s/OCTOUSER/$OCTOUSER/" \
        -e "s/OCTOCAM/cam${INUM}_$INSTANCE/" \
        -e "s/RESOLUTION/$RESOLUTION/" \
        -e "s/FRAMERATE/$FRAMERATE/" \
        -e "s/CAMPORT/$CAMPORT/" > $SCRIPTDIR/cam${INUM}_$INSTANCE.service
    fi
    
    #ustreamer
    if [ "$STREAMER" == ustreamer ]; then
        cat $SCRIPTDIR/octocam_ustream.service | \
        sed -e "s/OCTOUSER/$OCTOUSER/" \
        -e "s/OCTOCAM/cam${INUM}_$INSTANCE/" \
        -e "s/RESOLUTION/$RESOLUTION/" \
        -e "s/FRAMERATE/$FRAMERATE/" \
        -e "s/CAMPORT/$CAMPORT/" > $SCRIPTDIR/cam${INUM}_$INSTANCE.service
    fi
    
    mv $SCRIPTDIR/cam${INUM}_$INSTANCE.service /etc/systemd/system/
    echo $CAMPORT >> /etc/camera_ports
    #config.yaml modifications - only if INUM not set
    if [ -z "$INUM" ]; then
        echo "webcam:" >> $OCTOCONFIG/.$INSTANCE/config.yaml
        echo "    snapshot: http://$(hostname).local:$CAMPORT?action=snapshot" >> $OCTOCONFIG/.$INSTANCE/config.yaml
        if [ -z "$CAMHAPROXY" ]; then
            echo "    stream: http://$(hostname).local:$CAMPORT?action=stream" >> $OCTOCONFIG/.$INSTANCE/config.yaml
        else
            echo "    stream: /cam_$INSTANCE/?action=stream" >> $OCTOCONFIG/.$INSTANCE/config.yaml
        fi
        $OCTOEXEC --basedir $OCTOCONFIG/.$INSTANCE config append_value --json system.actions "{\"action\": \"Reset video streamer\", \"command\": \"sudo systemctl restart cam_$INSTANCE\", \"name\": \"Restart webcam\"}"
    fi
    
    #Either Serial number or USB port
    #Serial Number
    if [ -n "$CAM" ]; then
        echo SUBSYSTEM==\"video4linux\", ATTRS{serial}==\"$CAM\", ATTR{index}==\"0\", SYMLINK+=\"cam${INUM}_$INSTANCE\" >> /etc/udev/rules.d/99-octoprint.rules
    fi
    
    #USB port camera
    if [ -n "$USBCAM" ]; then
        echo SUBSYSTEM==\"video4linux\",KERNELS==\"$USBCAM\", SUBSYSTEMS==\"usb\", ATTR{index}==\"0\", DRIVERS==\"uvcvideo\", SYMLINK+=\"cam${INUM}_$INSTANCE\" >> /etc/udev/rules.d/99-octoprint.rules
    fi
    
    if [ -n "$CAMHAPROXY" ]; then
        HAversion=$(haproxy -v | sed -n 's/^.*version \([0-9]\).*/\1/p')
        #find frontend line, do insert
        sed -i "/use_backend $INSTANCE if/a\        use_backend cam${INUM}_$INSTANCE if { path_beg /cam${INUM}_$INSTANCE/ }" /etc/haproxy/haproxy.cfg
        if [ $HAversion -gt 1 ]; then
            EXTRACAM="backend cam${INUM}_$INSTANCE\n\
            http-request replace-path /cam${INUM}_$INSTANCE/(.*)   /|\1\n\
            server webcam1 127.0.0.1:$CAMPORT"
        else
            EXTRACAM="backend cam${INUM}_$INSTANCE\n\
            reqrep ^([^|\ :]*)|\ /cam${INUM}_$INSTANCE/(.*) |\1|\ /|\2 \n\
            server webcam1 127.0.0.1:$CAMPORT"
        fi
        
        echo "#cam${INUM}_$INSTANCE start" >> /etc/haproxy/haproxy.cfg
        sed -i "/#cam${INUM}_$INSTANCE start/a $EXTRACAM" /etc/haproxy/haproxy.cfg
        #these are necessary because sed append seems to have issues with escaping for the /\1
        sed -i 's/\/|1/\/\\1/' /etc/haproxy/haproxy.cfg
        sed -i 's/\/|2/\/\\2/' /etc/haproxy/haproxy.cfg
        #haproxy 1.x correction
        sed -i 's/|/\\/g' /etc/haproxy/haproxy.cfg
        echo "#cam${INUM}_$INSTANCE stop" >> /etc/haproxy/haproxy.cfg
        
        systemctl restart haproxy
    fi
}

add_camera() {
    PI=$1
    INUM=''
    get_settings
    if [ $SUDO_USER ]; then user=$SUDO_USER; fi
    echo 'Adding camera' | log
    if [ -z "$INSTANCE" ]; then
        PS3='Select instance number to add camera to: '
        readarray -t options < <(cat /etc/octoprint_instances | sed -n -e 's/^instance:\([[:graph:]]*\) .*/\1/p')
        options+=("Quit")
        unset 'options[0]'
        select camopt in "${options[@]}"
        do
            if [ "$camopt" == Quit ]; then
                main_menu
            fi
            echo "Selected instance for camera: $camopt" | log
            INSTANCE=$camopt
            OCTOCONFIG="/home/$user/"
            OCTOUSER=$user
            if grep -q "cam_$INSTANCE" /etc/udev/rules.d/99-octoprint.rules; then
                echo "It appears this instance already has at least one camera."
                if prompt_confirm "Do you want to add an additional camera for this instance?"; then
                    echo "Enter a number for this camera."
                    echo "Ex. entering 2 will setup a service called cam2_$INSTANCE"
                    echo
                    read INUM
                    if [ -z "$INUM" ]; then
                        echo "No value given, setting as 2"
                        INUM='2'
                    fi
                else
                    main_menu
                fi
            fi
            break
        done
    fi
    #for now just set a flag that we are going to write cameras behind haproxy
    if [ "$HAPROXY" == true ]; then
        if prompt_confirm "Add cameras to haproxy?"; then
            CAMHAPROXY=1
        fi
    fi
    
    if [ -z "$PI" ]; then
        detect_camera
        if [ -n "$NOSERIAL" ] && [ -n "$CAM" ]; then
            unset CAM
        fi
        #Failed state. Nothing detected
        if [ -z "$CAM" ] && [ -z "$TEMPUSBCAM" ] ; then
            echo
            echo -e "\033[0;31mNo camera was detected during the detection period.\033[0m"
            echo
            return
        fi
        
        if [ -z "$CAM" ]; then
            echo "Camera Serial Number not detected" | log
            echo -e "Camera will be setup with physical USB address of \033[0;32m $TEMPUSBCAM.\033[0m" | log
            echo "The camera will have to stay plugged into this location." | log
            USBCAM=$TEMPUSBCAM
        else
            echo -e "Camera detected with serial number: \033[0;32m $CAM \033[0m" | log
            check_sn "$CAM"
        fi
        
    else
        echo
        echo
        echo "Setting up a Pi camera service for /dev/video0"
        echo "Please note that mixing this setup with USB cameras may lead to issues."
        echo "Don't expect extensive support for trying to fix these issues."
        echo
        echo
    fi
    
    while true; do
        echo "Camera Port (ENTER will increment last value in /etc/camera_ports):"
        read CAMPORT
        if [ -z "$CAMPORT" ]; then
            CAMPORT=$(tail -1 /etc/camera_ports)
            
            if [ -z "$CAMPORT" ]; then
                CAMPORT=8000
            fi
            CAMPORT=$((CAMPORT+1))
        fi
        
        if [ $CAMPORT -gt 7000 ]; then
            break
        else
            echo "Camera Port must be greater than 7000"
        fi
        
        
    done
    
    echo "Settings can be modified after initial setup in /etc/systemd/system/cam${INUM}_$INSTANCE.service"
    echo
    while true; do
        echo "Camera Resolution [default: 640x480]:"
        read RESOLUTION
        if [ -z $RESOLUTION ]
        then
            RESOLUTION="640x480"
            break
        elif [[ $RESOLUTION =~ ^[0-9]+x[0-9]+$ ]]
        then
            break
        fi
        echo "Invalid resolution"
    done
    echo "Selected camera resolution: $RESOLUTION" | log
    echo "Camera Framerate (use 0 for ustreamer hardware) [default: 5]:"
    read FRAMERATE
    if [ -z "$FRAMERATE" ]; then
        FRAMERATE=5
    fi
    echo "Selected camera framerate: $FRAMERATE" | log
    
    #Need to check if this is a one-off install
    if [ -n "$camopt" ]; then
        write_camera
        #Pi Cam setup, replace cam_INSTANCE with /dev/video0
        if [ -n "$PI" ]; then
            echo SUBSYSTEM==\"video4linux\", ATTRS{name}==\"camera0\", SYMLINK+=\"cam${INUM}_$INSTANCE\" >> /etc/udev/rules.d/99-octoprint.rules
        fi
        systemctl start cam${INUM}_$INSTANCE.service
        systemctl enable cam${INUM}_$INSTANCE.service
        systemctl daemon-reload
        udevadm control --reload-rules
        udevadm trigger
        main_menu
    fi
}