#!/bin/bash
# This script is used to automate node deployment 
# For usage please generate AURORAL API Key and use it in the script
USAGE="$(basename "$0") [ -h ] [ -k keyid -s secret ]
AP initialisation script 
-- Tools:
    -h        show this help text
    -d        deletes the AP locally
    -D        deletes the AP locally and in platform
-- Required parameters:
    -k keyid  token for pushing pubkey to platform
    -s secret secret for pushing pubkey to platform 
-- Optional parameters:
    -e dev    Environment to use (dev, prod) (default: dev)
    -n mynode Name of the Access point in platform (default: hostname)
    -P 81     Port for Agent API (default: 81)
    -A dummy|custom|helio|nodered   
              ADAPTER mode (default: dummy)
    -S        enable SHACL validation (default: disabled)
    -O        enable ODRL validation (default: disabled)
"

#----------------------------------------------------------
# Variables
#----------------------------------------------------------

ENV_FILE=".env"
ENV_EXAMPLE="env.example"
ENV_BACKUP="env.edit"
AURORAL_URL_DEVELOPMENT="https://auroral.dev.bavenir.eu/"
AURORAL_URL_PRODUCTION="https://auroral.bavenir.eu/"
AURORAL_URL="$AURORAL_URL_DEVELOPMENT"
DEPENDENCIES=("docker" "docker-compose" "perl" )
ADAPTER_MODE="dummy"
ADAPTER_HOST="http://adapter"
ADAPTER_PORT=1250
AGID=""
NAME=$(hostname)
PASSWORD=""
DAEMON=0
MACHINE=''
PORT=81
ARCH=''
# Temporary variable
TMP=""

#----------------------------------------------------------
# Functions
#----------------------------------------------------------

# Print text in blue color
echoBlue () {
  echo -e "\033[1;34m$@\033[0m"
}
# Print text in yellow color
echoWarn () {
  echo -e "\033[1;31m$@\033[0m"
}

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
#   echoBlue "System running on ${MACHINE}"
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
  # echo "Generating certificates"
  PUBKEY=$(docker-compose run  --rm --entrypoint "/bin/bash -c 
  'cd  /gateway/persistance/keystore && 
   ./genkeys.sh > /dev/null 2>&1  && 
   cat gateway-pubkey.pem '" gateway)
  if [ $? != 0 ]; then
    echo "Error generating certificates"
    exit 1
  fi
  # display pubkey and ask to copy 
  # echoBlue "Please copy this public key to Access Point settings in AURORAL website:"
  # TMP_PUBKEY="\033[1;92m${PUBKEY}\033[0m"
  # echo  -e "${TMP_PUBKEY}"
}

# Run openssl in gateway container and generate random password
# stored in TMP
getRandomPassword() {
  TMP=$(hexdump -n 16 -e '4/4 "%08X" 1 "\n"' /dev/urandom)
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

# Test if already initialised
checkIfInitialised () {
  if [[ -f ".env" ]]; then
    INITIALISED=1
    return
  fi
    INITIALISED=0
}

getAgidFromEnvFile () {
    AGID=$(grep GTW_ID .env | cut -d '=' -f2 | xargs)
    echoBlue "AGID: ${AGID}"
}

# Write public key to file
writePubKeyToFile () {
    # PUBKEY=$(docker-compose run  --rm --entrypoint "/bin/bash -c 'cd  /gateway/persistance/keystore && cat gateway-pubkey.pem '" gateway)
    echo "${PUBKEY}" > "${AGID}.pub"
}

# Install node-red docker-compose
nodeRedExtension () {
  cp docker-compose.yml docker-compose.backup
  docker-compose -f docker-compose.yml -f extensions/node-red-compose.yml config > docker-compose.tmp;
  mv docker-compose.tmp docker-compose.yml
  TMP='proxy';  editEnvFile "ADAPTER_MODE";
  TMP='http://node-red'; editEnvFile "ADAPTER_HOST";
  TMP='1250'; editEnvFile "ADAPTER_PORT";
}

# Install helio docker-compose
helioExtension () {
  echo "Addin helio"
  cp docker-compose.yml docker-compose.backup
  docker-compose -f docker-compose.yml -f extensions/helio-compose.yml config > docker-compose.tmp;
  mv docker-compose.tmp docker-compose.yml
  TMP='semantic';  editEnvFile "ADAPTER_MODE";
}

# Enables shacl option in .env
shaclEnabled () {
    echo "Addin shacl"
    TMP="true"
    editEnvFile "SEMANTIC_SHACL_ENABLED";
    docker-compose -f docker-compose.yml -f extensions/shacl-compose.yml config > docker-compose.tmp;
    mv docker-compose.tmp docker-compose.yml
}

# Enables odrl option in .env
odrlEnabled () {
    TMP="true"
    editEnvFile "SEMANTIC_ODRL_ENABLED";
    docker-compose -f docker-compose.yml -f extensions/helio-compose.yml config > docker-compose.tmp;
    mv docker-compose.tmp docker-compose.yml
}

# Registers Node in auroral
registerInPlatform () {
  # echo "Registering in platform"
  # Generate random password
  getRandomPassword
  # Store to .env file
  PASSWORD=$TMP; editEnvFile "GTW_PWD";
  # REGISTRATION_BODY="{\"keyid\":\"${PLATFORM_KEYID}\",\"secret\":\"${PLATFORM_SECRET}\",\"node\":{\"pubkey\":\"${PUBKEY}\",\"name\": \"${NAME}\",\"type\": \"Auroral\",\"password\": \"${PASSWORD}\"}}"
  REGISTRATION_BODY="{\"keyid\":\"${PLATFORM_KEYID}\",\"secret\":\"${PLATFORM_SECRET}\",\"node\":{\"name\": \"${NAME}\",\"type\": \"Auroral\",\"password\": \"${PASSWORD}\"}}"
  URL=${AURORAL_URL}api/external/v1/node
  AGID=$(curl  -o - --silent -X POST  -H "Content-Type: application/json" -d "${REGISTRATION_BODY}" "${URL}" | perl -wne '/\"agid\":"(.*)"/i and print $1')
  if [ -z ${AGID} ]; then
    echo "Error registering gateway"
    exit 1
  fi
  echoBlue "Node registered in platform: ${AGID}"

}

# Send public key to platform
sendPubKeyToPlatform () {
  # Escape pubkey
  PUBKEY_ESCAPED=${PUBKEY//$'\n'/\\n}
  PUBKEY_BODY="{\"keyid\":\"${PLATFORM_KEYID}\",\"secret\":\"${PLATFORM_SECRET}\",\"pubkey\": \"${PUBKEY_ESCAPED}\"}"
  PUBKEY_URL=${AURORAL_URL}api/external/v1/node/${AGID}
  # RESPONSE=$(curl  -o - --silent -X PUT  -H "Content-Type: application/json" -d "'${PUBKEY_BODY}'" "${PUBKEY_URL}" | perl -wne '/\"message\":"(.*)"/i and print $1')
  RESPONSE=$(curl  -o - --silent -X PUT  -H "Content-Type: application/json" -d "${PUBKEY_BODY}" "${PUBKEY_URL}")
  if [ -z "$RESPONSE" ]; then
    echo "Error storing pubkey to platform"
    exit 1
  fi
  echoBlue "Public key stored in platform"
}

# Removes Node from auroral
removeNodeInPlatform () {
  DELETE_URL=${AURORAL_URL}api/external/v1/node/${AGID}/delete
  DELETE_BODY="{\"keyid\":\"${PLATFORM_KEYID}\",\"secret\":\"${PLATFORM_SECRET}\"}"
  echo "URL: ${DELETE_URL}"
  RESPONSE=$(curl  -o - --silent -X POST  -H "Content-Type: application/json" -d "${DELETE_BODY}" "${DELETE_URL}")
  if [ -z "$RESPONSE" ]; then
    echo "Error removing node from platform"
    exit 1
  fi
  echoBlue "Node removed from platform"
}

# Stops the APP with docker-compose
stopAP () {
  echoBlue 'Stopping' 
  docker-compose down
}

# Removes all edited files and create clean node
resetInstance () {
  # Removing all settings
  echo "-r RESET AP";
   if [ $INITIALISED == 1 ]; then
    stopAP
  fi
  # All volumes
  docker-compose down -v
  mv docker-compose.backup docker-compose.yml  > /dev/null 2>&1
  # .env
  rm ".env" > /dev/null 2>&1
  echoBlue "Node instance deleted... Please remove your Access Point credentials in AURORAL website if no longer needed"
}

# Exit script
# If it was not initialised - remove all files
exitAndClean () {
  if [[ $INITIALISED == '0' ]]; then
    rm ".env" > /dev/null 2>&1
    mv docker-compose.backup docker-compose.yml  > /dev/null 2>&1
  fi
  if [ -z "$1" ]; then 
    exit $1
  else
    exit 0
  fi
}

#----------------------------------------------------------
# Initial checks
#----------------------------------------------------------

getMachine
getArch
testDependencies "${DEPENDENCIES[@]}"

# Fill INITIALISED variable
checkIfInitialised
if [[ $INITIALISED == '0' ]]; then
  #  Create .env file
  cp $ENV_EXAMPLE $ENV_FILE
  # Create docker-compose.backup file
  cp docker-compose.yml docker-compose.backup
fi

# Parse parameters
while getopts ":he:NHSOt:P:A:g:i:k:s:n:Dd" opt; do
    case $opt in
        h)  echo "$USAGE"
            exitAndClean 0
            ;;
        e)  # set enviroment
            if [ $OPTARG = "prod" ]; then
                AURORAL_URL=$AURORAL_URL_PRODUCTION
                
            elif [ $OPTARG = "dev" ]; then
                AURORAL_URL=$AURORAL_URL_DEVELOPMENT
            else
                echoWarn "Unknown enviroment: $OPTARG"
                exitAndClean 1
            fi
            ENV=$OPTARG
            ;;
        S)  # SHACL
            shaclEnabled
            ;;
        O)  # ODRL
            odrlEnabled
            ;;
        k)  # token
            PLATFORM_KEYID=$OPTARG
            ;;
        s)  # token
            PLATFORM_SECRET=$OPTARG
            ;;
        P)  # port
            TMP=$OPTARG; editEnvFile "EXTERNAL_PORT";
            PORT=$OPTARG
            ;;
        A)  # ADAPTER mode (dummy, custom, helio, nodered)
            if [ $OPTARG = "dummy" ]; then
                TMP='dummy';  editEnvFile "ADAPTER_MODE";
            elif [ $OPTARG = "custom" ]; then
                TMP='semantic';  editEnvFile "ADAPTER_MODE";
            elif [ $OPTARG = "nodered" ]; then
                nodeRedExtension
            elif [ $OPTARG = "helio" ]; then
                helioExtension
            else
                echoWarn "Unknown adapter mode: $OPTARG"
                exitAndClean 1
            fi
            ;;
        n) # Name
            NAME=$OPTARG
            ;;
        d) # Delete node without removing from platform
            echoWarn "Destroying node without removing from platform"
            if [[ $INITIALISED == 1 ]]; then 
              echoBlue "Already initialised."
              getAgidFromEnvFile
              resetInstance
              exitAndClean 0
            fi
            echoBlue 'Node not initialised - exit'
            exitAndClean 0
            ;;
        D) # DESTROY node
            echoWarn "Destroying node locally and in platform"
             if [ $INITIALISED == 1 ]; then 
              echoBlue "Already initialised."
              getAgidFromEnvFile
              removeNodeInPlatform
              resetInstance
              exitAndClean 0
            fi
            echoBlue 'Node not initialised - exit'
            exitAndClean 0
            ;;
        *)
            echo "invalid command: $OPTARG"
            echo "$USAGE"
            exitAndClean 1   
            ;;
    esac
done

#----------------------------------------------------------
# Main
#----------------------------------------------------------


# test required parameters
if [ -z "$PLATFORM_KEYID" ]; then
        echo 'Please pass -k KEYID' >&2
        exitAndClean 1
fi

# test required parameters
if [ -z "$PLATFORM_SECRET" ]; then
        echo 'Please pass -s SECRET' >&2
        exitAndClean 1
fi

# # Check if already initialised
if [ $INITIALISED == 1 ]; then 
  echoBlue "Already initialised."
  getAgidFromEnvFile
  echo "Recreating  certificates"
  generateCertificates
  sendPubKeyToPlatform
  exit
fi

TMP=$AURORAL_URL"api/gtw/v1/"; editEnvFile "NM_HOST";

# Register in platform
registerInPlatform

# Fill AGID
TMP=$AGID; editEnvFile "GTW_ID";
# Fill PASSWORD
TMP=$PASSWORD; editEnvFile "GTW_PWD";
# COMPOSE_PROJECT_NAME
TMP=$AGID;
TMP="aur-node_${TMP:0:8}"; editEnvFile "COMPOSE_PROJECT_NAME"; 

# Generate certificates and write pubkey to file  
generateCertificates
# writePubKeyToFile

sendPubKeyToPlatform

echoBlue "Initialisation completed. Node ready to start - docker-compose up -d"
