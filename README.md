ecs-dockerswarm
======================
ecs-dockerswarm is a tutorial on using EMC's ECS as a multi-node Docker container setup using Docker Swarm, Docker Machine and Docker Compose.

## Description
[EMC Elastic Cloud Storage (ECS)](https://www.emc.com/storage/ecs-appliance/index.htm?forumID) is a software-defined cloud storage platform that exposes S3, Swift, and Atmos endpoints. This walk-through will demonstate the setup of a 3 Node ECS Cluster using Docker containers and Docker tools.

## Requirements
* Each ECS node requires 16GB of RAM and an attached volume with a minimum of 512GB. The attached volume stores persistent data that is replicated between  three nodes.
* [Docker Machine](https://docs.docker.com/machine/) installed on your local laptop. Use `0.3.0-rc2` or later [Docker Machine Releases](https://github.com/docker/machine/releases) or until all `--swarm` commands are merged into a stable release.
* [Docker Compose](https://docs.docker.com/compose/) installed on your local laptop. Use `1.3.0 RC2` or later [Docker Compose Releases](https://github.com/docker/compose/releases).
* [Docker Client](https://docs.docker.com/machine//) installed on your local laptop. (follow Docker Client installation directions)

This is for test and development purposes. Not for production use. Please reach out to your local EMC SE for information on production usage. EMC ECS ships as a commodity storage appliance for production use.

## Lets Get Going

#### Setup 3 Ubuntu Hosts with Docker Swarm using Docker Machine
The following examples use Ubuntu. Ubuntu is a requirement for using the setup scripts.

[Docker Machine](https://docs.docker.com/machine/) examples are shown with the AWS driver with the standard Ubuntu AMI. However, any cloud or compatible infrastructure with Docker Machine can be used.

1. The following *inbound* ports must be opened to your Docker-Machine hosts. Within AWS, this is called a *Security Group*

    | Port      | Protocol  | Reason                                |
    | ------    |:---------:| -------------------------------------:|
    | 22        | TCP       | SSH                                   |
    | 2376      | TCP       | Docker                                |
    | 3376      | TCP       | Docker Swarm |
    | 443       | TCP       | HTTPS GUI access for ECS |
    | 4443      | TCP       | API access for ECS |
    | 9898, 1098,1198,1298      | TCP       | ECS nodes to ECS nodes in other sites |
    | 8088, 9888      | TCP       | ECS nodes to ECS nodes in other sites |
    | 2181      | TCP       | ECS nodes to ECS nodes in other sites |
    | 9069      | TCP       | ECS nodes to ECS nodes in other sites |
    | 9094-9099 | TCP       | ECS nodes to ECS nodes in other sites |
    | 9201-9210 | TCP       | ECS nodes to ECS nodes in other sites |
    | 9100-9101 | TCP       | DT Query |
    | 3218      | TCP       | CAS API |
    | 9010-9011 | TCP       | Object Control HTTP/HTTPS |
    | 9020-9021 | TCP       | S3 Object API over HTTP/HTTPS |
    | 9022-9023 | TCP       | ATMOS Object API over HTTP/HTTPS |
    | 9024-9025 | TCP       | Swift Object API over HTTP/HTTPS |
    | 9028-9029 | TCP       | API Server over HTTP/HTTPS |
    | 9040      | TCP       | HDFS Service |
    | 1095, 1096, 5120, 5123, 7578, 9099| TCP       | Management access to Remote Management Module of ECS nodes |
    
    all port information can be found on the [ECS Security Configuration Guide](https://community.emc.com/docs/DOC-45012)

2. Create a [Docker Swarm](https://docs.docker.com/swarm/) ID. 

    1. This can be done by using `docker run swarm:0.3.0-rc2 create` on any host that can run Docker. If no host is available, use Docker Machine to create the host:
    ```
    docker-machine -D create --driver amazonec2 --amazonec2-access-key MYKEY --amazonec2-secret-key MYSECRETKEY --amazonec2-vpc-id vpc-myvpc swarm-create
    ```
    2. Connect to the Docker Machine: `docker-machine env swarm-create`
    3. Get shell access: `eval "$(docker-machine env swarm-create)"`
    4. Run the Swarm container: `docker run swarm:0.3.0-rc2 create` (currently must use the latest which is `v0.3.0-rc2` to support Docker Compose)
    5. The output will have a unique token such as `b353bb30194d59ab33e4d47c012ee895`.
3. Create a [Docker Swarm](https://docs.docker.com/swarm/) 3 node cluster using [Docker Machine](https://docs.docker.com/machine/). Each node requires:
    - a root drive of >=20GB
    - 28GB RAM or more
    - A Swarm token using image `0.3.0-rc2` or higher or until this is merged until this becomes the stable release

    1. Create Swarm Master: 
    ```
    docker-machine -D create --driver amazonec2 --amazonec2-access-key MYKEY --amazonec2-secret-key MYSECRETKEY --amazonec2-vpc-id vpc-myvpc --amazonec2-instance-type r3.xlarge --amazonec2-root-size 50 --swarm --swarm-image=swarm:0.3.0-rc2 --swarm-master --swarm-discovery token://b353bb30194d59ab33e4d47c012ee895 swarm-master
    ```
    2. Create Node 01: 
    ```
    docker-machine -D create --driver amazonec2 --amazonec2-access-key MYKEY --amazonec2-secret-key MYSECRETKEY --amazonec2-vpc-id vpc-myvpc --amazonec2-instance-type r3.xlarge --amazonec2-root-size 50 --swarm --swarm-image=swarm:0.3.0-rc2 --swarm-discovery token://b353bb30194d59ab33e4d47c012ee895 swarm-node01
    ```
    3. Create Node 02: 
    ```
    docker-machine -D create --driver amazonec2 --amazonec2-access-key MYKEY --amazonec2-secret-key MYSECRETKEY --amazonec2-vpc-id vpc-myvpc --amazonec2-instance-type r3.xlarge --amazonec2-root-size 50 --swarm --swarm-image=swarm:0.3.0-rc2 --swarm-discovery token://b353bb30194d59ab33e4d47c012ee895 swarm-node02
    ```
    
- note: The `-D` flag is used to look at diagnostics. It's not necessary.

#### Add A Volume to Each Node
Docker containers, by nature, are used for stateless applications. By attaching an outside volume (not the root volume), data persistence is achieved. The container running the ECS software is ephemeral and the volume containing the data can be attached to any ECS container. All ECS nodes replicate data to one another and store logs in this attached Volume. The volume needs to be >=512GB.

After the volume has been added, retrieve the mounted path. For instance, AWS uses `/dev/xvdf`. This can be retrieved by using `docker-machine ssh swarm-master "sudo fdisk -l"`, which shows the disk layout for the `swarm-master` machine.

This example shows how to attach a volume using AWS. 

  1. Login to the AWS Console
  2. Navigate to **EC2 -> Volumes -> Create Volume**
  3. Set the size to **512** or greater
  4. Set the **Availability Zone** to where your Docker Machine Hosts reside.
  5. Repeat this 2 more times so there are 3 Volumes
  6. Select 1 volume and navigate to **Actions -> Attach Volume**
  7. Attach 1 unique volume per Docker Machine Swarm host. Do not attach all three volumes to all three hosts.

#### Prepare the hosts
Each host requires a script to be ran that prepares the volumes attached as XFS and builds a multitude of folders and permissions.

1. Using Docker Machine, download the setup script from this repo
  ```
  docker-machine ssh swarm-master "curl -O https://raw.githubusercontent.com/emccode/ecs-dockerswarm/master/docker-machine-hostprep.sh"
  docker-machine ssh swarm-node01 "curl -O https://raw.githubusercontent.com/emccode/ecs-dockerswarm/master/docker-machine-hostprep.sh"
  docker-machine ssh swarm-node02 "curl -O https://raw.githubusercontent.com/emccode/ecs-dockerswarm/master/docker-machine-hostprep.sh"
  ```
2. The hosts require the **internal** IPs of all the ECS nodes in the cluster. You can retrieve all **external** IPs with `docker-machine ls` (not needed):
  ```
  NAME        ACTIVE   DRIVER      STATE     URL                     SWARM
  swarm-create   *   amazonec2   Running   tcp://52.4.23.123:2376
  swarm-master       amazonec2   Running   tcp://52.7.13.18:2376    swarm-master (master)
  swarm-node01       amazonec2   Running   tcp://54.12.23.16:2376   swarm-master
  swarm-node02       amazonec2   Running   tcp://52.7.19.173:2376   swarm-master
  ```
You will need to go into your cloud provider and get the **internal IP addresses** for each node. This will hopefully be added to `docker-machine` in the near future. Pay attention to [Issue #1342 FR: Get internal IP of cloud hosted machine](https://github.com/docker/machine/issues/1342) for when it will be baked into the master release.

3. The command to kick-off the host preparation accepts two arguments. 
    1. all three internal IP addresses as comma seperated values with no spaces such as `172.38.13.18,172.38.23.16,172.38.19.173`
    2. the mounted drive path without the `/dev/` portion such as `xvdf`. If no argument is specified, `xvdf` is the default.
    ```
    docker-machine ssh swarm-master "sudo sh docker-machine-hostprep.sh 172.38.13.18,172.38.23.16,172.38.19.173 xvdf"
    docker-machine ssh swarm-node01 "sudo sh docker-machine-hostprep.sh 172.38.13.18,172.38.23.16,172.38.19.173 xvdf"
    docker-machine ssh swarm-node02 "sudo sh docker-machine-hostprep.sh 172.38.13.18,172.38.23.16,172.38.19.173 xvdf"
    ```
4. The last output line will say `Host has been successfully prepared`

#### Docker Compose Up
The `docker-compose.yml` file will create 3 ECS containers including all  volume mounts and networking. 

1. Connect to the Docker Machine Swarm instance: `docker-machine env --swarm swarm-master`
2. Get shell access to the Swarm Cluster: `eval "$(docker-machine env --swarm swarm-master)"`
3. To test if swarm is working correctly, run `docker info` and you will see an output such as:
```
Containers: 4
Images: 3
Storage Driver:
Strategy: spread
Filters: affinity, health, constraint, port, dependency
Nodes: 3
 swarm-master: 52.7.13.18:2376
  └ Containers: 2
  └ Reserved CPUs: 0 / 4
  └ Reserved Memory: 0 B / 15.42 GiB
 swarm-node01: 54.12.23.16:2376
  └ Containers: 1
  └ Reserved CPUs: 0 / 4
  └ Reserved Memory: 0 B / 15.42 GiB
 swarm-node02: 52.7.19.173:2376
  └ Containers: 1
  └ Reserved CPUs: 0 / 4
  └ Reserved Memory: 0 B / 15.42 GiB
Execution Driver:
Kernel Version:
Operating System:
CPUs: 12
Total Memory: 94.38 GiB
Name:
ID:
Http Proxy:
Https Proxy:
No Proxy:
```
4. Copy this repo using `git clone https://github.com/emccode/ecs-docker.git` or save the `docker-compose.yml` file to a folder.
5. Navigate to your folder such as `ecs-docker`
6. Run `docker-compose up -d`. Docker Compose will be pointing towards the registerd Docker Client machine which is our swarm cluster:
```
Pulling ecsnode02 (emccode/ecsobjectsw:v2.0)...
swarm-node01: Pulling emccode/ecsobjectsw:v2.0... : downloaded
swarm-node02: Pulling emccode/ecsobjectsw:v2.0... : downloaded
swarm-master: Pulling emccode/ecsobjectsw:v2.0... : downloaded
Creating ecsdocker_ecsnode02_1...
Creating ecsdocker_ecsnode03_1...
Creating ecsdocker_ecsnode01_1...
```
7. Make sure all containers are up using `docker ps` and wait 10-15 minutes for ECS to completely load. 
```
CONTAINER ID        IMAGE                      COMMAND                CREATED             STATUS              PORTS               NAMES
9054fc14ee5a        emccode/ecsobjectsw:v2.0   "/opt/vipr/boot/boot   36 seconds ago      Up 35 seconds                           swarm-master/ecsdocker_ecsnode01_1
a90ef32ce5ec        emccode/ecsobjectsw:v2.0   "/opt/vipr/boot/boot   39 seconds ago      Up 38 seconds                           swarm-node02/ecsdocker_ecsnode03_1
e6356782748c        emccode/ecsobjectsw:v2.0   "/opt/vipr/boot/boot   39 seconds ago      Up 38 seconds                           swarm-node01/ecsdocker_ecsnode02_1
```
**Warning** It can't be guarenteed that all the containers will be spread amongst the three machines. The Docker Swarm strategy is set to `--spread` by default which means all the containers are evenly distributed across all Docker Swarm hosts. Review [Docker Swarm Advanced Scheduling](https://docs.docker.com/swarm/scheduler/strategy/) to learn more. 

#### ECS UI Access
After a few minutes, the ECS UI will be available. To access the UI, point your browser to one of the **Public IP addresses** using `https://`. You can retrieve all **external** IPs with `docker-machine ls` (not needed):
  ```
  NAME        ACTIVE   DRIVER      STATE     URL                     SWARM
  swarm-create       amazonec2   Running   tcp://52.4.23.123:2376
  swarm-master       amazonec2   Running   tcp://52.7.13.18:2376    swarm-master (master)
  swarm-node01       amazonec2   Running   tcp://54.12.23.16:2376   swarm-master
  swarm-node02       amazonec2   Running   tcp://52.7.19.173:2376   swarm-master
  ```
Username: root
Password: ChangeMe
![ecs-login-ui](https://s3.amazonaws.com/kennyonetime/ecsuilogin.png "ECS Login UI")

#### ECS Object Preparation
At this point, there are still more steps to be completed like adding the license.xml, creating the object store, etc. These steps have been automated in `object_prep.py`. This script only needs to be run once per cluster.

Download two files to one of the hosts:
```
docker-machine ssh swarm-master "curl -O https://raw.githubusercontent.com/emccode/ecs-dockerswarm/master/license.xml"
docker-machine ssh swarm-master "curl -O https://raw.githubusercontent.com/emccode/ecs-dockerswarm/master/object_prep.py"
```

Next, run the python script. In the `ECSNodes` flag, specify the Public IP address of one of the nodes. This script will take about 10-15 minutes to complete. Do not exit out of the script
```
docker-machine ssh swarm-master "sudo python object_prep.py --ECSNodes=52.7.13.18 --Namespace=ns1 --ObjectVArray=ova1 --ObjectVPool=ovp1 --UserName=emccode --DataStoreName=ds1 --VDCName=vdc1 --MethodName="
```

At this point, you can put the ECS nodes behind a load balancer and single IP/DNS name for traffic re-direction. Hooray!

## Contribution
Create a fork of the project into your own reposity. Make all your necessary changes and create a pull request with a description on what was added or removed and details explaining the changes in lines of code. If approved, project owners will merge it.

Licensing
---------
ecs-dockerswarm is freely distributed under the [MIT License](http://opensource.org/licenses/MIT). See LICENSE for details.

Support
-------
Please file bugs and issues at the Github issues page. For more general discussions you can contact the EMC Code team at <a href="https://groups.google.com/forum/#!forum/emccode-users">Google Groups</a> or tagged with **EMC** on <a href="https://stackoverflow.com">Stackoverflow.com</a>. The code and documentation are released with no warranties or SLAs and are intended to be supported through a community driven process.