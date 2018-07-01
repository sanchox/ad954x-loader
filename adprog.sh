#!/bin/bash

echo 30 > /sys/class/gpio/export
echo high > /sys/class/gpio/gpio30/direction
sleep 1
echo low > /sys/class/gpio/gpio30/direction

modprobe i2c-dev

I2CBUS="1"
I2CADDR="0x49"

function h2d() {  
	echo $((16#$1))
}

function d2h() {  
	printf "%02X" $1 
}

function hex_seq() {
	for i in $( seq $( h2d $1 ) $( h2d $2 ) )
	do
		 printf "%04X\n" $i
	done
}

function set_data() {
	page=${1:0:2}
	addr=${1:2:2}
	data=$2
	echo "Setting page $page addr $addr to $data"
	i2cset -y $I2CBUS $I2CADDR "0x${1:0:2}" "0x${1:2:2}" "0x$data" i
}

function transfer() {
	for index in $( hex_seq $1 $2 )
	do
		echo $index
		data=${map[$index]}
		if [ -z "$data" ]; then continue; fi
		echo "$index $data"
		set_data $index $data
	done
}

function io_update {
	echo "Updating I/O"
	i2cset -y $I2CBUS $I2CADDR "0x0" "0x5" "0x1" i
	sleep 1
}

function calibrate {
	echo "Calibrating"
	i2cset -y $I2CBUS $I2CADDR "0x0A" "0x02" "0x1" i
	io_update
	i2cset -y $I2CBUS $I2CADDR "0x0A" "0x02" "0x0" i
	io_update
}

function sync_distribution {
	echo "Syncronising distribution"
	i2cset -y $I2CBUS $I2CADDR "0x0A" "0x02" "0x2" i
	io_update
	i2cset -y $I2CBUS $I2CADDR "0x0A" "0x02" "0x0" i
	io_update
}

function write_eeprom {
	echo "Writing eeprom"
	i2cset -y $I2CBUS $I2CADDR "0x0E" "0x00" "0x1" i
	io_update
	i2cset -y $I2CBUS $I2CADDR "0x0E" "0x02" "0x1" i
	io_update
	res=1
	while [[ ! "$res" -eq "0" ]]; do
		i2cset -y $I2CBUS $I2CADDR "0x0D" "0x00" i
		res=$(i2cget -y $I2CBUS $I2CADDR)
		echo $res
	done
	i2cset -y $I2CBUS $I2CADDR "0x0E" "0x00" "0x0" i
	io_update
}

if [[ $# -eq 0 ]];
then
	exit;
fi

cmd_regex="&h([0-9a-zA-Z]?)([0-9a-zA-Z]{1,2}),&b([01]{8})\s+;([0-9a-zA-Z]{2}) Hex, ([0-9]+) Dec"

declare -A map

while read line
do	
	if [[ $line =~ $cmd_regex ]]; then
		page=${BASH_REMATCH[1]}
		if [ -z "$page" ]; then page=0; fi
	        addr=${BASH_REMATCH[2]}
	       	data=${BASH_REMATCH[4]}
		index=$( printf "%02X%02X" $((16#$page)) $((16#$addr)) )
		map["$index"]=$data
		echo "$index $data"
	fi
done < $1

#for index in ${!map[@]}
#do
#	echo "$index ${map[$index]}"
#done

transfer 100 108
io_update
calibrate 
transfer 200 214
transfer 300 31B
transfer 400 419
io_update
transfer 500 507
transfer 600 663
transfer 680 6e3
transfer 700 763
transfer 780 7e3
io_update
transfer a00 a10
sync_distribution
io_update

if [ "$2" == "eeprom" ]; then

transfer e10 e3f
write_eeprom

fi
