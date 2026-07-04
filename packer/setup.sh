#!/bin/bash
set -e

echo "🚀 Updating system packages..."
sudo apt-get update -y
sudo DEBIAN_FRONTEND=noninteractive apt-get upgrade -y

echo "📦 Installing base packages (NGINX, HAProxy, and Utils)..."
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y nginx haproxy curl wget vim htop net-tools

echo "🛑 Stopping and disabling services (Ansible will manage them later)..."
sudo systemctl stop nginx
sudo systemctl disable nginx
sudo systemctl stop haproxy
sudo systemctl disable haproxy

echo "🧹 Cleaning up and generalizing image for Azure (Sysprep)..."
sudo rm -rf /var/lib/waagent/*
sudo rm -rf /var/log/*
sudo apt-get clean
echo "✅ Golden Image setup complete!"
sudo waagent -force -deprovision+user