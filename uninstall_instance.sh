#!/bin/bash
if (( $EUID != 0 )); then
    echo "Please run as root (sudo)"
    exit
fi

if [ $SUDO_USER ]; then user=$SUDO_USER; fi
echo 'Do not remove the generic instance!'
PS3='Select instance to remove: '
readarray -t options < <(cat /etc/octoprint_instances | sed -n -e 's/^instance:\([[:alnum:]]*\) .*/\1/p')
select opt in "${options[@]}"
do
    echo "Selected instance: $opt"
    break
done

read -p "Do you want to remove everything associated with this instance?" -n 1 -r
echo    #new line
if [[ $REPLY =~ ^[Yy]$ ]]; then
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
fi
