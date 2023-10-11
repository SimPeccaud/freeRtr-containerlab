#!/bin/bash

wait_time_for_time_to_read=10
if [ "$1" = "--quick" ]; then
  shift 1
  wait_time_for_time_to_read=0
fi

echo "$0: wait_time_for_time_to_read=$wait_time_for_time_to_read" 1>&2

###

set -e

set -x

type -p containerlab || { echo "containerlab must be installed"; exit 1; }

#echo 0.a. 
git clone https://github.com/rare-freertr/freeRtr-containerlab && cd ./freeRtr-containerlab/lab/005-rare-hello-fod

#0.b. 
containerlab destroy -t rtr005.clab.yml || true
containerlab deploy -t rtr005.clab.yml

#0.c. 
containerlab inspect -t rtr005.clab.yml # for later inspection, if needed

# really needed
set +x
w=10
echo "sleeping $w seconds, to give freertr and FoD time to get ready" 1>&2
sleep "$w" # need enough time for freertr to be ready
set -x

clear

##

# 1. setup of hosts + test0: unblocked ping (FoD's exabgp not yet connected to freertr)
# (freertr is already configured as needed by ./clab-rtr005/rtr1/run/conf/rtr-sw.txt : interface as well as server bgp config)

# 1.a. setup of hosts
docker exec -ti clab-rtr005-host1 ifconfig eth1 10.1.10.1 netmask 255.255.255.0
docker exec -ti clab-rtr005-host1 route add -net 10.2.10.0 netmask 255.255.255.0 gw 10.1.10.10 

docker exec -ti clab-rtr005-host2 ifconfig eth1 10.2.10.2 netmask 255.255.255.0
docker exec -ti clab-rtr005-host2 route add -net 10.1.10.0 netmask 255.255.255.0 gw 10.2.10.10 

##

# 1.b. test0: unblocked ping (FoD's exabgp not yet connected to freertr)

# 1.b.1. test0.1: check freetrtr flowspec status/statistics (before unblocked ping):
#docker exec -ti clab-rtr005-rtr1 sh -c 'apt-get update && apt-get install netcat-traditional'
#docker exec -ti clab-rtr005-rtr1 sh -c '{ echo "show ipv4 bgp 1 flowspec database"; echo "show policy-map flowspec CORE ipv4"; echo exit; } | netcat 127.1 2323'
docker exec -ti clab-rtr005-rtr1 bash -c '{ echo "show ipv4 bgp 1 flowspec database"; echo "show policy-map flowspec CORE ipv4"; echo exit; } | (exec 3<>/dev/tcp/127.0.0.1/2323; cat >&3; cat <&3; exec 3<&-)'

# 1.b.2 test0.2: unblocked ping (FoD's exabgp not yet connected to freertr)
docker exec -ti clab-rtr005-host1 ping -c 5 10.2.10.2
#docker exec -ti clab-rtr005-host2 ping -c 5 10.1.10.1

# 1.b.3. test0.3: check freetrtr flowspec status/statistics (after blocked ping):
docker exec -ti clab-rtr005-rtr1 bash -c '{ echo "show ipv4 bgp 1 flowspec database"; echo "show policy-map flowspec CORE ipv4"; echo exit; } | (exec 3<>/dev/tcp/127.0.0.1/2323; cat >&3; cat <&3; exec 3<&-)'

#

set +x
echo 1>&2
wait1="$wait_time_for_time_to_read"
if [ "$wait_time_for_time_to_read" -gt 0 ]; then
  echo "waiting $wait1 (wait_time_for_time_to_read) seconds" 1>&2
  sleep "$wait1"
  clear
fi
set -x

##


# 2. add peering of fod's exabg to freertr

docker exec -ti clab-rtr005-fod1 ifconfig eth1 10.3.10.3/24
docker exec -ti clab-rtr005-fod1 ./exabgp/run-exabgp-generic --init-conf 10.3.10.3 10.3.10.3 1001 10.3.10.10 10.3.10.10 2001 -- --supervisord --restart
#to check the exabgp stdout: 
docker exec -ti clab-rtr005-fod1 tail log/exabgp-stdout.log

#

set +x
echo 1>&2
wait1="$wait_time_for_time_to_read"
if [ "$wait_time_for_time_to_read" -gt 0 ]; then
  echo "waiting $wait1 (wait_time_for_time_to_read) seconds" 1>&2
  sleep "$wait1"
  clear
fi
set -x

##

# 3. test1: blocked ping (with FoD's exabgp peering to freertr)

# 3.a. test1.a: add blocking rule via BGP

# 3.a.1.a. show exabgp current exported rules/routes (before adding the blocking rule):
docker exec -ti clab-rtr005-fod1 sh -c '. ./venv/bin/activate && exabgpcli show adj-rib out extensive'

# 3.a.1.b. show freertr flowspec status/statistics (before adding the blocking rule):
docker exec -ti clab-rtr005-rtr1 bash -c '{ echo "show ipv4 bgp 1 flowspec database"; echo "show policy-map flowspec CORE ipv4"; echo exit; } | (exec 3<>/dev/tcp/127.0.0.1/2323; cat >&3; cat <&3; exec 3<&-)'

# 3.a.2. proper adding of blocking rule:
docker exec -ti clab-rtr005-fod1 ./inst/helpers/enable_rule.sh 10.1.10.1/32 10.2.10.2/32 1 1 # first parameter: src IP prefix; second parameter: dst IP prefix; last but one parameter: 1=icmp ; last parameter: 1=enable rule on router, i.e., push it now

# 3.a.3.a. show exabgp current exported rules/routes (after adding the blocking rule):
docker exec -ti clab-rtr005-fod1 sh -c '. ./venv/bin/activate && exabgpcli show adj-rib out extensive'

# 3.a.3.b. show freertr flowspec status/statistics (after adding the blocking rule):
docker exec -ti clab-rtr005-rtr1 bash -c '{ echo "show ipv4 bgp 1 flowspec database"; echo "show policy-map flowspec CORE ipv4"; echo exit; } | (exec 3<>/dev/tcp/127.0.0.1/2323; cat >&3; cat <&3; exec 3<&-)'

#

set +x
echo 1>&2
wait1="$wait_time_for_time_to_read"
if [ "$wait_time_for_time_to_read" -gt 0 ]; then
  echo "waiting $wait1 (wait_time_for_time_to_read) seconds" 1>&2
  sleep "$wait1"
  clear
fi
set -x

##

# 3.b. test1.b: perform ping(s) to be blocked with status/statistics before and afterwards

# 3.b.1. show exabgp current exported rules/routes:
docker exec -ti clab-rtr005-fod1 sh -c '. ./venv/bin/activate && exabgpcli show adj-rib out extensive'

# 3.b.2. show freertr flowspec status/statistics (before ping(s) to be blocked):
docker exec -ti clab-rtr005-rtr1 bash -c '{ echo "show ipv4 bgp 1 flowspec database"; echo "show policy-map flowspec CORE ipv4"; echo exit; } | (exec 3<>/dev/tcp/127.0.0.1/2323; cat >&3; cat <&3; exec 3<&-)'

# 3.b.3. perform proper ping(s) to be blocked:
! docker exec -ti clab-rtr005-host1 ping -c 10 10.2.10.2
#! docker exec -ti clab-rtr005-host2 ping -c 10 10.1.10.1

# 3.b.4. show freertr flowspec status/statistics (after ping(s) to be blocked):
docker exec -ti clab-rtr005-rtr1 bash -c '{ echo "show ipv4 bgp 1 flowspec database"; echo "show policy-map flowspec CORE ipv4"; echo exit; } | (exec 3<>/dev/tcp/127.0.0.1/2323; cat >&3; cat <&3; exec 3<&-)'

#

set +x
echo 1>&2
wait1="$wait_time_for_time_to_read"
if [ "$wait_time_for_time_to_read" -gt 0 ]; then
  echo "waiting $wait1 (wait_time_for_time_to_read) seconds" 1>&2
  sleep "$wait1"
  clear
fi
set -x

##

# 4. test2: unblocked ping (with FoD's exabgp peering to freertr)

# 4.a. test2.a: remove blocking rule via BGP

# 4.a.1.a. show exabgp current exported rules/routes (before removing the blocking rule):
docker exec -ti clab-rtr005-fod1 sh -c '. ./venv/bin/activate && exabgpcli show adj-rib out extensive'

# 4.a.1.b. show freertr flowspec status/statistics (before removeing the blocking rule):
docker exec -ti clab-rtr005-rtr1 bash -c '{ echo "show ipv4 bgp 1 flowspec database"; echo "show policy-map flowspec CORE ipv4"; echo exit; } | (exec 3<>/dev/tcp/127.0.0.1/2323; cat >&3; cat <&3; exec 3<&-)'

# 4.a.2. proper removing of the blocking rule via BGP 
docker exec -ti clab-rtr005-fod1 ./inst/helpers/enable_rule.sh 10.1.10.1/32 10.2.10.2/32 1 0 # first parameter: src IP prefix; second parameter: dst IP prefix; last but one parameter: 1=icmp ; last parameter: 0=disable rule on router if it exists and is active or just create rule in INACTIVE state in FoD DB 

# 4.a.3.a. show exabgp current exported rules/routes (after removing the blocking rule):
docker exec -ti clab-rtr005-fod1 sh -c '. ./venv/bin/activate && exabgpcli show adj-rib out extensive'

# 4.a.3.b. show freertr flowspec status/statistics (after removing the blocking rule):
docker exec -ti clab-rtr005-rtr1 bash -c '{ echo "show ipv4 bgp 1 flowspec database"; echo "show policy-map flowspec CORE ipv4"; echo exit; } | (exec 3<>/dev/tcp/127.0.0.1/2323; cat >&3; cat <&3; exec 3<&-)'

#

set +x
echo 1>&2
wait1="$wait_time_for_time_to_read"
if [ "$wait_time_for_time_to_read" -gt 0 ]; then
  echo "waiting $wait1 (wait_time_for_time_to_read) seconds" 1>&2
  sleep "$wait1"
  clear
fi
set -x

##

# 4.b. test2.b: perform ping(s) to be NOT blocked with status/statistics before and afterwards

# 4.b.1. show exabgp current exported rules/routes:
docker exec -ti clab-rtr005-fod1 sh -c '. ./venv/bin/activate && exabgpcli show adj-rib out extensive'

# 4.b.2. show freertr flowspec status/statistics (before ping(s) NOT to be blocked):
docker exec -ti clab-rtr005-rtr1 bash -c '{ echo "show ipv4 bgp 1 flowspec database"; echo "show policy-map flowspec CORE ipv4"; echo exit; } | (exec 3<>/dev/tcp/127.0.0.1/2323; cat >&3; cat <&3; exec 3<&-)'

# 4.b.1. proper ping(s) to be not blocked:
docker exec -ti clab-rtr005-host1 ping -c 10 10.2.10.2
#docker exec -ti clab-rtr005-host2 ping -c 10 10.1.10.1

# 4.b.2. test2: show freertr flowspec status/statistics (after ping(s) NOT to be blocked)
docker exec -ti clab-rtr005-rtr1 bash -c '{ echo "show ipv4 bgp 1 flowspec database"; echo "show policy-map flowspec CORE ipv4"; echo exit; } | (exec 3<>/dev/tcp/127.0.0.1/2323; cat >&3; cat <&3; exec 3<&-)'

##
