// Circle's encodeForwardHookData (verbatim from the Arbitrum->HyperCore guide) and
// viem hashTypedData for the EIP-3009 ReceiveWithAuthorization on Arbitrum USDC.
// npm i viem ; node gen_cctp.mjs
import { hashTypedData } from 'viem'
function encodeForwardHookData(hyperCoreMintRecipient, hyperCoreDestinationDex = 0) {
  const magicHex = Buffer.from('cctp-forward', 'utf-8').toString('hex').padEnd(48, '0')
  const version = '00000000'
  if (!hyperCoreMintRecipient) return `0x${magicHex}${version}00000000`
  const address = hyperCoreMintRecipient.slice(2).toLowerCase()
  const dex = (hyperCoreDestinationDex >>> 0).toString(16).padStart(8, '0')
  return `0x${magicHex}${version}00000018${address}${dex}`
}
const trading = '0x1185457adb9913df15c0cfac2441986520827ce0'
const auth = hashTypedData({
  domain: { name: 'USD Coin', version: '2', chainId: 42161, verifyingContract: '0xaf88d065e77c8cC2239327C5EDb3A432268e5831' },
  types: { ReceiveWithAuthorization: [ { name: 'from', type: 'address' }, { name: 'to', type: 'address' }, { name: 'value', type: 'uint256' },
    { name: 'validAfter', type: 'uint256' }, { name: 'validBefore', type: 'uint256' }, { name: 'nonce', type: 'bytes32' } ] },
  primaryType: 'ReceiveWithAuthorization',
  message: { from: '0xb98df75e8c9b4de5d3368e95553eb029345b8376', to: '0xA95d9c1F655341597C94393fDdc30cf3c08E4fcE', value: 250000000n,
    validAfter: 0n, validBefore: 1731403600n, nonce: '0x' + '11'.repeat(32) } })
console.log(JSON.stringify({ hookPerps: encodeForwardHookData(trading, 0), hookSpot: encodeForwardHookData(trading, 4294967295), authDigest: auth }, null, 1))
// Output 2026-11-12: authDigest 0x3acfd19ea5f20698827fac62930bab711f94e44d933639666fae39a5448841ee
