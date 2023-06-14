Updated June 14, 2023.  
Want to support this work? Buy Me a Coffee. https://www.buymeacoffee.com/ppaukstelis.
Need help with octoprint_deploy? Ask on Discord: https://discord.gg/6vgSjgvR6u
# octoprint_deploy - ALL NEW
* These files provide a bash script for quickly deploying multiple octoprint instances on a single computer. For Linux systems (Ubuntu, Fedora, etc.) it will also install OctoPrint and a video streamer (mjpg-streamer or ustreamer). No need for lots of file editing or complicated Docker compose scripts! A background video on how it works from my ERRF2022 talk can be found here: https://www.youtube.com/watch?v=q0iCNl8-kJI&t=15378s
* octoprint_deploy and octoprint_install have now been merged! Maintaining two separate scripts was close to twice the amount of work. By merging the scripts many new features have been included, while also providing greater simplicity in setup. The biggest change is that there is no longer the notion of a single 'template' OctoPrint instance. Now, _any_ previously configured instance can be used as a template when a new instance is created. The choice is up to the user. 

# How to use
* OctoPi
  * OctoPi is intended as a single printer environment. This script makes multiple instances easy, but it cannot take into account everything OctoPi does (mostly surrounding cameras). You have been warned.
  * ssh into your Pi (pi@octopi.local; good idea to change your password now!).
  * run the command `git clone https://github.com/paukstelis/octoprint_deploy.git`.
  * run the command `sudo octoprint_deploy/octoprint_deploy.sh`.
  * Choose `Prepare System` from the menu.
    * You will be prompted for udev detection (only needed if you are adding more printers).
    * You will be prompted for installing a new streamer. This will be the default streamer for any _additional_ cameras that are installed.
  * Back in the ssh session, choose `New Instance` and follow the instructions.
      * Do not plug your printer in by USB until you are asked to do so.
      * If your printer does not have a serial number (all Creality printers), it will detect and use the physical USB address for udev entries.
  * Continue until you have added all the printers you want to use.
  * haproxy entries are updated so you can connect via http://octopi.local/instancename
  * To add more printers at a later date, just run the script again!
  * Want to use a Pi camera? After you have made your instance(s), run the script with `sudo octoprint_deploy/octoprint_deploy.sh picam` and follow the instructions (VERY EXPERIMENTAL).
* General Linux (Ubuntu/Mint/RPiOS/Debian/Fedora/Arch/etc.)
  * __You do not need to install OctoPrint using any Wiki instructions, snap, etc. The script will do it all for you.__
  * octoprint_deploy uses systemd services, so avoid distros that do not use systemd by default (MX Linux or chroot based systems like Chrome+crouton)
  * All commands assume you are operating out of your home directory.
  * Install Ubuntu 20+, Mint 20.3+, Debian, DietPi, RPiOS, Armbian, Fedora35+, or ArchLinux on your system (make sure your user is admin for sudo).
  * Install git if it isn't already: `sudo apt install git` or `sudo dnf install git` or `sudo pacman -S git` or `sudo zypper in git`.
  * run the command `git clone https://github.com/paukstelis/octoprint_deploy.git`.
  * run the command `sudo octoprint_deploy/octoprint_deploy.sh`.
  * Choose `Prepare System` from the menu. Select your distribution type. All deb-based system use the same selection. This will install necessary packages, install OctoPrint, and prompt you to create the first instance.
      * You will be asked if you want to use haproxy. This will make your instances available on port 80 e.g. http://hostname.local/instancename/
      * You will be asked which streamer you would like to install (ustreamer, mjpg-streamer or camera-streamer).
      * You will be prompted if you want to setup the admin user and do the first run wizard via the commandline.
      * You will be prompted if you want to install recommended plugins. 
  * Continue with octoprint_deploy script, choose `New Instance` and follow the instructions.
      * Do not plug the printer in by USB until you are asked to do so.
      * If your printer does not have a serial number (all Creality printers) it will be detected by the USB port you plugged it in to.
  * Add as many instances as you have printers, following the instructions.
  * To add more printers at a later date, or to add cameras to an instance, simply run the script again (`sudo octoprint_deploy/octoprint_deploy.sh`) and choose the appropriate options.
* Other features from the script
  * Remove instances
  * Add one more more USB cameras to an instance.
  * Test USB connections
  * Write udev rules without deploying instances.
  * Delete existing udev rules.
* Other features from commandline arguments
  * Want to get rid of everything? `sudo octoprint_deploy/octoprint_deploy.sh remove`
  * Backup and restore files for an instance from the menu, or backup all instances with `sudo octoprint_deploy/octoprint_deploy backup`
  * Restart all non-template instances from the command line: `sudo octoprint_deploy/octoprint_deploy.sh restart_all`
# Recent Changes






