#!/bin/bash
node1_ip=172.16.128.1
node2_ip=172.16.128.2
install -d -m 0700 ~/.ssh
ssh-keyscan "${node1_ip}" > ~/.ssh/known_hosts
ssh-keyscan "${node2_ip}" > ~/.ssh/known_hosts
./cleanup-oracle.sh --ora-version 26 --yes-i-am-sure \
--inventory-file /etc/files_needed_for_tk/rac-inventory \
--ora-disk-mgmt udev --ora-swlib-path /u01/oracle_install \
--ora-asm-disks /etc/files_needed_for_tk/rac-asm.json \
--ora-data-mounts /etc/files_needed_for_tk/rac-data-mounts.json
./install-oracle.sh --ora-swlib-bucket gs://bmaas-testing-oracle-software \
--instance-ssh-user ansible --instance-ssh-key /etc/files_needed_for_tk/ansible_private_ssh_key \
--ora-version 26 --ora-swlib-type gcs --cluster-type RAC \
--ora-asm-disks /etc/files_needed_for_tk/rac-asm.json \
--ora-data-mounts /etc/files_needed_for_tk/rac-data-mounts.json \
--cluster-config /etc/files_needed_for_tk/rac-config.json
