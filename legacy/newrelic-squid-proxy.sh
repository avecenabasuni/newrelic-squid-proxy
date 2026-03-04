#!/bin/bash

# This script installs and configures Squid Proxy on different Linux distributions
# Author: Avecena Basuni
# Date: 08-01-2025

# Display script information to terminal
# Display script metadata
echo -e "\033[1;33m=====================================================\033[0m"
echo -e "\033[1;32mSquid Proxy Installation and Configuration Script\033[0m"
echo -e "\033[1;34mCreated by: Avecena Basuni\033[0m"
echo -e "\033[1;34mDate: January 8, 2025\033[0m"
echo -e "\033[1;34mLicense: MIT License\033[0m"
echo -e "\033[1;33m=====================================================\033[0m"

set -e

# Define variables
SQUID_CONF_URL="https://raw.githubusercontent.com/avecenabasuni/newrelic-squid-proxy/refs/heads/main/squid.conf"  # Replace with your actual squid.conf URL
SQUID_CONF_PATH="/etc/squid/squid.conf"
PASSWORDS_FILE="/etc/squid/passwords"

# ANSI color codes
GREEN="\e[32m"
YELLOW="\e[33m"
RED="\e[31m"
RESET="\e[0m"

# Function to display a loading animation with faster response
loading_animation() {
    local pid=$1
    local delay=0.05  # Reduced delay from 0.1 to 0.05 for faster animation
    local spinner=("|" "/" "-" "\\")
    while [ -d "/proc/$pid" ]; do
        for symbol in "${spinner[@]}"; do
            printf "\r%s" "$symbol"
            sleep $delay
        done
    done
    printf "\r"  # Clear the spinner after completion
}

# Run a command in the background with loading animation.
# Captures exit code correctly (fixes race condition with $?).
run_with_spinner() {
    "$@" &>/dev/null &
    local bg_pid=$!
    loading_animation "$bg_pid"
    wait "$bg_pid"
    return $?
}

# Detect OS distribution
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$NAME
        VERSION=$VERSION_ID
    elif [ -f /etc/lsb-release ]; then
        . /etc/lsb-release
        OS=$DISTRIB_ID
        VERSION=$DISTRIB_RELEASE
    elif [ -f /etc/debian_version ]; then
        OS="Debian"
        VERSION=$(cat /etc/debian_version)
    elif [ -f /etc/redhat-release ]; then
        OS="RedHat/CentOS"
        VERSION=$(cat /etc/redhat-release)
    else
        echo -e "${RED}Unsupported OS. Exiting...${RESET}"
        exit 1
    fi

    echo -e "${GREEN}Detected OS: $OS $VERSION${RESET}"
}

# Call the OS detection function first
detect_os

# Prompt user for authentication setup (after OS detection so user knows OS is supported)
read -p "Do you want to enable authentication? (y/n): " ENABLE_AUTH

# Function to install packages based on the OS
install_packages() {
    if [[ "$OS" == "Ubuntu" || "$OS" == "Debian" ]]; then
        echo "Updating system and installing Squid (Ubuntu/Debian)..."
        run_with_spinner sudo apt update -y
        run_with_spinner sudo apt install -y squid apache2-utils
    elif [[ "$OS" == "RedHat/CentOS" ]]; then
        echo "Updating system and installing Squid (RedHat/CentOS)..."
        run_with_spinner sudo yum update -y
        run_with_spinner sudo yum install -y squid httpd-tools
    elif [[ "$OS" == "SLES" ]]; then
        echo "Updating system and installing Squid (SLES)..."
        run_with_spinner sudo zypper refresh
        run_with_spinner sudo zypper install -y squid apache2-utils
    else
        echo -e "${RED}Unsupported OS. Exiting...${RESET}"
        exit 1
    fi
}

# Update system and install Squid
install_packages

# Backup existing Squid configuration
if [ -f "$SQUID_CONF_PATH" ]; then
    echo "Backing up existing Squid configuration..."
    sudo cp "$SQUID_CONF_PATH" "$SQUID_CONF_PATH.bak"
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Backup created at $SQUID_CONF_PATH.bak${RESET}"
    else
        echo -e "${RED}Failed to create backup.${RESET}"
        exit 1
    fi
fi

# Download and apply Squid configuration
echo "Downloading new Squid configuration..."
if run_with_spinner sudo curl -o "$SQUID_CONF_PATH" "$SQUID_CONF_URL"; then
    echo -e "${GREEN}Downloaded new squid.conf from $SQUID_CONF_URL${RESET}"
else
    echo -e "${RED}Failed to download new squid.conf.${RESET}"
    exit 1
fi

# Handle authentication setup if enabled
if [ "$ENABLE_AUTH" == "y" ]; then
    echo "Setting up authentication..."
    if ! [ -f "$PASSWORDS_FILE" ]; then
        sudo touch "$PASSWORDS_FILE"
        sudo chmod 600 "$PASSWORDS_FILE"
        echo "Password file created at $PASSWORDS_FILE."
    fi
    read -p "Enter username for Squid Proxy: " USERNAME
    sudo htpasswd -c "$PASSWORDS_FILE" "$USERNAME"
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Authentication configured successfully.${RESET}"
    else
        echo -e "${RED}Failed to configure authentication.${RESET}"
        exit 1
    fi
else
    echo -e "${YELLOW}Authentication setup skipped.${RESET}"
fi

# Restart Squid service
echo "Restarting Squid service..."
if run_with_spinner sudo systemctl restart squid; then
    echo -e "${GREEN}Squid service restarted successfully.${RESET}"
else
    echo -e "${RED}Failed to restart Squid service.${RESET}"
    exit 1
fi

if run_with_spinner sudo systemctl enable squid; then
    echo -e "${GREEN}Squid enabled to start at boot.${RESET}"
else
    echo -e "${RED}Failed to enable Squid at boot.${RESET}"
fi

# Display Squid status
sudo systemctl status squid --no-pager

# Final message
echo -e "\033[1;33m=====================================================\033[0m"
if [ "$ENABLE_AUTH" == "y" ]; then
    echo -e "${GREEN}Squid Proxy installed and configured successfully!${RESET} Authentication is enabled."
else
    echo -e "${GREEN}Squid Proxy installed and configured successfully!${RESET} ${YELLOW}Authentication is not enabled.${RESET}"
fi
echo -e "\033[1;33m=====================================================\033[0m"
