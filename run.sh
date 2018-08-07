#!/bin/bash

echo "Export variables from config file"
source config
export $(cut -d= -f1 config| grep -v '^$\|^\s*\#' config)
envsubst < config > work_config
source work_config
export $(cut -d= -f1 work_config| grep -v '^$\|^\s*\#' work_config)

echo "Create directory for config-drives for CONTROLLER and COMPUTE"
mkdir -p config-drives/$CONTROLLER_NAME-config config-drives/$COMPUTE_NAME-config

echo "Download Ubuntu cloud image, if it doesn't exist"
wget -O /var/lib/libvirt/images/ubuntu-server-16.04.qcow2 -nc $VM_BASE_IMAGE

echo "Create two disks from image"
cp /var/lib/libvirt/images/ubuntu-server-16.04.qcow2 $CONTROLLER_HDD
cp /var/lib/libvirt/images/ubuntu-server-16.04.qcow2 $COMPUTE_HDD

echo "Generate MAC adress for external network"
export MAC_CONTROLLER_EXT=52:54:00:`(date; cat /proc/interrupts) | md5sum | sed -r 's/^(.{6}).*$/\1/; s/([0-9a-f]{2})/\1:/g; s/:$//;'`

echo "Check if SSH key exists"
if [ -e $SSH_PUB_KEY ]
then 
	echo "SSH key exists"
else
	echo "SSH key doesn't exists"
        exit 1
fi

echo "Create directory for libvirt network XMLs"
mkdir -p networks/

echo "Create external.xml from template"
envsubst < templates/external_template.xml > networks/external.xml

echo "Create internal.xml from template"
envsubst < templates/internal_template.xml > networks/internal.xml

echo "Create management.xml from template"
envsubst < templates/management_template.xml > networks/management.xml

echo "Create networks from XML templates"
virsh net-define networks/external.xml
virsh net-define networks/internal.xml
virsh net-define networks/management.xml

echo "Start networks"
virsh net-start external
virsh net-start internal
virsh net-start management

echo "Create meta-data for VMs"
envsubst < templates/meta-data_CONTROLLER_template > config-drives/CONTROLLER-config/meta-data
envsubst < templates/meta-data_COMPUTE_template > config-drives/COMPUTE-config/meta-data

echo "Create user-data for CONTROLLER"
envsubst < templates/user-data_CONTROLLER_template > config-drives/CONTROLLER-config/user-data
cat <<EOT >> config-drives/CONTROLLER-config/user-data
ssh_authorized_keys:
 - $(cat $SSH_PUB_KEY)
EOT

echo "Create user-data for COMPUTE"
envsubst < templates/user-data_COMPUTE_template > config-drives/COMPUTE-config/user-data
cat <<EOT >> config-drives/COMPUTE-config/user-data
ssh_authorized_keys:
 - $(cat $SSH_PUB_KEY)
EOT

echo "Create CONTROLLER.xml and COMPUTE.xml from template"
envsubst < templates/CONTROLLER_template.xml > CONTROLLER.xml
envsubst < templates/COMPUTE_template.xml > COMPUTE.xml

echo "Create config drives"
mkisofs -o "$CONTROLLER_CONFIG_ISO" -V cidata -r -J --quiet config-drives/CONTROLLER-config
mkisofs -o "$COMPUTE_CONFIG_ISO" -V cidata -r -J --quiet config-drives/COMPUTE-config

echo "Define VMs from XML templates"
virsh define CONTROLLER.xml
virsh define COMPUTE.xml

echo "Start VMs"
virsh start CONTROLLER
virsh start COMPUTE
