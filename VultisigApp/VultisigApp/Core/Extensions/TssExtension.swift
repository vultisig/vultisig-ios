//
//  TssExtensions.swift
//  VultisigApp
//

import Foundation
import Tss

struct KeysignSignature: Codable {
    let msg: String
    let r: String
    let s: String
    let derSignature: String
    let recoveryID: String
}

extension TssKeysignResponse {
    func getDERSignature() -> Result<Data, Error> {
        guard let derSig = Data(hexString: derSignature) else {
            return .failure(HelperError.runtimeError("fail to get der signature"))
        }

        return .success(derSig)
    }

    func getSignatureWithRecoveryID() -> Result<Data, Error> {
        guard let rData = Data(hexString: r) else {
            return .failure(HelperError.runtimeError("fail to get r data"))
        }

        guard let sData = Data(hexString: s) else {
            return .failure(HelperError.runtimeError("fail to get s data"))
        }

        guard let v = UInt8(recoveryID, radix: 16) else {
            return .failure(HelperError.runtimeError("fail to get recovery data"))
        }

        var signature = Data()
        signature.append(rData)
        signature.append(sData)
        signature.append(Data([v]))
        return .success(signature)
    }

    // EdDSA `r`/`s` from TSS are big-endian scalars; Ed25519 wants them
    // little-endian, so each half is reversed and concatenated into R || S.
    func getSignature() -> Result<Data, Error> {
        guard let rData = Self.eddsaComponentLittleEndian(fromBigEndianHex: r) else {
            return .failure(HelperError.runtimeError("fail to get r data"))
        }
        guard let sData = Self.eddsaComponentLittleEndian(fromBigEndianHex: s) else {
            return .failure(HelperError.runtimeError("fail to get s data"))
        }
        var signature = Data()
        signature.append(rData)
        signature.append(sData)
        return .success(signature)
    }

    /// Normalizes one big-endian EdDSA scalar hex (`r` or `s`) into the 32-byte
    /// little-endian half Ed25519 expects.
    ///
    /// tss-lib emits these via Go's `hex.EncodeToString(bigInt.Bytes())`, and
    /// `big.Int.Bytes()` strips leading zero bytes — so a scalar with a
    /// high-order zero byte (e.g. an S value < 2²⁴⁸, which occurs for a
    /// meaningful fraction of signatures) arrives as fewer than 64 hex chars.
    /// The value must be left-padded to a full 32 bytes *before* reversing;
    /// reversing the short value instead yields a truncated half and an
    /// assembled signature under 64 bytes that fails verification — an
    /// intermittent "signature verification failed" on EdDSA chains (Sui,
    /// Solana, Polkadot, TON…). An odd-length string is left-padded a nibble so
    /// it parses rather than being rejected. Returns nil for non-hex input or an
    /// over-long (> 32-byte) value.
    private static func eddsaComponentLittleEndian(fromBigEndianHex hex: String) -> Data? {
        let stripped = hex.hasPrefix("0x") ? String(hex.dropFirst(2)) : hex
        let evenHex = stripped.count.isMultiple(of: 2) ? stripped : "0" + stripped
        guard let bigEndian = Data(hexString: evenHex), bigEndian.count <= 32 else {
            return nil
        }
        let leftPadded = Data(repeating: 0, count: 32 - bigEndian.count) + bigEndian
        return Data(leftPadded.reversed())
    }

    func getJson() throws -> Data {
        let sig = KeysignSignature(msg: self.msg,
                                   r: self.r,
                                   s: self.s,
                                   derSignature: self.derSignature,
                                   recoveryID: self.recoveryID)
        return try JSONEncoder().encode(sig)
    }

    func fromJson(json: Data) throws -> TssKeysignResponse {
        let resp = try JSONDecoder().decode(KeysignSignature.self, from: json)
        let tssKeysignResp =  TssKeysignResponse()
        tssKeysignResp.msg = resp.msg
        tssKeysignResp.r = resp.r
        tssKeysignResp.s = resp.s
        tssKeysignResp.recoveryID = resp.recoveryID
        tssKeysignResp.derSignature = resp.derSignature
        return tssKeysignResp
    }
}
