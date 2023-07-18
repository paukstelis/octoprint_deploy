#!/bin/bash

new_instance() {
    #It is possible to not create an instance after preparing,so check if this is the first
    if [ -f /etc/octoprint_instances ]; then
        firstrun=false
    else
        firstrun=true
    fi
    
    #We can also pass this directly, from prepare.sh
    firstrun=$1
    TEMPLATE=''
    
    get_settings
    
    if [ $SUDO_USER ]; then user=$SUDO_USER; fi
    SCRIPTDIR=$(dirname $(readlink -f $0))
    
    while true; do
        echo "${green}Enter the name for new printer/instance (no spaces):${white}"
        read INSTANCE
        if [ -z "$INSTANCE" ]; then
            echo "Please provide an instance name"
            continue
        fi
        
        if ! has-space "$INSTANCE"; then
            break
        else
            echo "Instance names must not have spaces"
        fi
    done
    
    if [ "$firstrun" != "true" ]; then
        if test -f "/etc/systemd/system/$INSTANCE.service"; then
            echo "Already have an entry for $INSTANCE. Exiting."
            main_menu
        fi
        
        #Choose if should use an instance as template here
        echo
        echo
        echo
        echo "Using a template instance allows you to copy config settings"
        echo "and gcode files from one instance to your new instance."
        if prompt_confirm "Use an existing instance as a template?"; then
            PS3="${cyan}Select template instance: ${white}"
            get_instances true
            select opt in "${INSTANCE_ARR[@]}"
            do
                if [ "$opt" == Quit ]; then
                    main_menu
                fi
                
                TEMPLATE=$opt
                echo "Using $opt as template."
                break
            done
            PS3="${cyan}Select what components of the template to copy: ${white}"
            options=("Config Only" "Config and Gcode")
            select opt in "${options[@]}"
            do
                case $opt in
                    "Config Only")
                        COPY=1
                        break
                    ;;
                    "Config and Gcode")
                        COPY=2
                        break
                        ;;*) echo "invalid option $REPLY";;
                esac
            done
            
        else
            TEMPLATE=''
        fi
    fi
    
    if prompt_confirm "Ready to begin instance creation?"; then
        #CHANGE
        if [ -f /etc/octoprint_instances ]; then
            PORT=$(tail -1 /etc/octoprint_instances 2>/dev/null | sed -n -e 's/^.*\(port:\)\(.*\) udev:.*/\2/p')
        fi
        
        if [ -z "$PORT" ]; then
            PORT=4999
        fi
        
        PORT=$((PORT+1))
        echo Selected port is: $PORT
        #CHANGE
        OCTOUSER=$user
        OCTOPATH=$OCTOEXEC
        OCTOCONFIG="/home/$user"
        
        echo "Your new OctoPrint instance will be installed at ${cyan}/home/$user/.$INSTANCE${white}"
        echo
        echo
    else
        main_menu
    fi
    
    if [ -n "$TEMPLATE" ]; then
        BFOLD="/home/$user/.$TEMPLATE"
        #check to make sure first run is complete
        if grep -q 'firstRun: true' $BFOLD/config.yaml; then
            echo "Template profile and admin user will have to be setup."
            main_menu
        fi
    fi
    
    echo "Printer auto-detection must be completed before an instance can be created."
    if prompt_confirm "Begin printer auto-detection for udev entry?"; then
        detect_printer
    else
        echo "${magenta}Instance has not been created. Restart and do detection when you are ready.${white}"
        main_menu
    fi
    
    #Detection phase
    printer_udev false
    
    #USB cameras
    if [ "$firstrun" != "true" ]; then
        if prompt_confirm "Would you like to auto detect an associated USB camera (experimental)?"; then
            add_camera
        fi
    fi
    
    if prompt_confirm "Ready to write all changes. Do you want to proceed?"; then
        
        sudo -u $user mkdir $OCTOCONFIG/.$INSTANCE
        
        cat $SCRIPTDIR/octoprint_generic.service | \
        sed -e "s/OCTOUSER/$OCTOUSER/" \
        -e "s#OCTOPATH#$OCTOPATH#" \
        -e "s#OCTOCONFIG#$OCTOCONFIG#" \
        -e "s/NEWINSTANCE/$INSTANCE/" \
        -e "s/NEWPORT/$PORT/" > /etc/systemd/system/$INSTANCE.service
        
        #write phase
        printer_udev true
        
        #Append instance name to list for removal tool
        if [ -z "$UDEV" ] && [ -z "$TEMPUSB" ]; then
            echo "instance:$INSTANCE port:$PORT udev:false" >> /etc/octoprint_instances
        else
            echo "instance:$INSTANCE port:$PORT udev:true" >> /etc/octoprint_instances
        fi
        
        if [ -n "$TEMPLATE" ]; then
            #There may be other combinations of things to include/exclude
            if [ $COPY -eq 1 ]; then
                sudo -u $user rsync -r \
                --exclude 'timelapse' \
                --exclude 'uploads' \
                --exclude 'logs' \
                $BFOLD/* $OCTOCONFIG/.$INSTANCE/
            fi
            if [ $COPY -eq 2 ]; then
                sudo -u $user rsync -r \
                --exclude 'timelapse' \
                --exclude 'logs' \
                $BFOLD/* $OCTOCONFIG/.$INSTANCE/
            fi
            echo "${magenta}Copying template files....${white}"
            #cp -rp $BFOLD/* $OCTOCONFIG/.$INSTANCE
        fi
        
        #uniquify instances
        echo 'Uniquifying instance...'
        BASE=$OCTOCONFIG/.$INSTANCE
        sudo -u $user $OCTOEXEC --basedir $BASE config set appearance.name $INSTANCE
        sudo -u $user $OCTOEXEC --basedir $BASE config set server.commands.serverRestartCommand "sudo systemctl restart $INSTANCE"
        sudo -u $user $OCTOEXEC --basedir $BASE config set server.commands.systemRestartCommand "sudo reboot"
        sudo -u $user $OCTOEXEC --basedir $BASE config set plugins.discovery.upnpUuid $(uuidgen)
        sudo -u $user $OCTOEXEC --basedir $BASE config set plugins.errortracking.unique_id $(uuidgen)
        sudo -u $user $OCTOEXEC --basedir $BASE config set plugins.tracking.unique_id $(uuidgen)
        sudo -u $user $OCTOEXEC --basedir $BASE config set serial.port /dev/octo_$INSTANCE
        #clear additional ports
        sudo -u $user $OCTOEXEC --basedir $BASE config remove serial.additionalPorts
        sudo -u $user $OCTOEXEC --basedir $BASE config append_value serial.additionalPorts "/dev/octo_$INSTANCE"
        sudo -u $user $OCTOEXEC --basedir $BASE config set feature.modelSizeDetection false --bool
        sudo -u $user $OCTOEXEC --basedir $BASE config set webcam.ffmpeg /usr/bin/ffmpeg
        
        if [ "$HAPROXY" == true ]; then
            HAversion=$(haproxy -v | sed -n 's/^.*version \([0-9]\).*/\1/p')
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
        if [[ -n $CAM || -n $USBCAM || -n $BYIDCAM ]]; then
            systemctl start cam_$INSTANCE.service
            systemctl enable cam_$INSTANCE.service
        fi
    else
        main_menu
    fi
    
    if [ "$firstrun" == "true" ]; then
        firstrun_install
    else
        main_menu
    fi
    
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

printer_udev() {
    write=$1
    if [ "$write" == true ]; then
        #Printer udev identifier technique - either Serial number or USB port
        #Serial Number
        if [ -n "$UDEV" ]; then
            echo SUBSYSTEM==\"tty\", ATTRS{serial}==\"$UDEV\", SYMLINK+=\"octo_$INSTANCE\" >> /etc/udev/rules.d/99-octoprint.rules
        fi
        
        #USB port
        if [ -n "$USB" ]; then
            echo KERNELS==\"$USB\",SUBSYSTEM==\"tty\",SYMLINK+=\"octo_$INSTANCE\" >> /etc/udev/rules.d/99-octoprint.rules
        fi
    else
        #No serial number
        if [ -z "$UDEV" ] && [ -n "$TEMPUSB" ]; then
            echo "Printer Serial Number not detected"
            if prompt_confirm "Do you want to use the physical USB port to assign the udev entry? If you use this any USB hubs and printers detected this way must stay plugged into the same USB positions on your machine as they are right now"; then
                echo
                USB=$TEMPUSB
                echo "Your printer will be setup at the following usb address: ${cyan}$USB${white}"
                echo
            else
                main_menu
            fi
        else
            echo -e "Serial number detected as: ${cyan}$UDEV${white}"
            check_sn "$UDEV"
            echo
        fi
        #Failed state. Nothing detected
        if [ -z "$UDEV" ] && [ -z "$TEMPUSB" ]; then
            echo
            echo "${red}No printer was detected during the detection period.${white}"
            echo "Check your USB cable (power only?) and try again."
            echo
            echo
            if [ "$firstrun" == "true" ]; then
                echo "You can attempt adding a udev rule later from the Utilities menu."
            else
                main_menu
            fi
        fi
    fi
}

remove_instance() {
    opt=$1
    #disable and remove service file
    if [ -f /etc/systemd/system/$opt.service ]; then
        systemctl stop $opt.service
        systemctl disable $opt.service
        rm /etc/systemd/system/$opt.service 2>/dev/null
    fi
    
    #Get all cameras associated with this instance.
    #Is this right?
    get_cameras
    for camera in "${CAMERA_ARR[@]}"; do
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