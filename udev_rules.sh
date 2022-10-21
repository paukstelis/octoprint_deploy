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
logfile='printer_udev.log'  
echo "$(date) starting instance installation" >> $logfile


echo "UNPLUG PRINTER YOU ARE INSTALLING NOW (other printers can remain)"
echo "Enter the name for new printer/instance (no spaces):"
read INSTANCE
if [ -z "$INSTANCE" ]; then
    echo "No instance given. Exiting" | log
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


if prompt_confirm "Ready to write udev entry. Do you want to proceed?" 
then
   #Printer udev identifier technique - either Serial number or USB port
   #Serial Number
   if [ -n "$UDEV" ]; then
      #echo $UDEV
      echo SUBSYSTEM==\"tty\", ATTRS{serial}==\"$UDEV\", SYMLINK+=\"octo_$INSTANCE\" >> /etc/udev/rules.d/99-octoprint.rules
      echo This printer can now always be found at /dev/octo_$INSTANCE
   fi
   
   #USB port
   if [ -n "$USB" ]; then
      #echo $USB
      echo KERNELS==\"$USB\",SUBSYSTEM==\"tty\",SYMLINK+=\"octo_$INSTANCE\" >> /etc/udev/rules.d/99-octoprint.rules
      echo This printer can now always be found at /dev/octo_$INSTANCE
   fi

   #Reset udev
   udevadm control --reload-rules
   udevadm trigger
   systemctl daemon-reload
   sleep 1
 
fi

