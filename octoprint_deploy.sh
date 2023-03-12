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

get_settings() {
    #Get octoprint_deploy settings, all of which are written on system prepare
    if [ -f /etc/octoprint_deploy ]; then
        TYPE=$(cat /etc/octoprint_deploy | sed -n -e 's/^type: \(\.*\)/\1/p')
        if [ "$TYPE" == linux ]; then
            OCTOEXEC="sudo -u $user /home/$user/OctoPrint/bin/octoprint"
        else
            OCTOEXEC="sudo -u $user /home/$user/oprint/bin/octoprint"
        fi
        STREAMER=$(cat /etc/octoprint_deploy | sed -n -e 's/^streamer: \(\.*\)/\1/p')
        #echo $STREAMER
        HAPROXY=$(cat /etc/octoprint_deploy | sed -n -e 's/^haproxy: \(\.*\)/\1/p')
        #echo $HAPROXY
        HAPROXYNEW=$(cat /etc/octoprint_deploy | sed -n -e 's/^haproxynew: \(\.*\)/\1/p')
        if [ -z "$HAPROXYNEW" ]; then
            HAPROXYNEW="false"
        fi
    fi
}

# from stackoverflow.com/questions/3231804
prompt_confirm() {
    while true; do
        read -r -n 1 -p "${1:-Continue?} [y/n]: " REPLY
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

new_instance () {
    
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
    
    echo "Enter the name for new printer/instance (no spaces):"
    read INSTANCE
    if [ -z "$INSTANCE" ]; then
        echo "No instance given. Exiting" | log
        main_menu
    fi
    
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
        OCTOCONFIG="/home/$user/"
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
            OCTOCONFIG="/home/$user/"
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
    reqrep ^([^\ :]*)\ /cam${INUM}_$INSTANCE/(.*) \1\ /|\2 \n\
    server webcam1 127.0.0.1:$CAMPORT"
        fi

        echo "#cam${INUM}_$INSTANCE start" >> /etc/haproxy/haproxy.cfg
        sed -i "/#cam${INUM}_$INSTANCE start/a $EXTRACAM" /etc/haproxy/haproxy.cfg
        #these are necessary because sed append seems to have issues with escaping for the /\1
        sed -i 's/\/|1/\/\\1/' /etc/haproxy/haproxy.cfg
        sed -i 's/\/|2/\/\\2/' /etc/haproxy/haproxy.cfg
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
    
    echo "Camera Port (ENTER will increment last value in /etc/camera_ports):"
    read CAMPORT
    if [ -z "$CAMPORT" ]; then
        CAMPORT=$(tail -1 /etc/camera_ports)
        
        if [ -z "$CAMPORT" ]; then
            CAMPORT=8000
        fi
        
        CAMPORT=$((CAMPORT+1))
        echo Selected port is: $CAMPORT | log
    fi
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



usb_testing() {
    echo
    echo
    echo "Testing printer USB" | log
    detect_printer
    echo "Detected device at $TEMPUSB" | log
    echo "Serial Number detected: $UDEV" | log
    main_menu
}

#https://askubuntu.com/questions/39497
deb_packages() {
    #All extra packages needed can be added here for deb based systems. Only available will be selected.
    apt-cache --generate pkgnames \
    | grep --line-regexp --fixed-strings \
    -e make \
    -e v4l-utils \
    -e python-is-python3 \
    -e python3-venv \
    -e python3.9-venv \
    -e python3.10-venv \
    -e virtualenv \
    -e python3-dev \
    -e python3-setuptools \
    -e build-essential \
    -e python3-setuptools \
    -e libyaml-dev \
    -e python3-pip \
    -e cmake \
    -e libjpeg8-dev \
    -e libjpeg62-turbo-dev \
    -e gcc \
    -e g++ \
    -e libevent-dev \
    -e libjpeg-dev \
    -e libbsd-dev \
    -e ffmpeg \
    -e uuid-runtime\
    -e ssh\
    -e libffi-dev\
    -e haproxy\
    | xargs apt-get install -y | log
    
    #pacakges to REMOVE go here
    apt-cache --generate pkgnames \
    | grep --line-regexp --fixed-strings \
    -e brltty \
    | xargs apt-get remove -y | log
    
}

prepare () {
    echo
    echo
    MOVE=0
    echo 'Beginning system preparation' | log
    PS3='Installation type: '
    options=("OctoPi" "Ubuntu 20+, Mint, Debian, Raspberry Pi OS" "Fedora/CentOS" "ArchLinux" "Quit")
    select opt in "${options[@]}"
    do
        case $opt in
            "OctoPi")
                INSTALL=1
                break
            ;;
            "Ubuntu 20+, Mint, Debian, Raspberry Pi OS")
                INSTALL=2
                break
            ;;
            "Fedora/CentOS")
                INSTALL=3
                break
            ;;
            "ArchLinux")
                INSTALL=4
                break
            ;;
            "Quit")
                exit 1
            ;;
            *) echo "invalid option $REPLY";;
        esac
    done
    
    if [ $INSTALL -eq 1 ] && [[ "$ARCH" != arm ]]; then
        echo
        echo
        echo "WARNING! You have selected OctoPi, but are not using an ARM processor."
        echo "If you are using another linux distribution, select it from the list."
        echo "Unless you really know what you are doing, select N now."
        echo
        echo
        if prompt_confirm "Continue with OctoPi?"; then
            echo "OK!"
        else
            main_menu
        fi
    fi
    echo
    echo
    if prompt_confirm "Ready to begin?"
    then
        echo 'Adding current user to dialout and video groups.'
        usermod -a -G dialout,video $user
        
        #service start/stop may fail on non-OctoPi instances, but that is probably Ok
        if [ -f "/home/$user/.octoprint/config.yaml" ]; then
            if grep -q 'firstRun: false' /home/$user/.octoprint/config.yaml; then
                echo "It looks as though this installation has already been in use." | log
                echo "In order to use the script, the files must be moved."
                echo "If you chose to continue with the installation these files will be moved (not erased)."
                echo "They will be found at /home/$user/.old-octo"
                echo "If you have generated service files for OctoPrint, please stop and disable them."
                if prompt_confirm "Continue with installation?"; then
                    MOVE=1
                    echo "Continuing installation." | log
                    systemctl stop octoprint.service
                    echo "Moving files to /home/$user/.old-octo" | log
                    mv /home/$user/.octoprint /home/$user/.old-octo
                    systemctl start octoprint.service
                else
                    main_menu
                fi
            fi
        fi
        
        if [ $INSTALL -eq 1 ]; then
            OCTOEXEC="sudo -u $user /home/$user/oprint/bin/octoprint"
            OCTOPIP="sudo -u $user /home/$user/oprint/bin/pip"
            echo
            echo
            if prompt_confirm "Would you like to install and use ustreamer instead of mjpg-streamer?"; then
                echo 'streamer: ustreamer' >> /etc/octoprint_deploy
                apt-get -y install libevent-dev libbsd-dev
                sudo -u $user git clone --depth=1 https://github.com/pikvm/ustreamer
                sudo -u $user make -C ustreamer > /dev/null
            else
                echo 'streamer: mjpg-streamer' >> /etc/octoprint_deploy
            fi
            
            echo 'Disabling unneeded services....'
            systemctl disable octoprint.service
            systemctl disable webcamd.service
            systemctl stop webcamd.service
            systemctl disable streamer_select.service
            systemctl stop streamer_select.service
            echo 'Installing needed packages'
            apt-get -y install uuid-runtime
            echo "Adding systemctl and reboot to sudo"
            echo "$user ALL=NOPASSWD: /usr/bin/systemctl" > /etc/sudoers.d/octoprint_systemctl
            echo "$user ALL=NOPASSWD: /usr/sbin/reboot" > /etc/sudoers.d/octoprint_reboot
            echo 'haproxy: true' >> /etc/octoprint_deploy
            echo 'Modifying config.yaml'
            cp -p $SCRIPTDIR/config.basic /home/$user/.octoprint/config.yaml
            firstrun
            echo 'Connect to your octoprint (octopi.local) instance and setup admin user if you have not already'
            echo 'type: octopi' >> /etc/octoprint_deploy
            echo
            echo
            if prompt_confirm "Would you like to install recommended plugins now?"; then
                plugin_menu
            fi
            echo
            echo
            if prompt_confirm "Would you like to install cloud service plugins now?"; then
                plugin_menu_cloud
            fi
            systemctl restart octoprint.service
            
        fi
        
        if [ $INSTALL -gt 1 ]; then
            OCTOEXEC="sudo -u $user /home/$user/OctoPrint/bin/octoprint"
            OCTOPIP="sudo -u $user /home/$user/OctoPrint/bin/pip"
            echo "Adding systemctl and reboot to sudo"
            echo "$user ALL=NOPASSWD: /usr/bin/systemctl" > /etc/sudoers.d/octoprint_systemctl
            echo "$user ALL=NOPASSWD: /usr/sbin/reboot" > /etc/sudoers.d/octoprint_reboot
            echo "This will install necessary packages, download and install OctoPrint and setup a template instance on this machine."
            #install packages
            #All DEB based
            #Python 3.11 currently not compatible with OP, redefine for Fedora
            PYVERSION="python3"
            if [ $INSTALL -eq 2 ]; then
                apt-get update > /dev/null
                deb_packages
            fi
            #Fedora35/CentOS
            if [ $INSTALL -eq 3 ]; then
                dnf -y install gcc python3-devel cmake libjpeg-turbo-devel libbsd-devel libevent-devel haproxy openssh openssh-server libffi-devel
                systemctl enable sshd.service
                PYV=$(python3 -c"import sys; print(sys.version_info.minor)")
                if [ $PYV -eq 11 ]; then
                    dnf -y install python3.10-devel
                    PYVERSION='python3.10'
                fi
            fi
            
            #ArchLinux
            if [ $INSTALL -eq 4 ]; then
                pacman -S --noconfirm make cmake python python-virtualenv libyamlpython-pip libjpeg-turbo python-yaml python-setuptools libffi ffmpeg gcc libevent libbsd openssh haproxy v4l-utils
                usermod -a -G uucp $user
            fi
            echo "Enabling ssh server..."
            systemctl enable ssh.service
            echo "Installing OctoPrint virtual environment in /home/$user/OctoPrint"
            #make venv
            sudo -u $user $PYVERSION -m venv /home/$user/OctoPrint
            #update pip
            sudo -u $user /home/$user/OctoPrint/bin/pip install --upgrade pip
            #pre-install wheel
            sudo -u $user /home/$user/OctoPrint/bin/pip install wheel
            #install oprint
            sudo -u $user /home/$user/OctoPrint/bin/pip install OctoPrint
            #start server and run in background
            echo 'Creating generic OctoPrint template service...'
            cat $SCRIPTDIR/octoprint_generic.service | \
            sed -e "s/OCTOUSER/$user/" \
            -e "s#OCTOPATH#/home/$user/OctoPrint/bin/octoprint#" \
            -e "s#OCTOCONFIG#/home/$user/#" \
            -e "s/NEWINSTANCE/octoprint/" \
            -e "s/NEWPORT/5000/" > /etc/systemd/system/octoprint_default.service
            echo 'Updating config.yaml'
            sudo -u $user mkdir /home/$user/.octoprint
            sudo -u $user cp -p $SCRIPTDIR/config.basic /home/$user/.octoprint/config.yaml
            #Haproxy
            echo
            echo
            echo 'You have the option of setting up haproxy.'
            echo 'This binds instances to a name on port 80 instead of having to type the port.'
            echo
            echo
            if prompt_confirm "Use haproxy?"; then
                echo 'haproxy: true' >> /etc/octoprint_deploy
                #Check if using improved haproxy rules
                echo 'haproxynew: true' >> /etc/octoprint_deploy
                systemctl stop haproxy
                #get haproxy version
                HAversion=$(haproxy -v | sed -n 's/^.*version \([0-9]\).*/\1/p')
                mv /etc/haproxy/haproxy.cfg /etc/haproxy/haproxy.orig
                if [ $HAversion -gt 1 ]; then
                    cp $SCRIPTDIR/haproxy2x.basic /etc/haproxy/haproxy.cfg
                else
                    cp $SCRIPTDIR/haproxy1x.basic /etc/haproxy/haproxy.cfg
                fi
                systemctl start haproxy
                systemctl enable haproxy
            else
                systemctl stop haproxy
                systemctl disable haproxy
            fi
            
            echo
            echo
            echo
            PS3='Which video streamer you would like to install?: '
            options=("mjpeg-streamer" "ustreamer" "None")
            select opt in "${options[@]}"
            do
                case $opt in
                    "mjpeg-streamer")
                        VID=1
                        break
                    ;;
                    "ustreamer")
                        VID=2
                        break
                    ;;
                    "None")
                        break
                    ;;
                    *) echo "invalid option $REPLY";;
                esac
            done
            
            if [ $VID -eq 1 ]; then
                echo 'streamer: mjpg-streamer' >> /etc/octoprint_deploy
                #install mjpg-streamer, not doing any error checking or anything
                echo 'Installing mjpeg-streamer'
                sudo -u $user git clone https://github.com/jacksonliam/mjpg-streamer.git mjpeg
                #apt -y install
                sudo -u $user make -C mjpeg/mjpg-streamer-experimental > /dev/null
                sudo -u $user mv mjpeg/mjpg-streamer-experimental /home/$user/mjpg-streamer
                sudo -u $user rm -rf mjpeg
            fi
            
            if [ $VID -eq 2 ]; then
                echo 'streamer: ustreamer' >> /etc/octoprint_deploy
                #install ustreamer
                sudo -u $user git clone --depth=1 https://github.com/pikvm/ustreamer
                sudo -u $user make -C ustreamer > /dev/null
            fi
            
            if [ $VID -eq 3 ]; then
                echo "Good for you! Cameras are just annoying anyway."
            fi
            
            #Fedora has SELinux on by default so must make adjustments? Don't really know what these do...
            if [ $INSTALL -eq 3 ]; then
                semanage fcontext -a -t bin_t "/home/$user/OctoPrint/bin/.*"
                chcon -Rv -u system_u -t bin_t "/home/$user/OctoPrint/bin/"
                restorecon -R -v /home/$user/OctoPrint/bin
                if [ $VID -eq 1 ]; then
                    semanage fcontext -a -t bin_t "/home/$user/mjpg-streamer/.*"
                    chcon -Rv -u more sysystem_u -t bin_t "/home/$user/mjpg-streamer/"
                    restorecon -R -v /home/$user/mjpg-streamer
                fi
                if [ $VID -eq 2 ]; then
                    semanage fcontext -a -t bin_t "/home/$user/ustreamer/.*"
                    chcon -Rv -u system_u -t bin_t "/home/$user/ustreamer/"
                    restorecon -R -v /home/$user/ustreamer
                fi
                
            fi
            
            #Prompt for admin user and firstrun stuff
            firstrun
            echo 'type: linux' >> /etc/octoprint_deploy
            echo 'Starting template service on port 5000'
            echo -e "\033[0;31mConnect to your template instance and setup the admin user if you have not done so already.\033[0m"
            systemctl start octoprint_default.service
            systemctl enable octoprint_default.service
            echo
            echo
            if prompt_confirm "Would you like to install recommended plugins now?"; then
                plugin_menu
            fi
            echo
            echo
            if prompt_confirm "Would you like to install cloud service plugins now?"; then
                plugin_menu_cloud
            fi
            #this restart seems necessary in some cases
            systemctl restart octoprint_default.service
        fi
        echo 'instance:generic port:5000' > /etc/octoprint_instances
        touch /etc/octoprint_instances
        echo 'Adding camera port records'
        touch /etc/camera_ports
        if [ $MOVE -eq 1 ]; then
            echo "You can move your previously uploaded gcode to the template instance now."
            echo "If you do this, ALL new instances will have these gcode files."
            if prompt_confirm "Move old gcode files to template instance?"; then
                mv /home/$user/.old-octo/uploads /home/$user/.octoprint/uploads
            fi
        fi
        echo "System preparation complete!"
        
    fi
    main_menu
}

firstrun() {
    echo
    echo
    echo 'The template instance can be configured at this time.'
    echo 'This includes setting up the admin user and finishing the startup wizards.'
    echo 'If you do these now, you will not have to connect to the template with a browser.'
    echo
    echo
    if prompt_confirm "Do you want to setup your admin user now?"; then
        echo 'Enter admin user name (no spaces): '
        read OCTOADMIN
        if [ -z "$OCTOADMIN" ]; then
            echo -e "No admin user given! Defaulting to: \033[0;31moctoadmin\033[0m"
            OCTOADMIN=octoadmin
        fi
        echo "Admin user: $OCTOADMIN"
        echo 'Enter admin user password (no spaces): '
        read OCTOPASS
        if [ -z "$OCTOPASS" ]; then
            echo -e "No password given! Defaulting to: \033[0;31mfooselrulz\033[0m. Please CHANGE this."
            OCTOPASS=fooselrulz
        fi
        echo "Admin password: $OCTOPASS"
        $OCTOEXEC user add $OCTOADMIN --password $OCTOPASS --admin | log
    fi
    if [ -n "$OCTOADMIN" ]; then
        echo
        echo
        echo "The script can complete the first run wizards now. For more information on these, see the OctoPrint website."
        echo "It is standard to accept these, as no identifying information is exposed through their usage."
        echo
        echo
        if prompt_confirm "Do first run wizards now?"; then
            $OCTOEXEC config set server.firstRun false --bool | log
            $OCTOEXEC config set server.seenWizards.backup null | log
            $OCTOEXEC config set server.seenWizards.corewizard 4 --int | log
            
            if prompt_confirm "Enable online connectivity check?"; then
                $OCTOEXEC config set server.onlineCheck.enabled true --bool
            else
                $OCTOEXEC config set server.onlineCheck.enabled false --bool
            fi
            
            if prompt_confirm "Enable plugin blacklisting?"; then
                $OCTOEXEC config set server.pluginBlacklist.enabled true --bool
            else
                $OCTOEXEC config set server.pluginBlacklist.enabled false --bool
            fi
            
            if prompt_confirm "Enable anonymous usage tracking?"; then
                $OCTOEXEC config set plugins.tracking.enabled true --bool
            else
                $OCTOEXEC config set plugins.tracking.enabled false --bool
            fi
            
            if prompt_confirm "Use default printer (can be changed later)?"; then
                $OCTOEXEC config set printerProfiles.default _default
            fi
        fi
    fi
    
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

remove_instance_menu() {
    echo
    echo
    get_settings
    if [ $SUDO_USER ]; then user=$SUDO_USER; fi
    if [ -f "/etc/octoprint_instances" ]; then
        
        PS3='Select instance number to remove: '
        readarray -t options < <(cat /etc/octoprint_instances | sed -n -e 's/^instance:\([[:graph:]]*\) port:.*/\1/p')
        options+=("Quit")
        unset 'options[0]'
        select opt in "${options[@]}"
        do
            if [ "$opt" == Quit ]; then
                main_menu
            fi
            echo "Selected instance to remove: $opt" | log
            break
        done
        
        if prompt_confirm "Do you want to remove everything associated with this instance?"; then
            remove_instance $opt
        fi
    fi
    main_menu
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

remove_camera_menu() {
    get_settings
    #must choose where to find which cameras have been installed
    #probably safest to go with service files
    PS3='Select camera number to remove: '
    readarray -t cameras < <(ls -1 /etc/systemd/system/cam*.service | sed -n -e 's/^.*\/\(.*\).service/\1/p')
    cameras+=("Quit")
    
    select camera in "${cameras[@]}"
    do
        if [ "$camera" == Quit ]; then
            main_menu
        fi
        
        echo "Removing udev, service files, and haproxy entry for $camera" | log
        remove_camera $camera
        main_menu
    done
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
utility_menu() {
    echo
    echo
    PS3='Select an option: '
    options=("Instance Status" "USB Port Testing" "Sync Users" "Share Uploads" "Quit")
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
    PS3='Select an option: '
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
    PS3='Select instance number to backup: '
    readarray -t options < <(cat /etc/octoprint_instances | sed -n -e 's/^instance:\([[:graph:]]*\) .*/\1/p')
    options+=("Quit")
    select opt in "${options[@]}"
    do
        if [ "$opt" == Quit ]; then
            main_menu
        fi
        
        echo "Selected instance to backup: $opt" | log
        back_up $opt
        main_menu
    done
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

restore_menu() {
    echo
    echo
    PS3='Select backup to restore: '
    readarray -t options < <(ls /home/$user/*.tar.gz)
    options+=("Quit")
    select opt in "${options[@]}"
    do
        if [ "$opt" == Quit ] || [ "$opt" == generic ]; then
            main_menu
        fi
        
        echo "Selected $opt to restore" | log
        tar --same-owner -pxvf $opt
        main_menu
    done
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

#Get current udev identification for an instance, replace via auto-detect
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

octo_deploy_update() {
    sudo -u $user git -C octoprint_deploy pull
    exit
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

main_menu() {
    VERSION=0.2.3
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
    echo "*************************"
    echo "octoprint_deploy $VERSION"
    echo "*************************"
    echo
    PS3='Select operation: '
    if [ -f "/etc/octoprint_instances" ]; then
        options=("New instance" "Delete instance" "Add Camera" "Delete Camera" "Utilities" "Backup Menu" "Update" "Quit")
    else
        options=("Prepare system" "USB port testing" "Update" "Quit")
    fi
    
    select opt in "${options[@]}"
    do
        case $opt in
            "Prepare system")
                prepare
                break
            ;;
            "New instance")
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
# initiate logging
logfile='octoprint_deploy.log'
SCRIPTDIR=$(dirname $(readlink -f $0))
source $SCRIPTDIR/plugins.sh
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
