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

# set default qbittorrent webui port
export WEBUI_PORT=8080
info "qBittorrent web UI port defined as ${WEBUI_PORT}"

# set default qbittorrent daemon port
export INCOMING_PORT=6881
info "Incoming connections port defined as ${INCOMING_PORT}"

# check for variables
[[ -z ${LAN_CIDR} ]] && error "LAN Network is not defined!"
if [[ -n ${K8S_CLUSTER} && ${K8S_CLUSTER} == yes ]]; then
	[[ -z ${K8S_POD_CIDR} ]] && error "Kubernetes Pod Subnet is not defined!"
	[[ -z ${K8S_SVC_CIDR} ]] && error "Kubernetes Service Subnet is not defined!"
fi

# trim {LAN,POD,SVC}_NETWORK
export LAN_CIDR=$(echo ${LAN_CIDR} | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
info "LAN Network defined as ${LAN_CIDR}"
export K8S_POD_CIDR=$(echo ${K8S_POD_CIDR} | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
[[ -n ${K8S_POD_CIDR} ]] && info "Kubernetes Pod Subnet defined as ${K8S_POD_CIDR}"
export K8S_SVC_CIDR=$(echo ${K8S_SVC_CIDR} | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
[[ -n ${K8S_SVC_CIDR} ]] && info "Kubernetes Service Subnet defined as ${K8S_SVC_CIDR}"

# get default gateway
DEFAULT_GATEWAY=$(ip -4 route list 0/0 | cut -d ' ' -f 3)
info "Default gateway defined as ${DEFAULT_GATEWAY}"

info "Adding ${LAN_CIDR} as route via eth0"
ip route add ${LAN_CIDR} via ${DEFAULT_GATEWAY} dev eth0
if [[ -n ${K8S_POD_CIDR} ]]; then
	info "Adding ${K8S_POD_CIDR} as route via eth0"
	ip route add ${K8S_POD_CIDR} via ${DEFAULT_GATEWAY} dev eth0
fi
if [[ -n ${K8S_SVC_CIDR} ]]; then
	info "Adding ${K8S_SVC_CIDR} as route via eth0"
	ip route add ${K8S_SVC_CIDR} via ${DEFAULT_GATEWAY} dev eth0
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
if [[ -z ${K8S_CLUSTER} || ${K8S_CLUSTER} == no ]]; then
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
	K8S_POD_CIDR_cidr=$(ipcalc ${pod_ip} ${pod_mask} | grep -P -o -m 1 "(?<=Network:)\s+[^\s]+" | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
	info "Pod network defined as ${K8S_POD_CIDR_cidr}"
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

# accept output to DNS servers
iptables -A OUTPUT -p udp -m udp --dport 53 -j ACCEPT

# accept input to tunnel adapter (probably tun0)
debug "Allowing input to ${VPN_DEVICE_TYPE}"
iptables -A INPUT -i ${VPN_DEVICE_TYPE} -j ACCEPT

# accept input to/from LANs (172.x range is internal dhcp)
if [[ -z ${K8S_CLUSTER} || ${K8S_CLUSTER} == no ]]; then
	iptables -A INPUT -s "${DOCKER_NETWORK}" -d "${DOCKER_NETWORK}" -j ACCEPT
fi

# accept input to/from Kubernetes networks
if [[ -n ${K8S_POD_CIDR} ]]; then
	debug "Allowing input to/from ${K8S_POD_CIDR}"
	iptables -A INPUT -s ${K8S_POD_CIDR} -d ${K8S_POD_CIDR} -j ACCEPT
fi
if [[ -n ${K8S_SVC_CIDR} ]]; then
	debug "Allowing input to/from and ${K8S_SVC_CIDR}"
	iptables -A INPUT -s ${K8S_SVC_CIDR} -d ${K8S_SVC_CIDR} -j ACCEPT
fi

# accept input to VPN gateway
debug "Allowing ${VPN_PROTOCOL} input to VPN gateway at port ${VPN_PORT}"
iptables -A INPUT -i eth0 -p ${VPN_PROTOCOL} --sport ${VPN_PORT} -j ACCEPT

# accept input to qbittorrent webui port
debug "Allowing tcp input to/from web UI port (${WEBUI_PORT}) via eth0"
iptables -A INPUT -i eth0 -p tcp --dport ${WEBUI_PORT} -j ACCEPT

# accept input to qbittorrent daemon port - used for lan access
debug "Allowing tcp input from ${LAN_CIDR} to qBittorrent daemon port (${INCOMING_PORT}) via eth0"
iptables -A INPUT -i eth0 -s ${LAN_CIDR} -p tcp --dport ${INCOMING_PORT} -j ACCEPT

# accept output from tunnel adapter
debug "Allowing output to ${VPN_DEVICE_TYPE}"
iptables -A OUTPUT -o ${VPN_DEVICE_TYPE} -j ACCEPT

# accept output to/from LANs (172.x range is internal dhcp)
if [[ -z ${K8S_CLUSTER} || ${K8S_CLUSTER} == no ]]; then
	iptables -A OUTPUT -s "${DOCKER_NETWORK}" -d "${DOCKER_NETWORK}" -j ACCEPT
fi

# accept output to/from Kubernetes networks
if [[ -n ${K8S_POD_CIDR} ]]; then
	debug "Allowing output to/from ${K8S_POD_CIDR}"
	iptables -A OUTPUT -s ${K8S_POD_CIDR} -d ${K8S_POD_CIDR} -j ACCEPT
fi
if [[ -n ${K8S_SVC_CIDR} ]]; then
	debug "Allowing output to/from and ${K8S_SVC_CIDR}"
	iptables -A OUTPUT -s ${K8S_SVC_CIDR} -d ${K8S_SVC_CIDR} -j ACCEPT
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
iptables -A OUTPUT -o eth0 -d ${LAN_CIDR} -p tcp --sport ${INCOMING_PORT} -j ACCEPT

info "iptables defined as follows..."
echo "--------------------"
iptables -S
echo "--------------------"

public_ip=$(curl -sL https://wtfismyip.com/text)
if [[ $? == 0 ]]; then
	info "public IP is ${public_ip}"
else
	error "failed to get public IP. check resolv.conf"
fi

exec /bin/bash /etc/qbittorrent/start.sh
