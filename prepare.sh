#!/bin/bash

detect_installs() {
    #OctoPi will be the most common so do a search for that:
    if [ -f "/etc/octopi_version" ]; then
        echo "OctoPi installation detected."
        echo "Adding standard OctoPi instance to instance list."
        echo "instance:octoprint port:5000" >> /etc/octoprint_instances
        echo "octoexec: /home/$user/oprint/bin/octoprint" >> /etc/octoprint_deploy
        echo "octopip: /home/$user/oprint/bin/pip" >> /etc/octoprint_deploy
        echo "haproxy: true" >> /etc/octoprint_deploy
        streamer_install
        main_menu
    fi
    
    echo "Searching home directory for existing OctoPrint venv/binary....."
    octopresent=$(find /home/$user/ -type f -executable -print | grep "bin/octoprint")
    if [ -n "$octopresent" ]; then
        echo "OctoPrint binary found at $octopresent"
        PS3='Select option number: '
        options=("Use existing binary" "Install most recent OctoPrint" "More information")
        select opt in "${options[@]}"
        do
            case $opt in
                "Use existing binary")
                    OCTOEXEC=$octopresent
                    break
                ;;
                "Install most recent OctoPrint")
                    OCTOEXEC=thing
                    break
                ;;
                "More information")
                    exit 1
                ;;
                *) echo "invalid option $REPLY";;
            esac
        done
    else
        echo "No OctoPrint binary found in the current user's home directory. Doing complete install."
        FULLINSTALL=1
    fi
    echo "Looking for existing OctoPrint systemd files....."
    #get any service files that have bin/octoprint
    readarray -t syspresent < <(fgrep -l bin/octoprint /etc/systemd/system/*.service)
    prepare
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
    -e uuid-runtime\
    -e ssh\
    -e libffi-dev\
    -e haproxy\
    | xargs apt-get install -y
    
    #pacakges to REMOVE go here
    apt-cache --generate pkgnames \
    | grep --line-regexp --fixed-strings \
    -e brltty \
    | xargs apt-get remove -y
    
}

dnf_packages() {
    #untested
    dnf list all \
    | grep --line-regexp --fixed-strings \
    -e gcc\
    -e python3-devel\
    -e cmake\
    -e libjpeg-turbo-devel\
    -e libbsd-devel\
    -e libevent-devel\
    -e haproxy\
    -e openssh\
    -e openssh-server\
    -e libffi-devel\
    | xarg dnf install -y 
    
}

pacman_packages() {
    pacman -S --noconfirm make cmake python python-virtualenv libyamlpython-pip libjpeg-turbo python-yaml python-setuptools libffi ffmpeg gcc libevent libbsd openssh haproxy v4l-utils
}

zypper_packages() {
    zypper -y install gcc python3-devel cmake libjpeg-turbo-devel libbsd-devel libevent-devel haproxy openssh openssh-server libffi-devel
}

user_groups() {
    
    echo 'Adding current user to dialout and video groups.'
    usermod -a -G dialout,video $user
    
    if [ $INSTALL -eq 4 ]; then
        usermod -a -G uucp $user
    fi
}

prepare () {
    echo
    echo
    
    PS3='Installation type: '
    local options=("Ubuntu 20+, Mint, Debian, Raspberry Pi OS" "Fedora/CentOS" "ArchLinux" "Quit")
    select opt in "${options[@]}"
    do
        case $opt in
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
    
    if prompt_confirm "Ready to begin?"; then
        
        #CHOICE HERE between new_install or directly to haproxy/streamer based on if existing binary is used
        if [ -n "$FULLINSTALL" ]; then
            new_install
        else
            old_install
        fi
        touch /etc/camera_ports
    fi
    main_menu
}

old_install() {
    echo "octoexec:$octopresent" >> /etc/octoprint_deploy
    haproxy_install
    streamer_install
    #add existing instance(s) to /etc/octoprint_instances
}

new_install() {
    OCTOEXEC=/home/$user/OctoPrint/bin/octoprint
    echo "Adding systemctl and reboot to sudo"
    echo "$user ALL=NOPASSWD: /usr/bin/systemctl" > /etc/sudoers.d/octoprint_systemctl
    echo "$user ALL=NOPASSWD: /usr/sbin/reboot" > /etc/sudoers.d/octoprint_reboot
    echo "This will install necessary packages, download and install OctoPrint and setup a template instance on this machine."
    #install packages
    #All DEB based
    PYVERSION="python3"
    if [ $INSTALL -eq 2 ]; then
        apt-get update > /dev/null
        deb_packages
    fi
    
    #Fedora35/CentOS
    if [ $INSTALL -eq 3 ]; then
        systemctl enable sshd.service
        PYV=$(python3 -c"import sys; print(sys.version_info.minor)")
        if [ $PYV -eq 11 ]; then
            dnf -y install python3.10-devel
            PYVERSION='python3.10'
        fi
        dnf_packages
    fi
    
    #ArchLinux
    if [ $INSTALL -eq 4 ]; then
        pacman_packages
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
    
    #Check to verify that OctoPrint binary is installed
    if [ -f "/home/$user/OctoPrint/bin/octoprint" ]; then
        echo "OctoPrint apppears to have been installed successfully"
    else
        echo "WARNING! WARNING! WARNING!"
        echo "OctoPrint has not been installed correctly."
        echo "Please answer Y to remove everything and try running prepare system again."
        remove_everything
        exit
    fi
    
    haproxy_install
    streamer_install
    
    #These will retreived as settings
    echo "octoexec: /home/$user/OctoPrint/bin/octoprint" >> /etc/octoprint_deploy
    echo "octopip: /home/$user/OctoPrint/bin/pip" >> /etc/octoprint_deploy

    #Create first instance
    echo "It is time to create your first OctoPrint instance!!!"
    new_instance true
    echo
    echo
    if prompt_confirm "Would you like to install recommended plugins now?"; then
        plugin_menu
    fi
    
}

haproxy_install() {
    #Haproxy
    #Must do a check to see if haproxy already running.....this is a point where things could get complicated
    echo
    echo
    echo 'You have the option of setting up haproxy.'
    echo 'This binds instances to a name on port 80 instead of having to type the port.'
    echo
    echo
    if prompt_confirm "Use haproxy?"; then
        echo 'haproxy: true' >> /etc/octoprint_deploy
        #Check if using improved haproxy rules
        #echo 'haproxynew: true' >> /etc/octoprint_deploy
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
}

streamer_install() {
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
                VID=3
                break
            ;;
            *) echo "invalid option $REPLY";;
        esac
    done
    
    if [ $VID -eq 1 ]; then
        
        #install mjpg-streamer, not doing any error checking or anything
        echo 'Installing mjpeg-streamer'
        sudo -u $user git -C /home/$user/ clone https://github.com/jacksonliam/mjpg-streamer.git mjpeg
        #apt -y install
        sudo -u $user make -C /home/$user/mjpeg/mjpg-streamer-experimental > /dev/null
        
        sudo -u $user mv /home/$user/mjpeg/mjpg-streamer-experimental /home/$user/mjpg-streamer
        sudo -u $user rm -rf /home/$user/mjpeg
        if [ -f "/home/$user/mjpg-streamer/mjpg_streamer" ]; then
            echo "Streamer installed successfully"
        else
            echo "WARNING! WARNING! WARNING!"
            echo "Streamer has not been installed correctly."
            if prompt_confirm "Try installation again?"; then
                streamer_install
            fi
        fi
        echo 'streamer: mjpg-streamer' >> /etc/octoprint_deploy
    fi
    
    if [ $VID -eq 2 ]; then
        
        #install ustreamer
        sudo -u $user git -C /home/$user clone --depth=1 https://github.com/pikvm/ustreamer
        sudo -u $user make -C /home/$user/ustreamer > /dev/null
        if [ -f "/home/$user/ustreamer/ustreamer" ]; then
            echo "Streamer installed successfully"
        else
            echo "WARNING! WARNING! WARNING!"
            echo "Streamer has not been installed correctly."
            if prompt_confirm "Try installation again?"; then
                streamer_install
            fi
        fi
        echo 'streamer: ustreamer' >> /etc/octoprint_deploy
    fi
    
    if [ $VID -eq 3 ]; then
        echo 'streamer: none' >> /etc/octoprint_deploy
        echo "Good for you! Cameras are just annoying anyway."
    fi
    
}

firstrun_install() {
    echo
    echo
    echo 'The first instance can be configured at this time.'
    echo 'This includes setting up the admin user and finishing the startup wizards.'
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
        sudo -u $user $OCTOEXEC --basedir $BASE user add $OCTOADMIN --password $OCTOPASS --admin | log
    fi
    
    if [ -n "$OCTOADMIN" ]; then
        echo
        echo
        echo "The script can complete the first run wizards now. For more information on these, see the OctoPrint website."
        echo "It is standard to accept these, as no identifying information is exposed through their usage."
        echo
        echo
        if prompt_confirm "Do first run wizards now?"; then
            sudo -u $user $OCTOEXEC --basedir $BASE config set server.firstRun false --bool | log
            sudo -u $user $OCTOEXEC --basedir $BASE config set server.seenWizards.backup null | log
            sudo -u $user $OCTOEXEC --basedir $BASE config set server.seenWizards.corewizard 4 --int | log
            
            if prompt_confirm "Enable online connectivity check?"; then
                sudo -u $user $OCTOEXEC --basedir $BASE config set server.onlineCheck.enabled true --bool
            else
                sudo -u $user $OCTOEXEC --basedir $BASE config set server.onlineCheck.enabled false --bool
            fi
            
            if prompt_confirm "Enable plugin blacklisting?"; then
                sudo -u $user $OCTOEXEC --basedir $BASE config set server.pluginBlacklist.enabled true --bool
            else
                sudo -u $user $OCTOEXEC --basedir $BASE config set server.pluginBlacklist.enabled false --bool
            fi
            
            if prompt_confirm "Enable anonymous usage tracking?"; then
                sudo -u $user $OCTOEXEC --basedir $BASE config set plugins.tracking.enabled true --bool
            else
                sudo -u $user $OCTOEXEC --basedir $BASE config set plugins.tracking.enabled false --bool
            fi
            
            if prompt_confirm "Use default printer (can be changed later)?"; then
                sudo -u $user $OCTOEXEC --basedir $BASE config set printerProfiles.default _default
            fi
        fi
    fi
}

