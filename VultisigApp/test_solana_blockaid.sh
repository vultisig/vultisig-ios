#!/bin/bash

# Real Solana transaction data captured from the app
TRANSACTION_BASE64="5uyJucYvhyG4wob5h1yUuV5KkyrjDBaZEvGV865no7JW5dStC8WycBhGo1sMWbAfFdTyGfz7eY5ueFZMYUfqL75GivMXsVtnaMJ9TRPpdXSMi2FvbF7MKucX4FSPoTjYjKevNKWQ5S7kVoWqf8WxbKnotKkQNn4PoGdTeMeDXKANRPV259VAQfZfxFreBjkxain27TJXDzAmm11vkwan57NMYxerqAZ3KMvY2MwW3HHtKmsvc8SqJYDd47UMmtk25AA9Co6QNWJVHAWq7JZ2LA5orM2Lmb47UucMtuAw6EpE2o3biDhEwm5MujrH4GzZ3uupjYbZL98PEB3NkMetaUotf2zWYyYFeia8ddwzeEzj"

ACCOUNT_ADDRESS="CVAPxRchnZnxnyTmzY7K6oVRvDnYSEo26CXnSB5wgL7"

echo "🚀 Testing Solana Transaction with Blockaid API"
echo "============================================="
echo ""

# Test 0: Using the correct structure based on error feedback
echo "Test 0: Using correct structure with account_address and transactions at root level"
echo "----------------------------------------------------------------------------------"
response=$(curl -s -X POST https://api.vultisig.com/blockaid/v0/solana/message/scan \
  -H "Content-Type: application/json" \
  -d '{
    "chain": "solana",
    "account_address": "'"$ACCOUNT_ADDRESS"'",
    "transactions": ["'"$TRANSACTION_BASE64"'"],
    "metadata": {
      "domain": "vultisig.com"
    }
  }' 2>&1)
echo "Response: $response"

echo ""
echo ""

# Test 1: Original endpoint with message/accountAddress structure
echo "Test 1: Using /solana/message/scan endpoint (original structure)"
echo "----------------------------------------------------------------"
response=$(curl -s -X POST https://api.vultisig.com/blockaid/v0/solana/message/scan \
  -H "Content-Type: application/json" \
  -d '{
    "chain": "solana",
    "data": {
      "message": "'"$TRANSACTION_BASE64"'",
      "accountAddress": "'"$ACCOUNT_ADDRESS"'"
    },
    "metadata": {
      "domain": "vultisig.com"
    }
  }' 2>&1)
echo "Response: $response"

echo ""
echo ""

# Test 2: Try with the fields the error message suggested
echo "Test 2: Using fields suggested in error (account_address, transactions)"
echo "------------------------------------------------------------------------"
response=$(curl -s -X POST https://api.vultisig.com/blockaid/v0/solana/message/scan \
  -H "Content-Type: application/json" \
  -d '{
    "chain": "solana",
    "account_address": "'"$ACCOUNT_ADDRESS"'",
    "transactions": ["'"$TRANSACTION_BASE64"'"],
    "metadata": {
      "domain": "vultisig.com"
    }
  }' 2>&1)
echo "Response: $response"

echo ""
echo ""

# Test 3: Try transaction scan endpoint
echo "Test 3: Using /solana/transaction/scan endpoint"
echo "------------------------------------------------"
response=$(curl -s -X POST https://api.vultisig.com/blockaid/v0/solana/transaction/scan \
  -H "Content-Type: application/json" \
  -d '{
    "chain": "solana",
    "data": {
      "transaction": "'"$TRANSACTION_BASE64"'",
      "accountAddress": "'"$ACCOUNT_ADDRESS"'"
    },
    "metadata": {
      "domain": "vultisig.com"
    }
  }' 2>&1)
echo "Response: $response"

echo ""
echo ""

# Test 4: Try with chain-agnostic endpoint
echo "Test 4: Using /chain-agnostic/transaction/scan endpoint"
echo "--------------------------------------------------------"
response=$(curl -s -X POST https://api.vultisig.com/blockaid/v0/chain-agnostic/transaction/scan \
  -H "Content-Type: application/json" \
  -d '{
    "chain": "solana",
    "data": {
      "transaction": "'"$TRANSACTION_BASE64"'",
      "from": "'"$ACCOUNT_ADDRESS"'"
    },
    "metadata": {
      "domain": "vultisig.com"
    }
  }' 2>&1)
echo "Response: $response"

echo ""
echo ""

# Test 5: Try changing chain to "solana-mainnet"
echo "Test 5: Using chain name 'solana-mainnet'"
echo "------------------------------------------"
response=$(curl -s -X POST https://api.vultisig.com/blockaid/v0/solana/message/scan \
  -H "Content-Type: application/json" \
  -d '{
    "chain": "solana-mainnet",
    "data": {
      "message": "'"$TRANSACTION_BASE64"'",
      "accountAddress": "'"$ACCOUNT_ADDRESS"'"
    },
    "metadata": {
      "domain": "vultisig.com"
    }
  }' 2>&1)
echo "Response: $response"

echo ""
echo "============================================="
echo "✅ Testing complete!" 