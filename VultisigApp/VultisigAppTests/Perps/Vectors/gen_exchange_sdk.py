# /exchange vectors from the official hyperliquid-python-sdk (pip, py3.12 venv).
# Builds every action exactly as hyperliquid/exchange.py does, signs with the SDK's public
# test key, and prints the body `_post_action` would POST. Nothing is sent anywhere.
import copy, json
import eth_account
from eth_account.messages import encode_typed_data
from eth_utils import keccak
from hyperliquid.utils import signing as S

KEY = "0x0123456789012345678901234567890123456789012345678901234567890123"
W = eth_account.Account.from_key(KEY)
NONCE = 1731400000000
VAULT = "0x1234567890abcdef1234567890abcdef12345678"
AGENT = "0x5e9ee1089755c3435139848e47e6635505d5a13a"
BUILDER = "0xabcdefabcdefabcdefabcdefabcdefabcdefabcd"

def digest_of(data):
    m = encode_typed_data(full_message=data)
    return keccak(b"\x19" + m.version + m.header + m.body).hex()

def body(action, sig, nonce, vault=None, expires=None):
    return {"action": action, "nonce": nonce, "signature": sig,
            "vaultAddress": vault if action["type"] not in ["usdClassTransfer", "sendAsset"] else None,
            "expiresAfter": expires}

out = {"l1": [], "userSigned": []}

def l1(name, action, nonce=NONCE, vault=None, expires=None, mainnet=True):
    h = S.action_hash(action, vault, nonce, expires)
    data = S.l1_payload(S.construct_phantom_agent(h, mainnet))
    sig = S.sign_l1_action(W, action, vault, nonce, expires, mainnet)
    packed = __import__("msgpack").packb(action)
    out["l1"].append({"name": name, "msgpack": packed.hex(), "connectionId": h.hex(), "digest": digest_of(data),
                      "signature": sig, "body": body(action, sig, nonce, vault, expires)})

def wires(reqs, asset, builder=None, grouping="na"):
    return S.order_wires_to_order_action([S.order_request_to_order_wire(r, asset) for r in reqs], builder, grouping)

# order: market long = IOC at mid*(1+slippage), with builder fee 5bp (f=50)
l1("order_market_ioc_builder", wires([{"coin": "BTC", "is_buy": True, "sz": 0.00149, "limit_px": 67638.0, "order_type": {"limit": {"tif": "Ioc"}}, "reduce_only": False}], 0, {"b": BUILDER, "f": 50}))
# order: limit long + SL trigger (normalTpsl), expiresAfter, mainnet
l1("order_limit_sl_expires", wires([
    {"coin": "ETH", "is_buy": True, "sz": 0.24, "limit_px": 2400.0, "order_type": {"limit": {"tif": "Gtc"}}, "reduce_only": False},
    {"coin": "ETH", "is_buy": False, "sz": 0.24, "limit_px": 2200.0, "order_type": {"trigger": {"triggerPx": 2200.0, "isMarket": True, "tpsl": "sl"}}, "reduce_only": True},
], 1, None, "normalTpsl"), expires=NONCE + 60000)
# order on a vault/subaccount address
l1("order_vault_address", wires([{"coin": "SOL", "is_buy": False, "sz": 5.81, "limit_px": 185.5, "order_type": {"limit": {"tif": "Ioc"}}, "reduce_only": True}], 5), vault=VAULT)
l1("cancel", {"type": "cancel", "cancels": [{"a": 0, "o": 123456789}]})
l1("cancel_expires", {"type": "cancel", "cancels": [{"a": 1, "o": 42}, {"a": 5, "o": 77}]}, expires=NONCE + 30000)
l1("update_leverage_isolated", {"type": "updateLeverage", "asset": 1, "isCross": False, "leverage": 3})
l1("update_isolated_margin_add", {"type": "updateIsolatedMargin", "asset": 5, "isBuy": True, "ntli": S.float_to_usd_int(100.0)})
l1("update_isolated_margin_remove", {"type": "updateIsolatedMargin", "asset": 5, "isBuy": True, "ntli": S.float_to_usd_int(-25.5)})

def user(name, action, types, primary, fn, mainnet=True, drop_name=False):
    a = copy.deepcopy(action)
    sig = fn(W, a, mainnet)  # mutates a: adds signatureChainId + hyperliquidChain
    data = S.user_signed_payload(primary, types, a)
    d = digest_of(data)
    posted = copy.deepcopy(a)
    if drop_name: del posted["agentName"]
    out["userSigned"].append({"name": name, "digest": d, "signature": sig, "body": body(posted, sig, a.get("nonce", a.get("time")))})

AGENT_TYPES = [{"name": "hyperliquidChain", "type": "string"}, {"name": "agentAddress", "type": "address"}, {"name": "agentName", "type": "string"}, {"name": "nonce", "type": "uint64"}]
BF_TYPES = [{"name": "hyperliquidChain", "type": "string"}, {"name": "maxFeeRate", "type": "string"}, {"name": "builder", "type": "address"}, {"name": "nonce", "type": "uint64"}]
user("approve_agent_valid_until", {"type": "approveAgent", "agentAddress": AGENT, "agentName": f"vultisig valid_until {NONCE + 7*86400000}", "nonce": NONCE}, AGENT_TYPES, "HyperliquidTransaction:ApproveAgent", S.sign_agent)
user("approve_agent_unnamed", {"type": "approveAgent", "agentAddress": AGENT, "agentName": "", "nonce": NONCE}, AGENT_TYPES, "HyperliquidTransaction:ApproveAgent", S.sign_agent, drop_name=True)
user("approve_builder_fee", {"maxFeeRate": "0.05%", "builder": BUILDER, "nonce": NONCE, "type": "approveBuilderFee"}, BF_TYPES, "HyperliquidTransaction:ApproveBuilderFee", S.sign_approve_builder_fee)
user("withdraw3", {"destination": "0x9d7c000000000000000000000000000000003003", "amount": "499", "time": NONCE, "type": "withdraw3"}, S.WITHDRAW_SIGN_TYPES, "HyperliquidTransaction:Withdraw", S.sign_withdraw_from_bridge_action)
user("withdraw3_testnet_sdk_test", {"destination": "0x5e9ee1089755c3435139848e47e6635505d5a13a", "amount": "1", "time": 1687816341423, "type": "withdraw3"}, S.WITHDRAW_SIGN_TYPES, "HyperliquidTransaction:Withdraw", S.sign_withdraw_from_bridge_action, mainnet=False)

# The two contract discrepancies, as the SDK sees them.
def h(action): return S.action_hash(action, None, 2, None).hex()
contract = {"type": "order", "orders": [{"a": 0, "b": True, "p": "30000.0", "r": False, "s": "0.001", "t": {"limit": {"tif": "Gtc"}}}], "grouping": "na"}
canon = S.order_wires_to_order_action([S.order_request_to_order_wire({"coin": "BTC", "is_buy": True, "sz": 0.001, "limit_px": 30000.0, "order_type": {"limit": {"tif": "Gtc"}}, "reduce_only": False}, 0)])
swapped_only = json.loads(json.dumps(contract)); swapped_only["orders"][0] = {"a": 0, "b": True, "p": "30000.0", "s": "0.001", "r": False, "t": {"limit": {"tif": "Gtc"}}}
out["discrepancies"] = {
    "sdkCanonicalOrderWire": canon, "sdkFloatToWire30000": S.float_to_wire(30000.0),
    "connectionId_contractDoc_abprst_30000.0": h(contract),
    "connectionId_keyOrderFixed_abpsrt_30000.0": h(swapped_only),
    "connectionId_sdkCanonical_abpsrt_30000": h(canon),
}
print(json.dumps(out, indent=1))
