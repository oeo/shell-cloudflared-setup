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

# Main setup function
setup_tunnel() {
    print_message "Starting Cloudflare Tunnel setup..."

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

    # Get domain from user
    read -p "Enter your domain (e.g., example.com): " DOMAIN

    # Get local service port
    read -p "Enter the local port your service is running on (default: 80): " PORT
    PORT=${PORT:-80}

    # Login to cloudflared (if not already logged in)
    if [ ! -f ~/.cloudflared/cert.pem ]; then
        print_message "Please login to Cloudflare in your browser..."
        cloudflared tunnel login
    fi

    # Create tunnel
    print_message "Creating tunnel..."
    TUNNEL_ID=$(cloudflared tunnel create "tunnel-$DOMAIN" | awk '/Created tunnel/ {print $3}')
    print_message "Tunnel ID: $TUNNEL_ID"

    # Create config file
    print_message "Creating config file..."
    cat > ~/.cloudflared/config.yml << EOL
tunnel: ${TUNNEL_ID}
credentials-file: /root/.cloudflared/${TUNNEL_ID}.json

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
    cat > /root/cloudflared-tunnel.sh << EOL
#!/bin/bash
cloudflared tunnel --config /root/.cloudflared/config.yml run ${TUNNEL_ID}
EOL

    chmod +x /root/cloudflared-tunnel.sh

    # Start with PM2
    print_message "Starting tunnel with PM2..."
    pm2 start /root/cloudflared-tunnel.sh --name "cloudflare-tunnel" --interpreter bash
    pm2 save
    pm2 startup

    print_message "Setup complete!"
    print_message "Your tunnel should now be running and accessible at: ${DOMAIN}"
    print_message "To check status: pm2 status"
    print_message "To view logs: pm2 logs cloudflare-tunnel"
}

# Run setup
setup_tunnel
