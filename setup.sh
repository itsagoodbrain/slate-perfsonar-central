#!/bin/bash
# setup central-management for perfSONAR on centos7 and configure it


# make sure we're at the ip we should be to reach our configuration files
ping -c 1 perfsonar.slateci.io | grep -q $(hostname -I) && \
# TODO: make this include port etc and be more explicit
echo "Address configured properly point perfsonar testpoints to perfsonar.slateci.io" || \
echo "Address is not configured correctly. You will need to manually change where the perfsonar testpoints point to."

yum -y install \
epel-release \
http://software.internet2.edu/rpms/el7/x86_64/main/RPMS/perfSONAR-repo-0.8-1.noarch.rpm \
yum -y update-minimal
# TODO: remove this once the RC -> Release, idk why they don't have one out for staging
yum -y install perfSONAR-repo-nightly \
perfsonar-centralmanagement \
perfsonar-toolkit-ntp \
perfsonar-toolkit-security \
perfsonar-toolkit-servicewatcher \
perfsonar-toolkit-sysctl

yum clean all

# open the necessary ports
/usr/lib/perfsonar/scripts/configure_firewall install
# configure ntp which is used by tools and restart service
/usr/lib/perfsonar/scripts/configure_ntpd new
systemctl restart ntpd
# follow the recommended tuning options
/usr/lib/perfsonar/scripts/configure_sysctl
# run the servicewatcher the first time
/usr/lib/perfsonar/scripts/service_watcher

# TODO: finish the psconfig setup
# TODO: figure out how to automatically submit 
