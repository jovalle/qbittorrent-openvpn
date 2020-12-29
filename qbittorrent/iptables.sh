#!/bin/bash
# Forked from MarkusMcNugen/docker-qBittorrentvpn

info() {
	echo "[info] $@" | ts '%Y-%m-%d %H:%M:%.S'
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

# wait for tunnel
while : ; do
	tunnelstat=$(netstat -ie | grep -E "tun|tap")
	if [[ -n ${tunnelstat} ]]; then
		break
	else
		sleep 1
	fi
done

# set default qbittorrent webui port if missing
if [[ -z ${WEBUI_PORT} ]]; then
	export WEBUI_PORT=8080
fi
info "qBittorrent web UI port defined as ${WEBUI_PORT}"

# set default qbittorrent daemon port if missing
if [[ -z ${INCOMING_PORT} ]]; then
	export INCOMING_PORT=8999
fi
info "Incoming connections port defined as ${INCOMING_PORT}"

# check for variables
[[ -z ${LAN_NETWORK} ]] && error "LAN Network is not defined!"
if [[ -n ${KUBERNETES_ENABLED} && ${KUBERNETES_ENABLED} == yes ]]; then
	[[ -z ${POD_NETWORK} ]] && error "Kubernetes Pod Subnet is not defined!"
	[[ -z ${SVC_NETWORK} ]] && error "Kubernetes Service Subnet is not defined!"
fi

# trim {LAN,POD,SVC}_NETWORK
export LAN_NETWORK=$(echo ${LAN_NETWORK} | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
info "LAN Network defined as ${LAN_NETWORK}"
export POD_NETWORK=$(echo ${POD_NETWORK} | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
[[ -n ${POD_NETWORK} ]] && info "Kubernetes Pod Subnet defined as ${POD_NETWORK}"
export SVC_NETWORK=$(echo ${SVC_NETWORK} | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
[[ -n ${SVC_NETWORK} ]] && info "Kubernetes Service Subnet defined as ${SVC_NETWORK}"

# get default gateway
DEFAULT_GATEWAY=$(ip -4 route list 0/0 | cut -d ' ' -f 3)
info "Default gateway defined as ${DEFAULT_GATEWAY}"

info "Adding ${LAN_NETWORK} as route via eth0"
ip route add ${LAN_NETWORK} via ${DEFAULT_GATEWAY} dev eth0
if [[ -n ${POD_NETWORK} ]]; then
	info "Adding ${POD_NETWORK} as route via eth0"
	ip route add ${POD_NETWORK} via ${DEFAULT_GATEWAY} dev eth0
fi
if [[ -n ${SVC_NETWORK} ]]; then
	info "Adding ${SVC_NETWORK} as route via eth0"
	ip route add ${SVC_NETWORK} via ${DEFAULT_GATEWAY} dev eth0
fi

info "routes defined as follows..."
echo "--------------------"
ip route
echo "--------------------"

# setup fwmark if iptables mangle found
info "Checking for iptable_mangle module..."
lsmod | grep iptable_mangle
iptable_mangle_exit_code=$?

if [[ ${iptable_mangle_exit_code} == 0 ]]; then
	info "iptable_mangle support detected, adding fwmark for tables"

	# setup route for qbittorrent webui using set-mark to route traffic for port 8080 to eth0
	echo "${WEBUI_PORT}     webui" >> /etc/iproute2/rt_tables
	ip rule add fwmark 1 table webui
	ip route add default via ${DEFAULT_GATEWAY} table webui
fi

# if kubernetes is enabled, pod IP will likely be a /32 and IMO useless
if [[ -z ${KUBERNETES_ENABLED} || ${KUBERNETES_ENABLED} == no ]]; then
	# identify pod bridge interface name (probably eth0)
	pod_interface=$(netstat -ie | grep -vE "lo|tun|tap" | sed -n '1!p' | grep -P -o -m 1 '^[\w]+')
	debug "pod interface defined as ${pod_interface}"

	# identify ip for pod bridge interface
	pod_ip=$(ifconfig ${pod_interface} | grep -o "inet [0-9]*\.[0-9]*\.[0-9]*\.[0-9]*" | grep -o "[0-9]*\.[0-9]*\.[0-9]*\.[0-9]*")
	debug "pod IP defined as ${pod_ip}"

	# identify netmask for pod bridge interface
	pod_mask=$(ifconfig ${pod_interface} | grep -o "netmask [0-9]*\.[0-9]*\.[0-9]*\.[0-9]*" | grep -o "[0-9]*\.[0-9]*\.[0-9]*\.[0-9]*")
	debug "pod netmask defined as ${pod_mask}"

	# convert netmask into cidr format
	pod_network_cidr=$(ipcalc ${pod_ip} ${pod_mask} | grep -P -o -m 1 "(?<=Network:)\s+[^\s]+" | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
	info "Pod network defined as ${pod_network_cidr}"
fi

# set i/o default to drop
iptables -P INPUT DROP
ip6tables -P INPUT DROP 1>&- 2>&-
iptables -P OUTPUT DROP
ip6tables -P OUTPUT DROP 1>&- 2>&-

# accept i/o icmp (ping)
iptables -A INPUT -p icmp --icmp-type echo-reply -j ACCEPT
iptables -A OUTPUT -p icmp --icmp-type echo-request -j ACCEPT

# accept i/o from local loopback
iptables -A INPUT -i lo -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT

# accept input to tunnel adapter (probably tun0)
debug "Allowing input to ${VPN_DEVICE_TYPE}"
iptables -A INPUT -i ${VPN_DEVICE_TYPE} -j ACCEPT

# accept input to/from LANs (172.x range is internal dhcp)
if [[ -z ${KUBERNETES_ENABLED} || ${KUBERNETES_ENABLED} == no ]]; then
iptables -A INPUT -s "${docker_network_cidr}" -d "${docker_network_cidr}" -j ACCEPT
fi

# accept input to/from Kubernetes networks
if [[ -n ${POD_NETWORK} ]]; then
	debug "Allowing input to/from ${POD_NETWORK}"
	iptables -A INPUT -s ${POD_NETWORK} -d ${POD_NETWORK} -j ACCEPT
fi
if [[ -n ${SVC_NETWORK} ]]; then
	debug "Allowing input to/from and ${SVC_NETWORK}"
	iptables -A INPUT -s ${SVC_NETWORK} -d ${SVC_NETWORK} -j ACCEPT
fi

# accept input to VPN gateway
debug "Allowing ${VPN_PROTOCOL} input to VPN gateway at port ${VPN_PORT}"
iptables -A INPUT -i eth0 -p ${VPN_PROTOCOL} --sport ${VPN_PORT} -j ACCEPT

# accept input to qbittorrent webui port
debug "Allowing tcp input to/from web UI port (${WEBUI_PORT}) via eth0"
iptables -A INPUT -i eth0 -p tcp --dport ${WEBUI_PORT} -j ACCEPT

# accept input to qbittorrent daemon port - used for lan access
debug "Allowing tcp input from ${LAN_NETWORK} to qBittorrent daemon port (${INCOMING_PORT}) via eth0"
iptables -A INPUT -i eth0 -s ${LAN_NETWORK} -p tcp --dport ${INCOMING_PORT} -j ACCEPT

# accept output from tunnel adapter
debug "Allowing output to ${VPN_DEVICE_TYPE}"
iptables -A OUTPUT -o ${VPN_DEVICE_TYPE} -j ACCEPT

# accept output to/from LANs (172.x range is internal dhcp)
if [[ -z ${KUBERNETES_ENABLED} || ${KUBERNETES_ENABLED} == no ]]; then
iptables -A OUTPUT -s "${docker_network_cidr}" -d "${docker_network_cidr}" -j ACCEPT
fi

# accept output to/from Kubernetes networks
if [[ -n ${POD_NETWORK} ]]; then
	debug "Allowing output to/from ${POD_NETWORK}"
	iptables -A OUTPUT -s ${POD_NETWORK} -d ${POD_NETWORK} -j ACCEPT
fi
if [[ -n ${SVC_NETWORK} ]]; then
	debug "Allowing output to/from and ${SVC_NETWORK}"
	iptables -A OUTPUT -s ${SVC_NETWORK} -d ${SVC_NETWORK} -j ACCEPT
fi

# accept output from VPN gateway
debug "Allowing ${VPN_PROTOCOL} output to VPN gateway at port ${VPN_PORT}"
iptables -A OUTPUT -o eth0 -p ${VPN_PROTOCOL} --dport ${VPN_PORT} -j ACCEPT

# if iptable mangle is available (kernel module) then set marks
if [[ ${iptable_mangle_exit_code} == 0 ]]; then
	info "iptable_mangle support detected, setting marks"

	# accept output from qbittorrent webui port - used for external access
	debug "Allowing tcp output from qBittorrent web UI port (${WEBUI_PORT})"
	iptables -t mangle -A OUTPUT -p tcp --dport ${WEBUI_PORT} -j MARK --set-mark 1
	iptables -t mangle -A OUTPUT -p tcp --sport ${WEBUI_PORT} -j MARK --set-mark 1
	
fi

# accept output from qbittorrent webui port - used for lan access
iptables -A OUTPUT -o eth0 -p tcp --dport ${WEBUI_PORT} -j ACCEPT
iptables -A OUTPUT -o eth0 -p tcp --sport ${WEBUI_PORT} -j ACCEPT

# accept output to qbittorrent daemon port - used for lan access
debug "Allowing tcp output to qBittorrent daemon port"
iptables -A OUTPUT -o eth0 -d ${LAN_NETWORK} -p tcp --sport ${INCOMING_PORT} -j ACCEPT

info "iptables defined as follows..."
echo "--------------------"
iptables -S
echo "--------------------"

exec /bin/bash /etc/qbittorrent/start.sh