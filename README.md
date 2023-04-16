Updated April 15, 2023.  
Want to support this work? Buy Me a Coffee. https://www.buymeacoffee.com/ppaukstelis.
Need help with octoprint_deploy? Ask on Discord: https://discord.gg/6vgSjgvR6u
# octoprint_deploy
These files provide a bash script for quickly deploying multiple octoprint instances on a single computer. For Linux systems (Ubuntu, Fedora, etc.) it will also install OctoPrint and a video streamer (mjpg-streamer or ustreamer). No need for lots of file editing or complicated Docker compose scripts! A background video on how it works from my ERRF2022 talk can be found here: https://www.youtube.com/watch?v=q0iCNl8-kJI&t=15378s

# How to use
* OctoPi
  * Slightly dated YouTube video for OctoPi setup here: https://www.youtube.com/watch?v=J5VzI4AFav4&lc
  * Put the latest OctoPi image on your SD card.
  * ssh into your Pi (pi@octopi.local; good idea to change your password now!).
  * run the command `git clone https://github.com/paukstelis/octoprint_deploy.git`.
  * run the command `sudo octoprint_deploy/octoprint_deploy.sh`.
  * Choose `Prepare System` from the menu.
      * If you have already been using this system for some time, you will be prompted that files will be moved in order to generate a template instance.
      * You will be prompted if you want to switch from mjpeg-streamer to ustreamer.
      * You will be prompted if you want to setup the admin user and do the first run wizard using the commandline. If you do this now you can start making new instances when the system preparation is complete.
      * You will be prompted if you want to install recommended plugins and cloud plugins. This can be useful if you want to configure plugins in your template instance, before adding new instances.
      * If you did not setup admin user in the script, setup admin user by connecting to http://octopi.local via browser.
  * Back in the ssh session, choose `New Instance` and follow the instructions.
      * Do not plug your printer in by USB until you are asked to do so.
      * If your printer does not have a serial number (all Creality printers), it will detect and use the physical USB address for udev entries.
  * Continue until you have added all the printers you want to use.
  * haproxy entries are updated so you can connect via http://octopi.local/instancename
  * Please note, haproxy entries are NOT used for webcams once you use this system. Connect to them via hostname:port.
  * To add more printers at a later date, just run the script again!
  * Want to use a Pi camera? After you have made your instance(s), run the script with `sudo octoprint_deploy/octoprint_deploy.sh picam` and follow the instructions (VERY EXPERIMENTAL).
* General Linux (Ubuntu/Mint/RPiOS/Debian/Fedora/Arch/etc.)
  * __You do not need to install OctoPrint using any Wiki instructions, snap, etc. The script will do it for you.__
  * octoprint_deploy uses systemd services, so avoid distros that do not use systemd by default (MX Linux or chroot based systems like Chrome+crouton)
  * SELinux (Fedora) casues issues, particularly with camera services. Use at your own risk (or disable SELinux).
  * Basic guide video here: https://youtu.be/1YINWQ5fNn0
  * All commands assume you are operating out of your home directory.
  * Install Ubuntu 20+, Mint 20.3+, Debian, DietPi, RPiOS, Armbian, Fedora35+, or ArchLinux on your system (make sure your user is admin for sudo).
  * Install git if it isn't already: `sudo apt install git` or `sudo dnf install git` or `sudo pacman -S git`.
  * run the command `git clone https://github.com/paukstelis/octoprint_deploy.git`.
  * run the command `sudo octoprint_deploy/octoprint_deploy.sh`.
  * Choose `Prepare System` from the menu. Select your distribution type. All deb-based system use the same selection. This will install necessary packages, install OctoPrint, and start a template instance.
      * You will be asked if you want to use haproxy. This will make your instances available on port 80 e.g. http://hostname.local/instancename/
      * You will be asked which streamer you would like to install (mjpg-streamer or ustreamer).
      * You will be prompted if you want to setup the admin user and do the first run wizard via the commandline. If you do this now you can start making new instances as soon as the system preparation is complete.
      * You will be prompted if you want to install recommended plugins and cloud plugins. This can be useful if you want to configure plugins in your template instance, before adding new instances.
      * If you didn't setup admin user in the step above, setup admin user by connecting to your system (either http://localhost:5000 or http://[hostname]:5000 via a browser
      * __This instance is just a generic template used for making all your other instances. You need to make at least one instance using the script when this is done.__
  * Continue with octoprint_deploy script, choose `New Instance` and follow the instructions.
      * Do not plug the printer in by USB until you are asked to do so.
      * If your printer does not have a serial number (all Creality printers) it will be detected by the USB port you plugged it in to.
      * After adding the first instance, the template instance will be shutdown. This is normal.
  * Add as many instances as you have printers, following the instructions.
  * To add more printers at a later date, or to add cameras to an instance, simply run the script again (`sudo octoprint_deploy/octoprint_deploy.sh`) and choose the appropriate options.
  * Remember, camera installed with this script are experimental and always will be. The script makes some basic assumptions that you may need to change later. Cameras suck up quite a bit of USB bandwidth so while it is quite straightforward to run 10 printers with a modest computer, you can't also run 10 cameras.
* What else can you do?
  * Remove instances
  * Add USB webcams AFTER you've created the instance
  * Test USB connections
  * Write udev rules without deploying instances (udev_rules.sh)
  * Want to get rid of everything? `sudo octoprint_deploy/octoprint_deploy.sh remove`
  * Backup and restore files for an instance from the menu, or backup all instances with `sudo octoprint_deploy/octoprint_deploy backup`
  * Restart all non-template instances from the command line: `sudo octoprint_deploy/octoprint_deploy.sh restart_all`
  * Change udev rules for an instance with `sudo octoprint_deploy/octoprint_deploy.sh replace`
  * Always a good idea to update octoprint_deploy from time-to-time with `git -C octoprint_deploy pull`
# Recent Changes
* Remove path double slashes that seemed to prevented deletion of timelapse videos.
* Check for spaces in instance name, admin user, and password
* Force camera port to be greater than 7000
* Allow removal of individual camera services. Improvements to instance and camera removal.
* Haproxy fixed! No more trailing slash required! Running new octoprint_deploy on an older installation automatically update these entries.
* Multi-camera support (experimental). Clean-up of haproxy.cfg on instance removal still needs work.
* If haproxy is used, cameras stream can be placed behind it. PLEASE NOTE: if cameras are used with haproxy a relative stream path is used. This means that your stream will not show up in the Control tab unless you access with the haproxy path (http://host/instancename/) (remember, trailing slash is required!)





