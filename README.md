# usbip-docker
[USB/IP](http://usbip.sourceforge.net/) in Docker

This project provides Docker images to run a USB/IP server and client in Docker containers,
so that USB devices can be used remotely with minimal configuration.

## Server
### Example
```yaml
---
services:
  usbip-server:
    image: ckware/usbip-server
    container_name: usbip-server
    init: true
    restart: unless-stopped
    ports:
      - "3240:3240"
    environment:
      USBIP_DEVICE_IDS: "0000:0000"
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
1. Create a configuration file `docker-compose.yml` (see the examples and docs for an inspiration)

#### Container lifecycle
* Start the server: `docker-compose up -d`
* Stop the server: `docker-compose down`
* Restart a server named `usbip-server`:

  `docker-compose exec usbip-server restart`

### Required Docker configuration options
| Option        | Description            | Recommendation | Explanation |
| ------------- | ---------------------- | -------------- | ----------- |
| `ports`       | Network port           | `3240:3240`    | Network port for client communication.
| `volumes`     | Volumes for USB access | `/sys:/sys`    | Access to USB and other devices.

### Environment variables
See _Common environment variables_

## Client
### Example
```yaml
services:
  usbip-client:
    image: ckware/usbip-client
    container_name: usbip-client
    init: true
    restart: unless-stopped
    environment:
      USBIP_SERVER: "server-host"
      USBIP_DEVICE_IDS: "0000:0000"
    privileged: true
```

### Usage
#### Preparation
1. Enable kernel module `vhci-hcd` on the host:
   ```shell
   $ sudo sh -c 'modprobe vhci-hcd && echo vhci-hcd >>/etc/modules'
   ```
1. Create a configuration file `docker-compose.yml` (see the examples and docs for an inspiration)

#### Container lifecycle
* Start the client: `docker-compose up -d`
* Stop the client: `docker-compose down`
* Restart a client named `usbip-client`:

  `docker-compose exec usbip-client restart`

### Required Docker configuration options
| Option        | Description     | Required | Explanation |
| ------------- | --------------- | -------- | ----------- |
| `privileged`  | Root privileges | `true`   | Root privileges are **required** to write to `/sys/` (see issue [#22825](https://github.com/moby/moby/issues/22825) for details).

### Environment variables
All _Common environment variables_ and:

| Option             | Description            | Example       | Explanation |
| ------------------ | ---------------------- | ------------- | ----------- |
| `USBIP_SERVER`     | USB/IP server hostname | `server-host` | Hostname of the USB/IP server


## Common environment variables
| Option             | Description            | Example               | Explanation |
| ------------------ | ---------------------- | --------------------- | ----------- |
| `USBIP_DEVICE_IDS` | List of USB device IDs | `0000:0000,1111:1111` | Comma-separated device id list of managed USB devices (format VID:PID). This option does not support more than one device per ID.
| `USBIP_BUS_IDS`    | List of USB bus IDs    | `1-1.1,2-2.2`         | Comma-separated id list of managed USB devices (format: logical bus ID). This option can be used to use multiple devices with the same device id. The logical bus id of a device will change when it is plugged into a different USB port.
| `USBIP_DEBUG`      | Enable debug logging   | `true`                | When this option is set to any non-empty value, debug logging is enabled.

Only one of `USBIP_DEVICE_IDS` and `USBIP_BUS_IDS` is required; when both variables are given, `USBIP_BUS_IDS` is preferred.

## Pre-requisites
- A linux system with `docker-compose`.

The Docker Compose [documentation](https://docs.docker.com/compose/install/)
contains a comprehensive guide explaining several install options.
On debian-based systems, `docker-compose` may be installed by calling

```shell
$ sudo apt install docker-compose
```
