#!/bin/bash
#
# Set -x
##############################################################
#
#   Name: com.euromoneyplc.DEPprovisioning.sh
#   Description: Overall config to run DEPNotify stream
#   Notes: Based on YearOfTheGeek script: https://goo.gl/9up2ke
#   Author: Chris Jarvis
#   Date: 17/07/2018
#   Version History:
#     1.0: 17/07/2018 - Initial script
#     1.1: 30/07/2018 - Added a policyFin func & tidied up a few bits
#     1.2: 03/08/2018 - Refactoring functions & clean up
#     1.3: 08/08/2018 - Refactor & merged all policies down to 3 instead of about 6
#
#
##############################################################
#
# PATH & LOG Settings
#
# Get the current user
CURRENTUSER=$(python -c 'from SystemConfiguration import SCDynamicStoreCopyConsoleUser; import sys; username = (SCDynamicStoreCopyConsoleUser(None, None, None) or [None])[0]; username = [username,""][username in [u"loginwindow", None, u""]]; sys.stdout.write(username + "\n");')

# capture device type
deviceType="$(system_profiler SPHardwareDataType | grep "Model Identifier" | awk '{print $3}' | grep -i "Book")"

# Find the JAMF binary
JAMFBIN="$(which jamf | awk '{print $3}')"

if [[ $JAMFBIN != '/usr/local/bin/jamf' ]]; then
  #statements
  JAMFBIN=''/usr/local/bin/jamf''
fi

# Completion receipt folder
setupDone="/var/db/receipts/com.euromoneyplc.provisioning.done.bom"

# Policy Receipt path
receiptPath="/Users/Shared/DEPN/Receipts"

if [[ ! -d $receiptPath ]]; then
  # if it aint there; make it!
  mkdir -p $receiptPath
fi

# DNPLIST Path
DNPLIST="/Users/Shared/DEPN/DEPNotify.plist"

# Set the log file
DNLOG="/var/tmp/DEPNotify.log"
touch "$DNLOG"
#exec 3>&1 1>>${DNLOG} 2>&1

########################################
# DEPNotify Command functions
depCmd() {
  echo "Command: $*" >> /var/tmp/DEPNotify.log
}

depTitle() {
  echo "Command: MainTitle: $*" >> /var/tmp/DEPNotify.log
}

depText() {
  echo "Command: MainText: $*" >> /var/tmp/DEPNotify.log
}

depStat() {
  echo "Status: $*" >> /var/tmp/DEPNotify.log
}

depStep() {
  depCmd "WindowStyle: ActivateOnStep"
  depCmd "DeterminateStep: ${1}"
}

depReg() {
  /usr/bin/sudo -u "$CURRENTUSER" defaults write menu.nomad.DEPNotify "${1}" "${2}"
}
########################################
# Clean up Functions
#
# Create timestamp for logs & move them
resetDEP() {
  # Archive some
  timestamp="$(date | sed 's/\:/-/g' | sed 's/ /-/g' | sed 's/--/-/g')"
  /bin/mv $DNLOG /Library/Application\ Support/JAMF/DEP/DEPNotify-$timestamp.log
  /bin/mv $DNPLIST /Library/Application\ Support/JAMF/DEP/DEPNotifyPLIST-$timestamp.log
  /usr/bin/zip -r -X /Library/Application\ Support/JAMF/DEP/DEPReceipts_"$timestamp".zip $receiptPath

  # Delete the rest
  /bin/rm -Rf /Users/Shared/DEPN/DEPNotify.app
  /bin/rm -Rf /Users/Shared/DEPN/
  /bin/rm -Rf /Library/LaunchDaemons/com.euromoneyplc.launch.plist
  sudo -u "$CURRENTUSER" defaults delete menu.nomad.DEPNotify
}

# Unload the LaunchDaemon
unloadLD() {
  /bin/launchctl unload /Library/LaunchDaemons/com.euromoneyplc.launch.plist
  /bin/rm -Rf /Library/LaunchDaemons/com.euromoneyplc.launch.plist
}
########################################
#
# JAMF FUNCTIONS
jamfPol() {
  $JAMFBIN policy -verbose -event "$1"
}

# Policy Receipt Check
policyFin() {
  # grab the name
  package=$1

  # search for receipts
  results="$(find "$receiptPath" | grep -v grep | grep "$package")"

  # Strip the path
  results="$(basename "$results")"

  # Loop until result exists
  while :; do
    [[ "$results" == "$package" ]] && break
    sleep 1
  done
}

########################################
### DEPNotify Registration Page
#
depReg PathToPlistFile /Users/Shared/DEPN/
depReg RegisterMainTitle "Host Name"
depReg RegisterButtonLabel "Assign"
depReg UITextFieldUpperPlaceholder "Asset Number"
depReg UITextFieldUpperLabel "ComputerName"
depReg UIPopUpMenuLowerLabel "Site"
/usr/bin/sudo -u "$CURRENTUSER" defaults write menu.nomad.DEPNotify UIPopUpMenuLower -array "EU" "US" "AP" "CA"
#
# Main Intro UI
depTitle "Begin Deployment"
depText "This process will require you to add the hostname and select the region on the next page. \n \nIt will then bind to Active Directory, add the base packages and utilities. \n \nThe process will take about 30 minutes and reboot automatically at the end."
depCmd "Image: /Users/Shared/DEPN/em-logo.png"
depCmd "DeterminateManual: 5"
depCmd "WindowStyle: NotMovable"
#

##############################################################
######              Roll out DEPNotify!                 ######
##############################################################

# Check Finder & Dock are running and user is not '_mbsetupuser'
if pgrep -x "Finder" && pgrep -x "Dock" && [ "$CURRENTUSER" != "_mbsetupuser" ] && [ ! -f "${setupDone}" ]; then

  ##############################################
  #
  # Run some bits first
  #
  # Kill any installer processes running
  /usr/bin/killall Installer

  # Wait a few secs
  /bin/sleep 3

  # Caffeinate so we stay awake!
  /usr/bin/caffeinate -d -i -m -u &
  caffeinatepid=$!

  # Run DEPNotify fullscreen with JAMF
  /usr/bin/sudo -u "$CURRENTUSER" /Users/Shared/DEPN/DEPNotify.app/Contents/MacOS/DEPNotify -jamf -fullScreen &

  # Now we're running lets get the user input!
  depCmd "Image: /Users/Shared/DEPN/em-logo.png"
  depCmd "ContinueButtonRegister: Begin"
  depTitle "Begin Deployment"
  depText "Just waiting for you to begin...."
  depStep

  # Hold until we've got the reg screen plist
  while :; do
    [[ -f $DNPLIST ]] && break
    sleep 1
  done

  # Get the hostname from the plist
  hostName=$(/usr/libexec/plistbuddy $DNPLIST -c "print 'ComputerName'" | tr "[a-z]" "[A-Z]")
  hostSite=$(/usr/libexec/plistbuddy $DNPLIST -c "print 'Site'" | tr "[a-z]" "[A-Z]")

  # Check hostName is populated then set Host, Bonjour & Computer names
  if [ $hostName != "" ]; then
    /usr/sbin/scutil --set ComputerName "${hostName}"
    /usr/sbin/scutil --set HostName "${hostName}"
    /usr/sbin/scutil --set LocalHostName "${hostName}"
    /usr/local/bin/jamf setComputerName -name "${hostName}"
  fi

  # Change screen ready for deployment
  depCmd "MainTitle: Preparing for deployment"
  depCmd "MainText: Please do not shutdown, reboot or close the device. The process can take about 20 - 30 minutes.\n The machine will reboot automatically at the end"
  depStep "1"

  ########################################
  # Run Policies
  ########################################
  #
  # The structure of each policy run should be as follows:
  # 1. depTitle   <- Changes the title on the splash
  # 2. depText    <- Changes the text
  # 3. jamfPol    <- Runs the JAMF policy
  # 4. policyFin  <- Checks pkg receipt exists in JAMF folder
  # 5. depStep    <- Adds step to progress bar & reactivates window

  # Run Binding scripts and certificate installation
  depTitle "Running Deployment Policies..."
  depText "This will deploy various settings as well as install software and utilities..."
  jamfPol "install-DEPEnroll"
  depStep "2"


  ########################################

  # Install Cisco AnyConnect if its a laptop
  if [ $deviceType != "" ]; then

    depTitle "Cisco AnyConnect VPN"
    depStat "Installing Cisco AnyConnect VPN with settings package based on the region chosen..."

    # Site chosen by dropdown
    case $hostSite in

    EU*)
      package="install-anyconnect-uk";;
    US*)
      package="install-anyconnect-us";;
    AP*)
      package="install-anyconnect-ap";;
    CA*)
      package="install-anyconnect-us";;
    esac
    # Install anyconnect settings package based on site
    jamfPol "$package"

    # Install anyconnect app package
    jamfPol "install-anyconnect"
    policyFin "DEP-AnyConnect.txt"
    depStep "3"

  fi
  ########################################

  # Install Post Scripts
  depCmd "Image: /Users/Shared/DEPN/em-logo.png"
  depTitle "Post Install"
  depText "Now running some post install scripts and settings"
  jamfPol "install-DEPPost"
  policyFin "DEP-Post.txt"
  depStep "4"
  ########################################

    # Process complete
  depTitle "DEP Build Complete"
  depText "The process is now complete and clean up will begin. Once completed, the machine should automatically reboot."
  depStep "5"
  sleep 5
  ########################################
  #
  # CLEAN UP FILES AND LOGS
  ########################################
  # Kill the caffeinate process
  kill "$caffeinatepid"

  # Send final reboot command
  depStep
  depTitle "Quitting"
  depText "Quitting in 5 seconds"

  sleep 5
  depCmd "Quit: Quitting"

  # Create a bom file that allow this script to stop launching DEPNotify after done
  /bin/echo "$(date)" >> $setupDone

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
