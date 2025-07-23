# openvpn-easy-ipv6-portfw
This project aims to create an AIO openvpn install script with mixed function , for gaming,torrenting,ipv6,DYI Vpn ...


##Requirements 

- Ubuntu >= 18.04
- Debian > 10


Download and execute the script. Answer the questions asked by the script and it will take care of the rest. The setup now installs both UDP and TCP servers on the same random port (kernel xanmod is automatically installed for BBR). You choose the protocol each time you create a client. Encryption and, if available, IPv6 support can still be customised. The OpenVPN port is generated automatically.

```bash
wget https://raw.githubusercontent.com/Brazzo978/openvpn-easy-ipv6-portfw/refs/heads/main/opvpn-setup.sh
bash ./opvpn-setup.sh
```
Please be aware that the script is gona change ssh port to 65522 !!!
It will install openvpn on the server, configure it, Re-Run the script to get the option menù 




1) see openvpn service status
2) restart openvpn service 
3) add a new vpn client
4) remove a vpn client
5) list current client 
6) check client status (checks who is connected via openvpn status and via ping)
7) check if the script has been updated and optionally update
8) put the script in /usr/bin so that you can call the script with the name opvpn-setup (toggle add/remove)
9) uninstall everything and remove all tunnel files
10) add a port forwarding rule for a specific client (requires reboot)
11) list defined port forwarding rules
12) remove a previously defined port forwarding rule (requires reboot)
13) Exit from the script

Port forwarding rules are saved in `/etc/openvpn/port-forward.rules`.
When defining a new rule the script verifies that the chosen ports are free and
not already forwarded, then asks for confirmation before applying.

