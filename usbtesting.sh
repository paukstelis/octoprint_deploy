#!/bin/bash
journalctl --rotate > /dev/null 2>&1
journalctl --vacuum-time=1seconds > /dev/null 2>&1
echo "Plug your printer in via USB now (detection time-out in 1 min)"
counter=0
while [[ -z "$UDEV" ]] && [[ $counter -lt 30 ]]; do
   UDEV=$(timeout 1s journalctl -kf | sed -n -e 's/^.*SerialNumber: //p')
   TEMPUSB=$(timeout 1s journalctl -kf | sed -n -e 's/^.*\(cdc_acm\|ftdi_sio\|ch341\) \([0-9].*[0-9]\): \(tty.*\|FTD.*\|ch341-uart.*\).*/\2/p')
   counter=$(( $counter + 1 ))
   if [ -n "$TEMPUSB" ]; then
      echo $TEMPUSB
   fi
done

