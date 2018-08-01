#!/bin/bash
#
# Set -x
##############################################################
#
#	Name: com.euromoneyplc.DEPprovisioning.sh
#	Description: Overall config to run DEPNotify stream
# Notes: Based on YearOfTheGeek script: https://goo.gl/9up2ke
#	Author: Chris Jarvis
#	Date: 17/07/2018
#	Version History:
#   1.0: 17/07/2018 - Initial script
#   1.1: 30/07/2018 - Added a policyFin func & tidied up a few bits
#
#
##############################################################
#
# PATH & LOG Settings
########################################
# Get the current user
if [ ! -z "$3" ]; then
  CURRENTUSER=$3
else
  CURRENTUSER=$(python -c 'from SystemConfiguration import SCDynamicStoreCopyConsoleUser; import sys; username = (SCDynamicStoreCopyConsoleUser(None, None, None) or [None])[0]; username = [username,""][username in [u"loginwindow", None, u""]]; sys.stdout.write(username + "\n");')
fi

# capture device type
deviceType="$(system_profiler SPHardwareDataType | grep "Model Identifier" | awk '{print $3}' | grep -i "Book")"

# Find the JAMF binary
JAMFBIN="$(which jamf | awk '{print $3}')"

# check jamfbin is '/usr/local/bin/jamf'
if [[ $JAMFBIN != '/usr/local/bin/jamf' ]]; then
  # change to the expected path
  JAMFBIN='/usr/local/bin/jamf'
fi

# Setup Done File
setupDone="/var/db/receipts/com.euromoneyplc.provisioning.done.bom"

# DNPLIST Path
DNPLIST="/Users/Shared/DEPN/DEPNotify.plist"

# Set the log file
DNLOG="/var/tmp/DEPNotify.log"
touch "$DNLOG"
exec 3>&1 1>>${DNLOG} 2>&1

# DEPNotify Command functions
#
# Command function
depCmd() {
  echo "Command: $*" | tee /dev/fd/3
}
# Title on page
depTitle() {
  echo "Command: MainTitle: $*" | tee /dev/fd/3
}
# Text on page
depText() {
  echo "Command: MainText: $*" | tee /dev/fd/3
}
# Status function
depStat() {
  echo "Status: $*" | tee /dev/fd/3
}

depWin() {
  echo "Command: WindowStyle: Activate" | tee /dev/fd/3
}

# Run JAMF Policy
jamfPol() {
  $JAMFBIN policy -event "${1}" -verbose
  echo "$(date)" "${1} policy is currently running"
}

# Settings for the registration page
depReg() {
  /usr/bin/sudo -u "$CURRENTUSER" defaults write menu.nomad.DEPNotify "${1}" "${2}"
}

# Clean up files
resetDEP() {

  /bin/rm -Rf /Users/Shared/DEPN/DEPNotify.app
  /bin/rm -Rf $DNLOG
  /bin/rm -Rf $DNPLIST
  /bin/rm -Rf /Users/Shared/DEPN/
  /bin/launchctl unload /Library/LaunchDaemons/com.euromoneyplc.launch.plist
  /bin/rm -Rf /Library/LaunchDaemons/com.euromoneyplc.launch.plist
  sudo -u "$CURRENTUSER" defaults delete menu.nomad.DEPNotify
}

# Unload the LD
unloadLD() {
  /bin/launchctl unload /Library/LaunchDaemons/com.euromoneyplc.launch.plist
  /bin/rm -Rf /Library/LaunchDaemons/com.euromoneyplc.launch.plist
}

# Check to see if package receipt exists. Time range is 2 mins
# if it does, it returns the full package name. If not, it waits until
policyFin() {
  # Package name passed with FUNC
  package=$1
  # Path to JAMF pkg receipts
  receiptPath="/Library/Application Support/JAMF/Receipts"
  # Time range for find: currently 2 mins
  range="$(date -v -20M)"
  # Find pkg receipts that match $1 less than 2 mins old
  results="$(find "${receiptPath}" -newermt "$range" | grep -v grep | grep -i $package)"
  # Strip the path
  results="$(basename "$results")"

  # Loop until result exists; echo pkg name when it does
  while :; do
    [[ $results != "" ]] && echo $results && break
    sleep 1
  done

  depStatus "${1} Policy Completed....."
}
#
########################################
# Config the registration page
depReg PathToPlistFile /Users/Shared/DEPN/
depReg RegisterMainTitle "Host Name"
depReg RegisterButtonLabel "Assign"
depReg UITextFieldUpperPlaceholder "Asset Number"
depReg UITextFieldUpperLabel "ComputerName"
depReg UIPopUpMenuLowerLabel "Site"
/usr/bin/sudo -u "$CURRENTUSER" defaults write menu.nomad.DEPNotify UIPopUpMenuLower -array "EU" "US" "AP"
#
# Config the main page
depTitle "Begin Deployment"
depText "This process will require you to add the hostname and select the region on the next page. It will then bind to Active Directory and add the base packages and additonal ones according to geolocation selected. The process will take about 30 minutes and reboot automatically at the end."
depCmd "Image: /Users/Shared/DEPN/em-logo.png"
depCmd "DeterminateManual: 10"
depCmd "WindowStyle: NotMovable"
depCmd "DeterminateSManualStep: 0"
########################################

# Check Finder & Dock are running and user is not '_mbsetupuser'
if pgrep -x "Finder" &&
  pgrep -x "Dock" &&
  [ "$CURRENTUSER" != "_mbsetupuser" ] &&
  [ ! -f "${setupDone}" ]; then

  # Kill any installer processes running
  /usr/bin/killall Installer
  # Wait a few secs
  /bin/sleep 3

  # Caffeinate so we stay awake!
  /usr/bin/caffeinate -d -i -m -u &
  caffeinatepid=$!

  ########################################
  # Roll the DEPNotify!
  ########################################
  #
  # Run DEPNotify as $CURRENTUSER
  /usr/bin/sudo -u "$CURRENTUSER" /Users/Shared/DEPN/DEPNotify.app/Contents/MacOS/DEPNotify -jamf -fullScreen &

  ########################################
  # Get user input
  depCmd "Image: /Users/Shared/DEPN/em-logo.png"
  depCmd "ContinueButtonRegister: Begin"
  depTitle "Begin Deployment"
  depText "Just waiting for you to begin...."
  depCmd "DeterminateSManualStep: 1"

  # hold here until the user enters something
  while :; do
    [[ -f $DNPLIST ]] && break
    sleep 1
  done

  # Get the hostname from the plist
  hostName=$(/usr/libexec/plistbuddy $DNPLIST -c "print 'ComputerName'" | tr "[a-z]" "[A-Z]")
  hostSite=$(/usr/libexec/plistbuddy $DNPLIST -c "print 'Site'" | tr "[a-z]" "[A-Z]")

  # Check hostName is not empty, use to name machine & bind to AD
  if [ $hostName != "" ]; then
    /usr/sbin/scutil --set ComputerName "${hostName}"
    /usr/sbin/scutil --set HostName "${hostName}"
    /usr/sbin/scutil --set LocalHostName "${hostName}"
    /usr/local/bin/jamf setComputerName -name "${hostName}"
  fi

  # Change screen ready for deployment
  depCmd "MainTitle: Preparing for deployment"
  depCmd "MainText: Please do not shutdown, reboot or close the device. It will automatically reboot when complete."
  depCmd "DeterminateManualStep: 2"

  ########################################
  # Run Policies
  ########################################
  #
  # The structure of each policy run should be as follows:
  # 1. depTitle   <- Changes the title on the splash
  # 2. depText    <- Changes the text
  # 3. jamfPol    <- Runs the JAMF policy
  # 4. policyFin  <- Checks pkg receipt exists in JAMF folder
  #
  #
  # Run Binding scripts and certificate installation
  depCmd "Image: /Users/Shared/DEPN/em-logo.png"
  depTitle "Running enrollment scripts..."
  depText "This will run some basic settings and also bind the machine to Active Directory"
  jamfPol "10Enrollment"
  policyFin "EnrollmentScripts.pkg"

  depTitle "Installing Certificates"
  depText "Installing the various Euromoney certificates to system keychain"
  jamfPol "install-certEM"
  jamfPol "install-certEU"
  jamfPol "install-certAM"
  policyFin "EU01PICA01-SHA256.cer"

  #####   Advance the progress bar   #####
  ########################################
  depCmd "DeterminateManualStep: 3"
  ########################################

  # Install acceptable usage file
  depTitle "Installing user policy..."
  depText "This installs the acceptable usage policy that displays when the user logs in."
  jamfPol "install-userpolicy"
  #policyFin "Acceptable"

  #####   RESTART DEPWIN
  ########################################
  depWin

  # Install connect drive app
  depTitle "Connect Network Drives..."
  depText "This is the tool to connnect network drives on login according to the users security group membership on Active Directory."
  jamfPol "install-connect"
  policyFin "ConnectNetwork"

  # Install corporate wifi profile
  depTitle "Corporate Wifi profile..."
  depText "Installing the Wifi profile"
  jamfPol "install-corporateWifi"
  #policyFin "CorporateWifi"

  #####   RESTART DEPWIN
  ########################################
  depWin


  # Install SSH Config
  depTitle "SSH configuration"
  depText "Installing the SSH configuration"
  jamfPol "install-ssh"
  policyFin "SSH"

  #####   Advance the progress bar   #####
  ########################################
  depCmd "DeterminateManualStep: 4"
  ########################################

  # DockUtil
  depTitle "Installing Utilities"
  depText "Installing DockUtil..."
  jamfPol "install-dockutil"
  policyFin "dockutil-2.0.5"

  # SETREGTOOLPRO
  depText "Installing Firmware password tool..."
  jamfPol "install-fwtool"
  policyFin "setregproptool"

  # NoMAD
  depText "Installing NoMAD..."
  jamfPol "install-nomad"
  policyFin "NoMAD-1.1.4"

  #####   RESTART DEPWIN
  ########################################
  depWin


  # Install IT Service Desk bits
  depText "IT Service Desk"
  depText "Installing the various IT Service Desk tools, links, and icons"
  jamfPol "install-ITSD"
  jamfPol "install-sdicons"
  policyFin "itservicedesk"

  # Install Geektool
  depTitle "GeekTool"
  depText "Installing Geektool that display machine info on the desktop"
  jamfPol "install-geektool"
  policyFin "geektool"

  #####   Advance the progress bar   #####
  ########################################
  depCmd "DeterminateManualStep: 5"
  ########################################

  # Installing browsers
  depTitle "Browsers"
  depText "Installing additional browsers Google Chrome and Firefox..."

  # Install Firefox
  jamfPol "install-firefox"
  policyFin "firefox"

  # Install Chrome
  jamfPol "install-chrome"
  policyFin "chrome"

  #####   Advance the progress bar   #####
  ########################################
  depCmd "DeterminateManualStep: 6"
  ########################################

  #####   RESTART DEPWIN
  ########################################
  depWin

  # Install Cisco AnyConnect if its a laptop
  depStat "Installing Cisco AnyConnect with settings package based on site chosen..."
  if [ $deviceType != "" ]; then

    # Site chosen by dropdown
    case $hostSite in

    EU*)
      package="install-anyconnect-uk"
      ;;
    US*)
      package="install-anyconnect-us"
      ;;
    AP*)
      package="install-anyconnect-ap"
      ;;
    esac
    # Install anyconnect settings package based on site
    jamfPol "$package"

    # Install anyconnect app package
    jamfPol "install-anyconnect"
    policyFin "AnyConnect-4.5.00058"

  fi
  #####   Advance the progress bar   #####
  ########################################
  depCmd "DeterminateManualStep: 7"
  ########################################

  #####   RESTART DEPWIN
  ########################################
  depWin

  # Install Office
  depTitle "Microsoft Office 2016..."
  depText "Installing the base packages for Microsoft Office 2016. This may take some time due to their size"
  jamfPol "install-officebase"
  policyFin "Microsoft_Office_2016_VL_Serializer-2.0"

  #####   Advance the progress bar   #####
  ########################################
  depCmd "DeterminateManualStep: 8"
  ########################################

  # Install Skype for Business
  depTitle "Skype"
  deptext "Installing Skype For Business"
  jamfPol "install-skypebusiness"
  policyFin "Skype"

  # OneDrive
  depTitle "Microsoft OneDrive"
  depText "Installing OneDrive cloud storage application..."
  jamfPol "install-onedrive"
  policyFin "onedrive"

  # Email Archive
  depTitle "Email Archive"
  depText "Install email archive tool..."
  jamfPol "install-emailarchive"
  policyFin "EmailArchive"

  #####   Advance the progress bar   #####
  ########################################
  depCmd "DeterminateManualStep: 9"
  ########################################

  #####   RESTART DEPWIN
  ########################################
  depWin

  # Process complete
  depTitle "DEP Build Complete"
  depText "The process is now complete and clean up will begin.\nOnce completed, the machine will automatically reboot."

  #####   Advance the progress bar   #####
  ########################################
  depCmd "DeterminateManualStep: 10"
  ########################################
  #
  # CLEAN UP FILES AND LOGS
  ########################################
  # Kill the caffeinate process
  kill "$caffeinatepid"

  # Send final reboot command
  depTitle "Quitting"
  depText "Quitting in 5 seconds"
  sleep 5
  depCmd "Quit: Quitting"
  #
  ########################################
  # Finishing up and housekeeping
  ########################################
  # Wait a few seconds
  /bin/sleep 5

  # Create a bom file that allow this script to stop launching DEPNotify after done
  /usr/bin/touch $setupDone

  # Remove DEPN folder and the logs
  ########################################
  cleanDEP
  # Remove the Launch Daemon
  unloadLD
  ########################################

  # Reboot the machine
  ########################################
  sleep 10
  # Remove the Launch Daemon
  /sbin/shutdown -r now
  ########################################
fi

# Get out!
exit $?
