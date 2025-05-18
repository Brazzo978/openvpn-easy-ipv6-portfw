#!/bin/bash

SCRIPT_VERSION="1.0.0"   # <-- Aggiorna qui ad ogni release
GITHUB_RAW_URL="https://raw.githubusercontent.com/tuo-user/tuo-repo/main/openvpn_manager.sh" # MODIFICA con il tuo URL RAW
SCRIPT_NAME="openvpn_manager.sh"
SCRIPT_PATH="/usr/bin/$SCRIPT_NAME"

# Variabili globali
ENCRYPTION=""
TUN_MTU=""
MSS_FIX=""
RANDOM_PORT=""
VPN_NETWORK=""
VPN_SUBNET=""
PROTOCOL=""

# Funzione per check permessi root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo "Please run as root"
        exit 1
    fi
}

# Funzione per check OS
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

# Funzione installazione kernel xanmod (solo TCP)
install_xanmod_kernel() {
    echo "Installo kernel xanmod 6.12.15 necessario per TCP con BBR..."
    apt-get update
    apt-get install -y wget curl gnupg
    echo 'deb http://deb.xanmod.org releases main' | tee /etc/apt/sources.list.d/xanmod-kernel.list
    wget -qO - https://dl.xanmod.org/gpg.key | apt-key add -
    apt-get update
    apt-get install -y linux-image-6.12.15-x64v3-xanmod1
    echo "Riavvio necessario per usare il nuovo kernel!"
    reboot
}

# Check se OpenVPN già installato
check_if_already_installed() {
    if systemctl is-active --quiet openvpn@server; then
        return 0
    else
        return 1
    fi
}

# Funzione toggle in /usr/bin
toggleSystemVar() {
    CURRENT_SCRIPT=$(readlink -f "$0")
    if [ -f "$SCRIPT_PATH" ]; then
        echo "Il script è già in /usr/bin. Rimuovere? (y/n)"
        read -r choice
        if [[ $choice == "y" || $choice == "Y" ]]; then
            rm "$SCRIPT_PATH"
            echo "Script rimosso da /usr/bin!"
        else
            echo "Azione annullata."
        fi
    else
        echo "Script non presente in /usr/bin. Aggiungere? (y/n)"
        read -r choice
        if [[ $choice == "y" || $choice == "Y" ]]; then
            cp "$CURRENT_SCRIPT" "$SCRIPT_PATH"
            chmod +x "$SCRIPT_PATH"
            echo "Script aggiunto a /usr/bin!"
        else
            echo "Azione annullata."
        fi
    fi
}

# Funzione update script da github
check_for_script_update() {
    echo "Controllo aggiornamenti script..."
    wget -qO /tmp/openvpn_manager_new.sh "$GITHUB_RAW_URL"
    REMOTE_VERSION=$(grep "SCRIPT_VERSION=" /tmp/openvpn_manager_new.sh | head -1 | cut -d'"' -f2)
    echo "Versione attuale: $SCRIPT_VERSION, Versione online: $REMOTE_VERSION"
    if [ "$REMOTE_VERSION" != "$SCRIPT_VERSION" ]; then
        echo "Trovata versione più recente. Aggiornare? (y/n)"
        read -r scelta
        if [[ $scelta == "y" || $scelta == "Y" ]]; then
            cp /tmp/openvpn_manager_new.sh "$0"
            chmod +x "$0"
            echo "Script aggiornato! Riavvia."
            exit 0
        else
            echo "Update annullato."
        fi
    else
        echo "Già aggiornato."
    fi
    rm /tmp/openvpn_manager_new.sh
}

# Funzione validazione IP (accetta solo IP che finiscono con .0)
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

# Prompt IP di base VPN
prompt_for_ip() {
    local default_ip="10.0.0.0"
    while true; do
        echo "Consigliato: 10.0.0.0/24 per la VPN."
        read -rp "IP base VPN (es: 10.0.0.0) [invio per default $default_ip]: " VPN_IP
        VPN_IP=${VPN_IP:-$default_ip}
        if validate_ip "$VPN_IP"; then
            break
        else
            echo "IP non valido. L'ultimo ottetto deve essere 0."
        fi
    done
    VPN_SUBNET="255.255.255.0"
    VPN_NETWORK="$VPN_IP"
}

# Prompt MTU
prompt_for_mtu() {
    local default_mtu="1420"
    while true; do
        echo "MTU consigliato: 1420."
        read -rp "MTU per il tunnel (1280-1492) [invio per $default_mtu]: " TUN_MTU
        TUN_MTU=${TUN_MTU:-$default_mtu}
        if [[ $TUN_MTU -ge 1280 && $TUN_MTU -le 1492 ]]; then
            MSS_FIX=$((TUN_MTU - 40))
            echo "MTU: $TUN_MTU, MSS Fix: $MSS_FIX."
            break
        else
            echo "MTU non valido."
        fi
    done
}

# Prompt algoritmo cifratura
prompt_for_encryption() {
    echo "Scegli cifratura OpenVPN:"
    echo "1) CHACHA20-POLY1305 (default, consigliato)"
    echo "2) AES-128-CBC"
    echo "3) AES-256-CBC"
    echo "4) BF-CBC (Blowfish)"
    read -rp "Opzione [1-4]: " encryption_option
    case $encryption_option in
        1|"") ENCRYPTION="CHACHA20-POLY1305" ;;
        2) ENCRYPTION="AES-128-CBC" ;;
        3) ENCRYPTION="AES-256-CBC" ;;
        4) ENCRYPTION="BF-CBC" ;;
        *) ENCRYPTION="CHACHA20-POLY1305" ;;
    esac
    echo "Cifratura: $ENCRYPTION"
}

# Installazione OpenVPN & dipendenze
install_openvpn() {
    apt-get update
    apt-get install -y openvpn easy-rsa iptables-persistent
}

# Configurazione OpenVPN
configure_openvpn() {
    RANDOM_PORT=$(shuf -i 65523-65535 -n1)
    make-cadir ~/openvpn-ca
    cd ~/openvpn-ca || exit 1
    ./easyrsa init-pki
    EASYRSA_BATCH=1 ./easyrsa build-ca nopass <<< "test"
    EASYRSA_CERT_EXPIRE=825 EASYRSA_BATCH=1 ./easyrsa gen-req server nopass <<< "test"
    EASYRSA_CERT_EXPIRE=825 EASYRSA_BATCH=1 ./easyrsa sign-req server server <<< "yes"
    ./easyrsa gen-dh
    openvpn --genkey --secret ta.key
    cp pki/ca.crt pki/issued/server.crt pki/private/server.key pki/dh.pem ta.key /etc/openvpn/
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
tun-mtu $TUN_MTU
mssfix $MSS_FIX
user nobody
group nogroup
persist-key
persist-tun
status /var/log/openvpn-status.log
verb 3" > /etc/openvpn/server.conf
    systemctl enable openvpn@server
    systemctl start openvpn@server
    echo "OpenVPN in ascolto su porta $RANDOM_PORT."
}

# Configurazione iptables
configure_iptables() {
    SERVER_PUB_NIC=$(ip route get 8.8.8.8 | awk '{print $5; exit}')
    SERVER_TUN_NIC="tun0"
    echo 1 > /proc/sys/net/ipv4/ip_forward
    iptables -A FORWARD -i ${SERVER_PUB_NIC} -o ${SERVER_TUN_NIC} -j ACCEPT
    iptables -A FORWARD -i ${SERVER_TUN_NIC} -j ACCEPT
    iptables -t nat -A POSTROUTING -o ${SERVER_PUB_NIC} -j MASQUERADE
    iptables-save > /etc/iptables/rules.v4
    echo "Iptables configurato."
}

# Cambio porta SSH
move_ssh_port() {
    echo "Cambio SSH a porta 65522..."
    sed -i "s/#Port\s\+[0-9]\+/Port 65522/" /etc/ssh/sshd_config
    sed -i "s/Port\s\+[0-9]\+/Port 65522/" /etc/ssh/sshd_config
    systemctl restart sshd
    echo "SSH ora su porta 65522."
}

# Add client
add_client() {
    echo "Nome client da creare:"
    read -r CLIENT_NAME
    create_client_config "$CLIENT_NAME" "$PROTOCOL" "$RANDOM_PORT"
    echo "Client $CLIENT_NAME creato in /root/$CLIENT_NAME.ovpn."
}

# Remove client
remove_client() {
    echo "Nome client da rimuovere:"
    read -r CLIENT_NAME
    rm -f "/etc/openvpn/easy-rsa/pki/issued/${CLIENT_NAME}.crt"
    rm -f "/etc/openvpn/easy-rsa/pki/private/${CLIENT_NAME}.key"
    rm -f "/etc/openvpn/easy-rsa/pki/reqs/${CLIENT_NAME}.req"
    rm -f "/root/${CLIENT_NAME}.ovpn"
    echo "Client $CLIENT_NAME rimosso."
}

# List clients
list_clients() {
    echo "Client esistenti:"
    ls /etc/openvpn/easy-rsa/pki/issued/ 2>/dev/null | grep -v ca.crt | sed 's/.crt//'
}

# Stato client
check_client_status() {
    echo "Stato client:"
    while read -r client; do
        ip=$(grep "$client" /var/log/openvpn-status.log | awk '{print $1}')
        if [ -n "$ip" ]; then
            echo "$client ONLINE ($ip)"
        else
            echo "$client offline"
        fi
    done < <(ls /etc/openvpn/easy-rsa/pki/issued/ 2>/dev/null | grep -v ca.crt | sed 's/.crt//')
}

# Create client config
create_client_config() {
    CLIENT_NAME=$1
    SERVER_IP=$(curl -s4 ifconfig.me)
    cd ~/openvpn-ca || exit 1
    EASYRSA_CERT_EXPIRE=825 EASYRSA_BATCH=1 ./easyrsa gen-req $CLIENT_NAME nopass <<< "$CLIENT_NAME"
    EASYRSA_CERT_EXPIRE=825 EASYRSA_BATCH=1 ./easyrsa sign-req client $CLIENT_NAME <<< "yes"
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
tun-mtu $TUN_MTU
mssfix $MSS_FIX
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
    echo "Configurazione client salvata in /root/$CLIENT_NAME.ovpn"
}

# Rimuove OpenVPN
remove_openvpn() {
    systemctl stop openvpn@server
    systemctl disable openvpn@server
    apt-get remove --purge -y openvpn easy-rsa iptables-persistent
    rm -rf /etc/openvpn
    rm -rf ~/openvpn-ca
    rm -rf /root/*.ovpn
    rm -rf /etc/systemd/system/multi-user.target.wants/openvpn@server.service
    echo "OpenVPN e tutti i file rimossi."
}

# Menù management
management_menu() {
    while true; do
        echo "\n========= OpenVPN Management Menu ========="
        echo "1. Stato tunnel"
        echo "2. Riavvia tunnel"
        echo "3. Aggiungi client"
        echo "4. Rimuovi client"
        echo "5. Lista client"
        echo "6. Stato client"
        echo "7. Controlla update script"
        echo "8. Toggle script in /usr/bin"
        echo "9. Rimuovi OpenVPN & cleanup"
        echo "10. Esci"
        read -rp "Scelta: " opzione
        case $opzione in
            1) systemctl status openvpn@server;;
            2) systemctl restart openvpn@server; echo "Tunnel riavviato.";;
            3) add_client;;
            4) remove_client;;
            5) list_clients;;
            6) check_client_status;;
            7) check_for_script_update;;
            8) toggleSystemVar;;
            9) remove_openvpn;;
            10) exit 0;;
            *) echo "Opzione non valida!";;
        esac
    done
}

# MAIN
check_root
check_os

if check_if_already_installed; then
    management_menu
else
    # Protocollo
    echo "Scegli protocollo (tcp/udp):"
    select proto in "tcp" "udp"; do
        PROTOCOL=$proto
        break
    done
    if [[ "$PROTOCOL" == "tcp" ]]; then
        install_xanmod_kernel
    fi
    prompt_for_ip
    prompt_for_mtu
    prompt_for_encryption
    install_openvpn
    configure_openvpn $PROTOCOL
    move_ssh_port
    configure_iptables
    echo "Installazione e configurazione OpenVPN completata!"
    management_menu
fi
