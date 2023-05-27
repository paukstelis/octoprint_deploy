#!/bin/bash
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
            
            #NEW! Do check to verify that OctoPrint binary is installed
            if [ -f "/home/$user/OctoPrint/bin/octoprint" ]; then
                echo "OctoPrint apppears to have been installed successfully"
            else
                echo "WARNING! WARNING! WARNING!"
                echo "OctoPrint has not been installed correctly."
                echo "Please answer Y to remove everything and try running prepare system again."
                remove_everything
                exit
            fi
            
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
                    chcon -Rv -u system_u -t bin_t "/home/$user/mjpg-streamer/"
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
            #if prompt_confirm "Would you like to install cloud service plugins now?"; then
            #    plugin_menu_cloud
            #fi
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
        while true; do
            echo 'Enter admin user name (no spaces): '
            read OCTOADMIN
            if [ -z "$OCTOADMIN" ]; then
                echo -e "No admin user given! Defaulting to: \033[0;31moctoadmin\033[0m"
                OCTOADMIN=octoadmin
            fi
            if ! has-space "$OCTOADMIN"; then
                break
            else
                echo "Admin user name must not have spaces."
            fi
        done
        echo "Admin user: $OCTOADMIN"
        
        while true; do
            echo 'Enter admin user password (no spaces): '
            read OCTOPASS
            if [ -z "$OCTOPASS" ]; then
                echo -e "No password given! Defaulting to: \033[0;31mfooselrulz\033[0m. Please CHANGE this."
                OCTOPASS=fooselrulz
            fi
            
            if ! has-space "$OCTOPASS"; then
                break
            else
                echo "Admin password cannot contain spaces"
            fi
            
        done
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