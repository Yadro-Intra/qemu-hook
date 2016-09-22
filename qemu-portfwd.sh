#!/bin/bash

# put it into /etc/libvirt/hooks/qemu and chmod +x

# config is a JSON file with the same path and name as the hook is, but with ".json" suffix
# i.e. /etc/libvirt/hooks/qemu.json (see below)

# depends on jq(1) tool
# based on http://wiki.libvirt.org/page/Networking#Forwarding_Incoming_Connections

# The typical sequence of calls:
# /etc/libvirt/hooks/qemu centos-7-appserv-1 prepare begin -
# /etc/libvirt/hooks/qemu centos-7-appserv-1 start begin -
# /etc/libvirt/hooks/qemu centos-7-appserv-1 started begin -
# /etc/libvirt/hooks/qemu centos-7-appserv-1 stopped end -
# /etc/libvirt/hooks/qemu centos-7-appserv-1 release end -

exe=$(realpath "$0")
json="$exe".json

installDir='/etc/libvirt/hooks'
targetScript="$installDir/qemu"
targetJson="${targetScript}.json"

# Sample config:
#{
#	"forward": [
#		{
#			"enabled": true,
#			"guest": "centos-7-appserv-1",
#			"external_ip": "172.17.18.105",
#			"internal_ip": "192.168.122.131",
#			"ports": [ { "host":443, "guest":443 }, { "host":2222, "guest":22 } ]
#		},
#		{
#			"enabled": false,
#			"guest": "test1",
#			"external_ip": "10.1.0.1",
#			"internal_ip": "192.0.2.1",
#			"ports": [ { "host":443, "guest":443 }, { "host":2222, "guest":22 } ]
#		},
#		{
#			"enabled": false,
#			"guest": "test2",
#			"external_ip": "10.1.0.2",
#			"internal_ip": "192.0.2.2",
#			"ports": [ { "host":443, "guest":443 }, { "host":2222, "guest":22 } ]
#		}
#	]
#}
# Wanna comments? Just ot it! Add "comment": section and fill it with your stuff.

RUN=''
[ "$DEBUG_RULES" = 'yes' ] && RUN='echo RUN:'

# exec >>/var/log/qemu-hook.log 2>&1

LOGGER=$(type -p logger)

log () {
	if [ -n "$LOGGER" -a -x "$LOGGER" ]; then
		"$LOGGER" -t 'libvirt:hook:qemu' "$@"
	else
		echo "$(date '+%F_%T_%z') $@" >> /var/log/qemu-hook.log
	fi
}

error () {
	local rc="$1"
	shift
	log "ERROR($rc): $@"
	exit $rc
}

debug () {
	[ -z "$RUN" ] && return
	log "DEBUG: $@"
}

entry_enabled () {
	test $(jq ".forward[$i].enabled" "$json") = 'true'
}

fetch_value () {
	local idx="$1"
	local name="$2"

	jq ".forward[$idx].$name" "$json" | tr -d '"'
}

str_port_list () {
	local idx="$1"
	local num_ports=$(fetch_value $idx 'ports | length')
	local pi=0 host_port='' guest_port='' s=''

	for ((pi=0; pi<num_ports; pi++)); do
		host_port=$(fetch_value $idx "ports[$pi].host")
		guest_port=$(fetch_value $idx "ports[$pi].guest")
		s="$s [$pi:$host_port>$guest_port]"
	done
	echo "$s"
}

run_rules () {
	local op="$1" ; shift
	local external_ip="$1" ; shift
	local host_port="$1" ; shift
	local internal_ip="$1" ; shift
	local guest_port="$1" ; shift

	local OP1='-L' OP2='-L'

	debug "run_rules($@)"

	case "$op" in
	del)	OP1='-D'; OP2='-D';;
	add)	OP1='-A'; OP2='-I';;
	*)	error 1 "run_rules: Cannot perform '$op' to forward" \
			"'$external_ip:$host_port' to '$internal_ip:$guest_port'.";;
	esac

## These rules are from the official manual -- they don't work.
#	$RUN iptables -t nat $OP1 PREROUTING \
#		-d ${external_ip} -p tcp --dport ${host_port} \
#		-j DNAT --to ${internal_ip}:${guest_port}
#
#	$RUN iptables $OP2 FORWARD \
#		-d ${internal_ip}/32 -p tcp -m state --state NEW \
#		-m tcp --dport ${guest_port}

## These are from http://git.zaytsev.net/

#	$RUN iptables -t nat $OP2 PREROUTING \
#		-d ${external_ip} -i ${external_if} -p tcp -m tcp --dport ${host_port} \
#		-j DNAT --to-destination ${internal_ip}:${guest_port}

	$RUN iptables -t nat $OP2 PREROUTING \
		-d ${external_ip} -p tcp -m tcp --dport ${host_port} \
		-j DNAT --to-destination ${internal_ip}:${guest_port}

	$RUN iptables $OP2 FORWARD \
		-d ${internal_ip} \
		-p tcp -m state --state NEW -m tcp --dport ${guest_port} \
		-j ACCEPT
}

del_rules () {
	local idx="$1"
	local guest=$(fetch_value $idx "guest")
	local external_ip=$(fetch_value $idx "external_ip")
	local internal_ip=$(fetch_value $idx "internal_ip")
	local num_ports=$(fetch_value $idx 'ports | length')
	local pi=0 host_port='' guest_port=''

	debug "del_rules($@)"

	for ((pi=0; pi<num_ports; pi++)); do
		host_port=$(fetch_value $idx "ports[$pi].host")
		guest_port=$(fetch_value $idx "ports[$pi].guest")

		run_rules del "${external_ip}" "${host_port}" "${internal_ip}" "${guest_port}"
	done
}

add_rules () {
	local idx="$1"
	local guest=$(fetch_value $idx "guest")
	local external_ip=$(fetch_value $idx "external_ip")
	local internal_ip=$(fetch_value $idx "internal_ip")
	local num_ports=$(fetch_value $idx 'ports | length')
	local pi=0 host_port='' guest_port=''

	debug "add_rules($@)"

	for ((pi=0; pi<num_ports; pi++)); do
		host_port=$(fetch_value $idx "ports[$pi].host")
		guest_port=$(fetch_value $idx "ports[$pi].guest")

		run_rules add "${external_ip}" "${host_port}" "${internal_ip}" "${guest_port}"
	done
}

handle_entry () {
	local idx="$1"
	local name="$2"
	local task="$3"
	local guest=$(fetch_value $idx "guest") # assert $guest = $name
	local external_ip=$(fetch_value $idx "external_ip")
	local internal_ip=$(fetch_value $idx "internal_ip")
	local done='no'

	debug "[$name][$task][$idx] guest=[$guest]" \
		"external_ip=[$external_ip] internal_ip=[$internal_ip]" \
		"ports:$(str_port_list $idx)"

	case "$task" in
	start|prepare|release)	done='skip';;
	esac

	case "$task" in
	stopped|reconnect)	del_rules "$idx"; done='yes';;
	esac

	case "$task" in
	started|reconnect)	add_rules "$idx"; done='yes';;
	esac

	[ "$done" = 'no' ] && error 1 "Cannot perform task '$task' for guest '$name'."
	:
}

find_entry () {
	local name="$1"
	local guest=''
	local N=$(jq '.forward | length' "$json")
	local i=0

	for ((i=0; i<$N; i++)); do
		if entry_enabled "$i" ; then
			guest=$(fetch_value $i "guest")
			if [ "$guest" == "$name" ]; then
				debug "found '$i' for '$name'"
				echo $i
				return 0
			fi
		fi
	done
	return 1
}

main () {
	local guest="$1" ; [ -z "$guest" ] && error 1 "No guest."
	local task="$2" ; [ -z "$task" ] && error 1 "No task for guest '$guest'."
	local phase="$3" # no need
	local some_shit="$4"

	# log "$0 $@"

	[ -f "$json" ] || error 1 "No config file '$json' for guest '$guest' task '$task'."

	local idx=$(find_entry "$guest")
	[ -z "$idx" ] && error 1 "No config for guest '$guest'."

	handle_entry "$idx" "$@"
}

x_check () {
	echo "The script is being ran as '$exe'."

	echo -n "The installation directory '$installDir' "
	[ -d "$installDir/." ] || echo -n "NOT "; echo "exists."

	echo -n "The hook script '$targetScript' "
	[ -e "$targetScript" ] || echo -n "NOT "; echo "exists."
	echo -n "+ It is "
	[ -f "$targetScript" ] || echo -n "NOT "; echo "a file."
	echo -n "+ It is "
	[ -x "$targetScript" ] || echo -n "NOT "; echo "executable."

	echo -n "The hook's config '$targetJson' "
	[ -e "$targetJson" ] || echo -n "NOT "; echo "exists."
	echo -n "+ It is "
	[ -f "$targetJson" ] || echo -n "NOT "; echo "a file."
	echo -n "+ It is "
	[ -r "$targetJson" ] || echo -n "NOT "; echo "readable."

	local jq=$(type -p jq)
	echo -n "The jq(1) utility is "
	[ -z "$jq" ] && echo "NOT available!" || echo "installed as '$jq'."
	echo -n "+ It is "
	[ -n "$jq" -a -x "$jq" ] || echo -n "NOT "; echo "executable."

	if [ -r "$targetJson" -a -n "$jq" -a -x "$jq" ]; then
		echo -n "JSON in '$targetJson' is "
		"$jq" . "$targetJson" >/dev/null 2>&1 || echo -n "NOT "
		echo "valid."
	fi

	local virsh=$(type -p virsh)
	echo -n "The virsh(1) utility is "
	[ -z "$virsh" ] && echo "NOT available!" || echo "installed as '$virsh'."
	echo -n "+ It is "
	[ -n "$virsh" -a -x "$virsh" ] || echo -n "NOT "; echo "executable."
	if [ -n "$virsh" -a -x "$virsh" ]; then
		echo -n "+ You can "
		"$virsh" list >/dev/null 2>&1 || echo -n "NOT "
		echo "run it as '$(id -un)'."
	fi
}

confirm () {
	local prompt="$@" r=''

	while :; do
		read -p "${prompt}? " r </dev/tty
		case "$r" in
		y*|Y*)	return 0;;
		n*|N*)	return 1;;
		*)	echo 'Yes or No?';;
		esac
	done >/dev/tty
}

list_ips () {
	ip -o addr | grep -o '\<inet [0-9.]\+' | cut -d' ' -f2 | grep -v '127\.'
}

list_intfs () {
	ip -o link | grep -v LOOPBACK | cut -d: -f2 | tr -d '[ \t]'
}

norm_xml () {
	virsh "$@" | tr -s '[:space:]' ' ' | sed -e '1,$s/> </>\n</g' | tr '"' "'"
}

xml_for_net () {
	norm_xml net-dumpxml "$1"
}

xml_for_vm () {
	norm_xml dumpxml "$1"
}

ip_for_net () {
	xml_for_net "$1" | grep -m1 '<ip address=' | grep -wo '[0-9.]\+' | head -n1
}

fwd_for_net () {
	xml_for_net "$1" | grep -m1 '<forward '
}

net_is_on () {
	virsh net-list --name  | grep -v '^$' | grep -q '^'"$1"'$'
}

vm_is_on () {
	virsh list --name | grep -v '^$' | grep -q '^'"$1"'$'
}

running_vm_list () {
	virsh list --name | grep -v '^$'
}

x_install_script () {
	[ $(running_vm_list | wc -l) = 0 ] || error "Please, stop [$(running_vm_list)] first!"
	cp -iv "$exe" "$targetScript" || error $? "Cannot install '$exe' as '$targetScript'."
	chmod -v a+x "$targetScript" || error $? "Cannot chmod a+x '$targetScript'."
	echo "Script '$targetScript' installed ok."
}

net_for_vm () {
	xml_for_vm "$1" | grep '<source ' | grep ' network=' | sort -u
}

x_create_json_template () {
	local n=0
	local net='' ip='' fwd='' on='' dev=''

	{
	echo -e '{\t"comment_created": "'$(date '+%F %T %z')'",'

	echo -ne '\t"comment_libvirt_networks": [\n\t'
	n=0
	while read net; do
		[ -z "$net" ] && continue
		(( n == 0 )) || echo -ne ',\n\t'
		let n+=1
		net_is_on "$net" && on='true' || on='false'
		ip=$(ip_for_net "$net")
		fwd=$(fwd_for_net "$net")
		echo -e '{\t"net": "'"$net"'",'
		echo -e '\t\t"enabled": '$on','
		echo -e '\t\t"ip": "'"$ip"'",'
		echo -e '\t\t"fwd": "'"$fwd"'"'
		echo -ne '\t}'
	done < <(virsh net-list --all --name)
	echo ' ],'

	echo -ne '\t"comment_host_interfaces": [\n\t\t'
	n=0
	while read dev; do
		(( n == 0 )) || echo -ne ',\n\t\t'
		let n+=1
		ip=$(ip -o addr show dev "$dev" | grep -o '\<inet [0-9.]\+/' | grep -o '[0-9.]\+')
		echo -n "{ \"dev\": \"$dev\", \"ip\": \"$ip\" }"
	done < <(list_intfs)
	echo ' ],'

	echo -ne '\t"forward": [\n\t'
	n=0
	while read guest; do
		[ -z "$guest" ] && continue
		(( n == 0 )) || echo -ne ',\n\t'
		let n+=1
		vm_is_on "$guest" && on='true' || on='false'
		net=$(net_for_vm "$guest")
		echo -e '{\t"enabled": false,'
		echo -e '\t\t"guest": '"\"$guest\""','
		echo -e '\t\t"comment": {\t"running": '$on',\n\t\t\t\t"net": "'"$net"'" },'
		echo -e '\t\t"external_if": "!FILL-ME!",'
		echo -e '\t\t"internal_if": "!FILL-ME!",'
		echo -e '\t\t"external_ip": "1.2.3.4",'
		echo -e '\t\t"internal_ip": "192.168.122.130",'
		echo -e '\t\t"ports": [ { "host":2222, "guest":22 } ]'
		echo -ne '\t}'
	done < <(virsh list --all --name)
	echo -e '\t]'
	
	echo -e '}'
	} > qemu-template.json

	jq . qemu-template.json >/dev/null 2>&1 || error $? "Cannot construct valid JSON."
}

x_install_json () {
	cp -iv qemu-template.json "$targetJson" || error $? "Cannot install '$targetJson'."
}

x_install () {
	local installed='no'

	[ -w /etc/passwd ] || error 1 "You must be root here."
	[ -d "$installDir/." ] || error 1 "There is no '$installDir' directory."

	if [ -e "$targetScript" ]; then
		confirm "Write over existing '$targetScript'" && {
			x_install_script && installed='yes'
		}
	else
		x_install_script && installed='yes'
	fi

	x_create_json_template || error $? "Cannot create JSON template."
	if [ -e "$targetJson" ]; then
		echo -n "JSON in '$targetJson' is "
		jq . "$targetJson" >/dev/null 2>&1 || echo -n "NOT "
		echo "valid."
		confirm "Write over existing '$targetJson'" && x_install_json
	else
		x_install_json
	fi

	if [ "$installed" = 'yes' ]; then
		echo "Installed ok (you still have to edit '$targetJson')."
		echo "Don't forget to restart 'libvirtd' service now!"
		echo "Then run your guests back again..."
	fi
}

do_extra () {
	local cmd="$1"

	LOGGER='' # turn off logger call

	case "$cmd" in
	x-check)	x_check;;
	x-install)	x_install;;
	*)	error 1 "Unknown extra '$cmd'.";;
	esac
}

do_help () {
	local cmd=$(basename "$exe")

	cat <<-EOT

		$cmd [-h|--help] [ x-command | command ... ]

		<command ...> -- are the normal QEMU hook parameters.
		You shouldn't call'em from command line.

		X-Commands (extras):

		x-check		-- check the installation environment
		x-install	-- install the hook

	EOT
}

case "$1" in
''|-h|--help)	do_help "$0"; exit;;
x-*)		do_extra "$@"; exit;;
esac

main "$@" ; exit $?

# EOF #
