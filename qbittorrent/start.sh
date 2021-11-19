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
if [[ ! -e /config/qBittorrent ]]; then
	mkdir -p /config/qBittorrent/config/
	chown -R ${PUID}:${PGID} /config/qBittorrent
else
	chown -R ${PUID}:${PGID} /config/qBittorrent
fi

# copy default qbittorrent config if missing
if [[ ! -e /config/qBittorrent/config/qBittorrent.conf ]]; then
	/bin/cp /etc/qbittorrent/qBittorrent.conf /config/qBittorrent/config/qBittorrent.conf
	chmod 755 /config/qBittorrent/config/qBittorrent.conf
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

info "Starting qBittorrent daemon..."
/bin/bash /etc/qbittorrent/qbittorrent.init start &
chmod -R 755 /config/qBittorrent

sleep 1
qbpid=$(pgrep -o -x qbittorrent-nox)
info "qBittorrent PID: ${qbpid}"

if [[ -e /proc/${qbpid} ]]; then
	if [[ -e /config/qBittorrent/data/logs/qbittorrent.log ]]; then
		chmod 775 /config/qBittorrent/data/logs/qbittorrent.log
	fi
	sleep infinity
else
	error "qBittorrent failed to start!"
fi