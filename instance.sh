#!/bin/bash
new_instance() {
    
    echo "$(date) starting instance installation" | log
    get_settings
    
    if [ $SUDO_USER ]; then user=$SUDO_USER; fi
    SCRIPTDIR=$(dirname $(readlink -f $0))
    PIDEFAULT="/home/$user/oprint/bin/octoprint"
    BUDEFAULT="/home/$user/OctoPrint/bin/octoprint"
    if [ -z "$TYPE" ]; then
        echo "No installation type found. Have you run system prepare?"
        main_menu
    fi
    
    if [ "$TYPE" == octopi ]; then
        INSTALL=1
        DAEMONPATH=$PIDEFAULT
    fi
    
    if [ "$TYPE" == linux ]; then
        INSTALL=2
        DAEMONPATH=$BUDEFAULT
    fi
    
    while true; do
        echo "Enter the name for new printer/instance (no spaces):"
        read INSTANCE
        if [ -z "$INSTANCE" ]; then
            echo "No instance given. Exiting" | log
            main_menu
        fi
        
        if ! has-space "$INSTANCE"; then
            break
        else
            echo "Instance names must not have spaces"
        fi
    done
    
    if test -f "/etc/systemd/system/$INSTANCE.service"; then
        echo "Already have an entry for $INSTANCE. Exiting." | log
        main_menu
    fi
    
    if prompt_confirm "Use all default values?"; then
        PORT=$(tail -1 /etc/octoprint_instances | sed -n -e 's/^.*\(port:\)\(.*\)/\2/p')
        if [ -z "$PORT" ]; then
            PORT=5000
        fi
        PORT=$((PORT+1))
        echo Selected port is: $PORT | log
        OCTOUSER=$user
        OCTOPATH=$DAEMONPATH
        OCTOCONFIG="/home/$user"
        BFOLD="/home/$user/.octoprint"
        echo "Your OctoPrint instance will be installed at /home/$user/.$INSTANCE"
        echo
        echo
    else
        echo "Port on which this instance will run (ENTER will increment from last value in /etc/octoprint_instances):"
        read PORT
        if [ -z "$PORT" ]; then
            PORT=$(tail -1 /etc/octoprint_instances | sed -n -e 's/^.*\(port:\)\(.*\)/\2/p')
            
            if [ -z "$PORT" ]; then
                PORT=5000
            fi
            
            PORT=$((PORT+1))
            echo Selected port is: $PORT | log
            
        fi
        
        if [ -f /etc/octoprint_instances ]; then
            if grep -q $PORT /etc/octoprint_instances; then
                echo "Port may be in use! Check /etc/octoprint_instances and select a different port. Exiting." | log
                main_menu
            fi
        fi
        
        #collect user, basedir path, daemon path
        echo "Octoprint Daemon User [$user]:"
        read OCTOUSER
        if [ -z "$OCTOUSER" ]; then
            OCTOUSER=$user
        fi
        
        echo "Octoprint Executable Daemon Path [$DAEMONPATH]:"
        read OCTOPATH
        if [ -z "$OCTOPATH" ]; then
            OCTOPATH=$DAEMONPATH
        fi
        
        if [ -f "$OCTOPATH" ]; then
            echo "Executable path is valid" | log
        else
            echo "Exectuable path is not valid! Aborting" | log
            main_menu
        fi
        
        echo "Octoprint Config Path (where the hidden instance directory will be) [/home/$user/]:"
        read OCTOCONFIG
        if [ -z "$OCTOCONFIG" ]; then
            OCTOCONFIG="/home/$user"
        fi
        
        #octoprint_base is the generic .octoprint folder that contains all configuration, upload, etc.
        echo "Octoprint instance template path [/home/$user/.octoprint]:"
        read BFOLD
        if [ -z "$BFOLD" ]; then
            BFOLD="/home/$user/.octoprint"
        fi
        
        if [ -d "$BFOLD" ]; then
            echo "Template path is valid" | log
        else
            echo "Template path is not valid! Aborting" | log
            main_menu
        fi
    fi
    
    #check to make sure first run is complete
    if grep -q 'firstRun: true' $BFOLD/config.yaml; then
        echo "WARNING!! You must setup the template profile and admin user before continuing" | log
        main_menu
    fi
    
    if prompt_confirm "Begin auto-detect printer serial number for udev entry?"
    then
        detect_printer
    else
        echo "OK. Restart when you are ready" | log; exit 0
    fi
    
    #Failed state. Nothing detected
    if [ -z "$UDEV" ] && [ -z "$TEMPUSB" ]; then
        echo
        echo -e "\033[0;31mNo printer was detected during the detection period.\033[0m Check your USB cable (power only?) and try again."
        echo
        echo
        main_menu
    fi
    
    #No serial number
    if [ -z "$UDEV" ]; then
        echo "Printer Serial Number not detected"
        if prompt_confirm "Do you want to use the physical USB port to assign the udev entry? If you use this any USB hubs and printers detected this way must stay plugged into the same USB positions on your machine as they are right now"; then
            echo
            USB=$TEMPUSB
            echo -e "Your printer will be setup at the following usb address: $USB" | log
            echo
        else
            main_menu
        fi
    else
        echo -e "Serial number detected as: $UDEV" | log
        check_sn "$UDEV"
        echo
    fi
    
    echo
    
    #USB cameras
    if [[ -n $INSTALL ]]; then
        if prompt_confirm "Would you like to auto detect an associated USB camera (experimental)?"
        then
            add_camera
        fi
    fi
    echo
    
    if prompt_confirm "Ready to write all changes. Do you want to proceed?"
    then
        cat $SCRIPTDIR/octoprint_generic.service | \
        sed -e "s/OCTOUSER/$OCTOUSER/" \
        -e "s#OCTOPATH#$OCTOPATH#" \
        -e "s#OCTOCONFIG#$OCTOCONFIG#" \
        -e "s/NEWINSTANCE/$INSTANCE/" \
        -e "s/NEWPORT/$PORT/" > /etc/systemd/system/$INSTANCE.service
        
        #If a default octoprint service exists, stop and disable it
        if [ -f "/etc/systemd/system/octoprint_default.service" ]; then
            systemctl stop octoprint_default.service
            systemctl disable octoprint_default.service
        fi
        
        #stop and disable default octoprint service (octopi)
        if [ -f "/etc/systemd/system/octoprint.service" ]; then
            systemctl stop octoprint.service
            systemctl disable octoprint.service
        fi
        
        #Printer udev identifier technique - either Serial number or USB port
        #Serial Number
        if [ -n "$UDEV" ]; then
            echo SUBSYSTEM==\"tty\", ATTRS{serial}==\"$UDEV\", SYMLINK+=\"octo_$INSTANCE\" >> /etc/udev/rules.d/99-octoprint.rules
        fi
        
        #USB port
        if [ -n "$USB" ]; then
            echo KERNELS==\"$USB\",SUBSYSTEM==\"tty\",SYMLINK+=\"octo_$INSTANCE\" >> /etc/udev/rules.d/99-octoprint.rules
        fi
        
        #Append instance name to list for removal tool
        echo instance:$INSTANCE port:$PORT >> /etc/octoprint_instances
        
        #copy all files to our new directory
        cp -rp $BFOLD $OCTOCONFIG/.$INSTANCE
        
        #uniquify instances
        echo 'Uniquifying instance...'
        #Do config.yaml modifications here
        cat $BFOLD/config.yaml | sed -e "s/INSTANCE/$INSTANCE/" > $OCTOCONFIG/.$INSTANCE/config.yaml
        $DAEMONPATH --basedir $OCTOCONFIG/.$INSTANCE config set plugins.discovery.upnpUuid $(uuidgen)
        $DAEMONPATH --basedir $OCTOCONFIG/.$INSTANCE config set plugins.errortracking.unique_id $(uuidgen)
        $DAEMONPATH --basedir $OCTOCONFIG/.$INSTANCE config set plugins.tracking.unique_id $(uuidgen)
        $DAEMONPATH --basedir $OCTOCONFIG/.$INSTANCE config set serial.port /dev/octo_$INSTANCE
        $DAEMONPATH --basedir $OCTOCONFIG/.$INSTANCE config set webcam.ffmpeg /usr/bin/ffmpeg
        
        if [ "$HAPROXY" == true ]; then
            HAversion=$(haproxy -v | sed -n 's/^.*version \([0-9]\).*/\1/p')
            #find frontend line, do insert
            #Don't know how to do the formatting correctly here. This works, however.
            
            SEDREPLACE="#$INSTANCE start\n\
            acl is_$INSTANCE url_beg /$INSTANCE\n\
            http-request redirect scheme http drop-query append-slash  if is_$INSTANCE ! { path_beg /$INSTANCE/ }\n\
            use_backend $INSTANCE if { path_beg /$INSTANCE/ }\n\
            #$INSTANCE stop"
            
            sed -i "/option forwardfor except 127.0.0.1/a $SEDREPLACE" /etc/haproxy/haproxy.cfg
            echo "#$INSTANCE start" >> /etc/haproxy/haproxy.cfg
            echo "backend $INSTANCE" >> /etc/haproxy/haproxy.cfg
            if [ $HAversion -gt 1 ]; then
                echo "       http-request replace-path /$INSTANCE/(.*) /\1" >> /etc/haproxy/haproxy.cfg
                echo "       acl needs_scheme req.hdr_cnt(X-Scheme) eq 0" >> /etc/haproxy/haproxy.cfg
                echo "       http-request add-header X-Scheme https if needs_scheme { ssl_fc }" >> /etc/haproxy/haproxy.cfg
                echo "       http-request add-header X-Scheme http if needs_scheme !{ ssl_fc }" >> /etc/haproxy/haproxy.cfg
                echo "       http-request add-header X-Script-Name /$INSTANCE" >> /etc/haproxy/haproxy.cfg
                echo "       server octoprint1 127.0.0.1:$PORT" >> /etc/haproxy/haproxy.cfg
                echo "       option forwardfor" >> /etc/haproxy/haproxy.cfg
            else
                echo "       reqrep ^([^\ :]*)\ /$INSTANCE/(.*) \1\ /\2" >> /etc/haproxy/haproxy.cfg
                echo "       server octoprint1 127.0.0.1:$PORT" >> /etc/haproxy/haproxy.cfg
                echo "       option forwardfor" >> /etc/haproxy/haproxy.cfg
                echo "       acl needs_scheme req.hdr_cnt(X-Scheme) eq 0" >> /etc/haproxy/haproxy.cfg
                echo "       reqadd X-Scheme:\ https if needs_scheme { ssl_fc }" >> /etc/haproxy/haproxy.cfg
                echo "       reqadd X-Scheme:\ http if needs_scheme !{ ssl_fc }" >> /etc/haproxy/haproxy.cfg
                echo "       reqadd X-Script-Name:\ /$INSTANCE" >> /etc/haproxy/haproxy.cfg
            fi
            
            echo "#$INSTANCE stop" >> /etc/haproxy/haproxy.cfg
            
            #restart haproxy
            sudo systemctl restart haproxy.service
            
        fi
        
        if [[ -n $CAM || -n $USBCAM ]]; then
            write_camera
        fi
        
        #Reset udev
        udevadm control --reload-rules
        udevadm trigger
        systemctl daemon-reload
        sleep 1
        
        #Start and enable system processes
        systemctl start $INSTANCE.service
        systemctl enable $INSTANCE.service
        if [[ -n $CAM || -n $USBCAM ]]; then
            systemctl start cam_$INSTANCE.service
            systemctl enable cam_$INSTANCE.service
        fi
        
    fi
    main_menu
    
}

detect_printer() {
    echo
    echo
    dmesg -C
    echo "Plug your printer in via USB now (detection time-out in 1 min)"
    counter=0
    while [[ -z "$UDEV" ]] && [[ $counter -lt 60 ]]; do
        TEMPUSB=$(dmesg | sed -n -e 's/^.*\(cdc_acm\|ftdi_sio\|ch341\|cp210x\|ch34x\) \([0-9].*[0-9]\): \(tty.*\|FTD.*\|ch341-uart.*\|cp210x\|ch34x\).*/\2/p')
        UDEV=$(dmesg | sed -n -e 's/^.*SerialNumber: //p')
        counter=$(( $counter + 1 ))
        if [[ -n "$TEMPUSB" ]] && [[ -z "$UDEV" ]]; then
            break
        fi
        sleep 1
    done
    dmesg -C
}



remove_instance() {
    opt=$1
    #disable and remove service file
    if [ -f /etc/systemd/system/$opt.service ]; then
        systemctl stop $opt.service
        systemctl disable $opt.service
        rm /etc/systemd/system/$opt.service
    fi
    
    #Get all cameras associated with this instance
    readarray -t cameras < <(ls -1 /etc/systemd/system/cam*.service | sed -n -e 's/^.*\/\(.*\).service/\1/p')
    for camera in "${cameras[@]}"; do
        remove_camera $camera
    done
    
    #remove udev entry
    sed -i "/$opt/d" /etc/udev/rules.d/99-octoprint.rules
    #remove files
    rm -rf /home/$user/.$opt
    #remove from octoprint_instances
    sed -i "/$opt/d" /etc/octoprint_instances
    #remove haproxy entry
    if [ "$HAPROXY" == true ]; then
        sed -i "/use_backend $opt/d" /etc/haproxy/haproxy.cfg
        sed -i "/#$opt start/,/#$opt stop/d" /etc/haproxy/haproxy.cfg
        systemctl restart haproxy.service
    fi
    
}