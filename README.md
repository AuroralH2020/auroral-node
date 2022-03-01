# AURORAL_NODE #

This README documents the Node client of AURORAL platform, which is funded by European Union’s Horizon 2020 Framework Programme for Research and Innovation under grant agreement no 101016854 AURORAL.

The Node is the software necessary to connect an IoT infrastructure or a Service to AURORAL platform. It runs a docker environment with the necessary applications to connect to AURORAL and to use the local services offered by the Node such as the storage of semantic data or the access to the AURORAL standard API.

Visit the **[WIKI](https://github.com/AuroralH2020/auroral-node/wiki)** for technical information or the **[BLOG](https://blog.bavenir.eu/auroral/)** for tutorials and how-to articles.

### How To Start ###

In order to work with an AURORAL node it is necessary to have an AURORAL account, if you do not have one yet please register:

https://auroral.dev.bavenir.eu

After creating your account you will need to have a user with **system integrator** role, you can assign this role to your user or invite a new user to your organisation.

- To add new roles to a user you need to navigate to the organisation profile (Just click on your organisation avatar), and then select the 'Roles Management' tab, you need to have **ADMIN** role to do that (The first user of a new organisation is always **ADMIN**).
- To invite a new user you can click on the icon with a person and a plus sign (Top right corner), and invite a new user with the role **system integrator**.

Once a user with this role exists, a new tab on the side menu will appear, **Access Points**. There you can create a new access point and assign a password to it. Once the access point is created an AGID will be assigned to it. For each AURORAL Node that you wish to deploy you will need a pair AGID:password that will be requested during the configuration.

Your account is all set! Now you can proceed to install an AURORAL Node, please visit the section **NODE CLI**.

### Requirements ###

- Docker
- Docker-compose
- Available architecture images: amd64, arm64 or armv7 (RaspberryPi and similar)
- OS supported: Linux (Debian/Ubuntu)(*), MAC OS, Windows 10/11 with WSL and Raspbian

(*) Currently only tested for Linux on Debian and Ubuntu, other modern popular Linux distributions able to run Docker should also be supported.

### Node CLI ###

In order to facilitate the installation of the node we are providing an interactive script to go over the process. This scripts enables the user to initialize, just run or remove all the node files when no longer needed. Also backup is available and other features will be coming in the future.

### Who do I talk to? ###

Developed by bAvenir

* jorge.almela@bavenir.eu
* peter.drahovsky@bavenir.eu