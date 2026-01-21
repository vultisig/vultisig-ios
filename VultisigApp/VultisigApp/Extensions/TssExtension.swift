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

    // keep in mind EdDSA signature from TSS is in little endian format , need to convert it to bigendian
    func getSignature() -> Result<Data, Error> {
        guard var rData = Data(hexString: r) else {
            return .failure(HelperError.runtimeError("fail to get r data"))
        }
        rData.reverse()
        guard var sData = Data(hexString: s) else {
            return .failure(HelperError.runtimeError("fail to get s data"))
        }
        sData.reverse()
        var signature = Data()
        signature.append(rData)
        signature.append(sData)
        return .success(signature)
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
