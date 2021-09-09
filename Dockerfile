FROM debian
LABEL maintainer="Jay Ovalle (jovalle) <jay.ovalle@gmail.com>"
LABEL version="$(cat VERSION)"

VOLUME /downloads
VOLUME /config

ENV DEBIAN_FRONTEND noninteractive

RUN usermod -u 99 nobody

# Update packages and install repo dependencies
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        apt-transport-https \
        apt-utils \
        openssl \
        software-properties-common && \
    apt-add-repository 'deb https://deb.debian.org/debian stable main' && \
    apt update && \
    apt install -y qbittorrent-nox

# Cleanup
RUN apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Add configuration and scripts
ADD openvpn/ /etc/openvpn/
ADD qbittorrent/ /etc/qbittorrent/
RUN chmod +x /etc/qbittorrent/*.sh /etc/qbittorrent/*.init /etc/openvpn/*.sh

# Expose ports and run
EXPOSE 8080
EXPOSE 8999
EXPOSE 8999/udp
CMD ["/etc/openvpn/start.sh"]