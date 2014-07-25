#!/bin/bash
installPath="/opt/resolve-dynamic-hosts"
cronPath="/etc/cron.d"
updateFrequency=1

if [ "$EUID" -ne 0 ]
then
  echo "[$(tput setaf 1)Error$(tput sgr0)] This script needs superuser privileges to run...
Exiting..."
  exit 1
fi

read -p "Enter the location to install the script [/opt/resolve-dynamic-hosts]: " tmp

if [[ ! -z $tmp ]]
then
	installPath=$tmp
fi

unset tmp

# Get location of iptables
iptablespath="/sbin/iptables"
if [[ -f /usr/bin/which ]]
then
	iptablespath=`which iptables`
else
	read -p "Enter the location of iptables [/sbin/iptables]: " tmp
	if [[ ! -z $tmp ]]
	then
		iptablespath=$tmp
	fi
	unset tmp
fi

if [[ ! -f $iptablespath ]]
then
	echo "[$(tput setaf 1)Error$(tput sgr0)] iptables binary not found '$iptablespath'...
exiting..."
	exit 1
fi

read -p "Enter the frequency (minutes) with which to update the iptables Rules [1]: " tmp

if [[ ! -z $tmp ]]
then
	updateFrequency=$tmp
fi

if [ ! -d $cronPath ]
then
	echo "[$(tput setaf 1)Error$(tput sgr0)] cron path '$cronPath' not found....
exiting..."
	exit 1
fi

echo
echo
echo "###################################################################################################"
echo "Saving current iptables rules to backup.iptables to restore type iptables-restore < backup.iptables"
echo "###################################################################################################"
iptables-save > backup.iptables

echo
echo
echo "[$(tput setaf 4)Info$(tput sgr0)] Installing Cronjob..."
echo "*/$updateFrequency * * * * root $installPath/run.sh" > $cronPath/resolve-asterisk-dynamic-hosts

if [[ -f $cronPath/resolve-asterisk-dynamic-hosts ]]
then
	echo "[$(tput setaf 2) OK $(tput sgr0)] Installing Cronjob... Done"
else
	echo "[$(tput setaf 1)Error$(tput sgr0)] Installing Cronjob... Error..."
fi

echo "[$(tput setaf 4)Info$(tput sgr0)] Creating directories..."
mkdir -p $installPath

if [[ -d $installPath ]]
then
	echo "[$(tput setaf 2) OK $(tput sgr0)] Creating directories..."
else
	echo "[$(tput setaf 1)Error$(tput sgr0)] Creating directories... $(tput setaf 1)Error$(tput sgr0): directories not created '$installPath'..."
fi

echo "[$(tput setaf 4)Info$(tput sgr0)] Installing Script..."
echo "
#!/bin/bash
#set -x
PATH=\"/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin\"
workingDir=\$( dirname \"\${BASH_SOURCE[0]}\" )

while read -r line
do
	while read ips
	do
		digIpsCmd=\"dig A \$ips +short | grep -v '\\.$'\"
		ip=\"\`eval \${digIpsCmd}\`\"
		iplist=\$iplist\$ip,
	done < <(dig A \$line +short)
done < <(grep -h -E -o '^host=(.*?)' /etc/asterisk/* | grep -v dynamic | cut -d \"=\" -f2 | cut -d \";\" -f1)

while read -r ip port protocol
do
        while read ips
        do
                digIpsCmd=\"dig A \$ips +short | grep -v '\\.$'\"
                ip=\"\`eval \${digIpsCmd}\`\"

		if [[ ! -z \"\$port\" ]]
		then
	                ipportlist=\"\$ipportlist\$ip \$port \$protocol,\"
		else
			iplist=\$iplist\$ip,
		fi

        done < <(dig A \$ip +short)
done < <(cat \$workingDir/list | grep -v \"#\" | sed -e \"s/:/ /g\")

iptablesListCmd=\"$iptablespath -vnL DYNAMIC_HOSTS | sed '1,2d' | wc -l\"
numberOfRules=\"\`eval \${iptablesListCmd}\`\"

tmpIFS=\$IFS
IFS=\",\"
for ip in \$iplist
do
	$iptablespath -A DYNAMIC_HOSTS -s \$ip -j ACCEPT
#	$iptablespath -A DYNAMIC_HOSTS -d \$ip -j ACCEPT
done

for ips in \$ipportlist
do
	ip=\`echo \$ips | cut -d \" \" -f1\`
	port=\`echo \$ips | cut -d \" \" -f2\`
	protocol=\`echo \$ips | cut -d \" \" -f3\`
	$iptablespath -A DYNAMIC_HOSTS -p \$protocol --dport \$port -s \$ip -j ACCEPT
done
IFS=\$tmpIFS


for i in \$(seq 1 \$numberOfRules)
do
	$iptablespath -D DYNAMIC_HOSTS 1
done
" > ./run.sh

echo "# When specifying a port a protocol must also be specified each entry on a new line.
#
# Examples as follows:
#
# www.google.com:22:tcp
# www.ibm.com
" > ./list


install -m 700 run.sh $installPath
install -m 700 list $installPath

if [[ -f $installPath/run.sh ]]
then
	echo "[$(tput setaf 2) OK $(tput sgr0)] script installed..."
else
	echo "[$(tput setaf 1)Error$(tput sgr0)] script not installed, check permissions of '$installPath'..."
fi



echo "[$(tput setaf 4)Info$(tput sgr0)] Creating iptables chain..."

nc=`$iptablespath -N DYNAMIC_HOSTS 2>&1`

if [[ "$nc" == "iptables: Chain already exists." ]]
then
	echo "[$(tput setaf 3)Warn$(tput sgr0)] $nc"
else
	echo "[$(tput setaf 2) OK $(tput sgr0)] $nc"
fi

echo "[$(tput setaf 4)Info$(tput sgr0)] Adding dynamic hosts to INPUT chain"
$iptablespath -I INPUT -j DYNAMIC_HOSTS

echo "[$(tput setaf 4)Info$(tput sgr0)] Restarting cron...
"
/usr/sbin/service crond restart

echo

echo "[$(tput setaf 4)Info$(tput sgr0)] Saving iptables rules
"
/usr/sbin/service iptables save

echo
echo "$(tput setaf 2)Software installed!$(tput sgr0)

You can now edit $installPath/list"
