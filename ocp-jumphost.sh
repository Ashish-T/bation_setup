#!/usr/bin/env bash
# Openshift Jumphost (DNS,LB,NFS,DHCP,WEB) host setup script
# Ref: (https://www.linuxtechi.com/install-openshift-baremetal-upi/)

DOMAIN=cloudcafe.in

BOOT=bootstrap
MAS1=ocpmaster1
MAS2=ocpmaster2
MAS3=ocpmaster3
WOR1=ocpworker1
#WOR2=ocpworker2
INF1=ocpinfra1
#INF2=ocpinfra2
JUMP=jumphost

HIP=`ip -o -4 addr list eth0 | awk '{print $4}' | cut -d/ -f1`
SUBNET=`echo $HIP | cut -d. -f1-3`
REV=`echo $SUBNET | awk -F . '{print $3"."$2"."$1".in-addr.arpa"}' `

BOOTIP=$SUBNET.216
MAS1IP=$SUBNET.217
MAS2IP=$SUBNET.218
MAS3IP=$SUBNET.219
WOR1IP=$SUBNET.220
#WOR2IP=$SUBNET.221
INF1IP=$SUBNET.222
#INF2IP=$SUBNET.223
JUMPIP=$SUBNET.215

BOOTMAC=bomac
MAS1MAC=m1mac
MAS2MAC=m2mac
MAS3MAC=m3mac
WOR1MAC=w1mac
#WOR2MAC=w2mac
INF1MAC=i1mac
#INF2MAC=i2mac

PULLSECRET='{"auths":{"fake":{"auth": "bar"}}}'
#PULLSECRET='copy-and-paste-secret-file'

red=$(tput setaf 1)
grn=$(tput setaf 2)
yel=$(tput setaf 3)
blu=$(tput setaf 4)
bld=$(tput bold)
nor=$(tput sgr0)

# Download Openshift Software from Red Hat portal
toolsetup() {

echo "$bld$grn Downloading & Installing Openshift Software $nor"
curl -s -o openshift-install-linux.tar.gz https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/stable/openshift-install-linux.tar.gz
tar xpvf openshift-install-linux.tar.gz
rm -rf openshift-install-linux.tar.gz
mv openshift-install /usr/local/bin

curl -s -o openshift-client-linux.tar.gz https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/stable/openshift-client-linux.tar.gz
tar xvf openshift-client-linux.tar.gz
rm -rf openshift-client-linux.tar.gz
mv oc kubectl /usr/local/bin

curl -s -o rhcos-live.x86_64.iso https://mirror.openshift.com/pub/openshift-v4/dependencies/rhcos/4.9/latest/rhcos-live.x86_64.iso
curl -s -o rhcos-metal.x86_64.raw.gz https://mirror.openshift.com/pub/openshift-v4/dependencies/rhcos/4.9/latest/rhcos-metal.x86_64.raw.gz

#curl -s -o rhcos-live.x86_64.iso https://mirror.openshift.com/pub/openshift-v4/dependencies/rhcos/latest/latest/rhcos-live.x86_64.iso
#curl -s -o rhcos-metal.x86_64.raw.gz https://mirror.openshift.com/pub/openshift-v4/dependencies/rhcos/latest/latest/rhcos-metal.x86_64.raw.gz

}

# Configure DNS Server
dnssetup() {

echo "$bld$grn Configuring DNS Server $nor"
yum install bind bind-utils -y

cat <<EOF > /etc/named.conf
//
// named.conf
//
// Provided by Red Hat bind package to configure the ISC BIND named(8) DNS
// server as a caching only nameserver (as a localhost DNS resolver only).
//
// See /usr/share/doc/bind*/sample/ for example named configuration files.
//

options {
        listen-on port 53 { 127.0.0.1; $JUMPIP; };
#       listen-on-v6 port 53 { any; };
        directory       "/var/named";
        dump-file       "/var/named/data/cache_dump.db";
        statistics-file "/var/named/data/named_stats.txt";
        memstatistics-file "/var/named/data/named_mem_stats.txt";
        recursing-file  "/var/named/data/named.recursing";
        secroots-file  "/var/named/data/named.secroots";
        allow-query     { localhost; $SUBNET.0/24; };

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
        recursion yes;

//      dnssec-enable yes;
//      dnssec-validation yes;
//      dnssec-lookaside auto;
        # Using Google DNS
        forwarders {
                8.8.8.8;
                8.8.4.4;
        };

        /* Path to ISC DLV key */
//      bindkeys-file "/etc/named.iscdlv.key";
//
//      managed-keys-directory "/var/named/dynamic";
        pid-file "/run/named/named.pid";
//      session-keyfile "/run/named/session.key";
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

zone "$DOMAIN" IN {
  type master;
  file "/etc/named/zones/db.$DOMAIN";
};

zone "$REV" {
  type master;
  file "/etc/named/zones/db.reverse";
};

include "/etc/named.rfc1912.zones";
include "/etc/named.root.key";
EOF

mkdir /etc/named/zones
cat <<EOF > /etc/named/zones/db.$DOMAIN
\$TTL    604800
@   	IN  	SOA 	$JUMP.$DOMAIN. contact.$DOMAIN (
                  1     ; Serial
             604800     ; Refresh
              86400     ; Retry
            2419200     ; Expire
             604800     ; Minimum
)
	IN  	NS  	$JUMP

; Name server - A records
$JUMP.$DOMAIN.		IN	A	$JUMPIP

; Temp Bootstrap Node
$BOOT.$DOMAIN.		IN	A	$BOOTIP

; Controlplane Node
$MAS1.lab.$DOMAIN.	IN	A	$MAS1IP
$MAS2.lab.$DOMAIN.	IN	A	$MAS2IP
$MAS3.lab.$DOMAIN.	IN	A	$MAS3IP

; Worker Node
$WOR1.lab.$DOMAIN.	IN	A	$WOR1IP
;$WOR2.lab.$DOMAIN.	IN	A	$WOR2IP

; Infra Node
$INF1.lab.$DOMAIN.	IN	A	$INF1IP
;$INF2.lab.$DOMAIN.	IN	A	$INF2IP

; Openshift Internal - Load balancer
api.lab.$DOMAIN.	IN	A	$JUMPIP
api-int.lab.$DOMAIN.	IN	A	$JUMPIP
*.apps.lab.$DOMAIN.	IN	A	$JUMPIP

; ETCD Cluster
etcd-0.lab.$DOMAIN.	IN	A	$MAS1IP
etcd-1.lab.$DOMAIN.	IN	A	$MAS2IP
etcd-2.lab.$DOMAIN.	IN	A	$MAS3IP


; Openshift Internal SRV records (cluster name - lab)
_etcd-server-ssl._tcp.lab.$DOMAIN.	86400	IN	SRV	0	10	2380	etcd-0.lab
_etcd-server-ssl._tcp.lab.$DOMAIN.	86400	IN	SRV	0	10	2380	etcd-1.lab
_etcd-server-ssl._tcp.lab.$DOMAIN.	86400	IN	SRV	0	10	2380	etcd-2.lab

oauth-openshift.apps.lab.$DOMAIN.	IN	A	$JUMPIP
console-openshift-console.apps.lab.$DOMAIN.	IN	A	$JUMPIP

EOF

cat <<EOF > /etc/named/zones/db.reverse
\$TTL    604800
@   	IN  	SOA 	$JUMP.$DOMAIN. contact.$DOMAIN (
                  1     ; Serial
             604800     ; Refresh
              86400     ; Retry
            2419200     ; Expire
             604800     ; Minimum
)

; Name servers - NS records
	IN  	NS  	$JUMP.$DOMAIN.

; Name servers - PTR records
215	IN	PTR	$JUMP.$DOMAIN.

; OpenShift Container Platform Cluster - PTR records
216	IN	PTR	$BOOT.$DOMAIN.
;
217	IN	PTR	$MAS1.lab.$DOMAIN.
218	IN	PTR	$MAS2.lab.$DOMAIN.
219	IN	PTR	$MAS3.lab.$DOMAIN.
;
220	IN	PTR	$WOR1.lab.$DOMAIN.
;221	IN	PTR	$WOR2.lab.$DOMAIN.
;
222	IN	PTR	$INF1.lab.$DOMAIN.
;223	IN	PTR	$INF2.lab.$DOMAIN.
;
215	IN	PTR	api.lab.$DOMAIN.
215	IN	PTR	api-int.lab.$DOMAIN.
EOF

echo 'OPTIONS="-4"' >>/etc/sysconfig/named
systemctl start named;systemctl enable named
firewall-cmd --add-port=53/udp --permanent
firewall-cmd --reload

}

# Configure DHCP Server 
dhcpsetup() {

echo "$bld$grn Configuring DHCP Server $nor"
yum install dhcp -y 
yum install dhcp-server -y

cat <<EOF > /etc/dhcp/dhcpd.conf
authoritative;
ddns-update-style interim;
allow booting;
allow bootp;
allow unknown-clients;
ignore client-updates;
default-lease-time 14400;
max-lease-time 14400;
subnet $SUBNET.0 netmask 255.255.255.0 {
 option routers                  $JUMPIP; # lan
 option subnet-mask              255.255.255.0;
 option domain-name              "$DOMAIN";
 option domain-name-servers       $JUMPIP;
 range $SUBNET.1 $SUBNET.245;
}

host $BOOT {
 hardware ethernet $BOOTMAC;
 fixed-address $BOOTIP;
}

host $MAS1 {
 hardware ethernet $MAS1MAC;
 fixed-address $MAS1IP;
}

host $MAS2 {
 hardware ethernet $MAS1MAC;
 fixed-address $MAS2IP;
}

host $MAS3 {
 hardware ethernet $MAS3MAC;
 fixed-address $MAS3IP;
}

host $WOR1 {
 hardware ethernet $WOR1MAC;
 fixed-address $WOR1IP;
}

;host $WOR2 {
; hardware ethernet $WOR2MAC;
; fixed-address $WOR2IP;
;}

host $INF1 {
 hardware ethernet $INF1MAC;
 fixed-address $INF1IP;
}

;host $INF2 {
; hardware ethernet $INF2MAC;
; fixed-address $INF2IP;
;}

EOF

systemctl start dhcpd;systemctl enable dhcpd
firewall-cmd --add-service=dhcp --permanent
firewall-cmd --reload
}

# Configure Apache Web Server
websetup() {

echo "$bld$grn Configuring Apache Web Server $nor"
yum install -y httpd
sed -i 's/Listen 80/Listen 0.0.0.0:8080/' /etc/httpd/conf/httpd.conf
setsebool -P httpd_read_user_content 1
systemctl start httpd;systemctl enable httpd
firewall-cmd --add-port=8080/tcp --permanent
firewall-cmd --reload
}

# Configure HAProxy
lbsetup() {

echo "$bld$grn Configuring HAProxy Server $nor"
yum install haproxy -y 

cat <<EOF > /etc/haproxy/haproxy.cfg
# Global settings
#---------------------------------------------------------------------
global
    maxconn     20000
    log         /dev/log local0 info
    chroot      /var/lib/haproxy
    pidfile     /var/run/haproxy.pid
    user        haproxy
    group       haproxy
    daemon
    # turn on stats unix socket
    stats socket /var/lib/haproxy/stats
#---------------------------------------------------------------------
# common defaults that all the 'listen' and 'backend' sections will
# use if not designated in their block
#---------------------------------------------------------------------
defaults
    log                     global
    mode                    http
    option                  httplog
    option                  dontlognull
    option http-server-close
    option redispatch
    option forwardfor       except 127.0.0.0/8
    retries                 3
    maxconn                 20000
    timeout http-request    10000ms
    timeout http-keep-alive 10000ms
    timeout check           10000ms
    timeout connect         40000ms
    timeout client          300000ms
    timeout server          300000ms
    timeout queue           50000ms

# Enable HAProxy stats
listen stats
    bind :9000
    stats uri /stats
    stats refresh 10000ms

# Kube API Server
frontend k8s_api_frontend
    bind :6443
    default_backend k8s_api_backend
    mode tcp

backend k8s_api_backend
    mode tcp
    balance source
    server      $BOOT $BOOTIP:6443 check
    server      $MAS1 $MAS1IP:6443 check
    server      $MAS2 $MAS2IP:6443 check
    server      $MAS3 $MAS3IP:6443 check

# OCP Machine Config Server
frontend ocp_machine_config_server_frontend
    mode tcp
    bind :22623
    default_backend ocp_machine_config_server_backend

backend ocp_machine_config_server_backend
    mode tcp
    balance source
    server      $BOOT $BOOTIP:22623 check
    server      $MAS1 $MAS1IP:22623 check
    server      $MAS2 $MAS2IP:22623 check
    server      $MAS3 $MAS3IP:22623 check

# OCP Ingress - layer 4 tcp mode for each. Ingress Controller will handle layer 7.
frontend ocp_http_ingress_frontend
    bind :80
    default_backend ocp_http_ingress_backend
    mode tcp

backend ocp_http_ingress_backend
    balance source
    mode tcp
    server $MAS1 $MAS1IP:80 check
    server $MAS2 $MAS2IP:80 check
    server $MAS3 $MAS3IP:80 check
    server $INF1 $INF1IP:80 check
#    server $INF2 $INF2IP:80 check

frontend ocp_https_ingress_frontend
    bind *:443
    default_backend ocp_https_ingress_backend
    mode tcp

backend ocp_https_ingress_backend
    mode tcp
    balance source
    server $MAS1 $MAS1IP:443 check
    server $MAS2 $MAS2IP:443 check
    server $MAS3 $MAS3IP:443 check
    server $INF1 $INF1IP:443 check
#    server $INF2 $INF2IP:443 check

EOF

setsebool -P haproxy_connect_any 1
systemctl start haproxy;systemctl enable haproxy

firewall-cmd --add-port=6443/tcp --permanent
firewall-cmd --add-port=6443/tcp --permanent
firewall-cmd --add-port=22623/tcp --permanent
firewall-cmd --add-service=http --permanent
firewall-cmd --add-service=https --permanent
firewall-cmd --add-port=9000/tcp --permanent
firewall-cmd --reload
}

# Configure NFS Server
nfssetup() {

echo "$bld$grn Configuring NFS Server $nor"
yum install nfs-utils -y
mkdir -p /shares/registry
chown -R nobody:nobody /shares/registry
chmod -R 777 /shares/registry

cat <<EOF > /etc/exports
/shares/registry  *(rw,sync,no_subtree_check,no_root_squash,no_all_squash,insecure,no_wdelay)
EOF

setsebool -P nfs_export_all_rw 1
systemctl start nfs-server rpcbind nfs-mountd;systemctl enable nfs-server rpcbind
exportfs -rav
exportfs -v

firewall-cmd --add-service mountd --permanent
firewall-cmd --add-service rpc-bind --permanent
firewall-cmd --add-service nfs --permanent
firewall-cmd --reload

}

# Generate Manifests and Ignition files
manifes() {

echo "$bld$grn Generating Manifests and Ignition files $nor"
# Generate SSH Key
ssh-keygen -q -t rsa -N '' -f ~/.ssh/id_rsa <<<y >/dev/null 2>&1
PUBKEY=`cat ~/.ssh/id_rsa.pub`
echo $PUBKEY

rm -rf /var/www/html/ocp4
rm -rf ~/ocp-install
mkdir /var/www/html/ocp4
mkdir ~/ocp-install

cat <<EOF > ~/ocp-install/install-config.yaml
apiVersion: v1
baseDomain: $DOMAIN
compute:
  - hyperthreading: Enabled
    name: worker
    replicas: 0 
controlPlane:
  hyperthreading: Enabled
  name: master
  replicas: 3
metadata:
  name: lab # Cluster name
networking:
  clusterNetwork:
    - cidr: 10.128.0.0/14
      hostPrefix: 23
  networkType: OpenShiftSDN
  serviceNetwork:
    - 172.30.0.0/16

platform:
  none: {}
fips: false
pullSecret: 'PULL_SECRET'  
sshKey: "ssh-rsa PUBLIC_SSH_KEY"  

EOF

sed -i "s%PULL_SECRET%$PULLSECRET%" ~/ocp-install/install-config.yaml
sed -i "s%ssh-rsa PUBLIC_SSH_KEY%$PUBKEY%" ~/ocp-install/install-config.yaml
cp ~/ocp-install/install-config.yaml ~/ocp-install/install-config.yaml-bak
cp ~/ocp-install/install-config.yaml install-config.yaml

cp rhcos-live.x86_64.iso /var/www/html/ocp4/rhcos-live.x86_64.iso
cp rhcos-metal.x86_64.raw.gz /var/www/html/ocp4/rhcos

openshift-install create manifests --dir ~/ocp-install/
sed -i 's/mastersSchedulable: true/mastersSchedulable: false/' ~/ocp-install/manifests/cluster-scheduler-02-config.yml
openshift-install create ignition-configs --dir ~/ocp-install/
cp -R ~/ocp-install/*.ign /var/www/html/ocp4

chcon -R -t httpd_sys_content_t /var/www/html/ocp4/
chown -R apache: /var/www/html/ocp4/
chmod 755 /var/www/html/ocp4/

curl localhost:8080/ocp4/
}

# Install ALL
setupall () {

toolsetup
dnssetup
dhcpsetup
websetup
lbsetup
nfssetup
manifes
}

case "$1" in
    'toolsetup')
            toolsetup
            ;;
    'dnssetup')
            dnssetup
            ;;
    'dhcpsetup')
            dhcpsetup
            ;;
    'websetup')
            websetup
            ;;
    'lbsetup')
            lbsetup
            ;;
    'nfssetup')
            nfssetup
            ;;
    'manifes')
            manifes
            ;;
    'setupall')
            setupall
            ;;
    *)
            clear
            echo
            echo "$bld$blu Openshift Jumphost (DNS,LB,NFS,DHCP,WEB) host setup script $nor"
            echo
            echo "$bld$grn Usage: $0 { toolsetup | dnssetup | dhcpsetup | websetup | lbsetup | nfssetup | manifes | setupall } $nor"
            echo
            exit 1
            ;;
esac

exit 0
