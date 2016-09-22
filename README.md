# qemu-hook

bash script for /etc/libvirt/hooks/ to configure QEMU guests' connectivity
as described in the [libvirt Networking: Forwarding Incoming Connections](http://wiki.libvirt.org/page/Networking#Forwarding_Incoming_Connections) manual.

Run `./qemu-portfwd.sh x-check` to verify your environment (pre- and post-install).

Run `sudo ./qemu-portfwd.sh x-install` to install the hook and config (interactive).

The config is a JSON file where the script will look (using jq) for these fields:
```json
{
	"forward": [
		{
			"enabled": true,
			"guest": "test1",
			"external_ip": "10.1.0.1",
			"internal_ip": "192.0.2.1",
			"ports": [ { "host":443, "guest":443 }, { "host":2222, "guest":22 } ]
		},
		{
			"enabled": false,
			"guest": "test2",
			"external_ip": "10.1.0.2",
			"internal_ip": "192.0.2.2",
			"ports": [ { "host":443, "guest":443 }, { "host":2222, "guest":22 } ]
		}
	]
}
```

It is still to be tuned up...
