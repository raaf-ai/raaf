#!/bin/bash
# terragon-setup.sh - Custom setup script for your Terragon environment
# This script runs when your sandbox environment starts

# Example: Install dependencies
# npm install

# Example: Run database migrations
# npm run db:migrate

# Example: Set up environment
# cp .env.example .env
apt update
apt install -y ruby-full build-essential
gem install bundler

echo "Setup complete!"
