

Updated January 19, 2024.  

Want to support this work? Buy Me a Coffee. https://www.buymeacoffee.com/ppaukstelis.
Need help with octoprint_deploy? Visit support-octoprint-deploy on the OctoPrint Discord: https://discord.com/invite/yA7stPp

# octoprint_deploy 1.0.7

* These files provide a bash script for quickly deploying multiple octoprint instances on a single computer. For Linux systems (Ubuntu, Fedora, etc.) it will also install OctoPrint and a video streamer (ustreamer). No need for lots of file editing or complicated Docker compose scripts! A background video on how it generally works from my ERRF2022 talk can be found here: https://www.youtube.com/watch?v=q0iCNl8-kJI&t=15378s
* octoprint_deploy and octoprint_install are being merged! Maintaining two separate scripts was close to twice the amount of work. By merging the scripts many new features have been included, while also providing greater simplicity in setup. 
* The biggest change is that there is no longer the notion of a single 'template' OctoPrint instance. Now, _any_ previously configured instance can be used as a template when a new instance is created. The choice is up to the user. 
* Unfortunately, octoprint_deploy > 1.0.0 is not directly compatible with older versions, as so much has changed. If you want to use the new version of octoprint_deploy with an older setup, create backups (either with OctoPrint UI or with octoprint_deploy), then use the `remove` commandline argument before updating octoprint_deploy. Re-make your instances using the same instance names, then recover your backups.
# How to use
* OctoPi
  * OctoPi is intended as a single printer environment. This script makes adding multiple instances easy, but it cannot take into account everything OctoPi does (mostly surrounding cameras). You have been warned.
  * ssh into your Pi (pi@octopi.local; good idea to change your password now!).
  * run the command `git clone https://github.com/paukstelis/octoprint_deploy`.
  * run the command `sudo octoprint_deploy/octoprint_deploy.sh`.
  * Choose `Prepare System` from the menu.
    * This will register the OctoPi-created instance in octoprint_deploy.
    * You will be prompted for udev detection (only needed if you are adding multiple printers).
    * You will be prompted for installing a new streamer. This will be the default streamer for any _additional_ cameras that are installed. Users of the new OctoPi camera stack can just choose `Skip/None` and setup all cameras manually.
  * To add more printers choose `Add Instance` and follow the instructions.
      * You will be asked if you want to use an existing instance as a template. This will copy configuration files from this existing instance to your new instance.
      * If your printer does not have a serial number (all Creality printers), it will detect and use the physical USB address for udev entries.
  * Continue until you have added all the printers you want to use.
  * haproxy entries are updated so you can connect via http://octopi.local/instancename
  * To add more printers at a later date, just run the script again!
* General Linux (Ubuntu/Mint/RPiOS/Debian/Fedora/Arch/etc.)
  * __You do not need to install OctoPrint using any Wiki instructions, snap, etc. The script will do it all for you.__
  * octoprint_deploy uses systemd services, so avoid distros that do not use systemd by default (MX Linux or chroot based systems like Chrome+crouton). Similarly, LXC containers do not work well with udev rules and USB peripherals, so those should be avoided.
  * All commands assume you are operating out of your home directory.
  * Install Ubuntu 20+, Mint 20.3+, Debian, DietPi, RPiOS, Armbian, Fedora35+, ArchLinux, or openSUSE on your system (make sure your user is admin for sudo).
  * Install git if it isn't already: `sudo apt install git` or `sudo dnf install git` or `sudo pacman -S git` or `sudo zypper in git`.
  * run the command `git clone https://github.com/paukstelis/octoprint_deploy`.
  * run the command `sudo octoprint_deploy/octoprint_deploy.sh`.
  * Choose `Prepare System` from the menu. Select your distribution type. All deb-based system use the same selection. This will install necessary packages, install OctoPrint, and prompt you to create the first instance.
      * You will be asked if you want to use haproxy. This will make your instances available on port 80 e.g. http://hostname.local/instancename/
      * You will be asked which streamer you would like to install (ustreamer, mjpg-streamer or camera-streamer). Please note, not all distributions will be compatible with camera-streamer. __camera-streamer support will be added at a later date__
      * You will be asked to plug in a printer via USB for udev rule creation. __If you cannot plug in the printer and are only creating a single instance you can simply allow the detection to time-out__. The first instance will still be created. You can generate a udev rule later through the utility menu. Additional instances will require the printers to be plugged in (as will USB cameras).
      * You will be prompted if you want to setup the admin user and do the first run wizard via the commandline.
      * You will be prompted if you want to install recommended plugins. 
  * Continue with octoprint_deploy script, choose `Add Instance` and follow the instructions.
      * You will be prompted if you want to use a previously created instance as a template for your new instance.
      * If your printer does not have a serial number (all Creality printers) it will be detected by the USB port you plugged it in to.
      * You can also setup a camera for the instance at this time. Follow the instructions.
  * Add as many instances as you have printers, following the instructions.
  * To add more printers at a later date, or to add cameras to an instance later, simply run the script again (`sudo octoprint_deploy/octoprint_deploy.sh`) and choose the appropriate option.
* Utility menu - use the utility menu in the script to:
  * Add or remove instances or cameras
  * Check the status of all instances
  * Do printer USB port testing
  * Sync OctoPrint users from one instance to all other instances
  * Share the uploads directory between all instances (all instances have access to the same gcode files)
  * Modify which camera streaming software is used (WIP)
  * Modify a setting for all instances using the OctoPrint CLI interface (WIP)
  * Add/Remove udev rules for printers and cameras
  * Generate diagnostic output about octoprint_deploy. __Use this and provide output when you are looking for support__
* Other features from commandline arguments
  * Want to get rid of everything? `sudo octoprint_deploy/octoprint_deploy.sh remove`
  * Backup and restore files for an instance from the menu, or backup all instances with `sudo octoprint_deploy/octoprint_deploy backup`
  * Restart all instances from the command line: `sudo octoprint_deploy/octoprint_deploy.sh restart_all`
  * You can inject any function at start using the command line with the first argument `f` and the second argument the function name. 
# Recent Changes

  * Improve Instance Status function.
  * Remove octoprint_deploy backup technique and move entirely to native OctoPrint backups. Backups made in this way are moved to /home/$USER/instance_backup to make them easier to sort.
  * Camera settings written to separate env file. This can be found and edited at `/etc/cam_instancename.env`. 
  * Fixes for shared uploads function.
  * Command-line function injection. Will be useful in some cases.
  * Allow first instance creation without udev rule
  * Fixed dialout permissions.
  * Lots of changes, now octoprint_deploy 1.0.0
  * Udev utility menu
  * Diagnostic information from menu provides a variety of useful information about the system.
  * Cameras have additional fallback detection (/dev/v4l/by-id entries)
# TODO
  * Integration with OctoPi new camera stack. This may or may not happen.
  * Detection of existing instances/binaries that can be used instead of a full install (preserves plugins)
