#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored messages
print_message() {
    echo -e "${GREEN}[+] $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}[!] $1${NC}"
}

print_error() {
    echo -e "${RED}[-] $1${NC}"
}

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    print_error "Please run as root"
    exit 1
fi

# Install cloudflared
install_cloudflared() {
    print_message "Installing cloudflared..."

    # Add cloudflare gpg key
    mkdir -p --mode=0755 /usr/share/keyrings
    curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg | tee /usr/share/keyrings/cloudflare-main.gpg >/dev/null

    # Add cloudflare repository
    echo "deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/cloudflared.list

    # Install
    apt update
    apt install -y cloudflared
}

# Install PM2 if not present
install_pm2() {
    print_message "Installing PM2..."
    if ! command -v npm &> /dev/null; then
        curl -fsSL https://deb.nodesource.com/setup_lts.x | bash -
        apt install -y nodejs
    fi
    npm install -g pm2
}

# Function to create a single tunnel
create_tunnel() {
    local DOMAIN=$1
    local PORT=$2
    local INDEX=$3
    local TUNNEL_NAME=$(echo $DOMAIN | sed 's/\./-/g')  # Convert dots to dashes

    print_message "Setting up tunnel for $DOMAIN..."

    # Create tunnel
    print_message "Creating tunnel..."
    TUNNEL_ID=$(cloudflared tunnel create "${TUNNEL_NAME}-tunnel" | awk '/Created tunnel/ {print $3}')
    print_message "Tunnel ID: $TUNNEL_ID"

    # Create config file
    print_message "Creating config file..."
    cat > ~/.cloudflared/config-${TUNNEL_NAME}.yml << EOL
tunnel: ${TUNNEL_ID}
credentials-file: /root/.cloudflared/${TUNNEL_NAME}-tunnel.json

ingress:
  - hostname: ${DOMAIN}
    service: http://localhost:${PORT}
  - service: http_status:404
EOL

    # Create DNS record
    print_message "Creating DNS record..."
    cloudflared tunnel route dns ${TUNNEL_ID} ${DOMAIN}

    # Create startup script
    print_message "Creating startup script..."
    cat > /root/cloudflared-${TUNNEL_NAME}-tunnel.sh << EOL
#!/bin/bash
cloudflared tunnel --config /root/.cloudflared/config-${TUNNEL_NAME}.yml run ${TUNNEL_ID}
EOL

    chmod +x /root/cloudflared-${TUNNEL_NAME}-tunnel.sh

    # Start with PM2
    print_message "Starting tunnel with PM2..."
    pm2 start /root/cloudflared-${TUNNEL_NAME}-tunnel.sh --name "cloudflare-${TUNNEL_NAME}-tunnel" --interpreter bash
}

# Main setup function
setup_tunnels() {
    print_message "Starting Cloudflare Tunnels setup..."

    # Check if cloudflared is installed
    if ! command -v cloudflared &> /dev/null; then
        install_cloudflared
    fi

    # Check if PM2 is installed
    if ! command -v pm2 &> /dev/null; then
        install_pm2
    fi

    # Create directories
    mkdir -p ~/.cloudflared

    # Login to cloudflared (if not already logged in)
    if [ ! -f ~/.cloudflared/cert.pem ]; then
        print_message "Please login to Cloudflare in your browser..."
        cloudflared tunnel login
    fi

    # Get number of tunnels to create
    read -p "How many tunnels do you want to create? " TUNNEL_COUNT

    # Array to store tunnel configurations
    declare -A TUNNEL_CONFIGS

    # Gather all tunnel information first
    for ((i=1; i<=TUNNEL_COUNT; i++)); do
        print_message "Configuration for tunnel #$i"
        read -p "Enter domain (e.g., example.com): " DOMAIN
        read -p "Enter local port (default: 80): " PORT
        PORT=${PORT:-80}
        TUNNEL_CONFIGS[$i]="${DOMAIN}:${PORT}"
    done

    # Create all tunnels
    for ((i=1; i<=TUNNEL_COUNT; i++)); do
        IFS=':' read -r DOMAIN PORT <<< "${TUNNEL_CONFIGS[$i]}"
        create_tunnel "$DOMAIN" "$PORT" "$i"
    done

    # Save PM2 configuration and setup startup
    pm2 save
    pm2 startup

    print_message "All tunnels setup complete!"
    print_message "To check status: pm2 status"
    print_message "To view logs for a specific tunnel: pm2 logs cloudflare-tunnel-<number>-<domain>"
}

# Run setup
setup_tunnels
