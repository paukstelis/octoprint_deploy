#!/bin/bash

if (( $EUID != 0 )); then
    echo "Please run as root"
    exit
fi

if [ $SUDO_USER ]; then user=$SUDO_USER; fi

echo "Please select the type of installation:"
echo "1 - OctoPi"
echo "2 - Octobuntu"
echo "3 - Other (few defaults)"
read INSTALL

echo "UNPLUG PRINTER FROM USB"
echo "Enter the name for new printer/instance:"
read INSTANCE
if [ -z "$INSTANCE" ]; then
    echo "No instance given. Exiting"
    exit 1
fi

if test -f "/etc/systemd/system/$INSTANCE.service"; then
    echo "Already have an entry for $INSTANCE. Exiting."
    exit 1
fi

echo "Port on which this instance will run (ENTER will increment last value in /etc/octoprint_ports):"
read PORT
if [ -z "$PORT" ]; then
    PORT=$(tail -1 /etc/octoprint_ports)

    if [ -z "$PORT" ]; then
       PORT=4999
    fi

    PORT=$((PORT+1))
    echo Selected port is: $PORT
fi

if [ -f /etc/octoprint_ports ]; then
   if grep -q $PORT /etc/octoprint_ports; then
       echo "Port in use! Check /etc/octoprint_ports. Exiting."
       exit 1
   fi
fi

#collect user, basedir path, daemon path
echo "Octoprint Daemon User [$user]:"
read OCTOUSER
if [ -z "$OCTOUSER" ]; then
    OCTOUSER=$user
fi

PIDEFAULT="/home/$user/oprint/bin/octoprint"
BUDEFAULT="/home/$user/octoprint/bin/octoprint"
OTHERDEFAULT=""
if [ $INSTALL=1 ]; then
   DAEMONPATH=$PIDEFAULT
fi

if [ $INSTALL=2 ]; then
   DAEMONPATH=$BUDEFAULT
fi

if [ $INSTALL=3 ]; then
   DAEMONPATH=""
fi

echo "Octoprint Executable Daemon Path [$DAEMONPATH]:"
read OCTOPATH
if [ -z "$OCTOPATH" ]; then
    OCTOPATH=$DAEMONPATH
fi

if [[ -f $OCTOPATH ]]; then
   echo "Path is valid"
else
   echo "Path is not valid! Aborting"
   exit 1
fi

echo "Octoprint Config Path (where the hidden instance directory will be) [/home/$user/]:"
read OCTOCONFIG
if [ -z "$OCTOCONFIG" ]; then
    OCTOCONFIG="/home/$user/"
fi

#octoprint_base is the generic .octoprint folder that contains all configuration, upload, etc.
echo "Octoprint instance template base folder [/home/$user/.octoprint]:"
read BFOLD
if [ -z "$BFOLD" ]; then
    BFOLD="/home/$user/.octoprint"
fi

if [[ -d $BFOLD ]]; then
   echo "Path is valid"
else
   echo "Path is not valid! Aborting"
   exit 1
fi

read -p "Auto-detect printer serial number for udev entry?" -n 1 -r
echo    #new line
if [[ $REPLY =~ ^[Yy]$ ]]
then
   #clear out journalctl - probably a better way to do this
   journalctl --rotate > /dev/null 2>&1
   journalctl --vacuum-time=1seconds > /dev/null 2>&1
   echo "Plug your printer in via USB now (detection time-out in 1 min)"
   counter=0
   while [[ -z "$UDEV" ]] && [[ $counter -lt 30 ]]; do 
      UDEV=$(timeout 1s journalctl -kf | sed -n -e 's/^.*SerialNumber: //p')
      TEMPUSB=$(timeout 1s journalctl -kf | sed -n -e 's/^.*cdc_acm \(.*\): tty.*/\1/p')
      counter=$(( $counter + 1 ))
   done
   
   if [ -z "$UDEV" ]; then
       echo "Printer Serial Number not detected"
       read -p "Do you want to use the physical USB port to assign the udev entry? If you use this all USB hubs and printers must stay plugged into the same USB positions on your machine as they are right now (y/n)." -n 1 -r
       if [[ $REPLY =~ ^[Yy]$ ]]; then
          USB=$TEMPUSB
          echo "Your printer will be setup at the following usb address:"
          echo $USB
          echo           
       fi
       
   else
      echo "Serial number detected as: $UDEV"
   fi
fi

#Octobuntu cameras
if [ $INSTALL=2 ]; then
   read -p "Would you like to auto detect an associated USB camera?" -n 1 -r
   if [[ $REPLY =~ ^[Yy]$ ]]
   then
      #clear out journalctl - probably a better way to do this
      journalctl --rotate > /dev/null 2>&1
      journalctl --vacuum-time=1seconds > /dev/null 2>&1
      echo "Plug your CAMERA in via USB now (detection time-out in 1 min)"
      counter=0
      while [[ -z "$CAM" ]] && [[ $counter -lt 30 ]]; do 
         CAM=$(timeout 1s journalctl -kf | sed -n -e 's/^.*SerialNumber: //p')
         TEMPUSBCAM=$(timeout 1s journalctl -kf | sed -n -e 's/^.*cdc_acm \(.*\): tty.*/\1/p')
         counter=$(( $counter + 1 ))
      done
      if [ -z "$CAM" ]; then
       echo "Camera Serial Number not detected"
       echo "Your camera should remain at the same USB position and hub. Its position in in udev is $TEMPUSBCAM"
       USBCAM=$TEMPUSBCAM
      fi
   fi
fi

read -p "Ready to write all changes. Do you want to proceed? " -n 1 -r
echo    
if [[ $REPLY =~ ^[Yy]$ ]];
then
   cat octoprint_generic.service | \
   sed -e "s/OCTOUSER/$OCTOUSER/" \
       -e "s#OCTOPATH#$OCTOPATH#" \
       -e "s#OCTOCONFIG#$OCTOCONFIG#" \
       -e "s/NEWINSTANCE/$INSTANCE/" \
       -e "s/NEWPORT/$PORT/" > /etc/systemd/system/$INSTANCE.service
      
   #Printer udev identifier technique - either Serial number or USB port
   #Serial Number
   if [ -n "$UDEV" ]; then
      echo SUBSYSTEM==\"tty\", ATTRS{serial}==\"$UDEV\", SYMLINK+=\"octo_$INSTANCE\" >> /etc/udev/rules.d/99-octoprint.rules
   fi
   
   #USB port
   if [ -n "$USB" ]; then
      echo KERNELS==\"$USB\",SUBSYSTEMS==\"usb\",SYMLINK+=\"octo_$INSTANCE\" >> /etc/udev/rules.d/99-octoprint.rules
   fi
   
   #Octobuntu Cameras udev identifier - either Serial number or USB port
   #Serial Number
   if [ -n "$CAM" ]; then
      echo SUBSYSTEM==\"v4l\", ATTRS{serial}==\"$CAM\", SYMLINK+=\"$INSTANCE_cam\" >> /etc/udev/rules.d/99-octoprint.rules
   fi
   
   #USB port
   if [ -n "$USBCAM" ]; then
      echo KERNELS==\"$USBCAM\",SUBSYSTEMS==\"v4l\",SYMLINK+=\"$INSTANCE_cam\" >> /etc/udev/rules.d/99-octoprint.rules
   fi

   #just to be on the safe side, add user to dialout
   usermod -a -G dialout $OCTOUSER
   
   #Open port to be on safe side
   ufw allow $PORT/tcp
   
   #Append port in the port list
   echo $PORT >> /etc/octoprint_ports
   
   #copy all files to our new directory
   cp -rp $BFOLD $OCTOCONFIG/.$INSTANCE
   
   #Do config.yaml modifications here if needed..
   cat $BFOLD/config.yaml | sed -e "s/INSTANCE/$INSTANCE/" > $OCTOCONFIG/.$INSTANCE/config.yaml
   
   #Reset udev
   udevadm control --reload-rules
   udevadm trigger
   systemctl daemon-reload
   sleep 5
   
   #Start and enable system process
   systemctl start $INSTANCE
   systemctl enable $INSTANCE
fi

