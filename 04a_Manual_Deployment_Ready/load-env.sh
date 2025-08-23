#!/bin/bash
#
# Description:
#   This script loads environment variables from the .env file in the project's
#   root directory. It's designed to be sourced by other scripts to configure
#   the deployment environment.
#
# Usage:
#   source load-env.sh

# Exit immediately if a command exits with a non-zero status
set -e

# Check if the .env file exists
if [ ! -f ".env" ]; then
  echo "Error: .env file not found."
  echo "Please create a .env file with the required environment variables."
  exit 1
fi

# Export the variables from the .env file
export $(grep -v '^#' .env | xargs)

echo "Environment variables loaded successfully."
