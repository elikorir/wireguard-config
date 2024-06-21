#!/bin/bash

# Function to log messages with timestamp
log_message() {
    echo "$(date +'%Y-%m-%d %H:%M:%S') - $1"
}

# Function to install packages
install_packages() {
    log_message "Installing packages: $@"
    apt-get install -y "$@" || { log_message "Error: Failed to install packages"; exit 1; }
}

# Function to generate WireGuard private and public keys
generate_wireguard_keys() {
    private_key=$(wg genkey)
    echo "$private_key"
    echo "$private_key" | wg pubkey
}

# Function to generate client keypair
generate_client_keypair() {
    client_private_key=$(wg genkey)
    client_public_key=$(echo "$client_private_key" | wg pubkey)
    echo "$client_private_key;$client_public_key"
}

# Function to create WireGuard configuration file
create_wireguard_config() {
    local wg_private_key=$1
    local wg_public_key=$(echo "$wg_private_key" | wg pubkey)
    local client_public_key=$2

    wg_config="/etc/wireguard/wg0.conf"
    cat <<EOF > "$wg_config"
[Interface]
PrivateKey = $wg_private_key
Address = 10.0.0.1/24
ListenPort = 51820

[Peer]
PublicKey = $client_public_key
AllowedIPs = 10.0.0.2/32
EOF

    chmod 600 "$wg_config"
}

# Function to create wg-dynamic configuration file
create_wgdynamic_config() {
    local wg_private_key=$1
    local wg_public_key=$(echo "$wg_private_key" | wg pubkey)

    wg_dynamic_config="/etc/wg-dynamic/config.yml"
    cat <<EOF > "$wg_dynamic_config"
listen_address: 127.0.0.1:5000
private_key: $wg_private_key
public_key: $wg_public_key
peer_limit: 100
database: /var/lib/wg-dynamic/database.sqlite3
interface: wg0
EOF

    chmod 600 "$wg_dynamic_config"
}

# Function to start wg-dynamic service
start_wgdynamic_service() {
    log_message "Starting wg-dynamic service..."
    wg-dynamic "/etc/wg-dynamic/config.yml" &
}

# Function to enable IP forwarding
enable_ip_forwarding() {
    log_message "Enabling IP forwarding..."
    sysctl -w net.ipv4.ip_forward=1
    echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
}

# Function to restart WireGuard service
restart_wireguard_service() {
    log_message "Restarting WireGuard service..."
    systemctl restart wg-quick@wg0
}

# Function to generate client configuration file
generate_client_config() {
    local client_private_key=$1
    local client_public_key=$2
    local server_public_key=$3
    local server_public_ip=$4

    client_config="/etc/wireguard/clients/$client_public_key.conf"
    cat <<EOF > "$client_config"
[Interface]
PrivateKey = $client_private_key
Address = 10.0.0.2/24
DNS = 8.8.8.8   # Example DNS server, adjust as needed

[Peer]
PublicKey = $server_public_key
Endpoint = $server_public_ip:51820
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 25
EOF

    chmod 600 "$client_config"
    log_message "Generated client configuration: $client_config"
}

# Main function
main() {
    # Check if running as root
    if [[ $EUID -ne 0 ]]; then
        echo "This script must be run as root"
        exit 1
    fi

    # Update package repositories
    install_packages software-properties-common || exit 1
    add-apt-repository -y ppa:wireguard/wireguard || exit 1
    apt-get update || { log_message "Error: Failed to update package repositories"; exit 1; }

    # Install WireGuard and necessary tools
    install_packages wireguard build-essential libssl-dev pkg-config git || exit 1

    # Clone and build wg-dynamic
    log_message "Cloning and building wg-dynamic..."
    git clone https://github.com/WireGuard/wg-dynamic.git /opt/wg-dynamic || { log_message "Error: Failed to clone wg-dynamic repository"; exit 1; }
    cd /opt/wg-dynamic || { log_message "Error: Failed to change directory to /opt/wg-dynamic"; exit 1; }
    make || { log_message "Error: Failed to build wg-dynamic"; exit 1; }
    make install || { log_message "Error: Failed to install wg-dynamic"; exit 1; }

    # Generate WireGuard keys
    log_message "Generating WireGuard private and public keys..."
    wg_private_key=$(generate_wireguard_keys) || { log_message "Error: Failed to generate WireGuard private key"; exit 1; }

    # Generate client keypair (optional)
    log_message "Generating client keypair..."
    client_keypair=$(generate_client_keypair) || { log_message "Error: Failed to generate client keypair"; exit 1; }
    client_private_key=$(echo "$client_keypair" | cut -d';' -f1)
    client_public_key=$(echo "$client_keypair" | cut -d';' -f2)

    # Create WireGuard configuration file
    log_message "Creating WireGuard configuration file..."
    create_wireguard_config "$wg_private_key" "$client_public_key" || { log_message "Error: Failed to create WireGuard configuration file"; exit 1; }

    # Create wg-dynamic configuration file
    log_message "Creating wg-dynamic configuration file..."
    create_wgdynamic_config "$wg_private_key" || { log_message "Error: Failed to create wg-dynamic configuration file"; exit 1; }

    # Start wg-dynamic service
    start_wgdynamic_service || { log_message "Error: Failed to start wg-dynamic service"; exit 1; }

    # Enable IP forwarding
    enable_ip_forwarding || { log_message "Error: Failed to enable IP forwarding"; exit 1; }

    # Restart WireGuard service
    restart_wireguard_service || { log_message "Error: Failed to restart WireGuard service"; exit 1; }

    # Display generated keys (for demonstration purposes)
    log_message "WireGuard Private Key: $wg_private_key"
    log_message "WireGuard Public Key: $wg_public_key"
    log_message "Client Private Key: $client_private_key"
    log_message "Client Public Key: $client_public_key"

    # Optionally generate client configuration file
    generate_client_config "$client_private_key" "$client_public_key" "$wg_public_key" "<server_public_ip>"

    log_message "WireGuard setup complete."
}

# Execute main function
main "$@"
