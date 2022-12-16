#!/usr/bin/env python3
# Node initialisation script
# Author: Peter Drahovsky, bAvenir
# First version - only unattended mode is supported

import os
import argparse
import platform
import sys
import subprocess
import re 
import secrets
import requests


# Response codes:
# 0 - OK
# 1 - Deppendencies not installed
# 2 - Argument error
# 3 - Could not communicate with platform
# 4 - Could not generate certificates
# 5 - Docker related error
# 6 - Node is not initialised 
# 7 - Node is already initialised

version = '0.1'

# Define variables
dependensies=["docker", "docker-compose"]
auroral_url_production="https://auroral.bavenir.eu/"
auroral_url_development="https://auroral.dev.bavenir.eu/"
auroral_url=''

# Parse command line arguments

# Instantiate the parser
parser = argparse.ArgumentParser(description='Initialisation script for Auroral node')

# Required
parser.add_argument('-k', '--keyid', nargs='?', dest='keyid', type=str, help='token for communication with platform')
parser.add_argument('-s' '--secret', nargs='?', dest='secret', type=str, help='secret for communication with platform')

# Optional arguments
parser.add_argument('-p', '--port', dest='port', type=int, nargs='?',  help='Port for Agent API (default: 81)')
parser.add_argument('-e', '--env', dest='env', default='dev', type=str, nargs='?', choices=['dev', 'prod'], help='Which platform to use (default: dev)')
parser.add_argument('-a', '--adapter', dest='adapter_mode', default='dummy', type=str, nargs='?', choices=['dummy', 'custom', 'helio', 'nodered'], help='ADAPTER mode')
parser.add_argument('-n', '--name', dest='node_name', default=platform.node(), type=str, nargs='?', help='Your node name (default: hostname)')
# Optional flags
parser.add_argument('-S', '--SHACL', dest='use_shacl', action='store_true', help='Use SHACL validation')
parser.add_argument('-O', '--ODRL', dest='use_odrl', action='store_true', help='Use ODRL validation')
parser.add_argument('-u', '--unattended', dest='unattended', action='store_true', help='Use unattended mode')
parser.add_argument('-d', '--deleteLocal', dest='unregisterLocal', action='store_true', help='Delete node locally')
parser.add_argument('-D', '--deleteRemote', dest='unregisterGlobal', action='store_true', help='Delete node from platform and locally')
parser.add_argument('-b', '--backupNode', dest='backupNode', action='store_true', help='Create tgz backup of node')
parser.add_argument('-r', '--restoreNode', dest='restoreNode', action='store_true', help='Restores node from backup')
parser.add_argument('-c', '--regenerateCertificates', dest='regenerateCertificates', action='store_true', help='Regenerate certificates for gateway and send them to platform')
parser.add_argument('-A', '--showAgid', dest='showAgid', action='store_true', help='Once registered, shows AGID to stdout')
parser.add_argument('-v', '--version', action='version', version=version)

configuration = {
    # Default values
    'env': 'dev',
    'node_name': platform.node(),
}
def closeScript(code: int):
    if(code == 0 or code == 7):
        if(args and 'showAgid' in args and args.showAgid):
            # Extract agid
            with open('.env', 'r') as file:
                envFile = file.read()
                agid = re.search('GTW_ID=(.*)', envFile).group(1)
                print(agid)
    exit(code)

def printProgress(*args, **kwargs):
    print(*args, file=sys.stderr, **kwargs)
    
def checkIfInitialised():
    # printProgress("Checking if initialised")
    return os.path.exists('.env')

def backupComposeFile():
    # printProgress("Backing up docker-compose.yml")
    if not os.path.exists('./docker-compose.backup'):
        os.system('cp ./docker-compose.yml ./docker-compose.backup')  
    return 

def readEnvExampleFile()-> str:
    # printProgress("Reading .env file")
    with open('./env.example', 'r') as file:
        return file.read()

def writeEnvFile(envFile: str):
    # printProgress("Writing .env file")
    with open('./.env', 'w') as file:
        file.write(envFile)

def generateCertificatesGtw() -> str:
    printProgress("Generating certificates for gateway")
    result = subprocess.run('''docker-compose run  --rm --entrypoint "/bin/bash -c \
    'cd  /gateway/persistance/keystore && \
    ./genkeys.sh > /dev/null 2>&1  && \
    cat gateway-pubkey.pem '" gateway''', shell=True, capture_output=True,)
    if result.returncode != 0:
        printProgress("ERROR: sending certificate to platform")
        printProgress(result.stderr)
        closeScript(4)
    return result.stdout

# return agid, password
def registerInPlatform(name: str) -> tuple[str, str]:
    printProgress("Registering in platform")
    # Generate random password
    password = secrets.token_urlsafe(20)
    # Send request to platform
    url = auroral_url + 'api/external/v1/node'
    payload = {
        'keyid': args.keyid,
        'secret': args.secret,
        'node': {
            'name': configuration['node_name'],
            'password': password,
            'type': 'Auroral'
        }
    }
    x = requests.post(url, json = payload)

    if x.status_code != 200:
        printProgress("ERROR: Could not register in platform")
        closeScript(3)
    return [x.json().get('message').get('agid'), password]

# unregister in platform
def unregisterInPlatform():
    printProgress("Unregistering node from platform")
    with open('.env', 'r') as file:
        envFile = file.read()
        agid = re.search('GTW_ID=(.*)', envFile).group(1)
        url = re.search('NM_HOST=(.*)', envFile).group(1)
        url = url.replace('api/gtw/v1/', 'api/external/v1/node/'+ agid + '/delete')
        url = url.replace('"', '')
        payload = {
            'keyid': args.keyid,
            'secret': args.secret
        }
        x = requests.post(url, json = payload)

    if x.status_code != 200:
        printProgress("ERROR: Could not unregister from platform")
        closeScript(3)

def sendCertificateToPlatform(agid: str,  pubkey: str):
    printProgress("Sending certificate to platform")
    url = auroral_url + 'api/external/v1/node/' + agid
    payload = {
        'keyid': args.keyid,
        'secret': args.secret,
        'pubkey': pubkey.decode("utf-8") 
    }
    x = requests.put(url, json = payload)
    if x.status_code != 200:
        printProgress("ERROR: Could not send certificate to platform")
        closeScript(3)

def checkRequirements():
    for dep in dependensies:
        result = subprocess.run(dep + ' -v', shell=True, capture_output=True)
        if result.stderr:
            printProgress("ERROR: dependency" + dep + " not found")
            closeScript(1)
    # Check if docker is running
    result = subprocess.run('docker info', shell=True, capture_output=True)
    if result.returncode != 0:
        printProgress("ERROR: docker not running")
        closeScript(5)
    return

def unregisterLocal():
    printProgress("Unregistering local")
    # run docker-compose down
    os.system('docker-compose down -v')
    # remove docker-compose.backup file
    if os.path.exists('./docker-compose.backup'):
        os.system('rm ./docker-compose.yml')
        os.system('mv ./docker-compose.backup ./docker-compose.yml')
    # remove .env file
    if os.path.exists('./.env'):
        os.system('rm ./.env')

def checkIfVolumeExists(volumeName: str) -> bool:
    result = subprocess.run('docker volume ls', shell=True, capture_output=True)
    if result.returncode != 0:
        printProgress("ERROR: could not list volumes")
        closeScript(5)
    if volumeName in result.stdout.decode("utf-8"):
        return True
    return False

# Backup
def backupNode():
    printProgress("Backing up node")
    if(not checkIfInitialised()):
        printProgress("ERROR: Node not initialised!")
        closeScript(6)
    with open('.env', 'r') as file:
        envFile = file.read()
        COMPOSE_PREFIX = re.search('COMPOSE_PROJECT_NAME=(.*)', envFile).group(1)
    # run docker-compose down
    os.system('docker-compose down')
    # Create docker container with all the volumes mounted
    backup_command = '''docker run --rm -ti  \
                -v ''' + os.getcwd() +''':/hostdir '''
    # Add volumes
    # Gateway
    backup_command += '-v ' + COMPOSE_PREFIX + '_aur_gateway:/backup/gateway '
    # Redis
    backup_command += '-v ' + COMPOSE_PREFIX + '_aur_redis:/backup/redis '
    # Triplestore
    backup_command += '-v ' + COMPOSE_PREFIX + '_aur_triplestore:/backup/triplestore '
    if(checkIfVolumeExists(COMPOSE_PREFIX + '_aur_node-red')):
        # Node-Red
        backup_command += '-v ' + COMPOSE_PREFIX + '_aur_node-red:/backup/node-red '
    if(checkIfVolumeExists(COMPOSE_PREFIX + '_helio-db')):
        # Helio
        backup_command += '-v ' + COMPOSE_PREFIX + '_helio-db:/backup/helio '
    if(checkIfVolumeExists(COMPOSE_PREFIX + '_validation-db')):
        # Validation
        backup_command += '-v ' + COMPOSE_PREFIX + '_validation-db:/backup/shacl '
    # Command end
    backup_command += '''ubuntu /bin/bash -c 'tar cvf /hostdir/node_backup.tar /backup/ /hostdir/.env /hostdir/docker-compose.yml /hostdir/docker-compose.backup' '''
    os.system(backup_command)
    printProgress("Backup created in node_backup.tar")


# Restore
def restoreNode():
    printProgress("Restoring node")
    first_restore_command = '''docker run --rm -ti -v ''' + os.getcwd() + ''':/hostdir ubuntu /bin/bash -c \
        'tar -xvf  /hostdir/node_backup.tar ' '''
    os.system(first_restore_command)
    printProgress("docker-compose.yml, docker-compose.backup and .env restored")
    # Extract COMPOSE_PROJECT_NAME
    with open('.env', 'r') as file:
        envFile = file.read()
        COMPOSE_PREFIX = re.search('COMPOSE_PROJECT_NAME=(.*)', envFile).group(1)
    # run docker-compose down --no-start to create volumes
    os.system('docker-compose up --no-start')
    second_restore_command = '''docker run --rm -ti  \
                -v ''' + os.getcwd() +''':/hostdir '''
    # Add volumes
    # Gateway
    second_restore_command += '-v ' + COMPOSE_PREFIX + '_aur_gateway:/backup/gateway '
    # Redis
    second_restore_command += '-v ' + COMPOSE_PREFIX + '_aur_redis:/backup/redis '
    # Triplestore
    second_restore_command += '-v ' + COMPOSE_PREFIX + '_aur_triplestore:/backup/triplestore '
    if(checkIfVolumeExists(COMPOSE_PREFIX + '_aur_node-red')):
        # Node-Red
        second_restore_command += '-v ' + COMPOSE_PREFIX + '_aur_node-red:/backup/node-red '
    if(checkIfVolumeExists(COMPOSE_PREFIX + '_helio-db')):
        # Helio
        second_restore_command += '-v ' + COMPOSE_PREFIX + '_helio-db:/backup/helio '
    if(checkIfVolumeExists(COMPOSE_PREFIX + '_validation-db')):
        # Validation
        second_restore_command += '-v ' + COMPOSE_PREFIX + '_validation-db:/backup/shacl '
    # Command end
    second_restore_command += '''ubuntu /bin/bash -c 'tar -xvf /hostdir/node_backup.tar ' '''
    os.system(second_restore_command)


def initialise():
    global auroral_url

    # Check if already initialised
    if checkIfInitialised():
        printProgress("Already initialised")
        closeScript(7)
    
    printProgress('Initialising...')
    # Backup docker-compose.yml
    backupComposeFile()
    # Read .env file
    envFile = readEnvExampleFile()
    # Edits
    if 'adapter_mode' in configuration:
        if(configuration['adapter_mode'] == 'dummy'):
            envFile = re.sub(r'ADAPTER_MODE=.*\n', 'ADAPTER_MODE=dummy\n', envFile)
        elif(configuration['adapter_mode'] == 'custom'):
            envFile = re.sub(r'ADAPTER_MODE=.*\n', 'ADAPTER_MODE=semantic\n', envFile)
        elif(configuration['adapter_mode'] == 'nodered'):
            # Set .env file
            envFile = re.sub(r'ADAPTER_MODE=.*\n', 'ADAPTER_MODE=proxy\n', envFile)
            envFile = re.sub(r'ADAPTER_HOST=.*\n', 'ADAPTER_HOST=http://node-red\n', envFile)
            envFile = re.sub(r'ADAPTER_PORT=.*\n', 'ADAPTER_PORT=1250\n', envFile)
        elif(configuration['adapter_mode'] == 'helio'):
            # Set .env file
            envFile = re.sub(r'ADAPTER_MODE=.*\n', 'ADAPTER_MODE=semantic\n', envFile)
        else:
            printProgress("ERROR: Unknown extension")
            closeScript(1)
    if 'env' in configuration:
        if configuration['env'] == 'dev':
            auroral_url = auroral_url_development
            envFile = re.sub(r'XMPP_SERVICE=.*\n', 'XMPP_SERVICE=xmpp://auroral.dev.bavenir.eu:5222\n', envFile)
            envFile = re.sub(r'XMPP_DOMAIN=.*\n', 'XMPP_DOMAIN=auroral.dev.bavenir.eu\n', envFile)
            envFile = re.sub(r'NODE_ENV=.*\n', 'NODE_ENV=development\n', envFile)
        elif configuration['env'] == 'prod':
            auroral_url = auroral_url_production
            envFile = re.sub(r'XMPP_SERVICE=.*\n', 'XMPP_SERVICE=xmpp://xmpp.auroral.bavenir.eu:5222\n', envFile)
            envFile = re.sub(r'XMPP_DOMAIN=.*\n', 'XMPP_DOMAIN=auroral.bavenir.eu\n', envFile)
            envFile = re.sub(r'NODE_ENV=.*\n', 'NODE_ENV=production\n', envFile)
    if 'port' in configuration:
        envFile = re.sub("EXTERNAL_PORT=.*\n", "EXTERNAL_PORT=" + str(configuration['port'])+'\n', envFile)
    if 'use_shacl' in configuration:
        # Edit env file
        envFile = re.sub("SEMANTIC_SHACL_ENABLED=.*\n", "SEMANTIC_SHACL_ENABLED=true\n", envFile)
    if 'use_odrl' in configuration:
        # Edit env file
        envFile = re.sub("SEMANTIC_ODRL_ENABLED=.*\n", "SEMANTIC_ODRL_ENABLED=true\n", envFile)
    
    # Register in platform
    agid, password = registerInPlatform(configuration['node_name'])
    # Save agid and password to .env file
    envFile = re.sub(r'GTW_ID=.*\n', 'GTW_ID=' + agid + '\n', envFile)
    envFile = re.sub(r'GTW_PWD=.*\n', 'GTW_PWD=' + password + '\n', envFile)
    envFile = re.sub(r'COMPOSE_PROJECT_NAME=.*\n', 'COMPOSE_PROJECT_NAME=aur-node_' + agid[0:8] + '\n', envFile)
    # Redis password 
    envFile = envFile.replace('DB_PASSWORD=changeme', 'DB_PASSWORD=' + secrets.token_urlsafe(30) )  
    # Write .env file
    writeEnvFile(str(envFile))
    # Install docker-compose extensions
    if 'use_odrl' in configuration:
        # Add docker-compose extension
        os.system('docker-compose -f docker-compose.yml -f extensions/helio-compose.yml config > docker-compose.tmp;')  
        os.system('mv docker-compose.tmp docker-compose.yml')
    if 'use_shacl' in configuration:
        # Add docker-compose extension
        os.system('docker-compose -f docker-compose.yml -f extensions/shacl-compose.yml config > docker-compose.tmp;')  
        os.system('mv docker-compose.tmp docker-compose.yml')
    if 'adapter_mode' in configuration:
        if(configuration['adapter_mode'] == 'nodered'):
            # Add docker-compose extension
            os.system('docker-compose -f docker-compose.yml -f extensions/node-red-compose.yml config > docker-compose.tmp;')  
            os.system('mv docker-compose.tmp docker-compose.yml')
        elif(configuration['adapter_mode'] == 'helio'):
            # Add docker-compose extension
            os.system('docker-compose -f docker-compose.yml -f extensions/helio-compose.yml config > docker-compose.tmp;')  
            os.system('mv docker-compose.tmp docker-compose.yml')
    # Generate certificate
    pubkey = generateCertificatesGtw()
    # Send certificate to platform
    sendCertificateToPlatform(agid, pubkey)


def mainUnattended():
    # Check if -k and -s are defined
    if not args.keyid or not args.secret:
        printProgress("ERROR: -k and -s are required in unattended mode")
        closeScript(1)
    
    # Fill config
    if args.port:
        configuration['port'] = args.port
    if args.env:
        configuration['env'] = args.env
    if args.node_name:
        configuration['node_name'] = args.node_name
    if args.use_shacl:
        configuration['use_shacl'] = args.use_shacl
    if args.use_odrl:
        configuration['use_odrl'] = args.use_odrl
    if args.adapter_mode:
        configuration['adapter_mode'] = args.adapter_mode
    if args.unregisterGlobal:
        if(not checkIfInitialised()):
            printProgress("Node not initialised!")
            closeScript(7)
        unregisterInPlatform()
        unregisterLocal()
        closeScript(0)
    if args.unregisterLocal:
        if(not checkIfInitialised()):
            printProgress("Node not initialised!")
            closeScript(6)
        unregisterLocal()
        closeScript(0)
    if args.regenerateCertificates:
        if(not checkIfInitialised()):
            global auroral_url
            printProgress("Node not initialised!")
            closeScript(6)
        with open('.env', 'r') as file:
            envFile = file.read()
            agid = re.search('GTW_ID=(.*)', envFile).group(1)
            auroral_url = re.search('NM_HOST=(.*)', envFile).group(1)
            auroral_url = auroral_url.replace('api/gtw/v1/', '')[1:-1]
        pubkey = generateCertificatesGtw()
        # Send certificate to platform
        sendCertificateToPlatform(agid, pubkey)
        closeScript(0)

    # Run initialisation with config
    initialise()


def mainInteractive():
    printProgress('Interactive mode not implemented yet - please use unattended (-u). Closing...')
    closeScript(1)

# Parse args
try:
    args = parser.parse_args()
except SystemExit:
    closeScript(2)


def main() -> int:
    # Check requirements
    checkRequirements()

    # Check if backup / restore is requested
    if args.backupNode:
        backupNode()
        closeScript(0)
    if args.restoreNode:
        restoreNode()
        closeScript(0)

    if args.unattended:
       mainUnattended()
    else :
       mainInteractive()
    closeScript(0)

if __name__ == '__main__':
    main()
