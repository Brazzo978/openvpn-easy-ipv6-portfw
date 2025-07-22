#!/bin/bash

SCRIPT_VERSION="1.1.0"
GITHUB_RAW_URL="https://raw.githubusercontent.com/Brazzo978/openvpn-easy-ipv6-portfw/refs/heads/main/opvpn-setup.sh"
SCRIPT_NAME="openvpn-setup.sh"
SCRIPT_PATH="/usr/bin/$SCRIPT_NAME"

# Variabili globali
ENCRYPTION=""
TUN_MTU=""
MSS_FIX=""
RANDOM_PORT=""
VPN_NETWORK=""
VPN_SUBNET=""
PROTOCOL=""
USE_IPV6=""
VPN_NETWORK6=""
SERVER_PUB_NIC=""
PF_RULES_FILE="/etc/openvpn/port-forward.rules"


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
    wget -qO- https://dl.xanmod.org/gpg.key | gpg --dearmor -o /usr/share/keyrings/xanmod.gpg
    echo 'deb [signed-by=/usr/share/keyrings/xanmod.gpg] http://deb.xanmod.org releases main' \
        | tee /etc/apt/sources.list.d/xanmod-kernel.list
    apt-get update
    apt-get install -y linux-image-6.12.15-x64v3-xanmod1
    echo "Abilito BBR come scheduler TCP..."
    modprobe tcp_bbr
    echo 'tcp_bbr' | tee /etc/modules-load.d/tcp_bbr.conf
    cat <<EOF >/etc/sysctl.d/60-bbr.conf
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
EOF
    sysctl -p /etc/sysctl.d/60-bbr.conf
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

# Validazione generica IPv4 (qualsiasi ultimo ottetto)
validate_ipv4() {
    local ipaddr=$1
    local stat=1
    if [[ $ipaddr =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        local IFS=.
        read -r i1 i2 i3 i4 <<<"$ipaddr"
        if (( i1<=255 && i2<=255 && i3<=255 && i4<=255 )); then
            stat=0
        fi
    fi
    return $stat
}

# Controlla se una porta è già in ascolto sul sistema
port_in_use() {
    local port=$1
    ss -ln | grep -qE "[:.]$port\s"
}

# Verifica conflitti con altre regole di port forwarding
conflict_with_existing_rules() {
    local start=$1 end=$2
    local line r_start r_end
    [[ -f $PF_RULES_FILE ]] || return 1
    while read -r line; do
        if [[ $line =~ --dport\ ([0-9]+):([0-9]+) ]]; then
            r_start=${BASH_REMATCH[1]}
            r_end=${BASH_REMATCH[2]}
        elif [[ $line =~ --dport\ ([0-9]+) ]]; then
            r_start=${BASH_REMATCH[1]}
            r_end=$r_start
        else
            continue
        fi
        if (( start <= r_end && end >= r_start )); then
            return 0
        fi
    done < "$PF_RULES_FILE"
    return 1
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
    while true; do
        echo "Scegli cifratura OpenVPN:"
        echo "1) CHACHA20-POLY1305 (default, consigliato)"
        echo "2) AES-128-CBC"
        echo "3) AES-256-CBC"
        echo "4) BF-CBC (Blowfish)"
        read -rp "Opzione [1-4]: " encryption_option
        case $encryption_option in
            1|"") ENCRYPTION="CHACHA20-POLY1305"; break ;;
            2) ENCRYPTION="AES-128-CBC"; break ;;
            3) ENCRYPTION="AES-256-CBC"; break ;;
            4) ENCRYPTION="BF-CBC"; break ;;
            *) echo "Scelta non valida.";;
        esac
    done
    echo "Cifratura: $ENCRYPTION"
}

# Imposta porta OpenVPN casuale
set_random_port() {
    RANDOM_PORT=$(shuf -i 65523-65535 -n1)
    echo "Porta OpenVPN selezionata: $RANDOM_PORT"
}

# Prompt protocollo (udp/tcp)
prompt_for_protocol() {
    local default_proto="udp"
    while true; do
        read -rp "Protocollo (udp/tcp) [${default_proto}]: " PROTOCOL
        PROTOCOL=${PROTOCOL:-$default_proto}
        if [[ $PROTOCOL == "udp" || $PROTOCOL == "tcp" ]]; then
            break
        else
            echo "Inserire 'udp' o 'tcp'."
        fi
    done
}

# Verifica presenza IPv6 sull'interfaccia pubblica
check_ipv6_available() {
    if ip -6 addr show "$SERVER_PUB_NIC" | grep -q 'inet6.*global'; then
        return 0
    else
        return 1
    fi
}

# Prompt utilizzo IPv6
prompt_for_ipv6() {
    if check_ipv6_available; then
        read -rp "Abilitare supporto IPv6? [y/N]: " use_v6
        if [[ $use_v6 =~ ^[Yy]$ ]]; then
            USE_IPV6="yes"
            local default_v6="fd42:42:42::/64"
            while true; do
                read -rp "Prefisso IPv6 per i client [${default_v6}]: " VPN_NETWORK6
                VPN_NETWORK6=${VPN_NETWORK6:-$default_v6}
                if [[ $VPN_NETWORK6 =~ ^[0-9a-fA-F:]+/[0-9]{1,3}$ ]]; then
                    local prefix=${VPN_NETWORK6##*/}
                    if (( prefix >= 1 && prefix <= 128 )); then
                        break
                    fi
                fi
                echo "Prefisso IPv6 non valido."
            done
        fi
    fi
}

# Installazione OpenVPN & dipendenze
install_openvpn() {
    apt-get update
    apt-get install -y openvpn easy-rsa iptables-persistent
}

# Configurazione OpenVPN
configure_openvpn() {
    make-cadir ~/openvpn-ca
    cd ~/openvpn-ca || exit 1
    ./easyrsa init-pki
    EASYRSA_BATCH=1 ./easyrsa build-ca nopass <<< "test"
    EASYRSA_CERT_EXPIRE=825 EASYRSA_BATCH=1 ./easyrsa gen-req server nopass <<< "test"
    EASYRSA_CERT_EXPIRE=825 EASYRSA_BATCH=1 ./easyrsa sign-req server server <<< "yes"
    ./easyrsa gen-dh
    openvpn --genkey --secret ta.key
    cp pki/ca.crt pki/issued/server.crt pki/private/server.key pki/dh.pem ta.key /etc/openvpn/
    {
        echo "port $RANDOM_PORT"
        echo "proto $1"
        echo "dev tun"
        echo "ca ca.crt"
        echo "cert server.crt"
        echo "key server.key"
        echo "dh dh.pem"
        echo "auth SHA256"
        echo "tls-auth ta.key 0"
        echo "topology subnet"
        echo "server $VPN_NETWORK $VPN_SUBNET"
        echo "push \"redirect-gateway def1 bypass-dhcp\""
        echo "push \"dhcp-option DNS 1.1.1.1\""
        echo "push \"dhcp-option DNS 1.0.0.1\""
        if [[ $USE_IPV6 == "yes" ]]; then
            echo "server-ipv6 $VPN_NETWORK6"
            echo "push \"redirect-gateway ipv6\""
            echo "push \"dhcp-option DNS6 2606:4700:4700::1111\""
            echo "push \"dhcp-option DNS6 2606:4700:4700::1001\""
        fi
        echo "keepalive 10 120"
        echo "cipher $ENCRYPTION"
        echo "tun-mtu $TUN_MTU"
        echo "mssfix $MSS_FIX"
        echo "user nobody"
        echo "group nogroup"
        echo "persist-key"
        echo "persist-tun"
        echo "status /var/log/openvpn-status.log"
        echo "verb 3"
    } > /etc/openvpn/server.conf
    systemctl enable openvpn@server
    systemctl start openvpn@server
    echo "OpenVPN in ascolto su porta $RANDOM_PORT."
}

# Configurazione iptables
configure_iptables() {
    SERVER_PUB_NIC=$(ip route get 8.8.8.8 | awk '{print $5; exit}')
    SERVER_TUN_NIC="tun0"
    echo 1 > /proc/sys/net/ipv4/ip_forward
    iptables -A FORWARD -i "${SERVER_PUB_NIC}" -o "${SERVER_TUN_NIC}" -j ACCEPT
    iptables -A FORWARD -i "${SERVER_TUN_NIC}" -j ACCEPT
    iptables -t nat -A POSTROUTING -o "${SERVER_PUB_NIC}" -j MASQUERADE
    iptables-save > /etc/iptables/rules.v4
    if [[ $USE_IPV6 == "yes" ]]; then
        echo 1 > /proc/sys/net/ipv6/conf/all/forwarding
        ip6tables -A FORWARD -i "${SERVER_PUB_NIC}" -o "${SERVER_TUN_NIC}" -j ACCEPT
        ip6tables -A FORWARD -i "${SERVER_TUN_NIC}" -j ACCEPT
        ip6tables -t nat -A POSTROUTING -o "${SERVER_PUB_NIC}" -j MASQUERADE
        ip6tables-save > /etc/iptables/rules.v6
    fi
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
    EASYRSA_CERT_EXPIRE=825 EASYRSA_BATCH=1 ./easyrsa gen-req "$CLIENT_NAME" nopass <<< "$CLIENT_NAME"
    EASYRSA_CERT_EXPIRE=825 EASYRSA_BATCH=1 ./easyrsa sign-req client "$CLIENT_NAME" <<< "yes"
    {
        echo "client"
        echo "dev tun"
        [[ $USE_IPV6 == "yes" ]] && echo "tun-ipv6"
        echo "proto $2"
        echo "remote $SERVER_IP $3"
        echo "resolv-retry infinite"
        echo "nobind"
        echo "persist-key"
        echo "persist-tun"
        echo "remote-cert-tls server"
        echo "auth SHA256"
        echo "cipher $ENCRYPTION"
        echo "tun-mtu $TUN_MTU"
        echo "mssfix $MSS_FIX"
        echo "setenv opt block-outside-dns"
        echo "key-direction 1"
        echo "verb 3"
        echo "<ca>"
        cat ~/openvpn-ca/pki/ca.crt
        echo "</ca>"
        echo "<cert>"
        sed -n '/-----BEGIN CERTIFICATE-----/,/-----END CERTIFICATE-----/p' ~/openvpn-ca/pki/issued/"$CLIENT_NAME".crt
        echo "</cert>"
        echo "<key>"
        sed -n '/-----BEGIN PRIVATE KEY-----/,/-----END PRIVATE KEY-----/p' ~/openvpn-ca/pki/private/"$CLIENT_NAME".key
        echo "</key>"
        echo "<tls-auth>"
        cat /etc/openvpn/ta.key
        echo "</tls-auth>"
    } > /root/"$CLIENT_NAME".ovpn
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
    rm -f "$PF_RULES_FILE"
    rm -rf /etc/systemd/system/multi-user.target.wants/openvpn@server.service
    echo "OpenVPN e tutti i file rimossi."
}

# Gestione port forwarding
add_port_forwarding() {
    # chiedi IP client e validalo
    while true; do
        read -rp "IP del client destinatario: " PEER_IP
        if validate_ipv4 "$PEER_IP"; then
            break
        else
            echo "IP non valido."
        fi
    done

    # chiedi porta/intervallo e validalo
    while true; do
        read -rp "Porta o intervallo da inoltrare (es 80 o 1000-2000): " PORT_RANGE
        if [[ $PORT_RANGE =~ ^([0-9]{1,5})-([0-9]{1,5})$ ]]; then
            START=${BASH_REMATCH[1]}
            END=${BASH_REMATCH[2]}
            if (( START<1 || END>65535 || START>END )); then
                echo "Intervallo non valido."
                continue
            fi
        elif [[ $PORT_RANGE =~ ^([0-9]{1,5})$ ]]; then
            START=${BASH_REMATCH[1]}
            END=$START
            if (( START<1 || START>65535 )); then
                echo "Porta non valida."
                continue
            fi
        else
            echo "Formato porta errato."
            continue
        fi

        # non sovrapporsi alla porta VPN
        if (( RANDOM_PORT >= START && RANDOM_PORT <= END )); then
            echo "Conflitto con la porta OpenVPN ($RANDOM_PORT)."
            continue
        fi

        # non sovrapporsi ad altre regole
        conflict_with_existing_rules "$START" "$END" && { 
            echo "Conflitto con regola esistente."
            continue
        }

        # non usare porte già in uso sul sistema
        conflict=0
        for p in $(seq "$START" "$END"); do
            if port_in_use "$p"; then
                echo "Porta $p già in uso."
                conflict=1
                break
            fi
        done
        [[ $conflict -eq 1 ]] && continue

        break
    done

    # conferma
    printf "Confermi inoltro porte %s verso %s? [y/N]: " "$PORT_RANGE" "$PEER_IP"
    read -r ans
    [[ $ans =~ ^[Yy]$ ]] || { echo "Annullato"; return; }

    # crea e applica regole iptables
    if [[ $PORT_RANGE == *-* ]]; then
        IPTABLES_RULE_TCP="iptables -t nat -A PREROUTING -i ${SERVER_PUB_NIC} -p tcp --dport ${PORT_RANGE//\-/:} -j DNAT --to-destination ${PEER_IP}:${PORT_RANGE}"
        IPTABLES_RULE_UDP="iptables -t nat -A PREROUTING -i ${SERVER_PUB_NIC} -p udp --dport ${PORT_RANGE//\-/:} -j DNAT --to-destination ${PEER_IP}:${PORT_RANGE}"
    else
        IPTABLES_RULE_TCP="iptables -t nat -A PREROUTING -i ${SERVER_PUB_NIC} -p tcp --dport ${PORT_RANGE} -j DNAT --to-destination ${PEER_IP}:${PORT_RANGE}"
        IPTABLES_RULE_UDP="iptables -t nat -A PREROUTING -i ${SERVER_PUB_NIC} -p udp --dport ${PORT_RANGE} -j DNAT --to-destination ${PEER_IP}:${PORT_RANGE}"
    fi

    echo "$IPTABLES_RULE_TCP" >> "$PF_RULES_FILE"
    echo "$IPTABLES_RULE_UDP" >> "$PF_RULES_FILE"
    chmod +x "$PF_RULES_FILE"

    eval "$IPTABLES_RULE_TCP"
    eval "$IPTABLES_RULE_UDP"
    iptables-save > /etc/iptables/rules.v4

    echo "Regola aggiunta."
}


list_port_forwarding() {
    if [ -f "$PF_RULES_FILE" ]; then
        nl -ba "$PF_RULES_FILE"
    else
        echo "Nessuna regola definita."
    fi
}

remove_port_forwarding() {
    if [ ! -f "$PF_RULES_FILE" ]; then
        echo "Nessuna regola da rimuovere."
        return
    fi
    list_port_forwarding
    read -rp "Numero regola da rimuovere: " RULE_NUM
    RULE=$(sed -n "${RULE_NUM}p" "$PF_RULES_FILE")
    if [ -z "$RULE" ]; then
        echo "Numero non valido."
        return
    fi
    REMOVE_RULE=${RULE/-A/-D}
    eval "$REMOVE_RULE"
    sed -i "${RULE_NUM}d" "$PF_RULES_FILE"
    iptables-save > /etc/iptables/rules.v4
    echo "Regola rimossa."
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
        echo "10. Aggiungi port forwarding"
        echo "11. Lista port forwarding"
        echo "12. Rimuovi port forwarding"
        echo "13. Esci"
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
            10) add_port_forwarding;;
            11) list_port_forwarding;;
            12) remove_port_forwarding;;
            13) exit 0;;
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
    SERVER_PUB_NIC=$(ip route get 8.8.8.8 | awk '{print $5; exit}')
    prompt_for_protocol
    if [[ "$PROTOCOL" == "tcp" ]]; then
        install_xanmod_kernel
    fi
    set_random_port
    prompt_for_ip
    prompt_for_mtu
    prompt_for_encryption
    prompt_for_ipv6
    install_openvpn
    configure_openvpn "$PROTOCOL"
    move_ssh_port
    configure_iptables
    echo "Installazione e configurazione OpenVPN completata!"
    management_menu
fi
