//
//  DilithiumKeygen.swift
//  VultisigApp
//
//  Created by Johnny Luo on 10/2/2026.
//

import Foundation
import dilithium
import OSLog
import Mediator

struct DilithiumKeyshare {
    let PubKey: String
    let Keyshare: String
    let keyId: String
}

final class DilithiumKeygen {
    let vault: Vault
    let tssType: TssType
    let keygenCommittee: [String]
    let vaultOldCommittee: [String]
    let mediatorURL: String
    let sessionID: String
    let encryptionKeyHex: String
    let isInitiateDevice: Bool
    var messenger: DKLSMessenger
    let localPartyID: String
    var cache = NSCache<NSString, AnyObject>()
    var setupMessage: [UInt8] = []
    var keyshare: DilithiumKeyshare?
    let MLDSA_LIB_OK: dilithium.mldsa_lib_error = .init(0)

    init(vault: Vault,
         tssType: TssType,
         keygenCommittee: [String],
         vaultOldCommittee: [String],
         mediatorURL: String,
         sessionID: String,
         encryptionKeyHex: String,
         isInitiateDevice: Bool,
         setupMessage: [UInt8]
    ) {
        self.vault = vault
        self.tssType = tssType
        self.keygenCommittee = keygenCommittee
        self.vaultOldCommittee = vaultOldCommittee
        self.mediatorURL = mediatorURL
        self.sessionID = sessionID
        self.encryptionKeyHex = encryptionKeyHex
        self.isInitiateDevice = isInitiateDevice
        self.messenger = DKLSMessenger(mediatorUrl: self.mediatorURL, sessionID: self.sessionID, messageID: nil, encryptionKeyHex: self.encryptionKeyHex)
        self.localPartyID = vault.localPartyID
        self.setupMessage = setupMessage
    }

    func getSetupMessage() -> [UInt8] {
        return self.setupMessage
    }

    func getKeyshare() -> DilithiumKeyshare? {
        return self.keyshare
    }

    private func getDilithiumSetupMessage() throws -> [UInt8] {
        var buf = dilithium.tss_buffer()
        defer {
            dilithium.tss_buffer_free(&buf)
        }
        let threshold = DKLSHelper.getThreshod(input: self.keygenCommittee.count)
        let byteArray = DKLSHelper.arrayToBytes(parties: self.keygenCommittee)
        var ids = byteArray.to_mldsa_goslice()
        let err = mldsa_keygen_setupmsg_new(threshold, nil, &ids, &buf)
        if err != MLDSA_LIB_OK {
            throw HelperError.runtimeError("fail to setup keygen message, mldsa error:\(err)")
        }
        self.setupMessage = Array(UnsafeBufferPointer(start: buf.ptr, count: Int(buf.len)))
        return self.setupMessage
    }

    func GetDilithiumOutboundMessage(handle: dilithium.Handle) -> (mldsa_lib_error, [UInt8]) {
        var buf = dilithium.tss_buffer()
        defer {
            dilithium.tss_buffer_free(&buf)
        }
        let result = mldsa_keygen_session_output_message(handle, &buf)
        if result != MLDSA_LIB_OK {
            print("fail to get outbound message: \(result)")
            return (result, [])
        }
        return (result, Array(UnsafeBufferPointer(start: buf.ptr, count: Int(buf.len))))
    }

    func getOutboundMessageReceiver(handle: dilithium.Handle, message: dilithium.go_slice, idx: UInt32) -> [UInt8] {
        var buf_receiver = dilithium.tss_buffer()
        defer {
            dilithium.tss_buffer_free(&buf_receiver)
        }
        var mutableMessage = message
        let receiverResult = mldsa_keygen_session_message_receiver(handle, &mutableMessage, idx, &buf_receiver)
        if receiverResult != MLDSA_LIB_OK {
            print("fail to get receiver message,error: \(receiverResult)")
            return []
        }
        return Array(UnsafeBufferPointer(start: buf_receiver.ptr, count: Int(buf_receiver.len)))
    }

    func processDilithiumOutboundMessage(handle: dilithium.Handle) async throws {
        repeat {
            let (result, outboundMessage) = GetDilithiumOutboundMessage(handle: handle)
            if result != MLDSA_LIB_OK {
                print("fail to get outbound message,\(result)")
            }
            if outboundMessage.isEmpty {
                return
            }
            let message = outboundMessage.to_mldsa_goslice()
            let encodedOutboundMessage = Data(outboundMessage).base64EncodedString()
            for i in 0..<self.keygenCommittee.count {
                let receiverArray = getOutboundMessageReceiver(handle: handle,
                                                               message: message,
                                                               idx: UInt32(i))

                if receiverArray.isEmpty {
                    break
                }
                let receiverString = String(bytes: receiverArray, encoding: .utf8)!
                print("sending message from \(self.localPartyID) to: \(receiverString) , length:\(outboundMessage.count)")
                try await self.messenger.send(self.localPartyID, to: receiverString, body: encodedOutboundMessage)
            }
        } while 1 > 0
    }

    func pullInboundMessages(handle: dilithium.Handle) async throws -> Bool {
        let urlString = "\(mediatorURL)/message/\(sessionID)/\(self.localPartyID)"
        print("start pulling inbound messages from:\(urlString)")
        guard let url = URL(string: urlString) else {
            throw HelperError.runtimeError("invalid url string: \(urlString)")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
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
                    isFinished = try await processInboundMessage(handle: handle, data: data)
                    if isFinished {
                        return true
                    }
                } else {
                    try await Task.sleep(for: .milliseconds(100))
                }
            default:
                throw HelperError.runtimeError("invalid status code: \(httpResp.statusCode)")
            }
            let currentTime = DispatchTime.now()
            let elapsedTime = currentTime.uptimeNanoseconds - start.uptimeNanoseconds
            let elapsedTimeInSeconds = Double(elapsedTime) / 1_000_000_000
            if elapsedTimeInSeconds > 60 {
                throw HelperError.runtimeError("timeout: failed to create vault within 60 seconds")
            }
        } while !isFinished

        return false
    }

    func processInboundMessage(handle: dilithium.Handle, data: Data) async throws -> Bool {
        if data.isEmpty {
            return false
        }
        let decoder = JSONDecoder()
        let msgs = try decoder.decode([Message].self, from: data)
        let sortedMsgs = msgs.sorted(by: { $0.sequence_no < $1.sequence_no })
        for msg in sortedMsgs {
            let key = "\(self.sessionID)-\(self.localPartyID)-\(msg.hash)" as NSString
            if self.cache.object(forKey: key) != nil {
                print("message with key:\(key) has been applied before")
                continue
            }

            guard let decryptedBody = msg.body.aesDecryptGCM(key: self.encryptionKeyHex) else {
                throw HelperError.runtimeError("fail to decrypted message body")
            }
            guard let decodedMsg = Data(base64Encoded: decryptedBody) else {
                throw HelperError.runtimeError("fail to decrypted inbound message")
            }

            let descryptedBodyArr = [UInt8](decodedMsg)
            var decryptedBodySlice = descryptedBodyArr.to_mldsa_goslice()
            var isFinished: Int32 = 0
            let result = mldsa_keygen_session_input_message(handle, &decryptedBodySlice, &isFinished)

            if result != MLDSA_LIB_OK {
                throw HelperError.runtimeError("fail to apply message to mldsa,\(result)")
            } else {
                print("successfully applied inbound message to mldsa, isFinished:\(isFinished), hash:\(msg.hash), from:\(msg.from), to:\(msg.to) , length:\(decodedMsg.count)")
            }
            self.cache.setObject(NSObject(), forKey: key)
            try await Task.sleep(for: .milliseconds(50))
            try await deleteMessageFromServer(hash: msg.hash)
            try await self.processDilithiumOutboundMessage(handle: handle)
            if isFinished != 0 {
                return true
            }
        }
        return false
    }

    func deleteMessageFromServer(hash: String) async throws {
        let urlString = "\(mediatorURL)/message/\(self.sessionID)/\(self.localPartyID)/\(hash)"
        guard let url = URL(string: urlString) else {
            throw HelperError.runtimeError("invalid url string: \(urlString)")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        let (_, _) = try await URLSession.shared.data(for: request)
    }

    func DilithiumKeygenWithRetry(attempt: UInt8) async throws {
        print("keygen committee: \(self.keygenCommittee)")
        self.cache.removeAllObjects()
        do {
            var keygenSetupMsg: [UInt8]
            var handler = dilithium.Handle()
            if self.isInitiateDevice && attempt == 0 {
                keygenSetupMsg = try getDilithiumSetupMessage()
                self.setupMessage = keygenSetupMsg
                try await messenger.uploadSetupMessage(message: Data(keygenSetupMsg).base64EncodedString(), nil)
            } else {
                let strKeygenSetupMsg = try await messenger.downloadSetupMessageWithRetry(nil)
                keygenSetupMsg = Array(base64: strKeygenSetupMsg)
                self.setupMessage = keygenSetupMsg
            }
            var decodedSetupMsg = keygenSetupMsg.to_mldsa_goslice()

            let localPartyIDArr = self.localPartyID.toArray()
            var localPartySlice = localPartyIDArr.to_mldsa_goslice()
            let result = mldsa_keygen_session_from_setup(&decodedSetupMsg, &localPartySlice, &handler)
            if result != MLDSA_LIB_OK {
                throw HelperError.runtimeError("fail to create session from setup message,error:\(result)")
            }

            defer {
                let sessionFreeResult = mldsa_keygen_session_free(handler)
                if sessionFreeResult != MLDSA_LIB_OK {
                    print("fail to free keygen session \(sessionFreeResult)")
                }
            }
            let h = handler
            try await processDilithiumOutboundMessage(handle: h)
            let isFinished = try await pullInboundMessages(handle: h)
            if isFinished {
                try await processDilithiumOutboundMessage(handle: h)
                var keyshareHandler = dilithium.Handle()
                let keyShareResult = mldsa_keygen_session_finish(handler, &keyshareHandler)
                if keyShareResult != MLDSA_LIB_OK {
                    throw HelperError.runtimeError("fail to get keyshare,\(keyShareResult)")
                }
                defer {
                    var keyshareHandlerPtr = keyshareHandler
                    let freeResult = mldsa_keyshare_free(&keyshareHandlerPtr)
                    if freeResult != MLDSA_LIB_OK {
                        print("fail to free keyshare \(freeResult)")
                    }
                }
                let keyshareBytes = try getKeyshareBytes(handle: keyshareHandler)
                let publicKeyBytes = try getPublicKeyBytes(handle: keyshareHandler)
                let keyIdBytes = try getKeyId(handle: keyshareHandler)
                self.keyshare = DilithiumKeyshare(PubKey: publicKeyBytes.toHexString(),
                                                  Keyshare: keyshareBytes.toBase64(),
                                                  keyId: keyIdBytes.toHexString())
                print("publicKey:\(publicKeyBytes.toHexString())")
                print("keyId: \(keyIdBytes.toHexString())")
                try await Task.sleep(for: .milliseconds(500))
            }
        } catch {
            print("Failed to generate key, error: \(error.localizedDescription)")
            if attempt < 3 {
                print("keygen retry, attemp: \(attempt)")
                try await DilithiumKeygenWithRetry(attempt: attempt + 1)
            } else {
                throw error
            }
        }
    }

    func getKeyshareBytes(handle: dilithium.Handle) throws -> [UInt8] {
        var buf = dilithium.tss_buffer()
        defer {
            dilithium.tss_buffer_free(&buf)
        }
        let result = mldsa_keyshare_to_bytes(handle, &buf)
        if result != MLDSA_LIB_OK {
            throw HelperError.runtimeError("fail to get keyshare from handler, \(result)")
        }
        return Array(UnsafeBufferPointer(start: buf.ptr, count: Int(buf.len)))
    }

    func getPublicKeyBytes(handle: dilithium.Handle) throws -> [UInt8] {
        var buf = dilithium.tss_buffer()
        defer {
            dilithium.tss_buffer_free(&buf)
        }
        let result = mldsa_keyshare_public_key(handle, &buf)
        if result != MLDSA_LIB_OK {
            throw HelperError.runtimeError("fail to get public key from handler, \(result)")
        }
        return Array(UnsafeBufferPointer(start: buf.ptr, count: Int(buf.len)))
    }

    func getKeyId(handle: dilithium.Handle) throws -> [UInt8] {
        var buf = dilithium.tss_buffer()
        defer {
            dilithium.tss_buffer_free(&buf)
        }
        let result = mldsa_keyshare_key_id(handle, &buf)
        if result != MLDSA_LIB_OK {
            throw HelperError.runtimeError("fail to get key ID from handler, \(result)")
        }
        return Array(UnsafeBufferPointer(start: buf.ptr, count: Int(buf.len)))
    }
}
