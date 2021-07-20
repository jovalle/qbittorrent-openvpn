VERSION ?= $(shell cat VERSION)

all: build tag push

buildx:
	docker buildx build --platform linux/amd64,linux/arm64,linux/arm/v7 --push \
	-t jovalle/qbittorrent-openvpn:${VERSION} .

build:
	docker build -t jovalle/qbittorrent-openvpn-dev:${VERSION} .

tag:
	docker tag \
	jovalle/qbittorrent-openvpn-dev:${VERSION} \
	jovalle/qbittorrent-openvpn:${VERSION}

push:
	docker push jovalle/qbittorrent-openvpn:${VERSION}