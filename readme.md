# Cloudflare Tunnel Setup Script

This script is designed to automate the setup of a Cloudflare Tunnel to securely expose your local web service to the internet. It also utilizes PM2 to manage the tunnel process, ensuring it runs continuously.

## Prerequisites

- Ubuntu or a Debian-based system
- Root privileges
- Cloudflare account

## What this Script Does

1. Checks if you are running the script as a root user.
2. Installs `cloudflared` if it’s not already installed.
3. Installs `PM2` and `Node.js` if they are not already installed.
4. Prompts for your domain and the local port your service is running on.
5. Creates a Cloudflare Tunnel with the specified domain.
6. Configures the tunnel and sets up DNS records.
7. Creates a startup script and sets the tunnel to run continually with PM2.

## How to Use

1. Clone the repository or download the script file.
2. Ensure the script is executable: `chmod +x setup-cloudflared.sh`.
3. Run the script with root privileges: `sudo ./setup-cloudflared.sh`.
4. Follow the on-screen prompts to complete setup.

## Output

- Once setup is complete, your tunnel will be running, and you will be provided with a domain URL to access your service.
- Use `pm2 status` to check the status of the tunnel.
- Use `pm2 logs cloudflare-tunnel` to view the tunnel logs.

## Notes

- You will be prompted to log in to Cloudflare via your browser during the setup.
- The script assumes the default local service port is `80`, but you can specify a different one if necessary.

By following these instructions, you should have a secure Cloudflare Tunnel running to expose your local web service on the internet seamlessly.