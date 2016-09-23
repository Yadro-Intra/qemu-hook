# qemu-hook

bash script for /etc/libvirt/hooks/ to configure QEMU guests' connectivity
as described in the [libvirt Networking: Forwarding Incoming Connections](http://wiki.libvirt.org/page/Networking#Forwarding_Incoming_Connections) manual.

## Installation

1. Run `./qemu-portfwd.sh x-check` to verify your environment (pre- and post-install).
2. Stop the guests.
3. Run `sudo ./qemu-portfwd.sh x-install` to install the hook and config (interactive).
4. Restart the `libvirtd` service (it might be `libvirt-bin` and `libvirt-guest` in Ubuntu 16+).
5. Start the guests.

## Config notes

- **Hint:** run `sudo ./qemu-portfwd.sh x-install` and refuse to install.
Then check for `qemu-template.json` in the current directory...

The config is a JSON file where the script will look (using `jq`) for these fields:
```json
{
	"forward": [
		{
			"enabled": true,
			"guest": "test1",
			"external_if": "eth0",
			"internal_if": "virbr0",
			"external_ip": "10.1.0.1",
			"internal_ip": "192.0.2.1",
			"ports": [ { "host":443, "guest":443 }, { "host":2222, "guest":22 } ]
		},
		{
			"enabled": false,
			"guest": "test2",
			"external_if": "eth1",
			"internal_if": "virbr1",
			"external_ip": "10.1.0.2",
			"internal_ip": "192.0.2.2",
			"ports": [ { "host":443, "guest":443 }, { "host":2222, "guest":22 } ]
		}
	]
}
```

As there is no comments in JSON, you may use `"enabled"` entries to turn the section on and off.

Plus, one may add any other entries (say, `"comment": "this is my comment"`) as needed - any extra
fields are merely ignored here.

**It is still to be tuned up...**

## Debug considerations

There is a kernel TRACE facility (grep `/var/log/kern.log` for `TRACE:`):
```
iptables -t raw -A PREROUTING -p tcp --destination 192.168.0.0/24 --dport 80 -j TRACE
```
And tune up your `[r]syslog` config...

## SELinux

Real "Charlie Foxtrot" here :(


