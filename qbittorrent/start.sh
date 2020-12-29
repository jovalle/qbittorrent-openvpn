#!/bin/bash

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

# create base dir
if [[ ! -e /config/qbittorrent ]]; then
	mkdir -p /config/qbittorrent/config/
	chown -R ${PUID}:${PGID} /config/qbittorrent
else
	chown -R ${PUID}:${PGID} /config/qbittorrent
fi

# copy default qbittorrent config if missing
if [[ ! -e /config/qbittorrent/config/qbittorrent.conf ]]; then
	/bin/cp /etc/qbittorrent/qbittorrent.conf /config/qbittorrent/config/qbittorrent.conf
	chmod 755 /config/qbittorrent/config/qbittorrent.conf
fi

# check for missing group
/bin/egrep  -i "^${PGID}:" /etc/passwd
if [[ $? -eq 0 ]]; then
   info "Group ${PGID} exists"
else
   info "Adding ${PGID} group"
	 groupadd -g ${PGID} qbittorent
fi

# check for missing userid
/bin/egrep  -i "^${PUID}:" /etc/passwd
if [[ $? -eq 0 ]]; then
   info "User ${PUID} exists in /etc/passwd"
else
   info "Adding ${PUID} user"
	 useradd -c "qbittorrent user" -g $PGID -u $PUID qbittorent
fi

# set umask
export UMASK=$(echo ${UMASK} | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')

if [[ -z ${UMASK} ]]; then
  warn "umask not defined (via -e UMASK), defaulting to '002'"
  export UMASK="002"
else
  info "umask defined as '${UMASK}'"
fi

# set qbittorrent ports
if [[ -n ${WEBUI_PORT} ]]; then
	webui_port_exist=$(cat /config/qbittorrent/config/qbittorrent.conf | grep -m 1 'WebUI\\Port='${WEBUI_PORT})
	if [[ -z ${webui_port_exist} ]]; then
		webui_exist=$(cat /config/qbittorrent/config/qbittorrent.conf | grep -m 1 'WebUI\\Port')
		if [[ -n ${webui_exist} ]]; then
			# get line number of webui port
			LINE_NUM=$(grep -Fn -m 1 'WebUI\Port' /config/qbittorrent/config/qbittorrent.conf | cut -d: -f 1)
			sed -i "${LINE_NUM}s@.*@WebUI\\Port=${WEBUI_PORT}@" /config/qbittorrent/config/qbittorrent.conf
		else
			echo "WebUI\Port=${WEBUI_PORT}" >> /config/qbittorrent/config/qbittorrent.conf
		fi
	fi
fi

if [[ -n ${INCOMING_PORT} ]]; then
	incoming_port_exist=$(cat /config/qbittorrent/config/qbittorrent.conf | grep -m 1 'Connection\\PortRangeMin='${INCOMING_PORT})
	if [[ -z ${incoming_port_exist} ]]; then
		incoming_exist=$(cat /config/qbittorrent/config/qbittorrent.conf | grep -m 1 'Connection\\PortRangeMin')
		if [[ -n ${incoming_exist} ]]; then
			# get line number of Incoming
			LINE_NUM=$(grep -Fn -m 1 'Connection\PortRangeMin' /config/qbittorrent/config/qbittorrent.conf | cut -d: -f 1)
			sed -i "${LINE_NUM}s@.*@Connection\\PortRangeMin=${INCOMING_PORT}@" /config/qbittorrent/config/qbittorrent.conf
		else
			echo "Connection\PortRangeMin=${INCOMING_PORT}" >> /config/qbittorrent/config/qbittorrent.conf
		fi
	fi
fi

info "Starting qBittorrent daemon..."
/bin/bash /etc/qbittorrent/qbittorrent.init start &
chmod -R 755 /config/qbittorrent

sleep 1
qbpid=$(pgrep -o -x qbittorrent-nox)
info "qBittorrent PID: ${qbpid}"

if [[ -e /proc/${qbpid} ]]; then
	if [[ -e /config/qbittorrent/data/logs/qbittorrent.log ]]; then
		chmod 775 /config/qbittorrent/data/logs/qbittorrent.log
	fi
	sleep infinity
else
	error "qBittorrent failed to start!"
fi