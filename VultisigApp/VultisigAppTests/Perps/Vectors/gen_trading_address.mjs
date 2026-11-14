// Independent oracle for the trading-account address: @scure/bip32 non-hardened
// derivation from (root pubkey, chain code), apostrophes stripped as every
// Vultisig client does (vultisig-sdk derivePublicKey), then keccak address.
// npm i @scure/bip32 @noble/curves viem ; node gen_trading_address.mjs
import { HDKey } from '@scure/bip32'
import { secp256k1 } from '@noble/curves/secp256k1'
import { keccak256, toHex } from 'viem'
const priv = '0123456789012345678901234567890123456789012345678901234567890123'
const rootPub = toHex(secp256k1.getPublicKey(priv, true)).slice(2)
const chainCode = 'c9f3a1b2d4e5f60718293a4b5c6d7e8f9011223344556677889900aabbccddee'
const root = new HDKey({ publicKey: Buffer.from(rootPub, 'hex'), chainCode: Buffer.from(chainCode, 'hex') })
const out = { rootPub, chainCode }
for (const [name, path] of [['main', "m/44'/60'/0'/0/0"], ['trading', "m/44'/60'/0'/0/1000"]]) {
  const child = root.derive(path.replaceAll("'", ''))
  const uncompressed = secp256k1.ProjectivePoint.fromHex(child.publicKey).toRawBytes(false)
  out[name] = { path, pubkey: toHex(child.publicKey).slice(2), address: '0x' + keccak256(uncompressed.slice(1)).slice(-40) }
}
console.log(JSON.stringify(out, null, 1))
// Expected output: main 0xb98df75e8c9b4de5d3368e95553eb029345b8376, trading 0x1185457adb9913df15c0cfac2441986520827ce0
