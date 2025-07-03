#!/bin/bash
#
# Author  : Perry Driscoll - https://github.com/PezzaD84
# Created : 1.7.2025
# Updated : 3.7.2025
# Version : v1
#
#########################################################################################
# Description: 
#	Script to pull secure information from jamf and disaply it tlo the end user
#
#########################################################################################
# Copyright © 2024 Perry Driscoll <https://github.com/PezzaD84>
#
# This file is free software and is shared "as is" without any warranty of 
# any kind. The author gives unlimited permission to copy and/or distribute 
# it, with or without modifications, as long as this notice is preserved. 
# All usage is at your own risk and in no event shall the authors or 
# copyright holders be liable for any claim, damages or other liability.
#########################################################################################

############################################################################
# Debug Mode - Change to 1 if you wish to run the script in Debug mode
############################################################################

DEBUG="0"

############################################################################
# Variables - Token creation
############################################################################

JAMFETCHLOG="/Library/.JFETCH/Logs/JAMFETCH.log"
URL=$4
password=$5
token=$(curl -s -H "Content-Type: application/json" -H "Authorization: Basic ${password}" -X POST "$URL/api/v1/auth/token" | plutil -extract token raw -)

if [[ $DEBUG == "1" ]]; then
	mkdir -p /Library/.JFETCH/Logs
	echo "-----DEBUG MODE ENABLED-----" | tee -a "$JAMFETCHLOG"
fi
if [[ $DEBUG == "1" ]]; then
	echo "-----DEBUG MODE----- Bearer Token: $token" | tee -a "$JAMFETCHLOG"
fi

##############################################################
# Functions
##############################################################

DialogInstall(){
	
	pkgfile="SwiftDialog.pkg"
	logfile="/Library/Logs/SwiftDialogInstallScript.log"
	URL="https://github.com$(curl -sfL "$(curl -sfL "https://github.com/bartreardon/swiftDialog/releases/latest" | tr '"' "\n" | grep -i "expanded_assets" | head -1)" | tr '"' "\n" | grep -i "^/.*\/releases\/download\/.*\.pkg" | head -1)"
	
	# Start Log entries
	echo "--" >> ${logfile}
	echo "`date`: Downloading latest version." >> ${logfile}
	
	# Download installer
	curl -s -L -J -o /tmp/${pkgfile} ${URL}
	echo "`date`: Installing..." >> ${logfile}
	
	# Change to installer directory
	cd /tmp
	
	# Install application
	sudo installer -pkg ${pkgfile} -target /
	sleep 5
	echo "`date`: Deleting package installer." >> ${logfile}
	
	# Remove downloaded installer
	rm /tmp/"${pkgfile}"
	
}

##############################################################
# Check if SwiftDialog is installed (SwiftDialog created by Bart Reardon https://github.com/bartreardon/swiftDialog)
##############################################################

if ! command -v dialog &> /dev/null
then
	echo "SwiftDialog is not installed. App will be installed now....."
	sleep 2
	
	DialogInstall
	
else
	echo "SwiftDialog is installed. Checking installed version....."
	
	installedVersion=$(dialog -v | sed 's/./ /6' | awk '{print $1}')
	
	latestVersion=$(curl -sfL "https://github.com/bartreardon/swiftDialog/releases/latest" | tr '"' "\n" | grep -i "expanded_assets" | head -1 | tr '/' ' ' | awk '{print $7}' | tr -d 'v' | awk -F '-' '{print $1}')
	
	if [[ $installedVersion != $latestVersion ]]; then
		echo "Dialog needs updating"
		DialogInstall
	else
		echo "Dialog is up to date. Continuing...."
	fi
	sleep 3
fi

############################################################################
# Create json file for swiftDialog
############################################################################

cat << EOF > /tmp/dialogjson.json
{
	"listitem" : [
	]
}
EOF

############################################################################
# Display initial information selection window
############################################################################

JHELP=$(dialog \
--title "JamFetch" \
--icon "https://resources.jamf.com/images/logos/Jamf-Icon-color.png?_gl=1*skf9ox*_gcl_aw*R0NMLjE3NDYxNzQxOTIuQ2owS0NRancydEhBQmhDaUFSSXNBTlp6RFdydm5ETDh1Xzk1clJSUFRNX2lKSGZsZFNveC1FT0xXaTV3NzhSU0ZBRThqcmdpa3llWExuOGFBbU55RUFMd193Y0I.*_gcl_au*MTY5Mzg3ODc4MC4xNzUwMjQwNDU1*_ga*MTU4ODQzMTEwMC4xNzE4MDA2NTQ5*_ga_X3RD84REYK*czE3NTE1MzIxNzkkbzMzMiRnMSR0MTc1MTUzMjI0NyRqNTQkbDAkaDA." --iconsize 100 \
--message "Which details would you like to view:" \
--button1text "Continue" \
--button2text "Quit" \
--regular \
--button1disabled \
--vieworder "dropdown,textfield,checkbox" \
--checkbox "JAMF LAPS",enableButton1 --button1disabled \
--checkbox "FV Key",enableButton1 --button1disabled \
--selecttitle "Serial or Hostname",required \
--selectvalues "Serial Number,Hostname" \
--selectdefault "Hostname" \
--textfield "Device,required" \
--textfield "Reason,required" \
--json)

exit_code=$?

# Check if button2 was pressed (exit code 2)
if [[ $exit_code -eq 2 ]]; then
	echo "User Quit"
	exit 0
fi

DROPDOWN=$(echo $JHELP | plutil -extract "SelectedOption" raw -)
FV=$(echo $JHELP | plutil -extract "FV Key" raw -)
LAPS=$(echo $JHELP | plutil -extract "JAMF LAPS" raw -)
reason=$(echo $JHELP | plutil -extract "Reason" raw -)
name1=$(echo $JHELP | plutil -extract "Device" raw -)

if [[ $DEBUG == "1" ]]; then
	echo "-----DEBUG MODE----- Device Type: $DROPDOWN" | tee -a "$JAMFETCHLOG"
	echo "-----DEBUG MODE----- Device name: $name1" | tee -a "$JAMFETCHLOG"
	echo "-----DEBUG MODE----- Viewed Reason: $reason" | tee -a "$JAMFETCHLOG"
	echo "-----DEBUG MODE----- LAPS Selection: $LAPS" | tee -a "$JAMFETCHLOG"
	echo "-----DEBUG MODE----- FV Selection: $FV" | tee -a "$JAMFETCHLOG"
fi

############################################################################
# Get Device ID
############################################################################

if [[ $DROPDOWN == "Hostname" ]]; then 
	echo "User selected Hostname"
	
	name=$(echo $name1 | sed -e 's#’#%E2%80%99#g' -e 's# #%20#g')
	
	# Get Device ID
	ID=$(curl -s -X GET "$URL/JSSResource/computers/name/$name" -H 'Accept: application/json' -H "Authorization:Bearer ${token}" | plutil -extract "computer"."general"."id" raw -)
else
	echo "User selected Serial"
	
	# Get Device ID
	ID=$(curl -s -X GET "$URL/JSSResource/computers/serialnumber/$name1" -H 'Accept: application/json' -H "Authorization:Bearer ${token}" | plutil -extract "computer"."general"."id" raw -)
fi

if [[ $DEBUG == "1" ]]; then
	echo "-----DEBUG MODE----- JAMF ID: $ID" | tee -a "$JAMFETCHLOG"
fi

############################################################################
# Get FileVault Key
############################################################################

if [[ $FV == 'true' ]]; then
	echo "FileVault key requested"
	FVKey=$(curl -s -H "Content-Type: text/json" -H "Authorization:Bearer ${token}" -X GET "$URL/api/v1/computers-inventory/$ID/filevault" | plutil -extract "personalRecoveryKey" raw -)
	
	sed -i '' $'2a\\\n\t\t{"title" : "FV Recovery Key:", "icon" : "/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/FileVaultIcon.icns", "statustext" : "'$FVKey'"},' /tmp/dialogjson.json
	
else
	echo "FileVault not selected"
fi

############################################################################
# Get LAPS Details
############################################################################

if [[ $LAPS == 'true' ]]; then
	echo "LAPS Password requested"
	
	############################################################################
	# Get JAMF Management ID
	############################################################################
	
	MANAGEID=$(curl -s -X "GET" "$URL/api/v1/computers-inventory-detail/$ID" -H "Accept: application/json" -H "Authorization:Bearer ${token}" | plutil -extract "general"."managementId" raw -)
	
	if [[ $DEBUG == "1" ]]; then
		echo "-----DEBUG MODE----- Managed ID: $MANAGEID" | tee -a "$JAMFETCHLOG"
	fi
	
	############################################################################
	# Get LAPS Username
	############################################################################
	
	if [[ $LAPSname == "" ]]; then
		LAPSUSER=$(curl -s -X "GET" "$URL/api/v2/local-admin-password/$MANAGEID/accounts" -H "Accept: application/json" -H "Authorization:Bearer ${token}" | plutil -extract "results".0."username" raw -)
		############################################################################
		# Get Password
		############################################################################
		
		PASSWD=$(curl -s -X "GET" "$URL/api/v2/local-admin-password/$MANAGEID/account/$LAPSUSER/password" -H "Accept: application/json" -H "Authorization:Bearer ${token}" | plutil -extract password raw -)
	else
		LAPSUSER=$LAPSname
		
		############################################################################
		# Get Password
		############################################################################
		
		PASSWD=$(curl -s -X "GET" "$URL/api/v2/local-admin-password/$MANAGEID/account/$LAPSUSER/password" -H "Accept: application/json" -H "Authorization:Bearer ${token}" | plutil -extract password raw -)
	fi

sed -i '' $'2a\\\n\t\t{"title" : "LAPS Password:", "icon" : "https://github.com/PezzaD84/JAMF-LAPS-UI/blob/main/jamf_unlocked_yonder.png?raw=true", "statustext" : "'$PASSWD'"},' /tmp/dialogjson.json
sed -i '' $'2a\\\n\t\t{"title" : "LAPS Account:", "icon" : "/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/Everyone.icns", "statustext" : "'$LAPSUSER'"},' /tmp/dialogjson.json

	if [[ $DEBUG == "1" ]]; then
		echo "-----DEBUG MODE----- LAPS Account: $LAPSUSER" | tee -a "$JAMFETCHLOG"
	fi
	
else
	echo "LAPS not selected"
fi

############################################################################
# Display requested information
############################################################################

dialog \
--title "JamFetch" \
--message none \
--jsonfile /tmp/dialogjson.json \
--messagefont 'name=Arial,size=14' \
--icon none \
--height 300 \
--width 650

if [[ $DEBUG == "1" ]]; then
	echo "-----DEBUG MODE----- JSON File: $(cat /tmp/dialogjson.json)" | tee -a "$JAMFETCHLOG"
fi

rm /tmp/dialogjson.json

exit 0