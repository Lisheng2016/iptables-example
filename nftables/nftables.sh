#! /bin/sh
INTERNET="eth0"							# Internet-connected interface
LOOPBACK_INTERFACE="lo"					# Loopback interface name
IPADDR="my.ip.address"					# IP address of the internet-connnected interface
MY_ISP="my.isp.address.range"			# ISP server & NOC address range
SUBNET_BASE="my.subnet.network"			# Your subnet's network address
SUBNET_BROADCAST="my.subnet.bcast"		# Your subnet's broadcast address
LOOPBACK="127.0.0.0/8"					# Reserved loopback address range
CLASS_A="10.0.0.0/8"					# Class A private networks
CLASS_B="172.16.0.0/12"					# Class B private networks
CLASS_C="192.168.0.0/16"				# Class C private networks
CLASS_D_MULTICAST="224.0.0.0/5"			# Class D multicast address
CLASS_E_RESERVED_NET="240.0.0.0/5"		# Class E reserved address
BROADCAST_SRC="0.0.0.0"					# Broadcast source address
BROADCAST_DEST="255.255.255.255"		# Broadcast destination address
PRIVPORTS="0-1023"						# Well-known, privileged port range
UNPRIVPORTS="1024-65535"				# Unprivileged port range
XWINDOW_PORTS="6000-6063"   			# (TCP) X Windows
NFS_PORT="2049"							# (TCP) NFS
LOCKD_PORT="4045"						# (TCP) RPC LOCKD for NFS
SOCKS_PORT="1080"						# (TCP) SOCKS
OPENWINDOWS_PORT="2000"					# (TCP) OpenWindows
SQUID_PORT="3128"						# (TCP) Squid

# Location of nft in your system
$NFT=`which nft`

# import constants
# source Constants.sh

################ Enabling Kernel-Monitoring Support ################

# Enable broadcast echo Protection to ignore an echo request
# to a broadcast address thus preventing compromising all host 
# at one time
echo "1" > /proc/sys/net/ipv4/icmp_echo_ignore_broadcasts

# Disable Source Routed Packages 
# source routing, also called path addressing,allows a sender
# of a packet to partially or completely specify the route the
# packet takes through the network
echo "0" > /proc/sys/net/ipv4/conf/all/accept_source_route

# Enable TCP SYN Cookie Protection
# Protect against SYN Flooding Attack
echo "1" > /proc/sys/net/ipv4/tcp_syncookies

# Disable ICMP Redirect Acceptance
echo "0" > /proc/sys/net/ipv4/conf/all/accept_redirects

# Do not send ICMP redirect messages
echo "0" > /proc/sys/net/ipv4/conf/all/send_redirects

# Drop Spoofed Packets coming in on an interface ,which , if 
# replied to, would result in the reply going out a different 
# interface
for f in /proc/sys/net/ipv4/conf/*/rp_filter; do
	echo "1" > f
done

# Log packets with impossible addresses (address 0.0.0.0, 
# host 0 on any network ,any host on 127 network and Class
# E network)
echo "1" > /proc/sys/net/ipv4/conf/all/log_martians

################ Enabling Kernel-Monitoring Support ################


################ Removing Any Preexisting Rules ####################
# Removing all existing rules from all chains
# $NFT flush table <table_name>
for i in `$NFT list tables | awk 'print $2'`
do
	echo "Flushing ${i}"
	$NFT flush table ${i}
	for j in `$NFT list table ${i} | grep chain | awk 'print $2'`
	do
		echo "...Deleting chain ${j} from table ${i}"
		$NFT delete chain ${i} ${j}
	done
	echo "Deleting table ${i}"
	$NFT delete table ${i}
done
################ Removing Any Preexisting Rules ####################


############### Re-create default table and chains #################
$NFT -f setup-tables.sh

############### Re-create default table and chains #################


#############################  Main  ############################
$NFT add rule filter input iifname lo accept 
$NFT add rule filter output oifname lo accept

# Using conntrack to bypass already established or related traffic
$NFT add rule filter input ct state established,related accept
$NFT add rule filter input ct state invalid log prefix \"INVALID input: \" limit 
 rate 3/second drop
$NFT add rule filter output ct state established,related accept
$NFT add rule filter output ct state invalid log prefix \"INVALID output: \" limit
 rate 3/second drop


# Refuse spoofed packets pretending to be from ipaddr of server's 
# ethernet adaptor
$NFT add rule filter input iifname $INTERNET ip saddr $IPADDR

# There is no need to block outgoing packet's destinating for yourself 
# as it will be sent to lo interface anyway,this is to say,the packet 
# sent from your machine and to your machine never reaches external 
# interface

# Reject packages claiming to be from CLASS_A,CLASS_B and CLASS_C 
# private network
$NFT add rule filter input iifname $INTERNET ip saddr $CLASS_A drop
$NFT add rule filter input iifname $INTERNET ip saddr $CLASS_B drop
$NFT add rule filter input iifname $INTERNET ip saddr $CLASS_C drop

# Reject packages claiming from loopback interfaces
$NFT add rule filter input iifname $INTERNET ip saddr $LOOPBACK drop

# Reject malformed broadcast packages
$NFT add rule filter input iifname $INTERNET ip saddr $BROADCAST_DEST \
 log prefix \"With 255.255.255.255 as source: \" limit rate 3/second drop
$NFT add rule filter input iifname $INTERNET ip saddr $BROADCAST_SRC \
 log prefix \"With 0.0.0.0 as destination: \" limit rate 3/second drop

# Refuse directed broadcasts used to map networks and form
# DOS attacks
$NFT add rule filter input iifname $INTERNET ip daddr $SUBNET_BASE drop
$NFT add rule filter input iifname $INTERNET ip daddr $SUBNET_BROADCAST drop

# Refuse CLASS_D multicast address
# Illegal as soure address
$NFT add rule filter input iifname $INTERNET ip saddr $CLASS_D_MULTICAST drop

# Legitimate multicast packets are always UDP packets
# Refuse any not-udp packets to CLASS_D_MULTICAST address
$NFT add rule filter input iifname $INTERNET ip daddr $CLASS_D_MULTICAST ip protocol \
!= udp drop

# Accept incoming multicast packets
$NFT add rule filter input iifname $INTERNET ip daddr $CLASS_D_MULTICAST ip protocol \
udp accept

# Refuse packets from CLASS_E address
$NFT add rule filter input iifname $INTERNET ip saddr $CLASS_E_RESERVED_NET drop

# X Window connection establishment
# Refuse initializing from server to other machine
$NFT add rule filter output oifname $INTERNET ct state new tcp dport $XWINDOWS_PORTS reject

# Refuse all incoming establishment attemps to XWindows as all X traffic should
# be tunnelled through SSH
$NFT add rule filter input iifname $INTERNET ct state new tcp dport $XWINDOWS_PORTS drop


# Establishing a connection over TCP to NFS,Openwindows,squid or socks
$NFS add rule filter input iifname $INTERNET \
tcp dport \
{$SQUID_PORT,$NFS_PORT,$OPENWINDOWS_PORT,$SOCKS_PORT} \
ct state new drop

$NFS add rule filter output oifname $INTERNET \
tcp dport \
{$SQUID_PORT,$NFS_PORT,$OPENWINDOWS_PORT,$SOCKS_PORT} \
ct state new reject

# NFS and RPC lockd
$NFT add rule filter input iifname $INTERNET udp dport \
{$NFS_PORT,$LOCKD_PORT} drop

$NFT add rule filter output oifname $INTERNET udp dport \
{$NFS_PORT,$LOCKD_PORT} reject

# Allowing DNS Lookups as a client
isConntrack=`lsmod | grep ^nf_conntrack_ipv4 | awk '{print $1}'`
NAMESEVER="my.name.server"			# (TCP/UDP) DNS

$NFT add rule filter output oifname $INTERNET ip saddr $INTERNET \
udp sport $UNPRIVPORTS ip daddr $NAMESEVER udp dport 53 ct state new accept

$NFT add rule filter input iifname $INTERNET ip saddr $NAMESEVER \
udp sport 53 ip daddr $INTERNET udp dport $UNPRIVPORTS accept

# DNS retries over TCP
$NFT add rule filter output oifname $INTERNET ip daddr $NAMESEVER tcp \
dport 53 ip sddr $IPADDR sport $UNPRIVPORTS ct state new accept

$NFT add rule filter input iifname $INTERNET ip saddr $NAMESEVER tcp \
sport 53 ipaddr $INTERNET dport $UNPRIVPORTS flags != syn accept

# Email(TCP SMTP Port 25,POP Port 110,IMAP Port 143)
# Relay outgoing email with ISP's relay server
SMTP_GATEWAY="my.isp.server" 			# External mail server or relay

$NFT add rule filter output oifname $INTERNET ip daddr $SMTP_GATEWAY tcp dport 25
ip sddr $IPADDR tcp sport $UNPRIVPORTS accept

$NFT add rule filter input iifname $INTERNET ip saddr $SMTP_GATEWAY tcp sport 25 
ip daddr $IPADDR tcp dport $UNPRIVPORTS tcp flags != syn accept

# Sending mail to any external mail server
$NFT add rule output oifname $INTERNET ip saddr $IPADDR tcp sport $UNPRIVPORTS 
tcp dport 25 accept

$NFT add rule input iifname $INTERNET ip daddr $IPADDR tcp dport $UNPRIVPORTS 
tcp sport 25 tcp flags != syn accept

# Receving mail as an internal smtp server(TCP Port 25)
$NFT add rule filter input iifname $INTERNET ip daddr $IPADDR tcp dport 25 tcp sport $UNPRIVPORTS 
accept

$NFT add rule filter output oifname $INTERNET ip saddr $IPADDR tcp sport 25 tcp dport $UNPRIVPORTS
tcp flags != syn accept

# Receving mail as an POP over SSL client
POP_SERVER="my.isp.pop.server"
$NFT add rule filter input iifname $INTERNET ip daddr $IPADDR tcp dport $UNPRIVPORTS ip saddr $POP_SERVER tcp sport 995 
 tcp flags != syn accept

$NFT add rule filter output oifname $INTERNET ip saddr $IPADDR tcp sport $UNPRIVPORTS ip daddr $POP_SERVER dport 995
 accept

# Receving mail as an IMAP over SSL client
IMAP_SERVER="my.isp.imap.server"
$NFT add rule filter input iifname $INTERNET ip daddr $IPADDR tcp dport $UNPRIVPORTS ip saddr $POP_SERVER tcp sport 993 
 tcp flags != syn accept

$NFT add rule filter output oifname $INTERNET ip saddr $IPADDR tcp sport $UNPRIVPORTS ip daddr $POP_SERVER dport 993
 accept

# Hosting a POP over SSL server for remote clients
# POP_CLIENTS="network/mask"
$NFT add rule filter input iifname $INTERNET ip daddr $IPADDR tcp dport 995 <ip saddr [clients]> tcp sport $UNPRIVPORTS 
accept

$NFT add rule filter output oifname $INTERNET ip saddr $IPADDR tcp sport 995 tcp dport $UNPRIVPORTS
tcp flags != syn accept 

# SSH
SSH_PORTS="1024-65535"				# RSA authentication
#SSH_PORTS="1020-65535"				# RHOST authentication

# allow access to remote SSH server
$NFT add rule filter output oifname $INTERNET ip saddr $IPADDR tcp sport $SSH_PORTS 
tcp dport 22 accept

$NFT add rule filter input iifname $INTERNET ip daddr $IPADDR tcp dport $SSH_PORTS 
tcp sport 22 tcp flags != syn accept

# allowing SSH access to this server
$NFT add rule filter input iifname $INTERNET ip daddr $IPADDR tcp dport 22  
tcp sport $SSH_PORTS accept

$NFT add rule filter output oifname $INTERNET ip saddr $IPADDR tcp sport 22 
tcp dport $SSH_PORTS tcp flags != syn accept

# allowing outgoing FTP control channel
$NFT add rule filter output oifname $INTERNET ip saddr $IPADDR tcp sport $UNPRIVPORTS 
tcp dport 21 accept

$NFT add rule filter input iifname $INTERNET ip daddr $IPADDR tcp dport $UNPRIVPORTS 
tcp sport 21 accept

# Port-mode FTP data channel
$NFT add rule filter input iifname $INTERNET ip daddr $IPADDR tcp dport $UNPRIVPORTS 
tcp sport 20 accept

$NFT add rule filter output oifname $INTERNET ip saddr $IPADDR tcp sport $UNPRIVPORTS 
tcp dport 20 tcp flags != syn accept

# DHCP
# initialization or rebinding :No lease or lease time expired
$NFT add rule filter output oifname $INTERNET ip saddr $BROADCAST_SRC udp sport 67-68 ip daddr $BROADCAST_DEST
udp dport 67-68  accept

# Incoming DHCPOFFER from available DHCP server
$NFT add rule filter input iifname $INTERNET udp sport 67-68 udp dport 67-68 accept

# NTP 
TIME_SERVER="my.time.server"

# query as a client
$NFT add rule filter output oifname $INTERNET udp ip saddr $IPADDR udp sport $UNPRIVPORTS 
ip daddr $TIME_SERVER udp dport 123 accept

$NFT add rule filter input iifname $INTERNET udp ip daddr $IPADDR udp dport $UNPRIVPORTS 
ip saddr $TIME_SERVER udp sport 123 accept

# END of MAIN
# log all incoming and dropped packets
$NFT add rule filter input iifname $INTERNET log limit rate 3/second

# log all outgoing and dropped packets
$NFT add rule filter output oifname $INTERNET log limit rate 3/second













