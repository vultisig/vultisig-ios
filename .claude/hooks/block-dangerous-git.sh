#!/bin/bash
# Block dangerous operations: git force push, hard reset, mainnet RPCs, secrets, push to main

INPUT=$(cat)
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
CONTENT=$(echo "$INPUT" | jq -r '.tool_input.content // empty')

# --- Dangerous git commands ---
if echo "$CMD" | grep -qE 'git (push.*(--force|--force-with-lease|-f|-F)|reset --hard|clean -[a-z]*f|branch.*(--delete|-D))'; then
  echo "Dangerous git command blocked. Ask the user first." >&2
  exit 2
fi

# --- Direct push to main/master ---
if echo "$CMD" | grep -qE 'git push.*(origin|upstream).*(main|master)(\s|$)'; then
  echo "Direct push to main/master blocked. Use a feature branch and PR." >&2
  exit 2
fi

# --- Mainnet RPC calls ---
MAINNET_RPCS="mainnet\.infura\.io|rpc\.ankr\.com/eth$|api\.etherscan\.io|btc\.getblock\.io|rpc\.mainnet|solana-mainnet|thornode\.ninerealms\.com|mayanode\.mayachain\.info"
COMBINED="$CMD $FILE_PATH $CONTENT"
if echo "$COMBINED" | grep -qiE "$MAINNET_RPCS"; then
  echo "Mainnet RPC endpoint detected. Use testnet for development." >&2
  exit 2
fi

# --- Secret/credential file edits ---
if echo "$FILE_PATH" | grep -qiE '\.(env|pem|p12|keystore|credentials|secret)'; then
  echo "Editing secret/credential files is blocked. Ask the user first." >&2
  exit 2
fi

exit 0
