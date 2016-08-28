#!/bin/bash 
####################################
#Function 	: Sanity checks on Ubuntu 14.04
#Auther 	: Dipak Warade
#Date		: 24/07/2016
#Disclaimer	:Your use of the script,is at your sole risk. All information on these pages is provided "as -is", without any warranty. You may modify this script as per your requirement. should not be used without understanding of your environement and script functionality.
####################################
RED='\033[0;31m'
NC='\033[0m' # No Color
echo "################################### SUMMERY FROM `uname -n` #################################"
CPU=`top -b -n1 | grep "Cpu(s)" | awk '{print $2 + $4}'`
FREE_MEM=`free -m | grep Mem`
FREE_SWAP=`free -m | grep Swap`
CURRENT=`echo $FREE_MEM | cut -f3 -d' '`
CURRENT_SWAP=`echo $FREE_SWAP | cut -f3 -d' '`
TOTAL=`echo $FREE_MEM | cut -f2 -d' '`
TOTAL_SWAP=`echo $FREE_SWAP | cut -f2 -d' '`
SWAP=$(echo "scale = 2; $CURRENT_SWAP/$TOTAL_SWAP*100" | bc)
RAM=$(echo "scale = 2; $CURRENT/$TOTAL*100" | bc)
HDD=`df -lh | awk '{if ($6 == "/") { print $5 }}' | head -1 | cut -d'%' -f1`
MOUNT_RO=$(if mount|grep  -v rw >/tmp/ro_fs; then  echo "RO Mounts found check /tmp/ro_fs and investigate"; else echo "No Read Only Mounts Found"; fi)
LOAD=$(uptime|awk '{print $10, $11 ,$12}')
LINK_DOWN=$(ip link show|grep -i DOWN|wc -l)
printf "CURRENT CPU USAGE %%"\:" ${RED} $CPU ${NC}\n"
printf "CURRENT SWAP USAGE %%"\:" ${RED} $SWAP ${NC}\n"
printf "CURRENT / USAGE %% "\:" ${RED} $HDD ${NC}\n"
printf "CURRENT RAM USAGE %%"\:" ${RED} $RAM ${NC}\n"
printf "Read Only Mounts "\:" ${RED} $MOUNT_RO ${NC}\n"
printf "Current Load on the System 1min,5min,15min "\:" ${RED} $LOAD ${NC}\n"
printf "TOTAL Links Down,Investigate if more than 0  "\:" ${RED} $LINK_DOWN ${NC}\n"
#echo "CURRENT RAM % : $RAM"
#echo "HDD %: $HDD"
#echo $MOUNT_RO
#echo "Current Load on the System 1min,5min,15min : $LOAD"
#echo "TOTAL Links Down,Investigate if more than 0 : $LINK_DOWN"
