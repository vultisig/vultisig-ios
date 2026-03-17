#!/bin/bash
# Block dangerous operations: git force push, hard reset, mainnet RPCs, secrets, push to main, PR merge, env exposure

INPUT=$(cat)
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
CONTENT=$(echo "$INPUT" | jq -r '.tool_input.content // empty')

# --- Dangerous git commands ---
if echo "$CMD" | grep -qE 'git (push.*(--force[^-]|-f |-F )|reset --hard|clean -[a-z]*f|branch.*(--delete|-D))'; then
  echo "Dangerous git command blocked. Ask the user first." >&2
  exit 2
fi

# --- Direct push to main/master ---
if echo "$CMD" | grep -qE 'git push.*(origin|upstream).*(main|master)(\s|$)'; then
  echo "Direct push to main/master blocked. Use a feature branch and PR." >&2
  exit 2
fi

# --- PR merge (agents must not merge) ---
if echo "$CMD" | grep -qiE 'gh pr merge|git merge (main|master)'; then
  echo "PR merge blocked. Let a human merge PRs." >&2
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
if echo "$CMD $FILE_PATH" | grep -qiE '(^|[[:space:]])([^[:space:]]+\.(env|pem|p12|key|pfx|keystore|jks|credentials|secret)|\.env(\.[^[:space:]]+)?)($|[[:space:]])'; then
  echo "Editing secret/credential files is blocked. Ask the user first." >&2
  exit 2
fi

# --- Environment variable exposure ---
if echo "$CMD" | grep -qiE '\b(printenv|export -p)\b|echo.*(TOKEN|API_KEY|SECRET|PASSWORD|CREDENTIAL)|env\s*$|env\s*\|'; then
  echo "Environment variable exposure blocked. Agents must not read or print secrets." >&2
  exit 2
fi

exit 0
