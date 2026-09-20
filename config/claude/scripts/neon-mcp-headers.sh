#!/bin/bash
# headersHelper for the Neon MCP server (~/.claude.json mcpServers.Neon).
# Reads the bearer token from macOS Keychain instead of storing it in
# plaintext in ~/.claude.json. Outputs the exact JSON headers object
# Claude Code expects. Token stored via:
#   security add-generic-password -a "$USER" -s claude-mcp-neon-authorization -w "<token>" -U
set -euo pipefail

TOKEN=$(security find-generic-password -a "$USER" -s claude-mcp-neon-authorization -w)
printf '{"Authorization": %s}' "$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$TOKEN")"
