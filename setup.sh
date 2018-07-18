#!/bin/bash
# setup central-management for perfSONAR on centos7 and configure it


# make sure we're at the ip we should be to reach our configuration files
ping -c 1 perfsonar.slateci.net | grep -q $(hostname -I) && \
# TODO: make this include port etc and be more explicit
echo "Address configured properly point perfsonar testpoints to perfsonar.slateci.net" || \
echo "Address is not configured correctly."

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


# deploy example TODO: replace with our own if a lot of customization?
curl -L https://github.com/perfsonar/psconfig-web/raw/master/deploy/docker/pwa.sample.tar.gz -o pwa.sample.tar
tar -xzf pwa.sample.tar.gz -C /etc

sed -i 's/<pwa_hostname>/perfsonar.slateci.net/g' /etc/pwa/index.js /etc/pwa/auth/index.js
# if going to run a private sLS, need to also edit datasource section
# TODO: change this email address!!
sed -i 's/<email_address>/jproc@umich.edu/g' /etc/pwa/auth/index.js

# TODO: notice that perfsonar.slateci.net key and cert must be in place?
chmod 600 /etc/pki/tls/certs/perfsonar.slateci.net.crt /etc/pki/tls/private/perfsonar.slateci.net.key
sed -i 's/localhost/perfsonar.slateci.net/g' /etc/httpd/conf.d/ssl.conf

ln /etc/pki/tls/certs/perfsonar.slateci.net.crt /etc/pwa/auth/cert.pem
ln /etc/pki/tls/private/perfsonar.slateci.net.key /etc/pwa/auth/key.pem
ln /etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem /etc/pwa/auth/trusted.pem

# input required, create new users according to


# fix ports for running with MaDDash
sed -i '/listen/ s/ 80;/ 8000;/' /etc/pwa/nginx/conf.d/pwa.conf
sed -i '/listen/ s/ 443 ssl/ 8443/' /etc/pwa/nginx/conf.d/pwa.conf
# start docker containers
docker network create --subnet=172.18.0.0/16 pwa
mkdir -p /usr/local/data

docker run \
        --restart=always \
        --net pwa \
        --name mongo \
        --ip 172.18.0.22 \
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

# simple lookupservice

# install lookup-service withproper deps except for mongodb
yum -y install $(repoquery --requires --resolve lookup-service | grep $(uname -m) | grep -vwE mongodb)
rpm -Uvh --nodeps $(repoquery --location lookup-service)
# open needed ports
firewall-cmd --add-port=8090/tcp --permanent #lookup service
# TODO: do we need this? # firewall-cmd --add-port=5672/tcp --permanent #queue with rabbit |mq?
firewall-cmd --reload
# change config files
sed -i -e 's/localhost/perfsonar.slateci.net/' \
    # using docker mongodb instance, shared with pwa
    -e 's/127.0.0.1/172.18.0.22/' \
    # no username or password on default setup
    -e '/username/d' \
    -e '/password/d' \
    # be more accurate with the database nameing
    -e 's/services/hosts/'
    /etc/lookup-service/lookupservice.yaml
# TODO: be certain about the queservice settings being off

systemctl enable lookup-service
systemctl start lookup-service

# psconfig remote add --configure-archives perfsonar.slateci.net

# TODO: figure out why https keeps lookup/records from connecting
# TODO: figure out how to make sure essential processes like httpd restart if they die
# TODO: figure out how to automatically submit cd
