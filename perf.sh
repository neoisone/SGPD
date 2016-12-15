#!/bin/bash
#  Author : Shatadru Bandyopadhyay
#         : Ganesh Gore
#
# Licenced under GPLv3, check LICENSE.txt
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
perf=1
lsbyes=1
iotopyes=0
iostatold=0
ver=`uname -r`

function com_check(){
which $1 > /dev/null 2> /dev/null
if [ "$?" -ne "0" ];then
	echo Command : $1 Not found...
	if [ "$1" == "iotop" ]; then
		echo "Install iotop package (#yum install iotop) and run the script again. exiting..."
		exit
	elif [ "$1" == "sar" ]; then 
		echo "Install systat package (#yum install sysstat) and run the script again. exiting..."
		exit
	elif [ "$1" == "lsb_release" ]; then 
		lsbyes=0
	elif  [ "$1" == "perf" ]; then 
		echo "$1 is not installed"
		echo "Refer : https://access.redhat.com/solutions/386343"
		echo "Do you want to skip collection of perf data and continue ? (Y/N)"
		read a		
		if  [ "$a" == "Y" ] ||  [ "$a" == "y" ] ||  [ "$a" == "Yes" ] ; then
			perf=0
			sleep 1;
		else
			echo "Install $1 package (#yum install $1) and run the script again. exiting..."
			exit
		fi


	else
		echo "Install $1 package (#yum install $1) and run the script again. exiting..."
		exit
	fi
fi

}

function pkg_check() {
rpm -q $1 > /dev/null 2> /dev/null
if [ "$?" -ne "0" ];then
	echo Package : $1 Not found...
	if  [ "$1" == "kernel-debuginfo-$ver" ]; then 
		echo "Refer : https://access.redhat.com/solutions/386343"
		echo "Do you want to skip collection of perf data and continue ? (Y/N)"
		read a		
		if  [ "$a" == "Y" ] ||  [ "$a" == "y" ] ||  [ "$a" == "Yes" ] ; then
			perf=0
			sleep 1;
		else
			echo "Install $1 package (#yum install $1) and run the script again. exiting..."
			echo "Refer : [How can I download or install debuginfo packages for RHEL systems?] https://access.redhat.com/solutions/9907"
			exit
		fi
	fi	
fi
}

com_check sar
com_check lsb_release
com_check perf
pkg_check kernel-debuginfo-$ver
## OS CHECK ##

if [ $lsbyes -eq "1" ]; then
version=`lsb_release -r|cut -f2`
else
version=`cat /etc/redhat-release |cut -f7 -d " "`
fi

v=`echo $version|cut -f1 -d "."`

if [ $v -ge "6" ];then
com_check iotop
iotopyes=1
else
echo "iotop and pidstat command will not be collected as system is RHEL 5 or lower"
iotopyes=0
iostatold=1
fi

ITERATION=30
INTERVAL=2  # default interval
if [ -n "$1" ]; then
     ITERATION=$2
fi

if [ -n "$2" ]; then
     INTERVAL=$1
fi

echo "Start collecting data."
echo "Running for $ITERATION times, after $INTERVAL seconds interval"

#ITERATION=$((ITERATION / 2))
rm -rf /tmp/*.out

### End function ###
function end () {
dmesg >> /tmp/dmesg2.out
#Creating tarball of outputs
FILENAME="outputs-`date +%d%m%y_%H%M%S`.tar.bz2"
if [ "$perf" == "1" ]; then
	tar -cjvf "$FILENAME" /tmp/*.out $DIR"perf"
else
	tar -cjvf "$FILENAME" /tmp/*.out
fi
echo "Please upload the file:" $FILENAME
exit
}
trap end SIGHUP SIGINT SIGTERM



# One time data
#~~~
cat /proc/cpuinfo >> /tmp/cpu.out
dmesg >> /tmp/dmesg1.out
#~~~
# One time perf 
if [ "$perf" == "1" ]; then
	tempdirname=`cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 10 | head -n 1`
	mkdir /tmp/$tempdirname/
	DIR=/tmp/$tempdirname/
	echo "Collecting perf data"
	mkdir -p $DIR"perf"; cd $_
	perf record -a -g sleep 20
	perf archive
	cd ..
fi
#~~~




#~~~ Continuous collection by will run outside loop ~~~
#date >> /tmp/vmstat.out; vmstat $INTERVAL $ITERATION >> /tmp/vmstat.out &
if [ "$iostatold" -eq "1" ]; then
	iostat -t  -x $INTERVAL $ITERATION >> /tmp/iostat.out &
	else
	iostat -t -z -x $INTERVAL $ITERATION >> /tmp/iostat.out &
fi
sar $INTERVAL $ITERATION >> /tmp/sar.out &
sar -A $INTERVAL $ITERATION -p >> /tmp/sarA.out &
mpstat $INTERVAL $ITERATION -P ALL >> /tmp/mpstat.out &
#~~~

# ~~~ Loop begins to collect data ~~~
((count=0))
((CURRENT_ITERATION=1))
while true
do
	if((CURRENT_ITERATION <= ${ITERATION}))
	then	
		echo "$(date +%T): Collecting data : Iteration "$(($CURRENT_ITERATION))
		date >> /tmp/top.out; top -n 1 -b >> /tmp/top.out
		if [ "$iotopyes" -eq "1" ]; then
			date >> /tmp/iotop.out; iotop -n 1 -b >> /tmp/iotop.out
			date >> /tmp/pidstat.out ; pidstat >> /tmp/pidstat.out &
		fi
		date >> /tmp/mem.out; cat /proc/meminfo >> /tmp/mem.out
		date >> /tmp/free.out; free -m >> /tmp/free.out
		date >> /tmp/psf.out; ps auxf >> /tmp/psf.out
		date >> /tmp/ps_auxwwwm.out; ps auxwwwm >> /tmp/ps_auxwwwm.out
		date >> /tmp/ps.out  ; ps aux >> /tmp/ps.out  
		((CURRENT_ITERATION++))
		sleep $INTERVAL
		
		continue;
	else
		break;
	fi
	
done
#~~~ Collection End ~~~
end
