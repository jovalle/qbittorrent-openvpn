# qbittorrent-openvpn
Headless qbittorrent deployment with web UI and OpenVPN client. Includes support for Docker, Kubernetes and multi-arch.

## Run container from Docker registry
```
$ docker run --privileged  -d \
    -v /your/config/path/:/config \
    -v /your/downloads/path/:/downloads \
    -e "VPN_ENABLED=yes" \
    -e "LAN_CIDR=192.168.1.0/24" \
    -e "NAME_SERVERS=8.8.8.8,8.8.4.4" \
    -p 8080:8080 \
    -p 6881:6881 \
    -p 6881:6881/udp \
    jovalle/qbittorrent-openvpn
```

## Run in Kubernetes
See [manifests/](manifests/) for examples. There are a few variables (e.g. K8S_CLUSTER, K8S_POD_CIDR) that must be set to allow for proper connectivity in a Kubernetes cluster. Reference the pod and service subnet CIDRs before proceeding.

## Variables, Volumes, and Ports

### Environment Variables
| Variable | Required | Function | Example |
|----------|----------|----------|----------|
|`K8S_CLUSTER`| Yes* | Running in Kubernetes? (yes/no) Default:no|`K8S_CLUSTER=yes`|
|`K8S_POD_CIDR`| Yes* | Kubernetes Pod Subnet with CIDR notation |`K8S_POD_CIDR=10.244.0.0/16`|
|`K8S_SVC_CIDR`| Yes* | Kubernetes Service Subnet with CIDR notation |`K8S_SVC_CIDR=10.96.0.0/16`|
|`LAN_CIDR`| Yes | Local Network with CIDR notation |`LAN_CIDR=192.168.1.0/24`|
|`NAME_SERVERS`| No | Comma delimited name servers |`NAME_SERVERS=8.8.8.8,8.8.4.4`|
|`PGID`| No | GID applied to config files and downloads |`PGID=100`|
|`PUID`| No | UID applied to config files and downloads |`PUID=99`|
|`UMASK`| No | GID applied to config files and downloads |`UMASK=002`|
|`VPN_ENABLED`| Yes | Enable VPN? (yes/no) Default:yes|`VPN_ENABLED=yes`|
|`VPN_PASSWORD`| No | If username and password provided, configures ovpn file automatically |`VPN_PASSWORD=ac98df79ed7fb`|
|`VPN_USERNAME`| No | If username and password provided, configures ovpn file automatically |`VPN_USERNAME=ad8f64c02a2de`|

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
| `6881` | TCP | Yes | qBittorrent listening port | `6881:6881`|
| `6881` | UDP | Yes | qBittorrent listening port | `6881:6881/udp`|

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