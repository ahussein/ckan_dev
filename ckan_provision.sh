#!/usr/bin/env bash
set -e 
set -x

logfile='/tmp/ckan_install.log'

die(){
    echo "$1" | tee -a ${logfile}
    return 1
}

print_(){
    echo "$1" | tee -a ${logfile}
}

# Install the required packages
print_ "* Installing required packages"
sudo apt-get update > /dev/null 2>&1
sudo apt-get install -y python-dev postgresql libpq-dev python-pip python-virtualenv git-core solr-jetty openjdk-7-jdk > /dev/null 2>&1 || die "Failed to install required pacakges"

print_ "* Installing CKAN into python virtual environment"
mkdir -p ~/ckan/lib
sudo ln -s ~/ckan/lib /usr/lib/ckan
mkdir -p ~/ckan/etc
sudo ln -s ~/ckan/etc /etc/ckan

print_ "** Creating python virutal environment"
sudo mkdir -p /usr/lib/ckan/default
sudo chown `whoami` /usr/lib/ckan/default
virtualenv --no-site-packages /usr/lib/ckan/default > /dev/null || die "Failed to create python virtual environment"
#. /usr/lib/ckan/default/bin/activate || die "Failed to activate python virtual environment"

print_ "** Installing CKAN source code"
/usr/lib/ckan/default/bin/pip install -U distribute
/usr/lib/ckan/default/bin/pip install -e 'git+https://github.com/ckan/ckan.git#egg=ckan' > /dev/null 2>&1 || die "Failed to install CKAN source code"
/usr/lib/ckan/default/bin/pip install -r /usr/lib/ckan/default/src/ckan/requirements.txt > /dev/null 2>&1 || die "Failed to install CKAN source code"

print_ "* Setup PostgreSQL database"
sudo -u postgres psql -l > /dev/null 2>&1 || die "PostgreSQL is not installed correctly"
print_ "** Creating PostgreSQL user and database"
sudo -u postgres bash -c "psql -c \"CREATE USER ckan_default WITH PASSWORD 'ckan_default';\"" > /dev/null 2>&1 || die "Failed to create database user"
sudo -u postgres createdb -O ckan_default ckan_default -E utf-8 > /dev/null 2>&1 || die "Failed to create database"

print_ "* Creating CKAN config file"
sudo mkdir -p /etc/ckan/default
sudo chown -R `whoami` /etc/ckan/
sudo chown -R `whoami` ~/ckan/etc
/usr/lib/ckan/default/bin/paster make-config ckan /etc/ckan/default/production.ini
sed -i s/ckan_default:pass/ckan_default:ckan_default/g /etc/ckan/default/production.ini
sudo bash -c "echo solr_url=http://127.0.0.1:8983/solr >> /etc/ckan/default/production.ini"

print_ "* Setup Solr"
sudo sed -i s/NO_START=1/NO_START=0/g /etc/default/jetty
sudo bash -c "echo JETTY_HOST=0.0.0.0 >> /etc/default/jetty"
sudo bash -c "echo JETTY_PORT=8983 >> /etc/default/jetty"
sudo bash -c "echo JAVA_HOME=/usr/lib/jvm/java-7-openjdk-amd64/ >> /etc/default/jetty"
pushd /tmp; wget https://launchpad.net/~vshn/+archive/ubuntu/solr/+files/solr-jetty-jsp-fix_1.0.2_all.deb > /dev/null 2>&1
sudo dpkg -i solr-jetty-jsp-fix_1.0.2_all.deb > /dev/null 2>&1

sudo service jetty start > /dev/null 2>&1 || die "Failed to start Jetty server"

print_ "** Replacing default Solr schema"
sudo mv /etc/solr/conf/schema.xml /etc/solr/conf/schema.xml.bak
sudo ln -s /usr/lib/ckan/default/src/ckan/ckan/config/solr/schema.xml /etc/solr/conf/schema.xml
sudo service jetty restart > /dev/null 2>&1 || die "Failed to restart Jetty server"


set +x
