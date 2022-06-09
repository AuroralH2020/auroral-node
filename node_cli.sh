#!/bin/bash
cd $(dirname $0)

#----------------------------------------------------------
# Help
USAGE="$(basename "$0") [ -h ] [ -e env ]
-- AP initialisation script 
-- Run without parameters for basic initialization
-- Flags:
      -h  Shows help
      -r  Reset Node instance
      -u  Update  images
      -i  Run interactive mode
      -s  Stop Node
      -b  Backup node
      -k  Regenerate keys
      -a  Apply backup
     " 
#----------------------------------------------------------
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

#----------------------------------------------------------
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


# Displays password dialog and return given text in TMP 
getTextPasswordAnswer () {
  prompt=""
  unset TMP
  echo -n -e "\033[1;34m$1\033[0m"
  while IFS= read -p "$prompt" -r -s -n 1 char
  do
      if [[ $char == $'\0' ]]
      then
          break
      fi
      prompt='*'
      TMP+="$char"
  done
}

# Displays adapter select dialog
getAdapterMode () {
  local answer=1
  # pring question
  echoBlue 'Please select adapter mode'
  # wait for answer
  select yn in 'dummy' 'proxy' 'semantic'; do
    case $yn in
        dummy )    TMP='dummy';break;;
        proxy )    TMP='proxy';break;;
        semantic ) TMP='semantic';break;;
    esac
done
}

# Displays adapter select dialog
getExtensionSelection () {
  local answer=1
  # pring question
  echoBlue 'Do you want to install an extension?'
  # wait for answer
  select yn in 'No, just the Node' 'Node-red adapter' 'Helio adapter'; do
    case $yn in
        'No, just the Node' )      TMP='any';break;;
        'Node-red adapter' ) TMP='node-red';break;;
        'Helio adapter' )  TMP='helio';break;;
    esac
  done
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
    sed "s@$1=.*@$1=$value@" $ENV_FILE > "$ENV_BACKUP"
  else
    # edit env file and save to ENV_BACKUP
    sed "s@$1=.*@$1=\"$value\"@" $ENV_FILE > "$ENV_BACKUP"
  fi
  # move backup to env file
  cat "$ENV_BACKUP" > "$ENV_FILE"
  # rm backup file
  rm "$ENV_BACKUP" 
}

# Search for identity tag and replace with given value
# param: AGID
fillGatewayConfig () {
  docker-compose run  --rm --entrypoint "/bin/bash  -c ' cd /gateway/persistance/config/ && ./fillAgid.sh ${AGID}'" gateway
}

# Asks and run the APP with docker-compose
startAP () {
  checkIfRunning
  if [ $? == "1" ]; then
    return
  fi
  if [ $DAEMON == "0" ]; then
    echoBlue "Starting Node (-d)"
      docker-compose up -d
    else
    echoBlue "Starting Node"
     docker-compose up
    fi
}

# Stops the APP with docker-compose
stopAP () {
  echoBlue 'Stopping' 
  docker-compose down
}

askAndStartAP() {
  getYesNOanswer 'Run Node now?' ;
  if [ $? == "1" ]; then
  startAP
  else
    echoBlue "Bye "
    exit
  fi
}

backupAP () {
  echoBlue 'Backing up' 
  echoBlue 'Starting NODE' 
  startAP
  CONTAINERS=$(docker-compose ps -q)
  VOLUMES=$(echo -e "${CONTAINERS}" | perl -pe 's/^/ --volumes-from /g' | perl -pe 's/\n/ /g') 
  # TODO redis, gateway, triplestore + env
  docker run --rm -ti  $(echo $VOLUMES) -v $(pwd):/backup ubuntu /bin/bash -c 'tar cvf /backup/node_backup.tar /data /gateway/persistance /fuseki /backup/.env'
  echoBlue 'Stopping NODE' 
  stopAP
  echoBlue 'Done' 
  exit 0
}

restoreAP () {
  echo "RestoreAP"
  #Copy env file
  cp $ENV_EXAMPLE $ENV_FILE
  startAP
  # get containers IDs
  CONTAINERS=$(docker-compose ps -q)
  VOLUMES=$(echo -e "${CONTAINERS}" | perl -pe 's/^/ --volumes-from /g' | perl -pe 's/\n/ /g') 
  #restore backup
  docker run --rm -ti $(echo $VOLUMES) -v $(pwd):/backup ubuntu /bin/bash -c 'tar -xvf /backup/node_backup.tar '
  echoBlue 'Done' 
  echoBlue 'Stopping NODE' 
  stopAP
}

# Regenerate certificates
regenerateCertificates() {
  stopAP
  echoBlue 'Regenerating keys'
  generateCertificates
  echoBlue 'Done' 
  exit 0
}

# check if dependencies are installed
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

# Run genKeys.sh -- Get pub/priv keys
generateCertificates () {
  # run script to generate certs
  echo "Generating certificates"
  PUBKEY=$(docker-compose run  --rm --entrypoint "/bin/bash -c 
  'cd  /gateway/persistance/keystore && 
   ./genkeys.sh > /dev/null 2>&1  && 
   cat platform-pubkey.pem '" gateway)
  # display pubkey and ask to copy 
  echoBlue "Please copy this public key to Access Point settings in AURORAL website:"
  PUBKEY="\033[1;92m${PUBKEY}\033[0m"
  echo  -e "${PUBKEY}"
}



# Run openssl in gateway container and generate random password
# stored in TMP
getRandomPassword() {
  TMP=$(hexdump -n 16 -e '4/4 "%08X" 1 "\n"' /dev/urandom)
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
  echoBlue "System running on ${MACHINE}"
}

# detects Machine architecture
getArch () {
  archOut="$(uname -m)"
  case "${archOut}" in
      armv7l*)     arch=armv7;;
      arm64*)      arch=amd64;;
      x86_64*)     arch=x86_64;;
      amd64*)      arch=arm64;;
      *)           echoWarn "Unknown architecture (${archOut})"; arch="amd64"
  esac
  ARCH=${arch}
}

#check if docker-compose is running
checkIfRunning () {
  SERVICES=$(docker-compose ps -q | wc -l )
  if [ $SERVICES != "0" ]; then
    return 1
  else
    return 0
  fi
}

# update images and restart
updateImages () {
  checkIfRunning
  if [ $? == 1 ]; then 
    stopAP
  else 
    echo "node offline"
  fi
 echoBlue "Updating images"
 docker-compose pull
 askAndStartAP
 exit
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
    stopAP
  fi
  # All volumes
  docker-compose down -v
  mv docker-compose.backup docker-compose.yml  > /dev/null 2>&1
  # .env
  rm ".env" > /dev/null 2>&1
  echoBlue "Node instance deleted... Please remove your Access Point credentials in AURORAL website if no longer needed"
  exit 0
}

# Get opts
while getopts 'hirsuad:bk' OPTION; do
  case "$OPTION" in 
    h) echo "$USAGE";
       exit 0;;
    s) stopAP 
       exit 0;;
    k) regenerateCertificates;
       exit 0;;
    r) resetInstance; 
       exit 0;;
    i) DAEMON=1;;
    u) updateImages;
       exit 0;;
    b) backupAP;
       exit 0;;
    a) restoreAP;
       exit 0;;
  esac 
done

#----------------------------------------------------------
# Main program


# Test for dependencies
testDependencies "${DEPENDENCIES[@]}"

# Test if already initialised
checkIfInitialised
if [ $? == 1 ]; then 
  echoBlue "Already initialised."
  askAndStartAP
  exit
fi

# Get users machine
getMachine
getArch

# Create .env file
cp $ENV_EXAMPLE $ENV_FILE

# Generate password for REDIS
getRandomPassword;
editEnvFile "DB_PASSWORD";

# Production mode
getYesNOanswer 'Run in PRODUCTION mode?'; 
if [ $? == 1 ]; then 
  TMP="production"; 
else 
  TMP="development";
fi
editEnvFile "NODE_ENV";


# DB caching
getYesNOanswer 'Enable caching adapter values?' ; editEnvFile "DB_CACHE_ENABLED" $?

# Change External Port
getYesNOanswer 'Use default external port? (81)' ;
if [ $? == 0 ]; then
  getTextAnswer "Please specify the external port:" "";
  editEnvFile "EXTERNAL_PORT";
fi;

# Install adapter extension
getExtensionSelection 'Install extension?';
if [ $TMP == node-red ]; then 
  cp docker-compose.yml docker-compose.backup
  docker-compose -f docker-compose.backup -f extensions/node-red-compose.yml config > docker-compose.yml;
  TMP='proxy';  editEnvFile "ADAPTER_MODE";
  TMP='http://node-red'; editEnvFile "ADAPTER_HOST";
  TMP='1250'; editEnvFile "ADAPTER_PORT";
elif [ $TMP == helio ]; then
  echo 'HELIO';
  cp docker-compose.yml docker-compose.backup
  docker-compose -f docker-compose.backup -f extensions/helio-compose.yml config > docker-compose.yml;
  TMP='semantic';  editEnvFile "ADAPTER_MODE";
else
  # ANY EXTENSION - choose adapter mode
  # select adapter mode 
  getAdapterMode;
  if [ $TMP == 'proxy' ]; then 
    editEnvFile "ADAPTER_MODE" 
    getTextAnswer "Please specify proxy HOST:"; editEnvFile "ADAPTER_HOST";
    getTextAnswer "Please specify proxy PORT:"; editEnvFile "ADAPTER_PORT";
  else
    editEnvFile "ADAPTER_MODE" 
  fi
fi

# # select adapter mode 
# getAdapterMode;
# if [ $TMP == proxy ]; then 
#   editEnvFile "ADAPTER_MODE" 
#   getTextAnswer "Please specify proxy HOST:"; editEnvFile "ADAPTER_HOST";
#   getTextAnswer "Please specify proxy PORT:"; editEnvFile "ADAPTER_PORT";
# else
#   editEnvFile "ADAPTER_MODE" 
# fi

# Node agid + pasword
echo "Now please register new Node in AURORAL website: $AURORAL_NM_URL, in section 'Access points'"
getTextAnswer "Please insert generated AGID:" "36"; AGID=$TMP; editEnvFile "GTW_ID" 
getTextPasswordAnswer "Please insert Node password:" ""; editEnvFile "GTW_PWD" 

# Fill GatewayConfig.xml
fillGatewayConfig $AGID

# Genereate certificates
generateCertificates
getTextAnswer "Hit enter after done" "";

# Start Node
echoBlue 'Node initialisation completed' 
askAndStartAP
