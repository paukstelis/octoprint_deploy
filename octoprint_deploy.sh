#!/bin/bash

#all operations must be with root/sudo
if (( $EUID != 0 )); then
    echo "Please run as root (sudo)"
    exit
fi

#Get abbreviated architecture
ARCH=$(arch)
ARCH=${ARCH:0:3}
#echo $ARCH
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
    
    if [ $SUDO_USER ]; then user=$SUDO_USER; fi
    SCRIPTDIR=$(dirname $(readlink -f $0))
    PIDEFAULT="/home/$user/oprint/bin/octoprint"
    BUDEFAULT="/home/$user/OctoPrint/bin/octoprint"
    OTHERDEFAULT=""
    PS3='Installation type: '
    options=("OctoPi" "Linux/OctoBuntu" "Other" "Quit")
    select opt in "${options[@]}"
    do
        case $opt in
            "OctoPi")
                DAEMONPATH=$PIDEFAULT
                INSTALL=1
                break
            ;;
            "Linux/OctoBuntu")
                DAEMONPATH=$BUDEFAULT
                INSTALL=2
                break
            ;;
            "Other")
                DAEMONPATH=$OTHERDEFAULT
                break
            ;;
            "Quit")
                exit 1
            ;;
            *) echo "invalid option $REPLY";;
        esac
    done
    
    echo "UNPLUG PRINTER YOU ARE INSTALLING NOW (other printers can remain)"
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
            exit 1
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
    
    #check to make sure first run is complete
    if grep -q 'firstRun: true' $BFOLD/config.yaml; then
        echo "WARNING!! You must setup the base profile and admin user before continuing" | log
        main_menu
    fi
    
    if prompt_confirm "Begin auto-detect printer serial number for udev entry?"
    then
        echo
        #clear out journalctl - probably a better way to do this
        journalctl --rotate > /dev/null 2>&1
        journalctl --vacuum-time=1seconds > /dev/null 2>&1
        echo "Plug your printer in via USB now (detection time-out in 1 min)"
        counter=0
        while [[ -z "$UDEV" ]] && [[ $counter -lt 30 ]]; do
            UDEV=$(timeout 1s journalctl -kf | sed -n -e 's/^.*SerialNumber: //p')
            if [[ -z "$TEMPUSB" ]]; then
                TEMPUSB=$(timeout 1s journalctl -kf | sed -n -e 's/^.*\(cdc_acm\|ftdi_sio\|ch341\|cp210x\) \([0-9].*[0-9]\): \(tty.*\|FTD.*\|ch341-uart.*\|cp210x\).*/\2/p')
            else
                sleep 1
            fi
            counter=$(( $counter + 1 ))
        done
    else
        echo "OK. Restart when you are ready" | log; exit 0
    fi
    
    #Failed state. Nothing detected
    if [ -z "$UDEV" ] && [ -z "$TEMPUSB" ]; then
        echo
        echo -e "\033[0;31mNo printer was detected during the detection period.\033[0m Check your USB cable and try again."
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
            echo -e "Your printer will be setup at the following usb address:\033[0;34m $USB\033[0m" | log
            echo
        else
            main_menu
        fi
    else
        echo -e "Serial number detected as: \033[0;34m $UDEV\033[0m" | log
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
        
        #just to be on the safe side, add user to dialout and video
        usermod -a -G dialout,video $OCTOUSER
        echo 'User added to dialout and video groups. You may need to restart before connecting to printers/cameras'
        #Append instance name to list for removal tool
        echo instance:$INSTANCE port:$PORT >> /etc/octoprint_instances
        
        #copy all files to our new directory
        cp -rp $BFOLD $OCTOCONFIG/.$INSTANCE
        
        #Do config.yaml modifications here if needed..
        cat $BFOLD/config.yaml | sed -e "s/INSTANCE/$INSTANCE/" > $OCTOCONFIG/.$INSTANCE/config.yaml        
        #uniquify instances
        sed -i "s/upnpUuid: .*/upnpUuid: $(uuidgen)/" $OCTOCONFIG/.$INSTANCE/config.yaml

        if [[ -n $CAM || -n $USBCAM ]]; then
            write_camera
        fi
        
        #Reset udev
        udevadm control --reload-rules
        udevadm trigger
        systemctl daemon-reload
        sleep 1
        
        #Start and enable system processes
        systemctl start $INSTANCE
        systemctl enable $INSTANCE
        if [[ -n $CAM || -n $USBCAM ]]; then
            systemctl start cam_$INSTANCE.service
            systemctl enable cam_$INSTANCE.service
        fi
        
        #if we are on octopi, add in haproxy entry
        if [ $INSTALL -eq 1 ]; then
            #find frontend line, do insert
            sed -i "/option forwardfor except 127.0.0.1/a\        use_backend $INSTANCE if { path_beg /$INSTANCE/ }" /etc/haproxy/haproxy.cfg
            #add backend info, bracket with comments so we can remove later if needed. This all needs work, just slapping stuff in for now
            echo "#$INSTANCE start" >> /etc/haproxy/haproxy.cfg
            echo "backend $INSTANCE" >> /etc/haproxy/haproxy.cfg
            echo "       reqrep ^([^\ :]*)\ /$INSTANCE/(.*) \1\ /\2" >> /etc/haproxy/haproxy.cfg
            echo "       option forwardfor" >> /etc/haproxy/haproxy.cfg
            echo "       server octoprint1 127.0.0.1:$PORT" >> /etc/haproxy/haproxy.cfg
            echo "       acl needs_scheme req.hdr_cnt(X-Scheme) eq 0" >> /etc/haproxy/haproxy.cfg
            echo "       reqadd X-Scheme:\ https if needs_scheme { ssl_fc }" >> /etc/haproxy/haproxy.cfg
            echo "       reqadd X-Scheme:\ http if needs_scheme !{ ssl_fc }" >> /etc/haproxy/haproxy.cfg
            echo "       reqadd X-Script-Name:\ /$INSTANCE" >> /etc/haproxy/haproxy.cfg
            echo "#$INSTANCE stop" >> /etc/haproxy/haproxy.cfg
            #restart haproxy
            sudo systemctl restart haproxy.service
        fi
    fi
    main_menu
    
}

write_camera() {
    #Establish which streamer system is using, default mjpg-streamer
    STREAMER=$(cat /etc/octoprint_streamer)
    echo $STREAMER
    if [ -z "$STREAMER" ]; then
        $STREAMER='mjpg-streamer'
    fi
    
    #mjpg-streamer
    if [ "$STREAMER" == mjpg-streamer ]; then
        cat $SCRIPTDIR/octocam_mjpg.service | \
        sed -e "s/OCTOUSER/$OCTOUSER/" \
        -e "s/OCTOCAM/cam_$INSTANCE/" \
        -e "s/RESOLUTION/$RESOLUTION/" \
        -e "s/FRAMERATE/$FRAMERATE/" \
        -e "s/CAMPORT/$CAMPORT/" > $SCRIPTDIR/cam_$INSTANCE.service
    fi
    
    #ustreamer
    if [ "$STREAMER" == ustreamer ]; then
        cat $SCRIPTDIR/octocam_ustream.service | \
        sed -e "s/OCTOUSER/$OCTOUSER/" \
        -e "s/OCTOCAM/cam_$INSTANCE/" \
        -e "s/RESOLUTION/$RESOLUTION/" \
        -e "s/FRAMERATE/$FRAMERATE/" \
        -e "s/CAMPORT/$CAMPORT/" > $SCRIPTDIR/cam_$INSTANCE.service
    fi
    
    mv $SCRIPTDIR/cam_$INSTANCE.service /etc/systemd/system/
    echo $CAMPORT >> /etc/camera_ports
    #config.yaml modifications
    echo "webcam:" >> $OCTOCONFIG/.$INSTANCE/config.yaml
    echo "    snapshot: http://$(hostname).local:$CAMPORT?action=snapshot" >> $OCTOCONFIG/.$INSTANCE/config.yaml
    echo "    stream: http://$(hostname).local:$CAMPORT?action=stream" >> $OCTOCONFIG/.$INSTANCE/config.yaml
    echo
    
    #Either Serial number or USB port
    #Serial Number
    if [ -n "$CAM" ]; then
        echo SUBSYSTEM==\"video4linux\", ATTRS{serial}==\"$CAM\", ATTR{index}==\"0\", SYMLINK+=\"cam_$INSTANCE\" >> /etc/udev/rules.d/99-octoprint.rules
    fi
    
    #USB port camera
    if [ -n "$USBCAM" ]; then
        echo SUBSYSTEM==\"video4linux\",KERNELS==\"$USBCAM\",SUBSYSTEMS==\"usb\",ATTR{index}==\"0\",DRIVERS==\"uvcvideo\",SYMLINK+=\"cam_$INSTANCE\" >> /etc/udev/rules.d/99-octoprint.rules
    fi
    
}

add_camera() {
    
    if [ $SUDO_USER ]; then user=$SUDO_USER; fi
    echo 'Adding camera' | log
    if [ -z "$INSTANCE" ]; then
        PS3='Select instance to add camera to: '
        readarray -t options < <(cat /etc/octoprint_instances | sed -n -e 's/^instance:\([[:alnum:]]*\) .*/\1/p')
        #Not yet check to see if instance already has a camera
        select camopt in "${options[@]}"
        do
            echo "Selected instance for camera: $camopt" | log
            INSTANCE=$camopt
            OCTOCONFIG="/home/$user/"
            OCTOUSER=$user
            break
        done
    fi
    
    #clear out journalctl - probably a better way to do this
    journalctl --rotate > /dev/null 2>&1
    journalctl --vacuum-time=1seconds > /dev/null 2>&1
    echo "Plug your CAMERA in via USB now (detection time-out in 1 min)"
    counter=0
    while [[ -z "$CAM" ]] && [[ $counter -lt 30 ]]; do
        CAM=$(timeout 1s journalctl -kf | sed -n -e 's/^.*SerialNumber: //p')
        TEMPUSBCAM=$(timeout 1s journalctl -kf | sed -n -e 's|^.*input:.*/\(.*\)/input/input.*|\1|p')
        counter=$(( $counter + 1 ))
    done
    #Failed state. Nothing detected
    if [ -z "$CAM" ] && [ -z "$TEMPUSBCAM" ]; then
        echo
        echo -e "\033[0;31mNo camera was detected during the detection period.\033[0m"
        echo -e "You can use the Add Camera option to try again after finishing instance installation."
        echo
        echo
        return
    fi
    
    if [ -z "$CAM" ]; then
        echo "Camera Serial Number not detected" | log
        echo -e "Camera will be setup with physical USB address of \033[0;34m $TEMPUSBCAM.\033[0m" | log
        echo "The camera will have to stay plugged into this location." | log
        USBCAM=$TEMPUSBCAM
    else
        echo -e "Camera detected with serial number: \033[0;34m $CAM \033[0m" | log
        check_sn "$CAM"
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
    echo "Settings can be modified after initial setup in /etc/systemd/system/cam_$INSTANCE"
    echo
    echo "Camera Resolution (no sanity check, so get it right) [default: 640x480]:"
    read RESOLUTION
    if [ -z "$RESOLUTION" ]; then
        RESOLUTION="640x480"
    fi
    echo "Selected camera resolution: $RESOLUTION" | log
    #TODO check formating
    echo "Camera Framerate (use 0 for ustreamer hardware) [default: 5]:"
    read FRAMERATE
    if [ -z "$FRAMERATE" ]; then
        FRAMERATE=5
    fi
    echo "Selected camera framerate: $FRAMERATE" | log
    
    
    #Need to check if this is a one-off install
    if [ -n "$camopt" ]; then
        write_camera
        systemctl start cam_$INSTANCE.service
        systemctl enable cam_$INSTANCE.service
        main_menu
    fi
}

remove_instance() {
    if [ $SUDO_USER ]; then user=$SUDO_USER; fi
    #TODO Check to see that octoprint_instances exists before continuing
    echo 'Do not remove the generic instance!' | log
    PS3='Select instance to remove: '
    readarray -t options < <(cat /etc/octoprint_instances | sed -n -e 's/^instance:\([[:alnum:]]*\) .*/\1/p')
    select opt in "${options[@]}"
    do
        echo "Selected instance to remove: $opt" | log
        break
    done
    
    if prompt_confirm "Do you want to remove everything associated with this instance?"
    then
        #disable and remove service file
        if [ -f /etc/systemd/system/$opt.service ]; then
            systemctl stop $opt.service
            systemctl disable $opt.service
            rm /etc/systemd/system/$opt.service
        fi
        
        if [ -f /etc/systemd/system/cam_$opt.service ]; then
            systemctl stop cam_$opt.service
            systemctl disable cam_$opt.service
            rm /etc/systemd/system/cam_$opt.service
            sed -i "/cam_$opt/d" /etc/udev/rules.d/99-octoprint.rules
        fi
        #remove udev entry
        sed -i "/$opt/d" /etc/udev/rules.d/99-octoprint.rules
        #remove files
        rm -rf /home/$user/.$opt
        #remove from octoprint_instances
        sed -i "/$opt/d" /etc/octoprint_instances
        #remove haproxy entry
        if [ -f /etc/haproxy/haproxy.cfg ]; then
            sed -i "/use_backend $opt/d" /etc/haproxy/haproxy.cfg
            sed -i "/#$opt start/,/#$opt stop/d" /etc/haproxy/haproxy.cfg
            systemctl restart haproxy.service
        fi
    fi
    main_menu
}

usb_testing() {
    echo 'USB testing' | log
    journalctl --rotate > /dev/null 2>&1
    journalctl --vacuum-time=1seconds > /dev/null 2>&1
    echo "Plug your printer in via USB now (detection time-out in 1 min)"
    counter=0
    while [[ -z "$UDEV" ]] && [[ $counter -lt 30 ]]; do
        UDEV=$(timeout 1s journalctl -kf | sed -n -e 's/^.*SerialNumber: //p')
        TEMPUSB=$(timeout 1s journalctl -kf | sed -n -e 's/^.*\(cdc_acm\|ftdi_sio\|ch341\|cp210x\) \([0-9].*[0-9]\): \(tty.*\|FTD.*\|ch341-uart.*\|cp210x\).*/\2/p')
        counter=$(( $counter + 1 ))
        if [ -n "$TEMPUSB" ]; then
            echo "Detected device at $TEMPUSB" | log
        fi
        if [ -n "$UDEV" ]; then
            echo "Serial Number detected: $UDEV" | log
            check_sn "$UDEV"
        fi
    done
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
    | xargs apt-get install -y | log
    
    #pacakges to REMOVE go here
    apt-cache --generate pkgnames \
    | grep --line-regexp --fixed-strings \
    -e brltty \
    | xargs apt-get remove -y | log
    
}

prepare () {
    
    echo 'Beginning system preparation' | log
    echo 'This only needs to be run once to prepare your system to use octoprint_deploy.'
    echo 'Run this setup and then connect to OctoPrint through your browser to setup your admin user.'
    PS3='Installation type: '
    options=("OctoPi" "Ubuntu 18-22, Mint, Debian, Raspberry Pi OS" "Fedora 35+" "Quit")
    select opt in "${options[@]}"
    do
        case $opt in
            "OctoPi")
                INSTALL=1
                break
            ;;
            "Ubuntu 18-22, Mint, Debian, Raspberry Pi OS")
                INSTALL=2
                break
            ;;
            "Fedora 35+")
                INSTALL=3
                break
            ;;
            "Quit")
                exit 1
            ;;
            *) echo "invalid option $REPLY";;
        esac
    done
    
    if [ $INSTALL -eq 1 ] && [[ "$ARCH" != arm ]]; then
        echo "WARNING! You have selected OctoPi, but are not using an ARM processor."
        echo "If you are using another linux distribution, select it from the list."
        echo "Unless you really know what you are doing, select N now."
        if prompt_confirm "Continue with OctoPi?"; then
            echo "OK!"
        else
            main_menu
        fi
    fi
    
    if prompt_confirm "Ready to begin?"
    then
        echo 'instance:generic port:5000' > /etc/octoprint_instances
        echo 'Adding camera port records'
        touch /etc/camera_ports
        echo 'Adding current user to dialout and video groups.'
        usermod -a -G dialout,video $user
        
        
        if [ $INSTALL -eq 1 ]; then
            if grep -q 'firstRun: false' /home/$user/.octoprint/config.yaml; then
                echo "It looks as though this OctoPi installation may have already been used." | log
                echo "In order to use the script, the files must be backed up and then moved."
                echo "If you chose to continue with the installation these files will be moved (not erased)."
                echo "They will be found at /home/$user/.old-octo"
                if prompt_confirm "Continue with installation?"; then
                    echo "Continuing installation." | log
                    systemctl stop octoprint.service
                    echo "Moving files to /home/$user/.old-octo" | log
                    mv /home/$user/.octoprint /home/$user/.old-octo
                    systemctl start octoprint.service
                else
                    main_menu
                fi
            fi
            
            echo 'Disabling unneeded services....'
            systemctl disable octoprint.service
            systemctl disable webcamd.service
            systemctl stop webcamd.service
            systemctl disable streamer_select.service
            systemctl stop streamer_select.service
            echo "Adding systemctl and reboot to sudo"
            echo "$user ALL=NOPASSWD: /usr/bin/systemctl" >> /etc/sudoers.d/octoprint_systemctl
            echo "$user ALL=NOPASSWD: /usr/sbin/reboot" >> /etc/sudoers.d/octoprint_reboot
            #webcamd gets restarted? why? get it out of there for now
            #mv /etc/systemd/system/webcamd.service /home/$user/
            echo mjpg-streamer > /etc/octoprint_streamer
            echo 'Modifying config.yaml'
            cp -p $SCRIPTDIR/config.basic /home/pi/.octoprint/config.yaml
            echo 'Connect to your octoprint instance and setup admin user'
            
        fi
        
        if [ $INSTALL -gt 1 ]; then
            echo "Creating OctoBuntu installation equivalent."
            echo "Adding systemctl and reboot to sudo"
            echo "$user ALL=NOPASSWD: /usr/bin/systemctl" >> /etc/sudoers.d/octoprint_systemctl
            echo "$user ALL=NOPASSWD: /usr/sbin/reboot" >> /etc/sudoers.d/octoprint_reboot
            echo "This will install necessary packages, download and install OctoPrint and setup a base instance on this machine."
            #install packages
            #All DEB based
            if [ $INSTALL -eq 2 ]; then
                apt-get update > /dev/null
                deb_packages
            fi
            #Fedora35
            if [ $INSTALL -eq 3 ]; then
                dnf -y install python3-devel cmake libjpeg-turbo-devel
            fi
            
            echo "Installing OctoPrint in /home/$user/OctoPrint"
            #make venv
            sudo -u $user python3 -m venv /home/$user/OctoPrint
            #pre-install wheel
            sudo -u $user /home/$user/OctoPrint/bin/pip install wheel
            #install oprint
            sudo -u $user /home/$user/OctoPrint/bin/pip install OctoPrint
            #start server and run in background
            echo 'Creating generic service...'
            cat $SCRIPTDIR/octoprint_generic.service | \
            sed -e "s/OCTOUSER/$user/" \
            -e "s#OCTOPATH#/home/$user/OctoPrint/bin/octoprint#" \
            -e "s#OCTOCONFIG#/home/$user/#" \
            -e "s/NEWINSTANCE/octoprint/" \
            -e "s/NEWPORT/5000/" > /etc/systemd/system/octoprint_default.service
            echo 'Updating config.yaml'
            sudo -u $user mkdir /home/$user/.octoprint
            sudo -u $user cp -p $SCRIPTDIR/config.basic /home/$user/.octoprint/config.yaml
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
                echo mjpg-streamer > /etc/octoprint_streamer
                #install mjpg-streamer, not doing any error checking or anything
                echo 'Installing mjpeg-streamer'
                sudo -u $user git clone https://github.com/jacksonliam/mjpg-streamer.git mjpeg
                #apt -y install
                sudo -u $user make -C mjpeg/mjpg-streamer-experimental > /dev/null
                sudo -u $user mv mjpeg/mjpg-streamer-experimental /home/$user/mjpg-streamer
                sudo -u $user rm -rf mjpeg
            fi
            
            if [ $VID -eq 2 ]; then
                echo ustreamer > /etc/octoprint_streamer
                #install ustreamer
                sudo -u $user git clone --depth=1 https://github.com/pikvm/ustreamer
                sudo -u $user make -C ustreamer > /dev/null
            fi
            
            #Fedora has SELinux on by default so must make adjustments? Don't really know what these do...
            if [ $INSTALL -eq 3 ]; then
                semanage fcontext -a -t bin_t "/home/$user/OctoPrint/bin/.*"
                chcon -Rv -u system_u -t bin_t "/home/$user/OctoPrint/bin/"
                restorecon -R -v /home/$user/OctoPrint/bin
                if [ $VID -eq 1 ]; then
                    semanage fcontext -a -t bin_t "/home/$user/mjpg-streamer/.*"
                    chcon -Rv -u system_u -t bin_t "/home/$user/mjpg-streamer/"
                    restorecon -R -v /home/$user/mjpg-streamer
                fi
                if [ $VID -eq 2 ]; then
                    semanage fcontext -a -t bin_t "/home/$user/ustreamer/.*"
                    chcon -Rv -u system_u -t bin_t "/home/$user/ustreamer/"
                    restorecon -R -v /home/$user/ustreamer
                fi
                
            fi
            echo 'Starting generic service on port 5000'
            systemctl start octoprint_default.service
            systemctl enable octoprint_default.service
            
        fi
    fi
    main_menu
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

remove_everything() {
    if prompt_confirm "Remove everything?"; then
        readarray -t instances < <(cat /etc/octoprint_instances | sed -n -e 's/^instance:\([[:alnum:]]*\) .*/\1/p')
        for instance in "${instances[@]}"; do
            echo "Trying to remove instance $instance"
            systemctl stop $instance
            systemctl disable $instance
            rm /etc/systemd/system/$instance.service
            echo "Trying to remove camera for $instance"
            systemctl stop cam_$instance
            systemctl disable cam_$instance
            rm /etc/systemd/system/cam_$instance.service
            echo "Removing instance..."
            rm -rf /home/$user/.$instance
        done
        echo "Removing system stuff"
        rm /etc/systemd/system/octoprint_default.service
        rm /etc/octoprint_streamer
        rm /etc/octoprint_instances
        rm /etc/camera_ports
        rm /etc/udev/rules.d/99-octoprint.rules
        rm /etc/sudoers.d/octoprint_reboot
        rm /etc/sudoers.d/octoprint_systemctl
        echo "Removing template"
        rm -rf /home/$user/.octoprint
        rm -rf /home/$user/OctoPrint
        systemctl daemon-reload
        
        
    fi
    
}
main_menu() {
    #reset
    UDEV=''
    TEMPUSB=''
    CAM=''
    TEMPUSBCAM=''
    INSTANCE=''
    INSTALL=''
    PS3='Select operation: '
    if [ -f "/etc/octoprint_instances" ]; then
        options=("New instance" "Delete instance" "Add Camera" "USB port testing" "Quit")
    else
        options=("Prepare system" "New instance" "Delete instance" "Add Camera" "USB port testing" "Quit")
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
            break ;;
            "Delete instance")
                remove_instance
                break
            ;;
            "Add Camera")
                add_camera
                break
            ;;
            "USB port testing")
                usb_testing
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
if [ $SUDO_USER ]; then user=$SUDO_USER; fi
logfile='octoprint_deploy.log'
SCRIPTDIR=$(dirname $(readlink -f $0))

if [ "$1" == remove ]; then
    remove_everything
fi

main_menu
