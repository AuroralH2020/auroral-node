# AURORAL_NODE #

This README documents the node part of AURORAL platform, which is funded by European Union’s Horizon 2020 Framework Programme for Research and Innovation under grant agreement no 101016854 AURORAL.

### Used components ###
Node contains multiple components:
- AURORAL agent
  - custom component that hande all API requests and contains all logic
  - required
- Redis
  - in memory data store used for caching
  - optional
- Nginx
  - proxy server handling request redirection to agent
  - required
- AURORAL gateway
  - java application handling commmunication over XMPP with AURORAL network
  - required
- Wothive + Triplestore
  - semantic adapter 
  - optional
- AURORAL DLT Client
  - Fabric hyperledger client
  - optional
- Adapter
  - Connection to underlying smart infrastructure
  - optional

WoT, DLT and adapter are under development and are not enabled or included by default
  
### Requirements ###
- Docker
- Docker-compose
- Available architecture images: amd64, arm64 or armv7 (RaspberryPi and similar)

### Deployment ###

Docker-compose is the preferred deployment method

1. Create new *AP* in AURORAL neighborhood manager 
2. Create your *.env* configuration file based on *env.example*
   -  *GTW_ID* from AURORAL neighborhood manager
   -  *GTW_PWD* defined in AURORAL neighborhood manager
3.  Update `<identity>` tag in `gateway/GatewayConfig.xml` with your generated *AGID*
4.  Generate certificate pair with script `./gateway/keystore/genkeys.sh` and copy content of *platform-pubkey.pem* to AURORAL dashboard (key button)
5.  By default is choosed version *amd64 / arm64*. If you want to run on *armv7*, please change docker images in *docker-compose.yml* file
6.  Create folders *agent/imports* and *agent/exports*
7.  run *docker-compose up -d*

### FAQ ###
- message `Warn UNAUTHORIZED`: check step 2-4
- message `Permission denied`: there is a problem with permissions on Linux machines. You have to change permission to 755
  - *chmod -R 755 ./nginx*
  - *chmod -R 755 ./gateway*
  - *chmod -R 755 ./redis*
- Adapter - in some next revision will be also included generic adapter, which will allow you to interact with items. For now is adapter in *dummy mode*, so it always return same fake value.
- SSL and basic auth - this can be defined in *nginx.conf* file

### Who do I talk to? ###

Developed by bAvenir

* jorge.almela@bavenir.eu
* peter.drahovsky@bavenir.eu