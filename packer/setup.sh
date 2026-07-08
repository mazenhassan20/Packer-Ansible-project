#!/bin/bash
set -e

echo "🚀 Updating system packages..."
sudo apt-get update -y
sudo DEBIAN_FRONTEND=noninteractive apt-get upgrade -y

echo "📦 Installing base packages (NGINX, HAProxy, and Utils)..."
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
  nginx haproxy curl wget vim htop net-tools

echo "🛑 Stopping services — Ansible will manage them at config time..."
sudo systemctl stop nginx
sudo systemctl disable nginx
sudo systemctl stop haproxy
sudo systemctl disable haproxy

echo "🧹 Generalizing image for Azure..."
sudo rm -rf /var/lib/waagent/*
sudo find /var/log -name "*.log" -type f -delete 2>/dev/null || true
sudo find /var/log -name "*.gz"  -type f -delete 2>/dev/null || true

sudo apt-get clean
sudo apt-get autoremove -y

echo "✅ Golden Image setup complete!"
sudo waagent -force -deprovision+user
