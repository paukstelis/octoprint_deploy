

Updated April 1, 2024.  

Want to support this work? Buy Me a Coffee. https://www.buymeacoffee.com/ppaukstelis.
Need help with octoprint_deploy? Visit support-octoprint-deploy on the OctoPrint Discord: https://discord.com/invite/yA7stPp

# octoprint_deploy 1.0.11

* These files provide a bash script for quickly deploying multiple octoprint instances on a single computer. For Linux systems (Ubuntu, Fedora, etc.) it will also install OctoPrint and a video streamer (ustreamer). No need for lots of file editing or complicated Docker compose scripts! A background video on how it generally works from my ERRF2022 talk can be found here: https://www.youtube.com/watch?v=q0iCNl8-kJI&t=15378s
* This particular version is specific for the LatheEngraver

# How to Use

* Make sure git is installed with your package manager, e.g. `sudo apt install git`
* Clone the latheengraver branch: `git clone -b latheengraver https://github.com/paukstelis/octoprint_deploy`
* Begin installation: `sudo octoprint_deploy/octoprint_deploy.sh`
* When the installer asks if you want to install plugins, select Y and then use the Install All option
