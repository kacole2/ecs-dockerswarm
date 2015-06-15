#!/usr/bin/env bash
#Created by Kendrick Coleman of the EMC {code} Team and Licensed under MIT.
#Please visit us at emccode.github.io
#This script will prepare an Ubuntu Host for running an ECS container. 
#This has been properly tested with Docker Machine's default image in AWS.

#Read in variable arguments from command line
if [ -z "$1" ]; then
  echo "You forgot to specify 3 IP Addresses"
  exit 1
fi

case "$1" in  
     *\ * )
           echo "Please remove all spaces and have IP addresses as comma seperated values"
  		   exit 1
          ;;
esac

VOL="$2"
if [ -z "$2" ]; then
  VOL="xvdf"
  echo "Using xvdf as Volume mount"
fi

#update system and install xfs
echo "Updating Debian/Ubuntu"
apt-get update -y
echo "Install XFS Tools"
apt-get install xfsprogs -y

#create the seeds file
echo "Creating Seeds File"
printf '%s' $1 > seeds

#create network.json file
echo "Creating The network.json File"
hn=$(hostname)
ip=$(/sbin/ifconfig eth0 | grep 'inet addr:' | cut -d: -f2 | awk '{ print $1}')
printf '{"private_interface_name":"eth0","public_interface_name":"eth0","hostname":"%s","public_ip":"%s"}' $hn $ip > network.json

#create some folders, set permissions, and format the attached volume
echo "Creating /ecs/uuid-1 folder"
mkdir -p /ecs/uuid-1

echo "Formatting attached volume as XFS"
mkfs.xfs /dev/$VOL

echo "Mounting attached XFS volume to /ecs/uuid-1"
mount /dev/$VOL /ecs/uuid-1

echo "Adding /dev/$VOL mount to /etc/fstab"
echo "/dev/$VOL /ecs/uuid-1 xfs defaults 0 0" >> /etc/fstab

echo "Mounting /ecs/uuid-1"
mount -a

echo "Creating symlink"
ln -s /bin/grep /usr/bin/grep

echo "Downloading additional_prep.sh"
curl -O https://raw.githubusercontent.com/emccode/ecs-dockerswarm/master/additional_prep.sh

echo "Changing additional_prep.sh Permissions"
chmod 777 additional_prep.sh

echo "Starting the additional prep on attached volume"
./additional_prep.sh /dev/$VOL

echo "Changing /ecs Permissions"
chown -R 444 /ecs

echo "Creating /host/data folder"
mkdir -p /host/data
echo "Creating /host/files folder"
mkdir -p /host/files

echo "Copying network.json to /host/data"
cp network.json /host/data
echo 'Copying seeds to /host/files'
cp seeds /host/files

echo "Changing /host Permissions"
chown -R 444 /host	

echo "Creating /var/log/vipr/emcvipr-object folder"
mkdir -p /var/log/vipr/emcvipr-object
echo "Changing /var/log/vipr/emcvipr-object Permissions"
chown 444 /var/log/vipr/emcvipr-object
echo "Creating /data folder"
mkdir /data
echo "Changing /data Permissions"
chown 444 /data
echo "Host has been successfully prepared"