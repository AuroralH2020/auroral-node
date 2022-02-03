#!/bin/bash
cd $(dirname $0)
USAGE="$(basename "$0") [ -h ] [ -e env ]
-- AP initialisation script 
-- Run without parameters for basic initialization
-- Flags:
      -h  Shows help
      -r  Reset Node
      -u  Update  images
      -i  Run interactive mode
      -s  Stop Node
      -a  <username> add auth user
      -d  <username> delete auth user " 

# Configuration
ENV_FILE=".env"
ENV_EXAMPLE="env.example"
ENV_BACKUP="env.edit"
AURORAL_NM_URL="https://auroral.dev.bavenir.eu/nm/#!/myNodes"
DEPENDENCIES=("docker" "docker-compose" "perl" )
AGID=""
TMP=""
DAEMON=0
MACHINE=''
ARCH=''
# VARIABLES

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
  if [ -z "$2" ]; then 
    return
  else
    # Check size and repeat
    while  [[ ${#TMP} != $2 ]]; do
    echo -n -e "\033[1;31mIncorrect length. $1\033[0m"
    read TMP
    done
  fi
}

# Displays dialog and return given text in TMP 
getTextPasswordAnswer () {
  TMP=''
  # write question
  echo -n -e "\033[1;34m$1\033[0m"
  # wait for answer and store it to TMP
  stty_orig=$(stty -g)
  stty -echo
  read TMP
  stty $stty_orig
  # if size is defined (second argument)
  if [ -z "$2" ]; then 
    return
  else
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
  # if number do not quote
  if [ -n "$value" ] && [ "$value" -eq "$value" ] 2>/dev/null; then
   # edit env file and save to ENV_BACKUP
   sed "s/$1=.*/$1=$value/" $ENV_FILE > "$ENV_BACKUP"
  else
    # edit env file and save to ENV_BACKUP
    sed "s/$1=.*/$1=\"$value\"/" $ENV_FILE > "$ENV_BACKUP"
  fi
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
  checkIfRunning
  if [ $? == "1" ]; then
    return
  fi
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
createFolders () {
  mkdir ./agent > /dev/null 2>&1
  mkdir ./agent/exports > /dev/null 2>&1
  mkdir ./agent/imports > /dev/null 2>&1
  mkdir ./gateway/data  > /dev/null 2>&1
  mkdir ./gateway/log   > /dev/null 2>&1
  mkdir ./nginx/logs    > /dev/null 2>&1
  mkdir ./redis/data    > /dev/null 2>&1
}

#display warning if running on Linux
testPermissions () {
if [ $MACHINE == 'Linux' ]; then
    echoWarn "You are running on linux - setting permissions to 777"
    chmod -R 777 nginx   > /dev/null 2>&1
    chmod -R 777 redis   > /dev/null 2>&1
    chmod -R 777 gateway > /dev/null 2>&1
    chmod -R 777 agent   > /dev/null 2>&1
  fi
}

# disable running node
disableNode () {
  echoBlue "Disabling node"
  docker-compose down
  echoBlue "Done"
}

# Run genKeys.sh -- Get pub/priv keys
generateCertificates () {
  # run script to generate certs
  echo "Generating certificates"
  bash ./gateway/keystore/genkeys.sh > /dev/null 2>&1
  # display pubkey and ask to copy 
  echoBlue "Please copy this public key to Access Point settings in AURORAL website:"
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

# detects Machine architecture
getArch () {
  archOut="$(uname -m)"
  case "${archOut}" in
      armv7l*)     arch=armv7;;
      arm64*)      arch=amd64;;
      x86_64*)     arch=x86_64;;
      amd64*)      arch=arm64;;
      *)           echoWarn "Unknown architecture (${archOut}). Choosing amd64 image"; arch="amd64"
  esac
  ARCH=${arch}
}

#check if docker-compose is running
checkIfRunning () {
  SERVICES=$(docker-compose ps -q | wc -l )
  if [ $SERVICES != "0" ]; then
    echoBlue "Node is already running"
    return 1
  else
    echo 'Node is disabled '
    return 0
  fi
}

# update images and restart
updateImages () {
  checkIfRunning
  if [ $? == 1 ]; then 
    disableNode
  else 
    echo "node offline"
  fi
 echoBlue "Updating images"
 docker-compose pull
 runAp
 exit
}

# generate credentials in md5 and store them in .htpasswd file
addAuthUser () {
  echo "Adding user"
  getTextPasswordAnswer "Password for user ${username}:\n";
  password="${TMP}";
  printf "${username}:$(openssl passwd -apr1 ${password})\n"  >> ./nginx/.htpasswd
  echoBlue "User credentials stored"
}

# remove line containing $username in .htpasswd file
deleteAuthUser () {
  echo "Deleting  user"
  sed -i.bak "/${username}/d" ./nginx/.htpasswd 
  rm ./nginx/.htpasswd.bak
}

# Test if already initialised
checkIfInitialised () {
  if [[ -f ".env" ]]; then
    return 1
    # echoBlue "If you want to reset initialisation, run with -r parameter"
  fi
  return 0
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
  checkIfInitialised
   if [ $? == 1 ]; then
    disableNode
  fi
  # Gateway data
  rm -rf "./gateway/data" > /dev/null 2>&1
  rm  "./gateway/keystore/platform-key.der" > /dev/null 2>&1
  rm  "./gateway/keystore/platform-key.pem" > /dev/null 2>&1
  rm  "./gateway/keystore/platform-pubkey.der" > /dev/null 2>&1
  rm  "./gateway/keystore/platform-pubkey.pem" > /dev/null 2>&1
  rm  "./gateway/keystore/ogwapi-token" > /dev/null 2>&1
  rm "./nginx/.htpasswd" > /dev/null 2>&1
  touch "./nginx/.htpasswd" > /dev/null 2>&1
  rm  -rf "./gateway/log" > /dev/null 2>&1
  # Docker-compose
  rm  "./docker-compose.yml" > /dev/null 2>&1

  # NGINX
  rm  -rf "./gateway/logs" > /dev/null 2>&1
  # REDIS data
  rm -rf "./redis/data" > /dev/null 2>&1
  # .env
  rm ".env" > /dev/null 2>&1
  echo "Node instance deleted... Please remove your Access Point credentials in AURORAL website if no longer needed"
  exit 0
}

# Get opts
while getopts 'hirsua:d:' OPTION; do
  case "$OPTION" in 
    h) echo "$USAGE";
       exit 0;;
    s) stopAP 
       exit0;;
    r) resetInstance; 
       exit 0;;
    i) DAEMON=1;;
    u) updateImages;
       exit 0;;
    a) username=$OPTARG;
       addAuthUser;
       exit 0;;
    d) username=$OPTARG;
       deleteAuthUser;
       exit 0;;
  esac 
done

# Main program
# Test for dependencies
testDependencies "${DEPENDENCIES[@]}"

# Test if already initialised
checkIfInitialised
if [ $? == 1 ]; then 
  echoBlue "Already initialised."
  runAp
  exit
fi

# Get users machine
getMachine
getArch

DOCKER_FILENAME='./docker-compose/docker-compose'

# choose docker-compose file
# Not necessary after docker multiarch image
# if [ ${ARCH} == 'armv7' ]; then
#  DOCKER_FILENAME="${DOCKER_FILENAME}.armv7"
# fi



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
getYesNOanswer 'Enable Wot?'; 
if [ $? == 1 ]; then 
  editEnvFile "WOT_ENABLED" 1
  DOCKER_FILENAME="${DOCKER_FILENAME}.wot"
fi 

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

# Auth
getYesNOanswer 'Enable Basic authentification and ssl?'; 
if [ $? == 1 ]; then 
  BASIC_AUTH=1
  DOCKER_FILENAME="${DOCKER_FILENAME}.auth"
  mkdir ./nginx/cert > /dev/null 2>&1
  echoBlue 'Generating self signed certificate'; 
  openssl req -x509 -nodes -days 1825 -newkey rsa:2048 -subj "/C=GB/ST=London/L=London/O=Global Security/OU=Auroral Agent/CN=auroral-agent.local" -keyout ./nginx/cert/nginx-selfsigned.key -out nginx/cert/nginx-selfsigned.crt > /dev/null 2>&1
  echoBlue '...done'; 
  getYesNOanswer 'Do you want to add credentials for first user?'; 
  if [ $? == 1 ]; then 
    getTextAnswer "Username:"; 
    username=$TMP
    addAuthUser;
  fi 
fi 

echo "Choosing ${DOCKER_FILENAME}.yml"
cp "${DOCKER_FILENAME}.yml" ./docker-compose.yml

# TBD
#security

# create folders for NGINX AGENT GATEWAY and REDIS
createFolders

# fix if linux
testPermissions


# Start Node
echoBlue 'Node initialisation completed' 
runAp
