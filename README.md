# qbittorrent-openvpn
Headless qbittorrent deployment with web UI and OpenVPN client. Includes support for Docker, Kubernetes and multi-arch.

## Run container from Docker registry
```
$ docker run --privileged  -d \
    -v /your/config/path/:/config \
    -v /your/downloads/path/:/downloads \
    -e "VPN_ENABLED=yes" \
    -e "LAN_NETWORK=192.168.1.0/24" \
    -e "NAME_SERVERS=8.8.8.8,8.8.4.4" \
    -p 8080:8080 \
    -p 8999:8999 \
    -p 8999:8999/udp \
    jovalle/qbittorrent-openvpn
```

## Run in Kubernetes
See [manifests/](manifests/) for examples. There are a few variables (e.g. KUBERNETES_ENABLED, POD_NETWORK) that must be set to allow for proper connectivity in a Kubernetes cluster. Reference the pod and service subnet CIDRs before proceeding.

## Variables, Volumes, and Ports

### Environment Variables
| Variable | Required | Function | Example |
|----------|----------|----------|----------|
|`VPN_ENABLED`| Yes | Enable VPN? (yes/no) Default:yes|`VPN_ENABLED=yes`|
|`VPN_USERNAME`| No | If username and password provided, configures ovpn file automatically |`VPN_USERNAME=ad8f64c02a2de`|
|`VPN_PASSWORD`| No | If username and password provided, configures ovpn file automatically |`VPN_PASSWORD=ac98df79ed7fb`|
|`LAN_NETWORK`| Yes | Local Network with CIDR notation |`LAN_NETWORK=192.168.1.0/24`|
|`KUBERNETES_ENABLED`| Yes* | Running in Kubernetes? (yes/no) Default:no|`KUBERNETES_ENABLED=yes`|
|`POD_NETWORK`| Yes* | Kubernetes Pod Subnet with CIDR notation |`POD_NETWORK=10.244.0.0/16`|
|`SVC_NETWORK`| Yes* | Kubernetes Service Subnet with CIDR notation |`SVC_NETWORK=10.96.0.0/16`|
|`NAME_SERVERS`| No | Comma delimited name servers |`NAME_SERVERS=8.8.8.8,8.8.4.4`|
|`PUID`| No | UID applied to config files and downloads |`PUID=99`|
|`PGID`| No | GID applied to config files and downloads |`PGID=100`|
|`UMASK`| No | GID applied to config files and downloads |`UMASK=002`|
|`WEBUI_PORT`| No | Applies WebUI port to qBittorrents config at boot (Must change exposed ports to match)  |`WEBUI_PORT=8080`|
|`INCOMING_PORT`| No | Applies Incoming port to qBittorrents config at boot (Must change exposed ports to match) |`INCOMING_PORT=8999`|

\* required if deploying to a Kubernetes cluster

### Volumes
| Volume | Required | Function | Example |
|----------|----------|----------|----------|
| `config` | Yes | qBittorrent and OpenVPN config files | `/your/config/path/:/config`|
| `downloads` | No | Default download path for torrents | `/your/downloads/path/:/downloads`|

### Ports
| Port | Proto | Required | Function | Example |
|----------|----------|----------|----------|----------|
| `8080` | TCP | Yes | qBittorrent WebUI | `8080:8080`|
| `8999` | TCP | Yes | qBittorrent listening port | `8999:8999`|
| `8999` | UDP | Yes | qBittorrent listening port | `8999:8999/udp`|

## Access the Web UI
Access http://IPADDRESS:PORT from a browser on the same network.

### Default Credentials
| Credential | Default Value |
|----------|----------|
|`WebUI Username`| admin |
|`WebUI Password`| adminadmin |

## How to use OpenVPN
The container will fail to boot if `VPN_ENABLED` is set to yes or empty and a .ovpn is not present in the /config/openvpn directory. Drop a .ovpn file from your VPN provider into /config/openvpn and start the container again. You may need to edit the ovpn configuration file to load your VPN credentials from a file by setting `auth-user-pass`.

**Note:** The script will use the first ovpn file it finds in the /config/openvpn directory. Adding multiple ovpn files will not start multiple VPN connections.

### Example auth-user-pass option
`auth-user-pass credentials.conf`

### Example credentials.conf
```
username
password
```

### PUID/PGID
User ID (PUID) and Group ID (PGID) can be found by issuing the following command for the user you want to run the container as:

```
id <username>
```

## Credits and Inspirations
- [haugene/docker-transmission-openvpn](https://github.com/haugene/docker-transmission-openvpn)
- [hayduck/docker-qBittorrent-openvpn](https://github.com/hayduck/docker-qBittorrent-openvpn)
- [MarkusMcNugen/docker-qBittorrentvpn](https://github.com/MarkusMcNugen/docker-qBittorrentvpn)
- [zebpalmer/kubernetes-transmission-openvpn](https://github.com/zebpalmer/kubernetes-transmission-openvpn)