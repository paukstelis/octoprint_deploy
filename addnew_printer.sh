#!/bin/bash

if (( $EUID != 0 )); then
    echo "Please run as root (sudo)"
    exit
fi


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

# initiate logging
logfile='octoprint_deploy.log'  
echo "$(date) starting instance installation" >> $logfile

if [ $SUDO_USER ]; then user=$SUDO_USER; fi
SCRIPTDIR=$(dirname $(readlink -f $0))
PIDEFAULT="/home/$user/oprint/bin/octoprint"
BUDEFAULT="/home/$user/OctoPrint/bin/octoprint"
OTHERDEFAULT=""
PS3='Installation type: '
options=("OctoPi" "OctoBuntu" "Other" "Quit")
select opt in "${options[@]}"
do
    case $opt in
        "OctoPi")
            DAEMONPATH=$PIDEFAULT
            INSTALL=1
            break
            ;;
        "OctoBuntu")
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
    exit 1
fi

if test -f "/etc/systemd/system/$INSTANCE.service"; then
    echo "Already have an entry for $INSTANCE. Exiting." | log
    exit 1
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
   exit 1
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
   exit 1
fi

#check to make sure first run is complete
if grep -q 'firstRun: true' $BFOLD/config.yaml; then
    echo "WARNING!! You must setup the base profile and admin user before continuing" | log
    exit 1
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
      TEMPUSB=$(timeout 1s journalctl -kf | sed -n -e 's/^.*\(cdc_acm\|ftdi_sio\|ch341\) \([0-9].*[0-9]\): \(tty.*\|FTD.*\|ch341-uart.*\).*/\2/p')   
      counter=$(( $counter + 1 ))
   done
else
   echo "OK. Restart when you are ready" | log; exit 0
fi


if [ -z "$UDEV" ]; then
   echo "Printer Serial Number not detected"
   prompt_confirm "Do you want to use the physical USB port to assign the udev entry? If you use this any USB hubs and printers detected this way must stay plugged into the same USB positions on your machine as they are right now" || exit 0
   #if [[ $REPLY =~ ^[Yy]$ ]]; then
   echo
   USB=$TEMPUSB
   echo "Your printer will be setup at the following usb address:"
   echo $USB | log
   echo    
else
   echo "Serial number detected as: $UDEV" | log
fi

echo

#USB cameras
if [[ -n $INSTALL ]]; then
   if prompt_confirm "Would you like to auto detect an associated USB camera (experimental)?"
   then
      echo
      #clear out journalctl - probably a better way to do this
      journalctl --rotate > /dev/null 2>&1
      journalctl --vacuum-time=1seconds > /dev/null 2>&1
      echo "Plug your CAMERA in via USB now (detection time-out in 1 min)"
      counter=0
      while [[ -z "$CAM" ]] && [[ $counter -lt 30 ]]; do 
         CAM=$(timeout 1s journalctl -kf | sed -n -e 's/^.*SerialNumber: //p')
         TEMPUSBCAM=$(timeout 1s journalctl -kf | sed -n -e 's/^.*uvcvideo \(.*\): tty.*/\1/p')
         counter=$(( $counter + 1 ))
      done
      if [ -z "$CAM" ]; then
         echo "Camera Serial Number not detected" | log
         echo "You will have to use another tool for setting up camera services" | log
      else
         echo "Camera detected with serial number: $CAM" | log
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
   
   #Open port to be on safe side
   #ufw allow $PORT/tcp
   
   #Append port in the port list
   #echo $PORT >> /etc/octoprint_ports
   
   #Append instance name to list for removal tool
   echo instance:$INSTANCE port:$PORT >> /etc/octoprint_instances
   
   #copy all files to our new directory
   cp -rp $BFOLD $OCTOCONFIG/.$INSTANCE
   
   #Do config.yaml modifications here if needed..
   cat $BFOLD/config.yaml | sed -e "s/INSTANCE/$INSTANCE/" > $OCTOCONFIG/.$INSTANCE/config.yaml
   
   #If cameras were setup add stream and snapshot

   
   #MAJOR WORKAROUND - for some reason this will not cat and sed directly into systemd/system. no idea why. create and mv for now
   if [[ -n $CAM || -n $USBCAM ]]; then
      cat $SCRIPTDIR/octocam_generic.service | \
      sed -e "s/OCTOUSER/$OCTOUSER/" \
          -e "s/OCTOCAM/cam_$INSTANCE/" \
          -e "s/CAMPORT/$CAMPORT/" > $SCRIPTDIR/cam_$INSTANCE.service
      mv $SCRIPTDIR/cam_$INSTANCE.service /etc/systemd/system/
      echo $CAMPORT >> /etc/camera_ports
      #config.yaml modifications
      echo "webcam:" >> $OCTOCONFIG/.$INSTANCE/config.yaml
      echo "    snapshot: http://localhost:$CAMPORT?action=snapshot" >> $OCTOCONFIG/.$INSTANCE/config.yaml
      echo "    stream: http://localhost:$CAMPORT?action=stream" >> $OCTOCONFIG/.$INSTANCE/config.yaml
   echo
   fi
   #Octobuntu Cameras udev identifier - either Serial number or USB port
   #Serial Number        
   if [ -n "$CAM" ]; then
      echo SUBSYSTEM==\"video4linux\", ATTRS{serial}==\"$CAM\", ATTR{index}==\"0\", SYMLINK+=\"cam_$INSTANCE\" >> /etc/udev/rules.d/99-octoprint.rules
   fi
   
   #USB port
   #if [ -n "$USBCAM" ]; then
   #   echo KERNELS==\"$USBCAM\",SUBSYSTEMS==\"video4linux\", ATTR{index}==\"0\", SYMLINK+=\"cam_$INSTANCE\" >> /etc/udev/rules.d/99-octoprint.rules
   #fi
   
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
fi

