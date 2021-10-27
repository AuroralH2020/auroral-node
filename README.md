# AURORAL_NODE #

This README documents the node part of AURORAL platform, which is funded by European Union’s Horizon 2020 Framework Programme for Research and Innovation under grant agreement no 101016854 AURORAL.

### Used components ###
Node contains multiple components:
- AURORAL agent [REQUIRED]
  - Custom component that hande all API requests and contains all logic.
- Redis [REQUIRED]
  - In-memory data store used for caching and persistance.
- Nginx [REQUIRED]
  - Proxy server handling request redirection to agent.
- AURORAL gateway [REQUIRED]
  - Java application handling commmunication over XMPP with AURORAL network.
- Wothive + Triplestore [OPTIONAL]
  - Semantic storage and semantic services. 
- AURORAL DLT Client [OPTIONAL] [STILL UNAVAILABLE]
  - Fabric hyperledger client.
- Adapter [REQUIRED EXCEPT FOR TESTING]
  - Connection to underlying smart infrastructure.
  - AURORAL will provide adapters for certain technologies.
  - Can be developed by the user.

WoT, DLT and adapter are under development and are not enabled or included by default.
  
### Requirements ###
- Docker
- Docker-compose
- Available architecture images: amd64, arm64 or armv7 (RaspberryPi and similar)

### Deployment ###

Docker-compose is the preferred deployment method

1. Create new *Access Point* in AURORAL neighborhood manager, Access Point section. An Access Point is an AURORAL node identity.
2. Create your *.env* configuration file based on *env.example*.
   -  Create .env file in the root directory and add:
      -  *GTW_ID* from AURORAL neighborhood manager, Access Point *AGID*.
      -  *GTW_PWD* defined in AURORAL neighborhood manager
3.  Update `<platformSecurity><identity>` tag in `gateway/GatewayConfig.xml` with your generated *AGID*, identity obtained in Neighbourhood Manager
4.  Generate certificate pair with script `./gateway/keystore/genkeys.sh` and copy content of *platform-pubkey.pem* to Neighbourhood Manager.
    - Go to Neighbourhood Manager -> Access Point section
    - Click on the *KEY* button next to your Access Point
    - Replace the contents with your *platform-pubkey.pem*. Copy all text including initial and final headers.
5.  By default is choosed version *amd64 / arm64*. If you want to run on *armv7*, please change docker images in *docker-compose.yml* file. Architectures *amd64 / arm64* will function for most modern computers and cloud servers, while *armv7* will be used in other less powerful machines as RaspberryPi.
6.  Create folders *agent/imports* and *agent/exports* under root folder [OPTIONAL]
    - mkdir agent
    - mkdir imports exports
    - Necessary backup and restore functionality using filesystem.
7.  run *docker-compose up -d*

### FAQ ###

- message `Warn UNAUTHORIZED`: check step 2-4
- message `Permission denied`: there is a problem with permissions on Linux machines. You have to change permission to 755
  - *chmod -R 755 ./nginx*
  - *chmod -R 755 ./gateway*
  - *chmod -R 755 ./redis*
- Adapter - You can run the agent in proxy mode or dummy mode.
    - Dummy - Agent will respond consumption requests with some automated random value. Use for testing.
    - Proxy - Agent will redirect the consumption requests to the host specified in the configuration file .env. In future versions we will include adapters developed in AURORAL and how to run them alongside the node. 
- SSL and basic auth - This can be set-up in *nginx.conf* file. In future versions we will include instructions to configure the access to the node with additional security. Certificates are necessary to configure the SSL connections.

### Who do I talk to? ###

Developed by bAvenir

* jorge.almela@bavenir.eu
* peter.drahovsky@bavenir.eu