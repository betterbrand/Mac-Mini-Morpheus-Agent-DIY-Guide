#!/usr/bin/env bash
# Mac Mini Agent Setup Validator - Configuration
# Copy to validate-config.sh and fill in your values.
#
# Usage:
#   cp validate-config.example.sh validate-config.sh
#   nano validate-config.sh   # fill in your values
#   ./validate.sh

# Required: User accounts
AGENT_USER="sam"              # Agent's macOS username
ADMIN_USER="maint-admin"      # Admin's macOS username

# Required: Agent workspace (where persona files live)
WORKSPACE_DIR="$HOME/.openclaw"

# Optional: Proton Bridge (set BRIDGE_ENABLED=true if using Proton Mail)
BRIDGE_ENABLED=true
BRIDGE_CERT_PATH="$HOME/.config/proton-bridge-cert.pem"

# Optional: Signal (set SIGNAL_ENABLED=true if using Signal)
SIGNAL_ENABLED=false

# Optional: Morpheus (set MORPHEUS_ENABLED=true if using decentralized inference)
MORPHEUS_ENABLED=true

# Optional: Local inference via Ollama
# Many setups don't have a second Mac for local models -- that's fine.
# Set to false to skip all Ollama checks entirely.
OLLAMA_ENABLED=false
OLLAMA_HOST="127.0.0.1"       # IP of Ollama machine (or 127.0.0.1 if same machine)
OLLAMA_PORT=11434

# Optional: Safe multi-sig (set SAFE_ENABLED=true if using on-chain guardrails)
SAFE_ENABLED=false

# Log output directory
LOG_DIR="$HOME/.agent-validate"
