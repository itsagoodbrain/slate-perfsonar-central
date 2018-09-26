#!/bin/bash
# setup central-management for perfSONAR on centos7 and configure it

if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root"
   exit 1
fi
# TODO: remove if can avoid using
# SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
# CONFIG_DIR=$SCRIPT_DIR/config

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

# install the gui pswebadmin PWA
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
# TODO: add changes if going to run a private sLS, need to also edit datasource section
# TODO: assign a email redirect with the dns?
sed -i 's/<email_address>/pwa-admin@perfsonar.slateci.net/g' /etc/pwa/auth/index.js
# enable the interface even though there won't be emails, see commands below
# TODO: could maybe add a note to the html page?
sudo sed -i -e '/signup:/s/false/true/' /etc/pwa/shared/auth.ui.js /etc/pwa/auth/index.js

# # TODO: make these easier commands? replace test_signup with requested username after they complete form
# sudo sqlite3 /usr/local/data/auth/auth.sqlite "update users set email_confirmed=1 where username='test_signup';
# sqlite3 /usr/local/data/auth/auth.sqlite "select username, email from users where email_confirmed=0;""
# # the full addition and modification of permissions found here
# http://docs.perfsonar.net/release_candidates/4.1b1/pwa_user_management.html


# sed -e '/exports.local/a\\t//nodemailer confing \n\tmailer: { \n\t\thost: \'perfsonar.slateci.net\',\n\t\tsecure: false,\n\t},' index.js
# # setup email on host to accept requests from docker
# sed -i 's/^inet_interfaces = .*$/inet_interfaces = 172.18.0.1/' /etc/postfix/main.cf
# grep -q '^mynetworks' /etc/postfix/main.cf && \
#   sed -i  's/^mynetworks = .*$/mynetworks = 172.18.0.4/' /etc/postfix/main.cf \
#   || echo 'mynetworks = 172.18.0.4' >> /etc/postfix/main.cf
# grep -q '^myhostname' /etc/postfix/main.cf && \
#   sed -i  's/^myhostname = .*$/myhostname = perfsonar.slateci.net/' /etc/postfix/main.cf \
#   || echo 'myhostname = perfsonar.slateci.net' >> /etc/postfix/main.cf
# grep -q '^local_recipient_maps' /etc/postfix/main.cf && \
#   sed -i  's/^local_recipient_maps = .*$/local_recipient_maps = /' /etc/postfix/main.cf \
#   || echo 'local_recipient_maps = ' >> /etc/postfix/main.cf

# TODO: notice that perfsonar.slateci.net key and cert must be in place?
chmod 600 /etc/pki/tls/certs/perfsonar.slateci.net.crt /etc/pki/tls/private/perfsonar.slateci.net.key
sed -i 's/localhost/perfsonar.slateci.net/g' /etc/httpd/conf.d/ssl.conf

# set up certs where docker expects them
ln /etc/pki/tls/certs/perfsonar.slateci.net.crt /etc/pwa/auth/cert.pem
ln /etc/pki/tls/private/perfsonar.slateci.net.key /etc/pwa/auth/key.pem
ln /etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem /etc/pwa/auth/trusted.pem
# redirect /pub links
ln /etc/pwa/extras/apache-pwa-toolkit_web_gui.conf /etc/httpd/conf.d/apache-pwa-toolkit_web_gui.conf
systemctl restart httpd

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
    --ip 172.18.0.4 \
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

docker run \
    --name watchtower \
    --restart=always \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -d v2tec/watchtower \
    -i 86400

systemctl restart docker

# TODO: input required for user account creation
# http://docs.perfsonar.net/release_candidates/4.1b1/pwa_configure.html#user-management
# TODO: make scripts to add new users
# TODO: make scripts to add new admins to pwa and maddash and ?

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

# psconfig remote add --configure-archives perfsonar.slateci.net/pub/auto/ FQDN

# TODO: does this work just once or does it keep updating it?
# setting up maddash
psconfig remote add --configure-archives http://perfsonar.slateci.net/pub/config/slate


# TODO: make sure these pieces go into a script function
cd /usr/lib/esmond
. bin/activate
mkdir -pm 600  $(dirname $ESMOND_CONF)/tokens
python esmond/manage.py add_ps_metadata_post_user slateci | tee /dev/tty | awk '/Key/ {print $2}' > $(dirname $ESMOND_CONF)/tokens/slateci
python esmond/manage.py add_timeseries_post_user slateci
deactivate
# TODO: figure out a way to http://docs.perfsonar.net/release_candidates/4.1b1/multi_ma_install.html#authenticating-by-ip-address automatically
# not sure we want to do this... but it will work...
cd /usr/lib/esmond
. bin/activate
python esmond/manage.py add_user_ip_address slateci $(getent hosts $(curl -s -H "Content-Type: application/js" -X GET http://perfsonar.slateci.net/pub/config/slate_nodes_test.json? | jq -r '.organizations[] | .sites[] | .hosts[] | .addresses[]' | tr '\n' ' ') | awk '{print $1}' ORS=" ")
deactivate

# TODO: figure out why https keeps lookup/records from connecting
# TODO: figure out how to make sure essential processes like httpd restart if they die
# TODO: figure out how to automatically submit cd

# # TODO: What needs to happen next
# - make new testpoints broadcast their actual address not private locals
# - use PWA hostgroup to automatically collect up a group
# - figure out how to actually get the centralmanagement accepting test results
# - make MaDDash slurp up some tests defined with those hostgroups and display them
# - remove the automatically posted one
# - find all the config files you changed, link them maybe to one location? possible to collect them all and redeploy that way? hardlinking? softlinking would be better with references of where things go....
# - script nicely this setup script, some updating, and things like user account creation... try to divide into things that should be done once and things that can be repeated
