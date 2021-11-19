#!/bin/bash
# Forked from MarkusMcNugen/docker-qBittorrentvpn

set -e

info() {
	echo "[info] $@" | ts '%Y-%m-%d %H:%M:%.S'
}
warn() {
	echo "[warn] $@" | ts '%Y-%m-%d %H:%M:%.S'
}
error() {
	echo "[error] $@" | ts '%Y-%m-%d %H:%M:%.S'
	exit 1
}
debug() {
	if [[ -z ${DEBUG} ]]; then
		export DEBUG=no
	fi

	if [[ ${DEBUG} == yes ]]; then
		echo "[debug] $@"
	fi
}


# check for presence of network interface docker0
check_network=$(ifconfig | grep docker0 || true)

# if network interface docker0 is present then we are running in host mode and thus must exit
if [[ -n ${check_network} ]]; then
	error "Network type detected as 'Host', this will cause major issues. Please stop the container and switch to 'Bridge' mode"
fi

export VPN_ENABLED=$(echo ${VPN_ENABLED} | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
if [[ -n ${VPN_ENABLED} ]]; then
	info "VPN_ENABLED defined as '${VPN_ENABLED}'"
else
	warn "VPN_ENABLED not defined, defaulting to 'yes'"
	export VPN_ENABLED="yes"
fi

if [[ ${VPN_ENABLED} == "yes" ]]; then
	# create directory to store openvpn config files
	mkdir -p /config/openvpn

	# set perms and owner for files in /config/openvpn directory
	set +e
	chown -R ${PUID}:${PGID} /config/openvpn &> /dev/null
	exit_code_chown=$?
	chmod -R 775 /config/openvpn &> /dev/null
	exit_code_chmod=$?
	set -e

	if [[ ${exit_code_chown} != 0 || ${exit_code_chmod} != 0 ]]; then
		warn "Unable to chown/chmod /config/openvpn/, assuming SMB mountpoint"
	fi

	# wildcard search for openvpn config files (match on first result)
	export VPN_CONFIG=$(find /config/openvpn -maxdepth 1 -name "*.ovpn" -print -quit)

	# if ovpn file not found in /config/openvpn then exit
	if [[ -z ${VPN_CONFIG} ]]; then
		error "No OpenVPN config file located in /config/openvpn/ (ovpn extension), please download from your VPN provider and then restart this container, exiting..."
	fi

	info "OpenVPN config file (ovpn extension) is located at ${VPN_CONFIG}"

	# read username and password env vars and put them in credentials.conf, then update ovpn config
	if [[ -n ${VPN_USERNAME} ]] && [[ -n ${VPN_PASSWORD} ]]; then
		if [[ ! -e /config/openvpn/credentials.conf ]]; then
			touch /config/openvpn/credentials.conf
		fi

		echo "${VPN_USERNAME}" > /config/openvpn/credentials.conf
		echo "${VPN_PASSWORD}" >> /config/openvpn/credentials.conf

		# inject credentials.conf reference
		auth_cred_exist=$(cat ${VPN_CONFIG} | grep -m 1 'auth-user-pass')
		if [[ -n ${auth_cred_exist} ]]; then
			# get line number of auth-user-pass
			LINE_NUM=$(grep -Fn -m 1 'auth-user-pass' ${VPN_CONFIG} | cut -d: -f 1)
			sed -i "${LINE_NUM}s/.*/auth-user-pass credentials.conf\n/" ${VPN_CONFIG}
		else
			sed -i "1s/.*/auth-user-pass credentials.conf\n/" ${VPN_CONFIG}
		fi
	fi

	# set safe perms on openvpn credential file
	chmod 600 /config/openvpn/credentials.conf
	info "OpenVPN credentials file set to 644"

	# convert CRLF (windows) to LF (unix) for ovpn
	/usr/bin/dos2unix ${VPN_CONFIG} 1> /dev/null
	info "Converted CRLF to LF for ovpn"

	# parse values from ovpn file
	export vpn_remote_line=$(cat ${VPN_CONFIG} | grep -P -o -m 1 '(?<=^remote\s)[^\n\r]+' | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
	if [[ -n ${vpn_remote_line} ]]; then
		info "VPN remote line defined as '${vpn_remote_line}'"
	else
		echo "[error] VPN configuration file ${VPN_CONFIG} does not contain 'remote' line, showing contents of file before exit..." | ts '%Y-%m-%d %H:%M:%.S'
		cat ${VPN_CONFIG} && exit 1
	fi
	export VPN_REMOTE=$(echo ${vpn_remote_line} | grep -P -o -m 1 '^[^\s\r\n]+' | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
	if [[ -n ${VPN_REMOTE} ]]; then
		info "VPN_REMOTE defined as '${VPN_REMOTE}'"
	else
		error "VPN_REMOTE not found in ${VPN_CONFIG}, exiting..."
	fi
	export VPN_PORT=$(echo ${vpn_remote_line} | grep -P -o -m 1 '(?<=\s)\d{2,5}(?=\s)?+' | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
	if [[ -n ${VPN_PORT} ]]; then
		info "VPN_PORT defined as '${VPN_PORT}'"
	else
		error "VPN_PORT not found in ${VPN_CONFIG}, exiting..."
	fi
	export VPN_PROTOCOL=$(cat ${VPN_CONFIG} | grep -P -o -m 1 '(?<=^proto\s)[^\r\n]+' | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
	if [[ -n ${VPN_PROTOCOL} ]]; then
		info "VPN_PROTOCOL defined as '${VPN_PROTOCOL}'"
	else
		export VPN_PROTOCOL=$(echo ${vpn_remote_line} | grep -P -o -m 1 'udp|tcp-client|tcp$' | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
		if [[ -n ${VPN_PROTOCOL} ]]; then
			info "VPN_PROTOCOL defined as '${VPN_PROTOCOL}'"
		else
			warn "VPN_PROTOCOL not found in ${VPN_CONFIG}, assuming udp"
			export VPN_PROTOCOL="udp"
		fi
	fi

	# required for use in iptables
	if [[ ${VPN_PROTOCOL} == tcp-client ]]; then
		export VPN_PROTOCOL="tcp"
	fi

	VPN_DEVICE_TYPE=$(cat ${VPN_CONFIG} | grep -P -o -m 1 '(?<=^dev\s)[^\r\n\d]+' | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
	if [[ -n ${VPN_DEVICE_TYPE} ]]; then
		export VPN_DEVICE_TYPE=${VPN_DEVICE_TYPE}0
		info "VPN_DEVICE_TYPE defined as '${VPN_DEVICE_TYPE}'"
	else
		error "VPN_DEVICE_TYPE not found in ${VPN_CONFIG}, exiting..."
	fi

	# get values from env vars as defined by user
	export K8S_CLUSTER=$(echo ${K8S_CLUSTER} | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
	if [[ -n ${K8S_CLUSTER} ]]; then
		info "K8S_CLUSTER defined as '${K8S_CLUSTER}'"
    warn "Wiping /etc/resolv.conf to avoid nameserver conflict inheritance"
    cat /dev/null > /etc/resolv.conf
	else
		warn "K8S_CLUSTER not defined,(via -e K8S_CLUSTER), defaulting to 'no'"
		export K8S_CLUSTER="no"
		export DOCKER_NETWORK=172.17.0.0/16
	fi
	if [[ ${K8S_CLUSTER} == yes ]]; then
		export K8S_POD_CIDR=$(echo ${K8S_POD_CIDR} | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
		if [[ -n ${K8S_POD_CIDR} ]]; then
			info "K8S_POD_CIDR defined as '${K8S_POD_CIDR}'"
		else
			error "K8S_POD_CIDR not defined (via -e K8S_POD_CIDR), exiting..."
		fi
		export K8S_SVC_CIDR=$(echo ${K8S_SVC_CIDR} | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
		if [[ -n ${K8S_SVC_CIDR} ]]; then
			info "K8S_SVC_CIDR defined as '${K8S_SVC_CIDR}'"
		else
			error "K8S_SVC_CIDR not defined (via -e K8S_SVC_CIDR), exiting..."
		fi
	fi
	export LAN_CIDR=$(echo ${LAN_CIDR} | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
	if [[ -n ${LAN_CIDR} ]]; then
		info "LAN_CIDR defined as '${LAN_CIDR}'"
	else
		error "LAN_CIDR not defined (via -e LAN_CIDR), exiting..."
	fi
	export NAME_SERVERS=$(echo ${NAME_SERVERS} | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
	if [[ -n ${NAME_SERVERS} ]]; then
		info "NAME_SERVERS defined as '${NAME_SERVERS}'"
	else
		warn "NAME_SERVERS not defined (via -e NAME_SERVERS), defaulting to Google and FreeDNS name servers"
		export NAME_SERVERS="8.8.8.8,37.235.1.174,8.8.4.4,37.235.1.177"
	fi
	export VPN_OPTIONS=$(echo ${VPN_OPTIONS} | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
	if [[ -n ${VPN_OPTIONS} ]]; then
		info "VPN_OPTIONS defined as '${VPN_OPTIONS}'"
	else
		info "VPN_OPTIONS not defined (via -e VPN_OPTIONS)"
		export VPN_OPTIONS=""
	fi
elif [[ $VPN_ENABLED == no ]]; then
	warn "!!IMPORTANT!! You have set the VPN to disabled, you will NOT be secure!"
fi

# split comma seperated string into list from NAME_SERVERS env variable
IFS=',' read -ra name_server_list <<< "${NAME_SERVERS}"

# process name servers in the list
for name_server_item in "${name_server_list[@]}"; do

	# strip whitespace from start and end of lan_network_item
	name_server_item=$(echo ${name_server_item} | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')

	info "Adding ${name_server_item} to resolv.conf"
	echo "nameserver ${name_server_item}" >> /etc/resolv.conf

done

if [[ -z ${PUID} ]]; then
	info "PUID not defined. Defaulting to root user"
	export PUID="root"
fi

if [[ -z ${PGID} ]]; then
	info "PGID not defined. Defaulting to root group"
	export PGID="root"
fi

if [[ $VPN_ENABLED == yes ]]; then
	info "Starting OpenVPN..."
	cd /config/openvpn
	exec openvpn --config ${VPN_CONFIG} &
	sleep 5
	exec /bin/bash /etc/qbittorrent/iptables.sh
else
	exec /bin/bash /etc/qbittorrent/start.sh
fi
