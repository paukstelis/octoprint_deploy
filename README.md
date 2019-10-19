# octoprint_deploy
These files provide a simple bash script for quickly deploying multiple octoprint instances on a single computer (Ubuntu/debian based systems).

# How to use
Install Ubuntu on computer of interest.
Install Octoprint. You can follow the directions here: https://octoprint.org/download/
or here: https://community.octoprint.org/t/setting-up-octoprint-on-a-raspberry-pi-running-raspbian/2337

Start up Octoprint for the first time to setup a base instance profile. The base profile will be edited in several places to allow specific modifications during deployment.

[PLACE HOLDERS FOR EDITING STUFF]
Make sure whichever printer you are installing for is not plugged in via USB

Go to wherever you downloaded octoprint_deploy: cd octoprint_deploy
Run the bash script: $ sudo ./addnew_printer.sh
And follow the instructions:

>UNPLUG PRINTER FROM USB
>Enter the name for new printer/instance:
>printer01
>Port on which this instance will run (ENTER will increment last value in /etc/octoprint_ports):

>Selected port is: 5000
>Octoprint Daemon User [paul]:

>Octoprint Daemon Path [/home/paul/OctoPrint/venv/bin/octoprint]:

>Octoprint Config Path [/home/paul/]:

>Auto-detect printer serial number for udev entry?y
>Plug your printer in via USB now (detection time-out in 2 min)
>Serial number detected as: AL03M8MG
>Octoprint instance template base folder [/home/paul/.octoprint]:

>Do you want to proceed? y
