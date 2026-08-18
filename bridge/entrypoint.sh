#!/bin/sh
set -e

# Ensure the auth directory exists and is owned by nodeuser
# (Docker named volumes are created as root by default)
mkdir -p /app/.wwebjs_auth
chown -R nodeuser:nodeuser /app/.wwebjs_auth

# Remove stale Chromium profile locks
rm -f /app/.wwebjs_auth/*/SingletonLock \
      /app/.wwebjs_auth/*/SingletonSocket \
      /app/.wwebjs_auth/*/SingletonCookie

exec su -s /bin/sh -c 'npm start' nodeuser
