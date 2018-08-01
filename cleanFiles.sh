#!/bin/bash

# Clean up
# rename DEPNotify.log
timestamp="$(date | sed 's/\:/-/g' | sed 's/ /-/g')"
mv /var/tmp/DEPNotify.log /var/tmp/DEPNotify_$timestamp.log
# delete the bits
rm -Rf /var/db/receipts/com.euromoneyplc.provisioning.done.bom
rm -Rf /Users/Shared/DEPN/DEPNotify.plist
defaults delete menu.nomad.DEPNotify
rm -Rf /Library/Application\ Support/JAMF/Receipts/*
