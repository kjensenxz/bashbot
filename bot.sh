#!/usr/bin/env bash

# BashBot - IRC bot framework written in bash
# Copyright (C) 2016 Kenneth B. Jensen <kenneth@jensen.cf>
# Version 1.1.0 - See CHANGELOG for details

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

trap 'exit_prg' SIGINT SIGHUP SIGTERM SIGQUIT
error() {
	[ ${1} == "fatal" ] && printf "fatal " >&2
	printf "error: " >&2
	[ ${1} == "fatal" ] && printf "%s\nexiting from fatal error\n" "$2" && exit_prg
	printf "%s\n" "$1" >&2
}

init_prg() {
	# Load config
	[[ -f $config && -r $config ]] || error "fatal" "config file not found"
	. $config

	# check config
	[ -f $server ] && errmsg="server"
	[ -f $nickname ] && errmsg="nick"
	[ -f $password ] && errmsg="password"
	[ -f $owner ] && errmsg="owner"
	[ ${#channels} -le 0 ] && errmsg="channels"
	[ -v $errmsg ] && error "fatal" "$errmsg unspecified"
	
	# create pipes/file desc
	mkfifo "$infile" "$outfile" || error "fatal" "unable to create pipes"
	exec 3<> "$infile"
	exec 4<> "$outfile"

	# Open connection
	commands="${network} ${port}"
	[ $ssl == 'yes' ] && commands="--ssl ${commands}"
	ncat $commands <&3 >&4 || error "fatal" "ncat error; check your config.sh file" &
	unset commands
}

exit_prg() {
	pkill -P "$$"
	rm -f "$infile" "$outfile"
	exec 3>&-
	exec 4>&-
	exit ${1-0}
}

queue() {
	[ $debug == "yes" ] && printf "%s\r\n" "$*"
	printf "%s\r\n" "$*" >&3
}

msg() {
	queue "PRIVMSG $1 :$2"
}

# args: channel, sender, data
parse_pub() {
	return
}

# args: sender, data
parse_priv() {
	if [ $sender == $owner ]; then
		raw='!raw '+$pass # bash doesn't like ! in double quotes
		regex=
		[[ $2 =~ ^[[:space:]]$raw\s*(.*) ]] && queue ${BASH_REMATCH[1]}
		unset raw regex
	else 
		msg "$owner" "$sender: $2"
	fi

}

config=${1-config.sh}

init_prg
[ $debug == "yes" ] && echo "connecting to $network..."

# start a timer and connect
join='yes'
(sleep 2s && join='no' ) &

queue "NICK ${nickname}"
queue "USER ${nickname} 8 * :${nickname}"

while read -r prefix msg; do
	[ $debug == "yes" ] && echo "$prefix | $msg"
	if [[ $prefix == "PING" ]]; then
		queue "PONG ${msg}"
		join='no'
	elif [[ $msg =~ ^004 ]]; then
		join='no'
	elif [[ $msg =~ ^433 ]]; then
		join='no'
		error "fatal" "nickname in use; exiting"
		exit_prg
	fi
	if [[ $join == 'no' ]]; then 
		break
	fi
done <&4
unset join

# Identify with NickServ
[ $nickserv ] && msg "NickServ" "identify ${nickserv}"

# Join channels
for i in ${channels}; do
	queue "JOIN ${i}"
done

# Begin parsing input
while read -r prefix msg; do
	[ $debug == "yes" ] && echo "$prefix | $msg"
	if [[ $prefix == "PING" ]]; then
		queue "PONG ${msg}"
	elif [[ "$msg" =~ ^PRIVMSG\ (.*)\ :(.*)$ ]]; then
		sender=$( (cut -d '!' -f 1 | tr -d ':' ) <<< $prefix )
		dest=${BASH_REMATCH[1]}
		data=${BASH_REMATCH[2]}

		if [ $dest == $nickname ]; then
			dest=$sender
			parse_priv "$sender" "$data"
		else
			parse_pub "$dest" "$sender" "$data"
		fi
	elif [[ "$msg" =~ ^NICK\ :(.*) ]]; then
		nickname=${BASH_REMATCH[1]}
		[ $debug == "yes" ] && echo "Nick changed to $nickname"
	fi
done <&4

exit_prg
