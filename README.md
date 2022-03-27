Updated February 2022.  
Want to support this work? Buy Me a Coffee. https://www.buymeacoffee.com/ppaukstelis
# octoprint_deploy
These files provide a simple bash script for quickly deploying multiple octoprint instances on a single computer.
# BIG CHANGES
As of 02/22 there is no longer a need to download a specific image file.
YouTube video for OctoPi setup here: https://www.youtube.com/watch?v=J5VzI4AFav4&lc
# How to use
* OctoPi
  * Put the latest OctoPi image on your SD card
  * ssh into your Pi (pi@octopi.local; good idea to change your password now!)
  * run the command `git clone https://github.com/paukstelis/octoprint_deploy.git`
  * run the command `sudo octoprint_deploy/octoprint_deploy.sh`
  * Choose `Prepare System` from the menu
  * Setup admin user by connecting to http://octopi.local via browser
  * Back in the ssh session, choose `Add Instance` and follow the instructions.
  * If your printer does not have a serial number, it will time out and use the physical USB address for udev entries.
  * Continue until you have added all the printers you want to use
  * haproxy entries are updated so you can connect via http://octopi.local/instancename/
* Ubuntu (may work for other deb systems, not tested yet)
  * Install Ubuntu 20-21.X on your system (make sure your user is admin for sudo)
  * Install git if it isn't already: `sudo apt install git`
  * run the command `git clone https://github.com/paukstelis/octoprint_deploy.git`
  * run the command `sudo octoprint_deploy/octoprint_deploy.sh`
  * Choose `Prepare System` from the menu. This will install necessary packages, install octoprint, and start an instance
  * This converts your installation into an 'OctoBuntu' installation.
  * Setup admin user by connecting to your system (either http://localhost:5000 or http://[hostname]:5000 via browser
  * Continue with octoprint_deploy script and setup all your instances.
  * You may have to logout/reboot before connecting to printers or cameras as dialout and video permissions are established during setup.
* What else can you do?
  * Remove instances
  * Add USB webcams AFTER you've created the instance
  * Test USB connections
