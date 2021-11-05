#!/bin/bash
cd $(dirname $0)
USAGE="$(basename "$0") [ -h ] [ -e env ]
-- AP initialisation script
-- Run without parameters for basic initialization
-- Flags:
      -h  Shows help
      -r  Reset Node
      -i  Run interactive mode
      -s  Stop Node"

# Configuration
ENV_FILE=".env"
ENV_EXAMPLE="env.example"
ENV_BACKUP="env.edit"
AURORAL_NM_URL="https://auroral.dev.bavenir.eu/nm/#!/myNodes"
DEPENDENCIES=("docker" "docker-compose" "perl")
AGID=""
TMP=""
DAEMON=0
MACHINE=
# VARIABLES
SIMPLE=0

# Functions

# Print text in blue color
echoBlue () {
  echo -e "\033[1;34m$@\033[0m"
}

# Print text in yellow color
echoWarn () {
  echo -e "\033[1;33m$@\033[0m"
}

# Displays yes / no dialog and return value
getYesNOanswer () {
  local answer=1
  # pring question
  echoBlue $1
  # wait for answer
  select yn in 'Yes' 'No'; do
    case $yn in
        Yes ) return 1;break;;
        No ) return 0;break;;
    esac
done
}

# Displays dialog and return given text in TMP 
getTextAnswer () {
  TMP=''
  # write question
  echo -n -e "\033[1;34m$1\033[0m"
  # wait for answer and store it to TMP
  read TMP
  # if size is defined (second argument)
  if [ -z ${2+x} ]; then 
    # Check size and repeat
    while  [[ ${#TMP} != $2 ]]; do
    echo -n -e "\033[1;31mIncorrect length. $1\033[0m"
    read TMP
    done
  fi
}
# Edit field in .env file
# params: key, ?value 
# if value is not provided, it is taken from TMP variable
editEnvFile () {
  # if second parameter -> text value
  if [ -z ${2+x} ]; then 
    local value=$TMP 
  else
  # numeric value 0/1 -> transform to true/false
    if [ $2 = 1 ]; then
      echo "1"
      local value="true"
    elif [ $2 = 0 ]; then
      echo "2"
      local value="false"
    fi
  fi
  # edit env file and save to ENV_BACKUP
  sed "s/$1=.*/$1=\"$value\"/" $ENV_FILE > "$ENV_BACKUP"
  # move backup to env file
  cat "$ENV_BACKUP" > "$ENV_FILE"
  # rm backup file
  rm "$ENV_BACKUP" 
}

# Search for identity tag and replace with given value
# param: AGID
fillGatewayConfig () {
  #change AGID
  XML="./gateway/GatewayConfig.xml" 
  XML_BACKUP="./gateway/GatewayConfig.xml.edited" 
  NEW_IDENTITY="<identity>
			<!--
			AGID of the Access Point used to authenticate the gateway \(AGID string\)
			-->
			$1
		<\/identity>"
  perl -i  -0pe "s/<identity>.*<\/identity>/$NEW_IDENTITY/gms" gateway/GatewayConfig.xml
}

# Asks and run the APP with docker-compose
runAp () {
getYesNOanswer 'Run Node now?' ;
  if [ $? == "1" ]; then
    if [ $DAEMON == "0" ]; then
    echoBlue "Starting Node (-d)"
      docker-compose up -d
    else
    echoBlue "Starting Node"
     docker-compose up
    fi
  else
    echoBlue "Bye "
    exit
  fi
}

# Stops the APP with docker-compose
stopAP () {
  echoBlue 'Stopping' 
  docker-compose down
  exit 0
}
testDependencies () {
  # For all given parameters
  for i in "$@"
  do
    # Test 'param' -v answer
    eval "$i -v"  > /dev/null 2>&1
    if [ $? != 0 ]; then
      # if error, exit
      echo "Dependency \"$i\" not found. Please install it "
      exit 1
    fi
  done
}

#display warning if running on Linux
testPermissions () {
if [ $MACHINE == 'Linux' ]; then
    echoWarn "You are running on linux. If you are experiencing permissions problems change folders permission:\n \
    chmod -R 777 ./gateway \n \
    chmod -R 777 ./redis"
  fi
}

# Removes all edited files and create clean node
resetInstance () {
  # Removing all settings
  echo "-r RESET AP";
  getYesNOanswer "Are you sure you want to remove all node files?";
  if [ $? != 1 ]; then
      echo "Aborting..";
      return 
  fi
  # Gateway data
  rm -rf "./gateway/data" > /dev/null 2>&1
  rm  "./gateway/keystore/platform-key.der" > /dev/null 2>&1
  rm  "./gateway/keystore/platform-key.pem" > /dev/null 2>&1
  rm  "./gateway/keystore/platform-pubkey.der" > /dev/null 2>&1
  rm  "./gateway/keystore/platform-pubkey.pem" > /dev/null 2>&1
  rm  "./gateway/keystore/ogwapi-token" > /dev/null 2>&1
  rm  -rf "./gateway/log" > /dev/null 2>&1
  # NGINX
  rm  -rf "./gateway/logs" > /dev/null 2>&1
  # REDIS data
  rm -rf "./redis/data" > /dev/null 2>&1
  # .env
  rm ".env" > /dev/null 2>&1
  echo "Node instance deleted... Please remove your Access Point credentials in AURORAL website if no longer needed"
  exit 0
}

# Run genKeys.sh -- Get pub/priv keys
generateCertificates () {
  # run script to generate certs
  echo "Generating certificates"
  bash ./gateway/keystore/genkeys.sh > /dev/null 2>&1
  # display pubkey and ask to copy 
  echo "Please copy this public key to Access Point settings in AURORAL website:"
  echo -e "\033[1;92m$(cat ./gateway/keystore/platform-pubkey.pem)\033[0m"
}

# Detects Machine OS
getMachine () {
  unameOut="$(uname -s)"
  case "${unameOut}" in
      Linux*)     machine=Linux;;
      Darwin*)    machine=Mac;;
      CYGWIN*)    machine=Cygwin;;
      MINGW*)     machine=MinGw;;
      *)          machine="UNKNOWN:${unameOut}"
  esac
  MACHINE=${machine}
}

# Get opts
while getopts 'hirs' OPTION; do
  case "$OPTION" in 
    h) echo "$USAGE";
       exit 0;;
    s) stopAP 
       exit0;;
    r) resetInstance; 
       exit 0;;
    i) DAEMON=1;;
  esac 
done

# Main program
# Test for dependencies
testDependencies "${DEPENDENCIES[@]}"

# Test if already initialised
if [[ -d "./redis/data" ]]; then
  echoBlue "Already initialised."
  # echoBlue "If you want to reset initialisation, run with -r parameter"
  runAp
  exit
fi

# Get users machine
getMachine

# Test Permissions
testPermissions

# Create .env file
cp $ENV_EXAMPLE $ENV_FILE

# Production mode
getYesNOanswer 'Run in PRODUCTION mode?'; 
if [ $? == 1 ]; then 
  TMP="production"; 
else 
  TMP="development";
fi
editEnvFile "NODE_ENV";

# Wot
getYesNOanswer 'Enable Wot?' ; editEnvFile "WOT_ENABLED" $?
# DB caching
getYesNOanswer 'Enable caching adapter values?' ; editEnvFile "DB_CACHE_ENABLED" $?

# Change External Port
getYesNOanswer 'Use default external port? (81)' ;
if [ $? == 0 ]; then
  getTextAnswer "Please specify the external port:" "";
  editEnvFile "EXTERNAL_PORT";
fi;

# Node agid + pasword
echo "Now please register new Node in AURORAL website: $AURORAL_NM_URL, in section 'Access points'"
getTextAnswer "Please insert generated AGID:" "36"; AGID=$TMP; editEnvFile "GTW_ID" 
getTextAnswer "Please insert Node password:" ""; editEnvFile "GTW_PWD" 

# Fill GatewayConfig.xml
fillGatewayConfig $AGID

# Genereate certificates
generateCertificates
getTextAnswer "Hit enter after done" "";

# TBD
#security

# Start Node
echoBlue 'Node initialisation completed' 
runAp