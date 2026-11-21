// Private-side proof for the trading account: derive the child PRIVATE keys
// non-hardened from the fictional root (priv 0x0123..., chain code c9f3...)
// with @scure/bip32, and sign one Hyperliquid approveAgent digest with each.
// The trading signature must recover to 0x1185…7ce0, the main one to 0xb98d…8376.
import { HDKey } from '@scure/bip32'
import { secp256k1 } from '@noble/curves/secp256k1'
import { keccak256, toHex } from 'viem'
const root = new HDKey({ privateKey: Buffer.from('0123456789012345678901234567890123456789012345678901234567890123', 'hex'),
                         chainCode: Buffer.from('c9f3a1b2d4e5f60718293a4b5c6d7e8f9011223344556677889900aabbccddee', 'hex') })
const digest = 'abd132aaa31fbcc061d12529458d129b7249adcc3cae29b92e9b4c279c2db52a' // approve_agent_valid_until (SDK vectors)
const out = { digest }
for (const [name, path] of [['main', 'm/44/60/0/0/0'], ['trading', 'm/44/60/0/0/1000']]) {
  const child = root.derive(path)
  const sig = secp256k1.sign(digest, child.privateKey, { lowS: true })
  const uncompressed = secp256k1.ProjectivePoint.fromHex(child.publicKey).toRawBytes(false)
  out[name] = { address: '0x' + keccak256(uncompressed.slice(1)).slice(-40), r: '0x' + sig.r.toString(16).padStart(64, '0'),
                s: '0x' + sig.s.toString(16).padStart(64, '0'), v: sig.recovery + 27 }
}
console.log(JSON.stringify(out, null, 1))
