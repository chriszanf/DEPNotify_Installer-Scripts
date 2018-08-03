# DEPNotify Installer Script

These are my scripts for running with Joel Rennich's [DEPNotify](https://gitlab.com/Mactroll/DEPNotify) application.


## com.euromoneyplc.DEPprovisioning.sh

The main script is broken down into a few sections:

1. Paths & Logging
2. DEPNotify Command functions
3. DEPNotify Registration & Inital main page settings
4. Operations:

  1. Check Finder/Dock are running & the user is not \_mbsetupuser
  2. Kill any installers
  3. Caffeinate the machine
  4. Run DEPNotify.app
  5. Issue the ContinueButtonRegister command
  6. Run a `while` loop until the .plist is written
  7. Rename the machine based on the input
  8. Start running policies

    The policies are structured as follows:
      * depTitle   Changes the title on the splash
      * depText    Changes the text
      * jamfPol    Runs the JAMF policy
      * policyFin  Checks policy receipt exists in JAMF folder
      * depStep    Adds step to progress bar & reactivates window to bring it to the front

5. Clean-Up: de-caffeinate the machine, send the quit messages then archive some logs and delete the rest 
