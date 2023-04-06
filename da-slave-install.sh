#!/bin/sh
# @author jordavin,phillcoxon,mantas15
# @updated by The Regular Guy
# @date 04.06.2023
# @version 1.0.5
# @source
# ------------------------------------------------------------------------------
# -----------------------------------#
# System vars.			          			 #
# -----------------------------------#
cur_hostname="$(hostnamectl --static)"
serverip="$(hostname -I | awk '{print $1}')"
servername="$(hostname -s)"
OS=$(cat /etc/redhat-release | awk {'print $1}')
VN=$(cat /etc/centos-release | tr -dc '0-9.' | cut -d \. -f1)
# -----------------------------------#
# Declare vars.			   			 #
# -----------------------------------#
logfile=/root/install.log
builddir=~/dsbuild/
sshport=22

#Check that user is root.
if [ “$(id -u)” = “0” ]; then
	printf "We are root. Continue on....\n"
else
	printf "This script must be run as root\n"
	exit
fi
#What Distro are you on?
printf "Distro are you on??\n" 2>&1
if [ "${OS}" = "AlmaLinux" ] || [ "${OS}" = "Rocky" ]; then
	echo "System runs on "${OS}" "${VN}". Checking Continue on...."
	mkdir -p "${builddir}"
else
	[ "${VN}" != "8.*" ]
	elseif
	echo "System runs on  unsupported Linux. Exiting..."
	exit
fi
if [ -z "$1" ]; then
	echo "usage <username> <userpass> <master ip>"
	exit 0
fi
if [ -z "$2" ]; then
	echo "usage <username> <userpass> <master ip>"
	exit 0
fi
if [ -z "$3" ]; then
	echo "usage <username> <userpass> <master ip>"
	exit 0
fi
echo "Saving most outputs to ${logfile}"

echo "doing updates and installs"
yum update -y >${logfile}
yum install epel-release -y >>${logfile}
yum install bind bind-utils wget -y >>${logfile}

systemctl start named >>${logfile}
systemctl stop named >>${logfile}

echo "creating user "$1" and adding to wheel"
useradd -G wheel $1 >>${logfile}
echo $2 | passwd $1 --stdin >>${logfile}
echo "Disabling root access to ssh to server use "$1"."
cursshport="$(cat /etc/ssh/sshd_config | grep "Port ")"
	read -p "Enter SSH port to change to:" customsshport
	if [ $customsshport ]; then
		sshport=$customsshport
	fi
	echo "Set to Port: "$sshport
	echo "Securing the server, please wait..."
	sed -i -e "s/$cursshport/Port ${sshport}/g" /etc/ssh/sshd_config >>${logfile}
	sed -i -e 's/#UseDNS yes/UseDNS no/g' /etc/ssh/sshd_config >>${logfile}
	sed -i -e 's/#AddressFamily any/AddressFamily inet/g' /etc/ssh/sshd_config >>${logfile}
	sed -i -e 's/#LoginGraceTime 2m/LoginGraceTime 2m/g' /etc/ssh/sshd_config >>${logfile}
	sed -i -e 's/#MaxAuthTries 6/MaxAuthTries 5/g' /etc/ssh/sshd_config >>${logfile}
	sed -i -e 's/#MaxStartups 10:30:100/MaxStartups 10:30:100/g' /etc/ssh/sshd_config >>${logfile}
	sed -i -e 's/.*PermitRootLogin yes/PermitRootLogin prohibit-password/g' /etc/ssh/sshd_config >>${logfile}
	sed -i -e 's/PasswordAuthentication yes/PasswordAuthentication no/g' /etc/ssh/sshd_config >>${logfile}
	sed -i -e 's/#ClientAliveInterval .*/ClientAliveInterval 120/g' /etc/ssh/sshd_config >>${logfile}
	sed -i -e 's/#ClientAliveCountMax .*/ClientAliveCountMax 15/g' /etc/ssh/sshd_config >>${logfile}
systemctl restart sshd

echo "installing and configuring directslave"
cd ~
wget -q https://directslave.com/download/directslave-3.4.4-advanced-all.tar.gz >>${logfile}
tar -xf directslave-3.4.4-advanced-all.tar.gz
mv directslave /usr/local/
cd /usr/local/directslave/bin
mv directslave-linux-amd64 directslave
cd /usr/local/directslave
chown named:named -R /usr/local/directslave

randomnum="$(tr -cd 'a-zA-Z0-9' </dev/urandom 2>/dev/null | head -c25)"
curip="$(hostname -I | awk '{print $1}')"

cat >/usr/local/directslave/etc/directslave.conf <<EOF
background	1
host            $curip
port            2222
ssl             off
cookie_sess_id  DS_SESSID
cookie_auth_key $randomnum
debug           0
uid             25
gid             25
pid             /usr/local/directslave/run/directslave.pid
access_log	/usr/local/directslave/log/access.log
error_log	/usr/local/directslave/log/error.log
action_log	/usr/local/directslave/log/action.log
named_workdir   /etc/namedb/secondary
named_conf	/etc/namedb/directslave.inc
retry_time	1200
rndc_path	/usr/sbin/rndc
named_format    text
authfile        /usr/local/directslave/etc/passwd
EOF

#mkdir /etc/namedb
mkdir -p /etc/namedb/secondary
touch /etc/namedb/secondary/named.conf
touch /etc/namedb/directslave.inc
chown named:named -R /etc/namedb
mkdir /var/log/named
touch /var/log/named/security.log
chmod a+w -R /var/log/named

cat >/etc/named.conf <<EOF
//
// named.conf
//
// Provided by Red Hat bind package to configure the ISC BIND named(8) DNS
// server as a caching only nameserver (as a localhost DNS resolver only).
//
// See /usr/share/doc/bind*/sample/ for example named configuration files.
//
// See the BIND Administrator's Reference Manual (ARM) for details about the
// configuration located in /usr/share/doc/bind-{version}/Bv9ARM.html
options {
	listen-on port 53 { any; };
	listen-on-v6 port 53 { none; };
	directory 	"/var/named";
	dump-file 	"/var/named/data/cache_dump.db";
	statistics-file "/var/named/data/named_stats.txt";
	memstatistics-file "/var/named/data/named_mem_stats.txt";
	recursing-file  "/var/named/data/named.recursing";
	secroots-file   "/var/named/data/named.secroots";
		allow-query     { any; };
		allow-notify	{ $3; };
		allow-transfer	{ none; };
	/*
	 - If you are building an AUTHORITATIVE DNS server, do NOT enable recursion.
	 - If you are building a RECURSIVE (caching) DNS server, you need to enable
	   recursion.
	 - If your recursive DNS server has a public IP address, you MUST enable access
	   control to limit queries to your legitimate users. Failing to do so will
	   cause your server to become part of large scale DNS amplification
	   attacks. Implementing BCP38 within your network would greatly
	   reduce such attack surface
	*/
	recursion no;
	dnssec-enable yes;
	dnssec-validation yes;
	/* Path to ISC DLV key */
	bindkeys-file "/etc/named.iscdlv.key";
	managed-keys-directory "/var/named/dynamic";
	pid-file "/run/named/named.pid";
	session-keyfile "/run/named/session.key";
};
logging {
        channel default_debug {
                file "data/named.run";
                severity dynamic;
        };
};
zone "." IN {
	type hint;
	file "named.ca";
};
include "/etc/named.rfc1912.zones";
include "/etc/named.root.key";
include "/etc/namedb/directslave.inc";
EOF

touch /usr/local/directslave/etc/passwd
chown named:named /usr/local/directslave/etc/passwd
/usr/local/directslave/bin/directslave --password $1:$2
/usr/local/directslave/bin/directslave --check >>${logfile}
rm /usr/local/directslave/run/directslave.pid

cat >/etc/systemd/system/directslave.service <<EOL
[Unit]
Description=DirectSlave for DirectAdmin
After=network.target
[Service]
Type=simple
User=named
ExecStart=/usr/local/directslave/bin/directslave --run
Restart=always
[Install]
WantedBy=multi-user.target
EOL

echo "setting enabled and starting up"
chown root:root /etc/systemd/system/directslave.service
chmod 755 /etc/systemd/system/directslave.service
systemctl daemon-reload >>${logfile}
systemctl enable named >>${logfile}
systemctl enable directslave >>${logfile}
systemctl restart named >>${logfile}
systemctl restart directslave >>${logfile}
systemctl status directslave >>${logfile}
echo "adding simple firewalld and opening Firewalld ports"
yum update -y >>${logfile}
yum install firewalld -y >>${logfile}

systemctl start firewalld >>${logfile}
systemctl enable firewalld >>${logfile}
firewall-cmd --permanent --add-service=dns
firewall-cmd --permanent --add-port=2222/tcp
firewall-cmd --reload
systemctl restart firewalld >>${logfile}
echo "all done!" >>${logfile}
exit 0
