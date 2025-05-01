#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if script is run as root
if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}Error: This script must be run as root${NC}" >&2
    exit 1
fi

# Function to handle errors
handle_error() {
    echo -e "${RED}Error occurred on line $1${NC}" >&2
    echo -e "${YELLOW}Cleaning up...${NC}"
    rm -rf /tmp/website_temp_* 2>/dev/null
    exit 1
}

# Trap errors
trap 'handle_error $LINENO' ERR

# Function to clean web directory
clean_web_directory() {
    echo -e "${YELLOW}Cleaning /var/www/html...${NC}"
    rm -rf /var/www/html/*
    rm -rf /var/www/mywebsite 2>/dev/null
}

# Function to install packages
install_packages() {
    local packages=("nginx" "git")
    local to_install=()

    for pkg in "${packages[@]}"; do
        if ! command -v "$pkg" &> /dev/null; then
            to_install+=("$pkg")
        fi
    done

    if [ ${#to_install[@]} -gt 0 ]; then
        echo -e "${YELLOW}Updating package lists...${NC}"
        apt-get update
        
        echo -e "${YELLOW}Installing required packages: ${to_install[*]}...${NC}"
        apt-get install -y "${to_install[@]}"
    else
        echo -e "${GREEN}All required packages are already installed${NC}"
    fi
}

# Function to get valid Git URL
get_git_url() {
    while true; do
        read -p "Enter the Git clone URL for your website: " git_url
        
        if [[ $git_url =~ ^https?:// ]]; then
            break
        else
            echo -e "${RED}Invalid URL format. Please provide a valid HTTP/HTTPS URL.${NC}"
        fi
    done
}

# Function to deploy website
deploy_website() {
    local git_url=$1
    
    # Create temporary directory
    temp_dir=$(mktemp -d -t website_temp_XXXXX)
    
    # Clone repository
    echo -e "${YELLOW}Cloning repository...${NC}"
    git clone "$git_url" "$temp_dir"
    
    # Check if clone was successful
    if [ $? -ne 0 ]; then
        echo -e "${RED}Failed to clone repository. Please check the URL and try again.${NC}"
        exit 1
    fi
    
    # Move website files
    echo -e "${YELLOW}Setting up website...${NC}"
    mv "$temp_dir" /var/www/mywebsite
    chown -R www-data:www-data /var/www/mywebsite
    chmod -R 755 /var/www/mywebsite
    
    # Copy to web root
    cp -a /var/www/mywebsite/. /var/www/html/
}

# Function to configure Nginx
configure_nginx() {
    echo -e "${YELLOW}Configuring Nginx...${NC}"
    
    # Remove default config if exists
    rm -f /etc/nginx/sites-enabled/default 2>/dev/null
    rm -f /etc/nginx/sites-available/default 2>/dev/null
    
    # Create new config
    cat > /etc/nginx/sites-available/mywebsite << 'EOF'
server {
    listen 80 default_server;
    listen [::]:80 default_server;

    root /var/www/html;
    index index.html index.htm index.nginx-debian.html;

    server_name _;

    location / {
        try_files $uri $uri/ =404;
    }
}
EOF

    # Enable configuration
    ln -sf /etc/nginx/sites-available/mywebsite /etc/nginx/sites-enabled/
    
    # Test and restart Nginx
    echo -e "${YELLOW}Testing Nginx configuration...${NC}"
    nginx -t
    
    echo -e "${YELLOW}Restarting Nginx...${NC}"
    systemctl restart nginx
}

# Main execution
main() {
    # Clean existing website
    clean_web_directory
    
    # Install required packages
    install_packages
    
    # Get Git URL from user
    get_git_url
    
    # Deploy website
    deploy_website "$git_url"
    
    # Configure Nginx
    configure_nginx
    
    # Completion message
    ip_address=$(hostname -I | awk '{print $1}')
    echo -e "\n${GREEN}Website deployment successful!${NC}"
    echo -e "Access your website at: http://${ip_address}"
    echo -e "Website files are located at: /var/www/mywebsite"
    echo -e "Web root is at: /var/www/html"
}

# Run main function
main

exit 0
