#!/bin/bash
## postinstall

echo  "DEPNotify: disable auto updates ASAP" >> /var/log/jamf.log
	defaults write /Library/Preferences/com.apple.SoftwareUpdate.plist AutomaticDownload -bool NO
	defaults write /Library/Preferences/com.apple.SoftwareUpdate.plist ConfigDataInstall -bool NO
	defaults write /Library/Preferences/com.apple.SoftwareUpdate.plist CriticalUpdateInstall -bool NO
	defaults write /Library/Preferences/com.apple.commerce.plist AutoUpdateRestartRequired -bool NO
	defaults write /Library/Preferences/com.apple.commerce.plist AutoUpdate -bool NO
	defaults write /Library/Preferences/com.apple.SoftwareUpdate.plist AutomaticCheckEnabled -bool NO

# Disable diagnostic data
	SUBMIT_DIAGNOSTIC_DATA_TO_APPLE=FALSE
	SUBMIT_DIAGNOSTIC_DATA_TO_APP_DEVELOPERS=FALSE

## Make the main script executable
echo  "setting main script permissions" >> /var/log/jamf.log
	chmod a+x /Users/Shared/DEPN/com.euromoneyplc.DEPprovisioning.sh

## Set permissions and ownership for launch daemon
echo  "set LaunchDaemon permissions" >> /var/log/jamf.log
	chmod 644 /Library/LaunchDaemons/com.euromoneyplc.launch.plist
	chown root:wheel /Library/LaunchDaemons/com.euromoneyplc.launch.plist

## Load launch daemon into the Launchd system
echo  "load LaunchDaemon" >> /var/log/jamf.log
	launchctl load /Library/LaunchDaemons/com.euromoneyplc.launch.plist

exit $? # Dynamnic success
