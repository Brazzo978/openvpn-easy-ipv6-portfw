# openvpn-easy-ipv6-portfw
This project aims to create an all-in-one OpenVPN install script with many extra features for gaming, torrenting and IPv6 usage.


## Requirements

- Ubuntu >= 18.04
- Debian > 10

### Features

- Automatic installation of the latest xanmod kernel with BBR
- UDP and TCP servers running on the same random port
- IPv6 support and static IPs for every client
- Optional Web GUI on port 65535 to manage profiles
- Built-in port forwarding management

Download and execute the script. Answer the questions asked by the script and it will take care of the rest. The setup now installs both UDP and TCP servers on the same random port. Each new client receives a static IP address valid for both protocols, and you select the desired protocol when creating the profile. Encryption and, if available, IPv6 support can still be customised. The OpenVPN port is generated automatically.


```bash
wget https://raw.githubusercontent.com/Brazzo978/openvpn-easy-ipv6-portfw/refs/heads/main/opvpn-setup.sh
bash ./opvpn-setup.sh
```
Please be aware that the script is gona change ssh port to 65522 !!!
It will install OpenVPN on the server and configure it automatically. Re-run the script at any time to access the management menu with all the available options.




1) see openvpn service status
2) restart openvpn service 
3) add a new vpn client
4) remove a vpn client
5) list current client 
6) check client status (shows VPN IP, real address and connection time)
7) check if the script has been updated and optionally update
8) put the script in /usr/bin so that you can call the script with the name opvpn-setup (toggle add/remove)
9) uninstall everything and remove all tunnel files
10) add a port forwarding rule for a specific client (requires reboot)
11) list defined port forwarding rules
12) remove a previously defined port forwarding rule (requires reboot)
13) enable/disable the optional Web GUI on port 65535
14) Exit from the script

The Web GUI lets you download client profiles and monitor connected users.
When enabling it you will be asked to set a password; disabling it removes
Apache and stops listening on port 65535.

Port forwarding rules are saved in `/etc/openvpn/port-forward.rules`.
When defining a new rule the script verifies that the chosen ports are free and
not already forwarded, then asks for confirmation before applying.

