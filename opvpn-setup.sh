#!/bin/bash

# Function to check if the user is root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo "Please run as root"
        exit 1
    fi
}

# Function to check the OS version
check_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        VERSION_ID=$(echo $VERSION_ID | cut -d '.' -f1)
        if [[ ("$OS" == "debian" && "$VERSION_ID" -lt 10) || ("$OS" == "ubuntu" && "$VERSION_ID" -lt 18) ]]; then
            echo "Unsupported OS version. Please use Debian 10 or higher, or Ubuntu 18.04 or higher."
            exit 1
        fi
    else
        echo "Unsupported OS. Please use Debian or Ubuntu."
        exit 1
    fi
}

# Function to check if OpenVPN is already installed
check_if_already_installed() {
    if systemctl is-active --quiet openvpn@server; then
        echo "OpenVPN is already installed."
        return 0
    else
        return 1
    fi
}

# Function to display the management menu
management_menu() {
    echo "OpenVPN is already installed. What would you like to do?"
    echo "1. Check tunnel status"
    echo "2. Restart the tunnel"
    echo "3. Remove the tunnel"
    echo "4. Exit"
    read -rp "Select an option: " option

    case $option in
        1)
            systemctl status openvpn@server
            ;;
        2)
            systemctl restart openvpn@server
            echo "OpenVPN tunnel restarted."
            ;;
        3)
            remove_openvpn
            ;;
        4)
            exit 0
            ;;
        *)
            echo "Invalid option. Exiting."
            exit 1
            ;;
    esac
}

# Function to install OpenVPN
install_openvpn() {
    apt-get update
    apt-get install -y openvpn easy-rsa iptables-persistent
}

# Function to validate IP address
validate_ip() {
    local ip=$1
    local stat=1

    if [[ $ip =~ ^([0-9]{1,3}\.){3}0$ ]]; then
        OIFS=$IFS
        IFS='.'
        ip=($ip)
        IFS=$OIFS
        if [[ ${ip[0]} -le 255 && ${ip[1]} -le 255 && ${ip[2]} -le 255 && ${ip[0]} -ge 10 ]]; then
            stat=0
        fi
    fi
    return $stat
}

# Function to prompt user for IP
prompt_for_ip() {
    local default_ip="10.0.0.0"
    while true; do
        echo "It is recommended to use 10.0.0.0/24 for the VPN subnet."
        read -rp "Enter the VPN base IP address [Press Enter to use $default_ip]: " VPN_IP
        VPN_IP=${VPN_IP:-$default_ip}
        if validate_ip "$VPN_IP"; then
            break
        else
            echo "Invalid IP address. Please ensure the last octet is 0 and try again."
        fi
    done

    VPN_SUBNET="255.255.255.0"
    VPN_NETWORK="$VPN_IP"
}

# Function to prompt user for encryption method
prompt_for_encryption() {
    echo "Choose the encryption method for OpenVPN:"
    echo "1) CHACHA20-POLY1305 (default, recommended)"
    echo "2) AES-128-CBC"
    echo "3) AES-256-CBC"
    echo "4) BF-CBC (Blowfish)"
    read -rp "Select an option [1-4]: " encryption_option

    case $encryption_option in
        1|"") # Default to CHACHA20-POLY1305 if no input
            ENCRYPTION="CHACHA20-POLY1305"
            ;;
        2)
            ENCRYPTION="AES-128-CBC"
            ;;
        3)
            ENCRYPTION="AES-256-CBC"
            ;;
        4)
            ENCRYPTION="BF-CBC"
            ;;
        *)
            echo "Invalid option. Defaulting to CHACHA20-POLY1305."
            ENCRYPTION="CHACHA20-POLY1305"
            ;;
    esac

    echo "Encryption set to $ENCRYPTION"
}

# Function to configure OpenVPN
configure_openvpn() {
    RANDOM_PORT=$(shuf -i 65523-65535 -n1)

    # Set up the Easy-RSA environment
    make-cadir ~/openvpn-ca
    cd ~/openvpn-ca || exit

    # Build the CA
    ./easyrsa init-pki
    EASYRSA_BATCH=1 ./easyrsa build-ca nopass <<< "test"

    # Generate a certificate and key for the server
    EASYRSA_CERT_EXPIRE=825 EASYRSA_BATCH=1 ./easyrsa gen-req server nopass <<< "test"
    EASYRSA_CERT_EXPIRE=825 EASYRSA_BATCH=1 ./easyrsa sign-req server server <<< "yes"

    # Generate DH parameters
    ./easyrsa gen-dh

    # Generate a key for the HMAC signature
    openvpn --genkey --secret ta.key

    # Copy the files to the OpenVPN directory
    cp pki/ca.crt pki/issued/server.crt pki/private/server.key pki/dh.pem ta.key /etc/openvpn/

    # Create the server configuration file
    echo "port $RANDOM_PORT
proto $1
dev tun
ca ca.crt
cert server.crt
key server.key
dh dh.pem
auth SHA256
tls-auth ta.key 0
topology subnet
server $VPN_NETWORK $VPN_SUBNET
push \"redirect-gateway def1 bypass-dhcp\"
push \"dhcp-option DNS 1.1.1.1\"
push \"dhcp-option DNS 1.0.0.1\"
keepalive 10 120
cipher $ENCRYPTION
tun-mtu 1420
mssfix 1380
user nobody
group nogroup
persist-key
persist-tun
status openvpn-status.log
verb 3" > /etc/openvpn/server.conf

    # Enable and start the OpenVPN service
    systemctl enable openvpn@server
    systemctl start openvpn@server

    echo "OpenVPN is configured to use port $RANDOM_PORT."
}

# Function to configure iptables for port forwarding
configure_iptables() {
    SERVER_PUB_NIC=$(ip route get 8.8.8.8 | awk '{print $5; exit}')
    SERVER_TUN_NIC="tun0"

    echo "Configuring iptables for port forwarding..."

    # Enable IPv4 forwarding
    echo 1 > /proc/sys/net/ipv4/ip_forward

    # IPv4 iptables rules
    iptables -A FORWARD -i ${SERVER_PUB_NIC} -o ${SERVER_TUN_NIC} -j ACCEPT
    iptables -A FORWARD -i ${SERVER_TUN_NIC} -j ACCEPT
    iptables -t nat -A POSTROUTING -o ${SERVER_PUB_NIC} -j MASQUERADE
    iptables -t nat -A PREROUTING -i ${SERVER_PUB_NIC} -p udp --dport 1:65521 -j DNAT --to-destination ${VPN_NETWORK%.*}.2
    iptables -t nat -A PREROUTING -i ${SERVER_PUB_NIC} -p tcp --dport 1:65521 -j DNAT --to-destination ${VPN_NETWORK%.*}.2

    # Save the iptables rules
    iptables-save > /etc/iptables/rules.v4

    echo "Iptables configuration complete."
}

# Function to move SSH to a different port
move_ssh_port() {
    echo "Moving SSH to port 65522..."
    sed -i "s/#Port\s\+[0-9]\+/Port 65522/" /etc/ssh/sshd_config
    sed -i "s/Port\s\+[0-9]\+/Port 65522/" /etc/ssh/sshd_config
    systemctl restart sshd
    echo "SSH port has been changed to 65522. Please reconnect using this port."
}

# Function to create client configuration with embedded certificates and keys
create_client_config() {
    CLIENT_NAME=$1
    SERVER_IP=$(curl -s4 ifconfig.me)  # Force use of IPv4

    # Generate client certificate and key
    EASYRSA_CERT_EXPIRE=825 EASYRSA_BATCH=1 ./easyrsa gen-req $CLIENT_NAME nopass <<< "$CLIENT_NAME"
    EASYRSA_CERT_EXPIRE=825 EASYRSA_BATCH=1 ./easyrsa sign-req client $CLIENT_NAME <<< "yes"

    # Embed all required parts into the .ovpn file, with correct formatting
    echo "client
dev tun
proto $2
remote $SERVER_IP $3
resolv-retry infinite
nobind
persist-key
persist-tun
remote-cert-tls server
auth SHA256
cipher $ENCRYPTION
tun-mtu 1420
mssfix 1380
setenv opt block-outside-dns
key-direction 1
verb 3
<ca>
$(cat ~/openvpn-ca/pki/ca.crt)
</ca>
<cert>
$(sed -n '/-----BEGIN CERTIFICATE-----/,/-----END CERTIFICATE-----/p' ~/openvpn-ca/pki/issued/$CLIENT_NAME.crt)
</cert>
<key>
$(sed -n '/-----BEGIN PRIVATE KEY-----/,/-----END PRIVATE KEY-----/p' ~/openvpn-ca/pki/private/$CLIENT_NAME.key)
</key>
<tls-auth>
$(cat /etc/openvpn/ta.key)
</tls-auth>" > /root/$CLIENT_NAME.ovpn

    echo "Client configuration is available at /root/$CLIENT_NAME.ovpn"
}

# Function to remove OpenVPN
remove_openvpn() {
    systemctl stop openvpn@server
    systemctl disable openvpn@server
    apt-get remove --purge -y openvpn easy-rsa iptables-persistent
    rm -rf /etc/openvpn
    rm -rf ~/openvpn-ca
    echo "OpenVPN and all associated files have been removed."
}

# Main script
check_root
check_os

if check_if_already_installed; then
    management_menu
else
    # Ask the user for the base IP (last octet must be 0)
    prompt_for_ip

    # Ask the user for TCP or UDP
    echo "Do you want to use TCP or UDP for OpenVPN?"
    select proto in "tcp" "udp"; do
        case $proto in
            tcp ) PROTOCOL="tcp"; break;;
            udp ) PROTOCOL="udp"; break;;
        esac
    done

    # Ask for encryption method
    prompt_for_encryption

    install_openvpn
    configure_openvpn $PROTOCOL
    move_ssh_port
    configure_iptables

    # Ask for a client name and create client config
    echo "Enter a name for the client configuration file:"
    read -r CLIENT_NAME

    create_client_config $CLIENT_NAME $PROTOCOL $RANDOM_PORT

    echo "OpenVPN installation and configuration completed."
fi
