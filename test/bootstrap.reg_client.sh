#!/bin/bash

NODE_MOUNT_PREFIX="/node"

function retrycmd_if_failure() {
    retries=$1; max_wait_sleep=$2; shift && shift
    for i in $(seq 1 $retries); do
        ${@}
        [ $? -eq 0  ] && break || \
        if [ $i -eq $retries ]; then
            echo Executed \"$@\" $i times;
            return 1
        else
            sleep $(($RANDOM % $max_wait_sleep))
        fi
    done
    echo Executed \"$@\" $i times;
}

function apt_get_update() {
    retries=10
    apt_update_output=/tmp/apt-get-update.out
    for i in $(seq 1 $retries); do
        timeout 120 apt-get update 2>&1 | tee $apt_update_output | grep -E "^([WE]:.*)|([eE]rr.*)$"
        [ $? -ne 0  ] && cat $apt_update_output && break || \
        cat $apt_update_output
        if [ $i -eq $retries ]; then
            return 1
        else sleep 30
        fi
    done
    echo Executed apt-get update $i times
}

function apt_get_install() {
    retries=$1; wait_sleep=$2; timeout=$3; shift && shift && shift
    for i in $(seq 1 $retries); do
        apt-get install --no-install-recommends -y ${@}
        [ $? -eq 0  ] && break || \
        if [ $i -eq $retries ]; then
            return 1
        else
            sleep $wait_sleep
            apt_get_update
        fi
    done
    echo "completed"
    echo Executed apt-get install --no-install-recommends -y \"$@\" $i times;
}

function config_linux() {
    export DEBIAN_FRONTEND=noninteractive
    apt_get_update
    apt_get_install 20 10 180 default-jre zip csh unzip
}

function mount_avere() {
    COUNTER=0
    for VFXT in $(echo $NFS_IP_CSV | sed "s/,/ /g")
    do
        MOUNT_POINT="${BASE_DIR}${NODE_MOUNT_PREFIX}${COUNTER}"
        echo "Mounting to ${VFXT}:${NFS_PATH} to ${MOUNT_POINT}"
        mkdir -p $MOUNT_POINT
        # no need to write again if it is already there
        if grep -F --quiet "${VFXT}:${NFS_PATH}    ${MOUNT_POINT}" /etc/fstab; then
            echo "not updating file, already there"
        else
            echo "${VFXT}:${NFS_PATH}    ${MOUNT_POINT}    nfs hard,nointr,proto=tcp,mountproto=tcp,retry=30 0 0" >> /etc/fstab
            mount ${MOUNT_POINT}
        fi
        COUNTER=$(($COUNTER + 1))
    done
}

function setup_staf_server() {
    # Install Docker and Blobfuse.
    wget https://packages.microsoft.com/config/ubuntu/18.04/packages-microsoft-prod.deb
    sudo dpkg -i packages-microsoft-prod.deb
    sudo apt update
    sudo apt install docker.io blobfuse -y

    # Configure blobfuse.
    sudo mkdir /mnt/resource/blobfusetmp -p
    sudo chown $LINUX_USER /mnt/resource/blobfusetmp
    mkdir -p blobmnt
    echo "accountName <pipelines_sa>"         >  fuse_connection.cfg
    echo "accountKey <pipelines_sa_key>"      >> fuse_connection.cfg
    echo "containerName vfxt-pipelines-blob"  >> fuse_connection.cfg
    chmod 600 fuse_connection.cfg

    # Mount the Azure blob to blobmnt.
    blobfuse blobmnt \
        --tmp-path=/mnt/resource/blobfusetmp \
        --config-file=fuse_connection.cfg \
        --file-cache-timeout-in-seconds=0 \
        -o attr_timeout=240 \
        -o entry_timeout=240 \
        -o negative_timeout=120

    # Copy Azure blob contents.
    cp -r blobmnt/docker-staf .

    # Unmount the Azure blob and clean up.
    sudo umount blobmnt
    sudo rm -r blobmnt /mnt/resource/blobfusetmp

    # Build Docker STAF image.
    sudo docker build -t azpipelines/staf docker-staf/.

    # Run Docker STAF image.
    sudo docker run -d -p 6500:6500 -p 6550:6550 -t azpipelines/staf
}

function setup_sv_virtualenv() {
    # Install Ansible.
    sudo apt install ansible -y

    # Clone Avre-ansible and Avere-sv repos.
    GIT_USERNAME="<git_username>"
    GIT_PASSWORD="<git_password>"
    git clone https://${GIT_USERNAME}:${GIT_PASSWORD}@msazure.visualstudio.com/DefaultCollection/One/_git/Avere-ansible
    git clone https://${GIT_USERNAME}:${GIT_PASSWORD}@msazure.visualstudio.com/DefaultCollection/One/_git/Avere-sv

    # Copy requirements.txt (needed for Ansible playbooks).
    cp Avere-sv/requirements.txt /tmp/requirements.sv
    cp Avere-sv/requirements.txt /tmp/requirements.ats

    # Copy pip.conf to a few places.
    PIP_CONF_FILE=$(find /nfs -name pip.conf -print -quit)
    sudo cp -v $PIP_CONF_FILE /etc/.
    sudo cp -v $PIP_CONF_FILE /etc/default/.

    # Run Ansible playbooks.
    ansible-playbook Avere-ansible/ansible/ats_venv/ats_venv.yml
    ansible-playbook Avere-ansible/ansible/sv_venv/sv_venv.yml

    # Set ownership of $LINUX_USER's homedir and make Python dir writeable.
    chown -R $LINUX_USER /home/$LINUX_USER
    chmod -R 777 /usr/sv/env/lib/python2.7

    # Virtual env setup.
    cd Avere-sv
    source /usr/sv/env/bin/activate
    export PYTHONPATH=~/Avere-sv:~/Avere-sv/averesv:$PYTHONPATH:$PATH
    python setup.py develop
    cd ..
}

function setup_staf_client() {
    # Install Blobfuse.
    wget https://packages.microsoft.com/config/ubuntu/18.04/packages-microsoft-prod.deb
    sudo dpkg -i packages-microsoft-prod.deb
    sudo apt update
    sudo apt install blobfuse -y

    # Configure blobfuse.
    sudo mkdir /mnt/resource/blobfusetmp -p
    sudo chown $LINUX_USER /mnt/resource/blobfusetmp
    mkdir -p blobmnt
    echo "accountName <pipelines_sa>"         >  fuse_connection.cfg
    echo "accountKey <pipelines_sa_key>"      >> fuse_connection.cfg
    echo "containerName vfxt-pipelines-blob"  >> fuse_connection.cfg
    chmod 600 fuse_connection.cfg

    # Mount the Azure blob to blobmnt.
    blobfuse blobmnt \
        --tmp-path=/mnt/resource/blobfusetmp \
        --config-file=fuse_connection.cfg \
        --file-cache-timeout-in-seconds=0 \
        -o attr_timeout=240 \
        -o entry_timeout=240 \
        -o negative_timeout=120

    # Copy Azure blob contents (STAF tarball).
    cp blobmnt/STAF*.tar.gz /tmp

    # Unmount the Azure blob and clean up.
    sudo umount blobmnt
    sudo rm -r blobmnt /mnt/resource/blobfusetmp

    # Run Ansible playbook.
    ansible-playbook Avere-ansible/ansible/staf/staf.yml

    # Set STAF envars to load on login.
    sudo sed -i '1isource /usr/local/staf/STAFEnv.sh' ~/.bashrc
}

function main() {
    echo "STEP: config_linux"
    config_linux

    echo "STEP: mount_avere"
    mount_avere

    # $HOME isn't set at this point in the VM's lifecycle. Set it and go there.
    ORIG_DIR=$(pwd)
    export HOME=/home/$LINUX_USER
    cd $HOME

    set -e
    if [ "$REG_CLIENT_TYPE" == "SERVER" ]; then
        echo "STEP: setup_staf_server"
        setup_staf_server
    fi

    echo "STEP: setup_sv_virtualenv"
    setup_sv_virtualenv

    if [ "$REG_CLIENT_TYPE" == "CLIENT" ]; then
        echo "STEP: setup_staf_client"
        setup_staf_client
    fi

    # Set ownership of $LINUX_USER's homedir and make Python dir writeable.
    chown -R $LINUX_USER /home/$LINUX_USER

    set +e

    cd $ORIG_DIR

    echo "DONE: installation complete"
}

main
