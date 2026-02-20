//
//  DilithiumKeysign.swift
//  VultisigApp
//
//  Created by Claude on 12/2/2026.
//

import Foundation
import vscore
import OSLog
import Mediator
import Tss

struct DilithiumKeysignResponse: Codable {
    let msg: String              // Message hash that was signed (hex)
    let signature: String        // Raw MLDSA signature (hex, ~2560 bytes)

    func toJson() throws -> Data {
        return try JSONEncoder().encode(self)
    }
}

final class DilithiumKeysign {
    let keysignCommittee: [String]
    let mediatorURL: String
    let sessionID: String
    let messsageToSign: [String]
    let vault: Vault
    let encryptionKeyHex: String
    let isInitiateDevice: Bool
    let localPartyID: String
    let chainPath: String
    let publicKey: String
    var messenger: DKLSMessenger?
    var cache = NSCache<NSString, AnyObject>()
    var signatures = [String: DilithiumKeysignResponse]()
    let MLDSA_LIB_OK: vscore.mldsa_lib_error = .init(0)

    init(keysignCommittee: [String],
         mediatorURL: String,
         sessionID: String,
         messsageToSign: [String],
         vault: Vault,
         encryptionKeyHex: String,
         chainPath: String,
         isInitiateDevice: Bool,
         publicKey: String) {
        self.keysignCommittee = keysignCommittee
        self.mediatorURL = mediatorURL
        self.sessionID = sessionID
        self.messsageToSign = messsageToSign
        self.vault = vault
        self.encryptionKeyHex = encryptionKeyHex
        self.chainPath = chainPath
        self.isInitiateDevice = isInitiateDevice
        self.localPartyID = vault.localPartyID
        self.publicKey = publicKey
    }

    func getSignatures() -> [String: DilithiumKeysignResponse] {
        return self.signatures
    }

    func getKeyshareString() -> String? {
        for ks in vault.keyshares {
            if ks.pubkey == self.publicKey {
                return ks.keyshare
            }
        }
        return nil
    }

    func getKeyshareBytes() throws -> [UInt8] {
        guard let localKeyshare = getKeyshareString() else {
            throw HelperError.runtimeError("fail to get local keyshare")
        }
        let keyshareData = Data(base64Encoded: localKeyshare)
        guard let keyshareData else {
            throw HelperError.runtimeError("fail to decode keyshare")
        }
        return [UInt8](keyshareData)
    }

    func getDilithiumKeyshareID() throws -> [UInt8] {
        var buf = vscore.tss_buffer()
        defer {
            vscore.tss_buffer_free(&buf)
        }
        let keyShareBytes = try getKeyshareBytes()
        var keyshareSlice = keyShareBytes.to_mldsa_goslice()
        var h = vscore.Handle()
        let result = mldsa_keyshare_from_bytes(&keyshareSlice, &h)
        if result != MLDSA_LIB_OK {
            throw HelperError.runtimeError("fail to create keyshare handle from bytes, \(result)")
        }

        defer {
            let freeResult = mldsa_keyshare_free(&h)
            if freeResult != MLDSA_LIB_OK {
                print("fail to free keyshare \(freeResult)")
            }
        }
        let keyIDResult = mldsa_keyshare_key_id(h, &buf)
        if keyIDResult != MLDSA_LIB_OK {
            throw HelperError.runtimeError("fail to get key id from keyshare: \(keyIDResult)")
        }
        return Array(UnsafeBufferPointer(start: buf.ptr, count: Int(buf.len)))
    }

    func getDilithiumKeysignSetupMessage(message: String) throws -> [UInt8] {
        var buf = vscore.tss_buffer()
        defer {
            vscore.tss_buffer_free(&buf)
        }
        let keyIdArr = try getDilithiumKeyshareID()
        var keyIdSlice = keyIdArr.to_mldsa_goslice()

        // create setup message and upload it to relay server
        let byteArray = DKLSHelper.arrayToBytes(parties: self.keysignCommittee)
        var ids = byteArray.to_mldsa_goslice()

        let decodedMsgData = Data(hexString: message)
        guard let decodedMsgData else {
            throw HelperError.runtimeError("fail to hex decoded the message to sign")
        }
        let msgArr = [UInt8](decodedMsgData)
        var msgSlice = msgArr.to_mldsa_goslice()
        let err: vscore.mldsa_lib_error
        // For multi-chain vaults using Dilithium keys, only unhardened HD derivation is supported.
        // For vaults imported from a seed phrase/private key, only a single chain is supported (no derivation path).
        if !self.chainPath.isEmpty {
            guard let chainPathData = self.chainPath.replacingOccurrences(of: "'", with: "").data(using: .utf8) else {
                throw HelperError.runtimeError("fail to encode chainPath to UTF-8")
            }
            let chainPathArr = [UInt8](chainPathData)
            var chainPathSlice = chainPathArr.to_mldsa_goslice()
            err = mldsa_sign_setupmsg_new(vscore.MlDsa44, &keyIdSlice, &chainPathSlice, &msgSlice, &ids, &buf)

        } else {
            err = mldsa_sign_setupmsg_new(vscore.MlDsa44, &keyIdSlice, nil, &msgSlice, &ids, &buf)
        }
        if err != MLDSA_LIB_OK {
            throw HelperError.runtimeError("fail to setup keysign message, mldsa error:\(err)")
        }
        return Array(UnsafeBufferPointer(start: buf.ptr, count: Int(buf.len)))
    }

    func getOutboundMessageReceiver(handle: vscore.Handle, message: vscore.go_slice, idx: UInt32) -> [UInt8] {
        var buf_receiver = tss_buffer()
        defer {
            tss_buffer_free(&buf_receiver)
        }
        var mutableMessage = message
        let receiverResult = mldsa_sign_session_message_receiver(handle, &mutableMessage, idx, &buf_receiver)
        if receiverResult != MLDSA_LIB_OK {
            print("fail to get receiver message,error: \(receiverResult)")
            return []
        }
        return Array(UnsafeBufferPointer(start: buf_receiver.ptr, count: Int(buf_receiver.len)))
    }

    func GetDilithiumOutboundMessage(handle: vscore.Handle) -> (vscore.mldsa_lib_error, [UInt8]) {
        var buf = vscore.tss_buffer()
        defer {
            vscore.tss_buffer_free(&buf)
        }
        let result = mldsa_sign_session_output_message(handle, &buf)
        if result != MLDSA_LIB_OK {
            print("fail to get outbound message: \(result)")
            return (result, [])
        }
        return (result, Array(UnsafeBufferPointer(start: buf.ptr, count: Int(buf.len))))
    }

    func processDilithiumOutboundMessage(handle: vscore.Handle) async throws {
        repeat {
            let (result, outboundMessage) = GetDilithiumOutboundMessage(handle: handle)
            if result != MLDSA_LIB_OK {
                print("fail to get outbound message,\(result)")
            }
            if outboundMessage.isEmpty {
                return
            }
            let message = outboundMessage.to_mldsa_goslice()
            let encodedOutboundMessage = outboundMessage.toBase64()
            for i in 0..<self.keysignCommittee.count {
                let receiverArray = getOutboundMessageReceiver(handle: handle,
                                                               message: message,
                                                               idx: UInt32(i))

                if receiverArray.isEmpty {
                    break
                }
                let receiverString = String(bytes: receiverArray, encoding: .utf8)!
                print("sending message from \(self.localPartyID) to: \(receiverString), content length:\(encodedOutboundMessage.count)")
                try await self.messenger?.send(self.localPartyID,
                                         to: receiverString,
                                         body: encodedOutboundMessage)
            }
        } while 1 > 0

    }

    func pullInboundMessages(handle: vscore.Handle, messageID: String) async throws -> Bool {
        let urlString = "\(mediatorURL)/message/\(sessionID)/\(self.localPartyID)"
        print("start pulling inbound messages from:\(urlString)")
        guard let url = URL(string: urlString) else {
            throw HelperError.runtimeError("invalid url string: \(urlString)")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(messageID, forHTTPHeaderField: "message_id")
        var isFinished = false
        let start = DispatchTime.now()
        repeat {
            let (data, resp) = try await URLSession.shared.data(for: request)
            guard let httpResp = resp as? HTTPURLResponse else {
                throw HelperError.runtimeError("fail to convert resp to http url response")
            }
            switch httpResp.statusCode {
            case 200 ... 299:
                if !data.isEmpty {
                    isFinished = try await processInboundMessage(handle: handle,
                                                                 data: data,
                                                                 messageID: messageID)
                    if isFinished {
                        return true
                    }
                } else {
                    try await Task.sleep(for: .milliseconds(100))
                }
                // success
            default:
                throw HelperError.runtimeError("invalid status code: \(httpResp.statusCode)")
            }
            let currentTime = DispatchTime.now()
            let elapsedTime = currentTime.uptimeNanoseconds - start.uptimeNanoseconds
            let elapsedTimeInSeconds = Double(elapsedTime) / 1_000_000_000
            // timeout for 60 seconds
            if elapsedTimeInSeconds > 60 {
                throw HelperError.runtimeError("timeout: failed to keysign within 60 seconds")
            }
        } while !isFinished

        return false
    }

    func processInboundMessage(handle: vscore.Handle, data: Data, messageID: String) async throws -> Bool {
        let decoder = JSONDecoder()
        let msgs = try decoder.decode([Message].self, from: data)
        let sortedMsgs = msgs.sorted(by: { $0.sequence_no < $1.sequence_no })
        for msg in sortedMsgs {
            let key = "\(self.sessionID)-\(self.localPartyID)-\(messageID)-\(msg.hash)" as NSString
            if self.cache.object(forKey: key) != nil {
                print("message with key:\(key) has been applied before")
                continue
            }
            print("Got message from: \(msg.from), to: \(msg.to), key:\(key)")
            guard let decryptedBody = msg.body.aesDecryptGCM(key: self.encryptionKeyHex) else {
                throw HelperError.runtimeError("fail to decrypted message body")
            }

            // need to have a variable to save the array , otherwise mldsa function can't access the memory
            guard let decodedMsg = Data(base64Encoded: decryptedBody) else {
                throw HelperError.runtimeError("fail to decrypted inbound message")
            }

            let descryptedBodyArr = [UInt8](decodedMsg)

            var decryptedBodySlice = descryptedBodyArr.to_mldsa_goslice()
            var isFinished: Int32 = 0
            let result = mldsa_sign_session_input_message(handle, &decryptedBodySlice, &isFinished)
            if result != MLDSA_LIB_OK {
                throw HelperError.runtimeError("fail to apply message to mldsa,\(result)")
            }

            self.cache.setObject(NSObject(), forKey: key)
            try await deleteMessageFromServer(hash: msg.hash, messageID: messageID)
            try await self.processDilithiumOutboundMessage(handle: handle)
            // local party keysign finished
            if isFinished != 0 {
                return true
            }
        }
        return false
    }

    func deleteMessageFromServer(hash: String, messageID: String) async throws {
        let urlString = "\(mediatorURL)/message/\(self.sessionID)/\(self.localPartyID)/\(hash)"
        guard let url = URL(string: urlString) else {
            throw HelperError.runtimeError("invalid url string: \(urlString)")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.addValue(messageID, forHTTPHeaderField: "message_id")
        let (_, _) = try await URLSession.shared.data(for: request)
    }

    func DilithiumKeysignOneMessageWithRetry(attempt: UInt8, messageToSign: String) async throws {
        self.cache.removeAllObjects()
        let msgHash = Utils.getMessageBodyHash(msg: messageToSign)
        let localMessenger = DKLSMessenger(mediatorUrl: self.mediatorURL,
                                           sessionID: self.sessionID,
                                           messageID: msgHash,
                                           encryptionKeyHex: self.encryptionKeyHex)
        self.messenger = localMessenger
        do {
            var keysignSetupMsg: [UInt8]
            if self.isInitiateDevice && attempt == 0 {
                keysignSetupMsg = try getDilithiumKeysignSetupMessage(message: messageToSign)
                try await localMessenger.uploadSetupMessage(message: keysignSetupMsg.toBase64(), nil)
            } else {
                // download the setup message from relay server
                let strKeysignSetupMsg = try await localMessenger.downloadSetupMessageWithRetry(nil)
                keysignSetupMsg = Array(base64: strKeysignSetupMsg)
            }

            // Note: MLDSA library does not have mldsa_decode_message function
            // Trusting the setup message from initiator (as per plan)
            let finalSetupMsgArr = keysignSetupMsg
            var decodedSetupMsg = finalSetupMsgArr.to_mldsa_goslice()

            var handler = vscore.Handle()

            let localPartyIDArr = self.localPartyID.toArray()
            var localPartySlice = localPartyIDArr.to_mldsa_goslice()

            let keyShareBytes = try getKeyshareBytes()
            var keyshareSlice = keyShareBytes.to_mldsa_goslice()
            var keyshareHandle = vscore.Handle()
            let result = mldsa_keyshare_from_bytes(&keyshareSlice, &keyshareHandle)
            if result != MLDSA_LIB_OK {
                throw HelperError.runtimeError("fail to create keyshare handle from bytes, \(result)")
            }

            defer {
                mldsa_keyshare_free(&keyshareHandle)
            }
            let sessionResult = mldsa_sign_session_from_setup(vscore.MlDsa44,&decodedSetupMsg,
                                                             &localPartySlice,
                                                             keyshareHandle,
                                                             &handler)
            if sessionResult != MLDSA_LIB_OK {
                throw HelperError.runtimeError("fail to create sign session from setup message,error:\(sessionResult)")
            }
            // free the handler
            defer {
                mldsa_sign_session_free(handler)
            }
            let h = handler

            try await processDilithiumOutboundMessage(handle: h)
            let isFinished = try await pullInboundMessages(handle: h, messageID: msgHash)
            if isFinished {
                try await processDilithiumOutboundMessage(handle: h)
                let sig = try dilithiumSignSessionFinish(handle: h)
                let resp = DilithiumKeysignResponse(
                    msg: messageToSign,
                    signature: sig.toHexString()
                )
                let keySignVerify = KeysignVerify(serverAddr: self.mediatorURL,
                                                  sessionID: self.sessionID)
                // Mark keysign complete with generic signature
                await markDilithiumKeysignComplete(keySignVerify: keySignVerify, message: msgHash, sig: resp)
                self.signatures[messageToSign] = resp
                try await Task.sleep(for: .milliseconds(500))
            }
        } catch {
            print("Failed to sign message (\(messageToSign)), error: \(error.localizedDescription)")
            if attempt < 3 {
                try await DilithiumKeysignOneMessageWithRetry(attempt: attempt+1, messageToSign: messageToSign)
            }
        }
    }

    func dilithiumSignSessionFinish(handle: vscore.Handle) throws -> [UInt8] {
        var buf = vscore.tss_buffer()
        defer {
            vscore.tss_buffer_free(&buf)
        }
        let result = mldsa_sign_session_finish(handle, &buf)
        if result != MLDSA_LIB_OK {
            throw HelperError.runtimeError("fail to get keysign signature \(result)")
        }
        return Array(UnsafeBufferPointer(start: buf.ptr, count: Int(buf.len)))
    }

    func markDilithiumKeysignComplete(keySignVerify: KeysignVerify, message: String, sig: DilithiumKeysignResponse) async {
        do {
            let jsonData = try sig.toJson()
            let header = ["message_id": message]
            _ = try await Utils.asyncPostRequest(urlString: keySignVerify.urlString, headers: header, body: jsonData)
        } catch {
            print("Failed to send request to mediator, error:\(error)")
        }
    }

    func DilithiumKeysignWithRetry() async throws {
        for msg in self.messsageToSign {
            try await DilithiumKeysignOneMessageWithRetry(attempt: 0, messageToSign: msg)
        }
    }

}
