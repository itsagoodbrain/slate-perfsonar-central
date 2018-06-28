#!/bin/bash
# setup central-management for perfSONAR on centos7 and configure it


# make sure we're at the ip we should be to reach our configuration files
ping -c 1 perfsonar.slateci.io | grep -q $(hostname -I) && \
# TODO: make this include port etc and be more explicit
echo "Address configured properly point perfsonar testpoints to perfsonar.slateci.io" || \
echo "Address is not configured correctly. You will need to manually csed -i 's/<pwa_hostname>/perfsonar.slateci.io/' /etc/pwa/index.js
hange where the perfsonar testpoints point to."

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

# install the gui pswebadmin
yum install -y docker
mkdir -p /etc/docker
systemctl enable docker
systemctl start docker

cat <<EOT >> /etc/logrotate.d/docker-container
/var/lib/docker/containers/*/*.log {
  rotate 7
  daily
  compress
  size=1M
  missingok
  delaycompress
  copytruncate
}
EOT


# deploy example TODO: replace with our own?
curl -L https://github.com/perfsonar/psconfig-web/raw/master/deploy/docker/pwa.sample.tar.gz -o pwa.sample.tar
tar -xzf pwa.sample.tar.gz -C /etc

sed -i 's/<pwa_hostname>/perfsonar.slateci.io/g' /etc/pwa/index.js /etc/pwa/auth/index.js
# if going to run a private sLS, need to also edit datasource section
# TODO: change this email address!!
sed -i 's/<email_address>/jproc@umich.edu/g' /etc/pwa/auth/index.js

# TODO: better ssl security
openssl req -x509 -newkey rsa:4096 -keyout /etc/pwa/auth
/key.pem -out /etc/pwa/auth
/cert.pem -days 365 -nodes -subj "/C=US/OU=SlateCI/CN=slateci.io"
openssl x509 -in /etc/ssl/certs/ca-bundle.trust.crt -out /etc/pwa/auth/trusted.pem -outform PEM

# input required, create new users according to


# fix ports for running with MaDDash
sed -i '/listen/ s/80/8000/' /etc/pwa/nginx/conf.d/pwa.conf
sed -i '/listen/ s/ 443 ssl/ 8443/' /etc/pwa/nginx/conf.d/pwa.conf
# start docker containers
docker network create pwa
mkdir -p /usr/local/data

docker run \
        --restart=always \
        --net pwa \
        --name mongo \
        -v /usr/local/data/mongo:/data/db \
        -d mongo
docker run \
    --restart=always \
    --net pwa \
    --name sca-auth \
    -v /etc/pwa/auth:/app/api/config \
    -v /usr/local/data/auth:/db \
    -d perfsonar/sca-auth
docker run \
    --restart=always \
    --net pwa \
    --name pwa-admin1 \
    -v /etc/pwa:/app/api/config:ro \
    -d perfsonar/pwa-admin
docker run \
    --restart=always \
    --net pwa \
    --name pwa-pub1 \
    -v /etc/pwa:/app/api/config:ro \
    -d perfsonar/pwa-pub
docker run \
    --restart=always \
    --net pwa \
    --name nginx \
    -v /etc/pwa/shared:/shared:ro \
    -v /etc/pwa/nginx:/etc/nginx:ro \
    -v /etc/pwa/auth:/certs:ro \
    -p 8000:8000 \
    -p 8443:8443 \
    -p 9443:9443 \
    -d nginx

systemctl restart docker
# TODO: finish the pwa ccustomization for easier psconfig setup

# psconfig remote add --configure-archives perfsonar.slateci.io

# TODO: figure out how to automatically submit cd
