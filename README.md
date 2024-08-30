# openvpn-easy-ipv6-portfw
This project aims to create an AIO openvpn install script with mixed function , for gaming,torrenting,ipv6,DYI Vpn ...


##Requirements 

- Ubuntu >= 18.04
- Debian > 10


Download and execute the script. Answer the questions asked by the script and it will take care of the rest. For most VPS providers.

```bash
wget https://raw.githubusercontent.com/Brazzo978/?
bash ./openvpn-setup.sh
```

It will install openvpn on the server, configure it, Re-Run the script to get the option menù 




1) see openvpn service status
2) restart openvpn service 
3) add a new vpn client
4) remove a vpn client
5) list current client 
6) check client status (checks who is connected via openvpn status and via ping)
7) uninstall everything and remove everything related to the tunnel.
8) WIP  checks if the script has been updated and if a new version is there ask the user if it wants to update
9) let you put the script in /usr/bin so that you can call the script with the name wg-setup ( its a toggle so you can add and remove as you wish )
10) UWIP wizard for adding a port forwarding rule to a determined user , it will ask you the ip address you'd like to open a port and a port or a port range (ex: 80 or  100-6500) (requires a reboot ) 
11) UWIP List in a readable form the port forwarding rules you defined
12) UWIP Remove a port forwarding you previusly defined (requires a reboot of the host )
13) Exit from the script

