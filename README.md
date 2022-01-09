# RUDY
RUDY manages **R**emote **U**SB **D**evices easil**Y**.

This project provides Docker images that integrate USB/IP with MQTT,
so that USB devices can be used remotely with minimal configuration.

## Key features
- Use USB devices on a remote host
- Specify devices by their device id and serial number
- Automatically heal errors when client and server are not in sync
- Allow integration with udev

## Server
### Example Configuration
```yaml
---
services:
  rudy-server:
    image: ckware/rudy-server
    container_name: rudy-server
    init: true
    restart: unless-stopped
    ports:
      - "3240:3240"
    environment:
      USBIP_DEVICE_IDS: "0000:0000"
      MQTT_OPTIONS: "-h broker-host"
      MQTT_PUBLISH_TOPIC: "rudy/server"
      MQTT_RELOAD_ON_TOPIC: "rudy/client/error/server"
    volumes:
      - "/sys/bus/usb/drivers/usb:/sys/bus/usb/drivers/usb"
      - "/sys/bus/usb/drivers/usbip-host:/sys/bus/usb/drivers/usbip-host"
      - "/sys/devices/platform:/sys/devices/platform"
```

### Usage
#### Preparation
1. Enable kernel module `usbip-host` on the host:
   ```shell
   $ sudo sh -c 'modprobe usbip-host && echo usbip-host >>/etc/modules'
   ```
1. Create a configuration file `docker-compose.yml` (see the example for an inspiration)

#### Lifecycle commands
All commands assume that the container is named `rudy-server`.
| Action | Command
| ------ | -------
| Start the server | `docker-compose up -d`
| Stop the server  | `docker-compose down`
| View the server logs | `docker logs -t rudy-server`
| Reload the server | `docker exec rudy-server reload`
| List all devices connected to the server host | `docker exec rudy-server usbip list -l`
| List devices available for clients | `docker exec rudy-server usbip list -r localhost`

### Docker configuration options
| Option        | Description            | Recommendation | Explanation |
| ------------- | ---------------------- | -------------- | ----------- |
| `ports`       | Network port           | `3240:3240`    | Network port for USB/IP client communication.
| `volumes`     | Volumes for USB access | `/sys:/sys`    | Access to USB and other related devices.

Depending on the USB devices used, it may be necessary to add additional options to gain the required permissions (e.g. `privileged: true`).

### Environment variables
All _Common environment variables_.

## Client
### Example
```yaml
services:
  rudy-client:
    image: ckware/rudy-client
    container_name: rudy-client
    init: true
    restart: unless-stopped
    environment:
      USBIP_SERVER: "server-host"
      USBIP_DEVICE_IDS: "0000:0000"
      MQTT_OPTIONS: "-h broker-host"
      MQTT_PUBLISH_TOPIC: "rudy/client"
      MQTT_RELOAD_ON_TOPIC: "rudy/server/start"
    volumes:
      - "/var/run/vhci_hcd:/var/run/vhci_hcd"
    privileged: true
```

### Usage
#### Preparation
1. Enable kernel module `vhci-hcd` on the host:
   ```shell
   $ sudo sh -c 'modprobe vhci-hcd && echo vhci-hcd >>/etc/modules'
   ```
1. Create a configuration file `docker-compose.yml` (see the example for an inspiration)

#### Lifecycle commands
All commands assume that the container is named `rudy-client`.

| Action | Command
| ------ | -------
| Start the client | `docker-compose up -d`
| Stop the client | `docker-compose down`
| View the client logs | `docker logs -t rudy-client`
| Reload the client | `docker exec rudy-client reload`
| List devices currently managed by the client | `docker exec rudy-client usbip port`

### Docker configuration options
| Option        | Description           | Recommendation                        | Explanation |
| ------------- | --------------------- | ------------------------------------- | ----------- |
| `volumes`     | Volume for port state | `/var/run/vhci_hcd:/var/run/vhci_hcd` | USB/IP manages the state of attached ports within this directory. It reflects a part of the kernel state which affects all clients and should thus be shared across the host and all clients.
| `privileged`  | Root privileges       | `true`                                | Root privileges are **required** to write to `/sys/` (see issue [#22825](https://github.com/moby/moby/issues/22825) for details).

### Environment variables
All _Common environment variables_ and:

| Variable               | Description            | Supported values | Default | Example       | Explanation
| ---------------------- | ---------------------- | ---------------- | ------- | ------------- | -----------
| `USBIP_SERVER`         | USB/IP server hostname | Hostnames        | _none_  | `server-host` | Hostname of the USB/IP server
| `USBIP_PORT`           | USB/IP server port     | IP port numbers  | 3240    | `13240`       | Port of the USB/IP server
| `USBIP_DETACH_ORPHANS` | Detach dangling ports  | `true` / `false` | `true`  | `false`       | When set to `true` (which is the default), all attached devices that match `USBIP_DEVICE_IDS` are detached on shutdown. This option has no effect when `USBIP_DEVICE_IDS` is not set. It can help to repair the USB/IP state when client and server are not in sync.
| `USBIP_DETACH_ALL`     | Detach all ports       | `true` / `false` | `false` | `true`        | When set to `true`, all attached devices are detached on shutdown, no matter what their device id or bus id is. This option affects all clients on a host. It is safe to use when the host runs only one client; otherwise, all clients should be reloaded after the client which has this option set.
| `USBIP_ATTACH_DELAY`   | Attach delay           | Integer numbers  | `2`     | `3`           | Delay in seconds that is applied after attaching a device and before requesting the list of attached devices.

## Common environment variables
| Variable            | Description              | Supported values          | Default | Example               | Explanation
| ------------------  | ------------------------ | ------------------------- | ------- | --------------------- | -----------
| `USBIP_DEVICE_IDS`  | USB device IDs           | `VID:PID[:SID]` list      | _none_  | `0000:0000,1111:1111:abc` | Comma-separated device id list of managed USB devices. See the next section for details about the syntax.
| `USBIP_DEVICE_ID_SEPARATOR` | Device-ID separator | A single character | `,`     | `;`     | Separator for the device id list. Useful when filtering by a serial that contains a comma.
| `USBIP_SID_REGEX`   | Treat `SID` as regex     | `true` / `false`          | `false` | `true`                | When set to `true`, the value of `SID` is not taken literally but as a regular expression.
| `USBIP_BUS_IDS`     | USB bus IDs              | List of logical bus IDs   | _none_  | `1-1.1,2-2.2`         | Comma-separated bus id list of managed USB devices. This option can be used to differentiate between devices that share the same device id. The logical Bus-ID of a device will change when it is plugged into a different USB port.
| `MQTT_OPTIONS`      | Common MQTT options      | All options [supported by `mosquitto_pub`](https://mosquitto.org/man/mosquitto_pub-1.html) | _none_ | `-h broker-host -i rudy-client` | Default MQTT options for both publish and subscribe
| `MQTT_PUBLISH_TO_TOPIC`  | MQTT topic for publishing    | [Topic names](http://docs.oasis-open.org/mqtt/mqtt/v3.1.1/os/mqtt-v3.1.1-os.html#_Toc398718106) | _none_ | `rudy/client` | When this option is set, the service will publish its state below the configured topic.
| `MQTT_PUBLISH_OPTIONS`   | MQTT options for publish     | All options [supported by `mosquitto_pub`](https://mosquitto.org/man/mosquitto_pub-1.html) | _none_ | `-q 1` | MQTT options for publishing only. This option overrides `MQTT_OPTIONS`: when set, `MQTT_OPTIONS` is ignored for publishing.
| `MQTT_RELOAD_ON_TOPIC`   | MQTT topic for a reload hook | [Topic names](http://docs.oasis-open.org/mqtt/mqtt/v3.1.1/os/mqtt-v3.1.1-os.html#_Toc398718106) | _none_ | `rudy/server/start` | When this option is set, the service will subscribe to the configured topic and reload if a message is published to it.
| `MQTT_SUBSCRIBE_OPTIONS` | MQTT options for subscribe   | All options [supported by `mosquitto_pub`](https://mosquitto.org/man/mosquitto_pub-1.html) | _none_ | `-q 2` | MQTT options for subscribing only. This option overrides `MQTT_OPTIONS`: when set, `MQTT_OPTIONS` is ignored for subscribing.
| `RUDY_DEBUG`        | Enable debug logging     | String                    | _none_  | `true`                | When set to any non-empty value, debug logging is enabled.
| `RUDY_TRACE`        | Enable trace logging     | String                    | _none_  | `true`                | When set to any non-empty value, trace logging is enabled.

### Syntax of device IDs
The variable `USBIP_DEVICE_IDS` contains a comma-separated list of device ids. Each device id consists of the vendor id (`VID`), the product id (`PID`) and an optional serial id (`SID`), separated by colons. The serial id allows filtering when multiple devices with the same `VID:PID` are connected to the host, and only a part of them should be used remotely.

#### No filtering
Without serial id, all devices whose id matches `VID:PID` are managed. Example that picks up all devices with id `0000:0000` or `1111:1111`:
```yaml
    USBIP_DEVICE_IDS: "0000:0000,1111:1111"
```

#### Filter by serial - literally
The `SID` allows to filter devices by their serial number. When `SID` is set to the serial of a device, only this device is managed.
Example that picks up all devices with id `0000:0000` and the single device with id `1111:1111` and serial `abc`:
```yaml
    USBIP_DEVICE_IDS: "0000:0000,1111:1111:abc"
```
**Notice:** Only a single device per `VID:PID:SID` combination is supported. If you need to manage several devices with the same `VID:PID:SID` combination, you may consider enabling regex filtering.

#### Filter by serial - regular expression
When `USBIP_SID_REGEX` is set to `true`, the `SID` is treated as regular expression that the serial of a device must match. Example that picks up all devices with id `0000:0000` and all devices with id `1111:1111` whose serial starts with `a` and ends with `c`:
```yaml
    USBIP_DEVICE_IDS: "0000:0000,1111:1111:a.*c"
    USBIP_SID_REGEX: "true"
```
**Notice:** Setting `USBIP_SID_REGEX` to `true` may slightly increase the startup time, because the `SID` is compared against all devices of the server with matching `VID:PID`.

#### Filter by serial - containing a comma
If you need to specify a serial containing a comma, use a different list separator and declare it in `USBIP_DEVICE_ID_SEPARATOR`. Example:
```yaml
    USBIP_DEVICE_ID_SEPARATOR: ";"
    USBIP_DEVICE_IDS: "0000:0000;1111:1111:a,b"
```

## Pre-requisites
- A linux system with `docker-compose`.

The Docker Compose [documentation](https://docs.docker.com/compose/install/)
contains a comprehensive guide explaining several install options.
On debian-based systems, `docker-compose` may be installed by calling

```shell
$ sudo apt install docker-compose
```

## Advanced topics
### MQTT publishing
Configure `MQTT_PUBLISH_TOPIC` to publish client and server states via MQTT.

Example:
- Server configuration:
  ```yaml
  environment:
    USBIP_DEVICE_IDS: "4971:1011"
    MQTT_PUBLISH_TOPIC: "rudy/server"
  ```
- Client configuration:
  ```yaml
  environment:
    USBIP_DEVICE_IDS: "4971:1011"
    MQTT_PUBLISH_TOPIC: "rudy/client"
  ```
- MQTT messages published on starting server and client and then stopping client and server:
  ```
  rudy/server/bind 1-1.4
  rudy/server/start Exportable USB devices
  ======================
   - localhost
        1-1.4: SimpleTech : unknown product (4971:1011)
             : /sys/devices/platform/soc/3f980000.usb/usb1/1-1/1-1.4
             : (Defined at Interface level) (00/00/00)
  rudy/client/attach 0: server-host 3240 1-1.4
  rudy/client/start 0
  rudy/client/detach 0
  rudy/client/stop
  rudy/server/unbind 1-1.4
  rudy/server/stop
  ```

### Prepare for Client Errors
Configure `MQTT_RELOAD_ON_TOPIC` on the server to reload the server when the client reports a server-related error.
In combination with the Docker `restart` option, this may help to solve some problems without user interaction.

Example:
- Server configuration:
  ```yaml
  environment:
    MQTT_RELOAD_ON_TOPIC: "rudy/client/error/server"
  ```
- Client configuration:
  ```yaml
  restart: unless-stopped
  environment:
    MQTT_PUBLISH_TOPIC: "rudy/client"
  ```

### Prepare Client for Server Restart
Configure `MQTT_RELOAD_ON_TOPIC` on the client to reload the client each time the server is restarted.

Example:
- Server configuration:
  ```yaml
  environment:
    USBIP_DEVICE_IDS: "4971:1011"
    MQTT_PUBLISH_TOPIC: "rudy/server"
  ```
- Client configuration:
  ```yaml
  environment:
    USBIP_SERVER: "server-host"
    USBIP_DEVICE_IDS: "4971:1011"
    MQTT_RELOAD_ON_TOPIC: "rudy/server/start"
  ```

### Multiple clients

It's possible to connect multiple clients to a single server.

Example: Let's assume the following devices are plugged into the server host.
1. Device-ID `1111:1111`, serial number `abc`, for client 1
1. Device-ID `1111:1111`, serial number `def`, for client 2
1. Device-ID `1111:1111`, serial number `ghi`, should not be managed.

Configuration:
- Server
  ```yaml
  environment:
    USBIP_DEVICE_IDS: "1111:1111:abc,1111:1111:def"
  ```
- Client 1
  ```yaml
  environment:
    USBIP_DEVICE_IDS: "1111:1111:abc"
  ```
- Client 2
  ```yaml
  environment:
    USBIP_DEVICE_IDS: "1111:1111:def"
  ```

**Notice:** It's not useful to start more than one server per host,
because the USB/IP device reservation is managed in the kernel.
Thus, all bound devices would be visible to all servers.

## References
* This project is an integration of
  * [USB/IP](http://usbip.sourceforge.net/) - USB Request over IP Network
  * [Mosquitto](https://mosquitto.org/) - An Open Source MQTT Broker
  * The [OCI image](https://github.com/opencontainers/image-spec) format 
  * [Docker](https://www.docker.com)
