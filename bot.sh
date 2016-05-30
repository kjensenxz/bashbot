#/usr/bin/env bash

# BashBot - IRC bot framework written in bash
# Copyright (C) 2016 Kenneth B. Jensen <kenneth@jensen.cf>


# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

trap 'exit_prg' SIGINT SIGHUP SIGTERM
error() {
	printf "error: %s\n" "$*" >&2
}

init_prg() {
	# Load config; create pipes/fd
	. ./config.sh
	mkfifo "$infile" "$outfile"
	exec 3<> "$infile"
	exec 4<> "$outfile"

	# Open connection
	commands="${network} ${port}"
	[ $ssl == 'yes' ] && commands="--ssl ${commands}"
	ncat $commands <&3 >&4 &
	unset commands
}

exit_prg() {
	pkill -P "$$"
	rm -f "$infile" "$outfile"
	exec 3>&-
	exec 4>&-
	exit
}

queue() {
#	echo "$*"
#	echo -e "$*\r\n" >&3
	printf "%s\r\n" "$*"
	printf "%s\r\n" "$*" >&3
}

if [ ! -f "./config.sh" ]; then
	echo "config file not found; exiting"
	exit
fi

init_prg
echo "${network}"

# start a timer and connect
join='yes'
(sleep 2s && join='no' ) &

queue "NICK ${nickname}"
queue "USER ${nickname} 8 * :${nickname}"

while read -r prefix msg; do
	echo "$prefix | $msg"
	if [[ $prefix == "PING" ]]; then
		queue "PONG ${msg}"
		join='no'
	elif [[ $msg =~ ^004 ]]; then
		join='no'
	elif [[ $msg =~ ^433 ]]; then
		join='no'
		error "nickname in use; exiting"
		exit_prg
	fi
	if [[ $join == 'no' ]]; then 
		break
	fi
done <&4
unset join

# join channels, add parsing here
for i in ${channels}; do
	queue "JOIN ${i}"
done
while read -r prefix msg; do
	echo "${prefix} | ${msg}"
	if [[ $prefix == "PING" ]]; then
		queue "PONG ${msg}"
	fi

done <&4

exit_prg
