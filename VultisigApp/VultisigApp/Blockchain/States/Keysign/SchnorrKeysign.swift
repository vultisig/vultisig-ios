//
//  SchnorrKeysign.swift
//  VultisigApp
//
//  Created by Johnny Luo on 12/12/2024.
//

import Foundation
import goschnorr
import OSLog
import Mediator
import Tss

/// Swift cannot disambiguate the bare `LIB_OK` C enum case between the
/// `godkls` and `goschnorr` frameworks (both headers export `LIB_OK` under
/// different parent enum types) when compiling in wholemodule mode.
/// Reference the goschnorr value via this typed constant instead.
private extension goschnorr.schnorr_lib_error {
    static let schnorrLibOK = goschnorr.schnorr_lib_error(rawValue: 0)
}

private let logger = Logger(subsystem: "com.vultisig.app", category: "net-schnorr-keysign")

final class SchnorrKeysign {
    let keysignCommittee: [String]
    let mediatorURL: String
    let sessionID: String
    let messsageToSign: [String]
    let vault: Vault
    let encryptionKeyHex: String
    let isInitiateDevice: Bool
    let localPartyID: String
    let publicKeyEdDSA: String
    var messenger: DKLSMessenger? = nil
    var cache = NSCache<NSString, AnyObject>()
    var signatures = [String: TssKeysignResponse]()
    var keyshare: [UInt8] = []
    private let httpClient: HTTPClientProtocol = HTTPClient()

    init(keysignCommittee: [String],
         mediatorURL: String,
         sessionID: String,
         messsageToSign: [String],
         vault: Vault,
         encryptionKeyHex: String,
         isInitiateDevice: Bool,
         publicKeyEdDSA: String) {
        self.keysignCommittee = keysignCommittee
        self.mediatorURL = mediatorURL
        self.sessionID = sessionID
        self.messsageToSign = messsageToSign
        self.vault = vault
        self.encryptionKeyHex = encryptionKeyHex
        self.isInitiateDevice = isInitiateDevice
        self.localPartyID = vault.localPartyID
        self.publicKeyEdDSA = publicKeyEdDSA
    }

    func getSignatures() -> [String: TssKeysignResponse] {
        return self.signatures
    }

    func getKeyshareString() -> String? {
        for ks in vault.keyshares {
            if ks.pubkey == self.publicKeyEdDSA {
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

    func getKeyshareID() throws -> [UInt8] {
        var buf = goschnorr.tss_buffer()
        defer {
            goschnorr.tss_buffer_free(&buf)
        }
        let keyShareBytes = try getKeyshareBytes()
        var keyshareSlice = keyShareBytes.to_dkls_goslice()
        var h = goschnorr.Handle()
        let result = schnorr_keyshare_from_bytes(&keyshareSlice, &h)
        if result != .schnorrLibOK {
            throw HelperError.runtimeError("fail to create keyshare handle from bytes, \(result)")
        }
        let keyIDResult = schnorr_keyshare_key_id(h, &buf)
        if keyIDResult != .schnorrLibOK {
            throw HelperError.runtimeError("fail to get key id from keyshare: \(keyIDResult)")
        }
        return Array(UnsafeBufferPointer(start: buf.ptr, count: Int(buf.len)))
    }

    func getKeysignSetupMessage(message: String) throws -> [UInt8] {
        var buf = goschnorr.tss_buffer()
        defer {
            goschnorr.tss_buffer_free(&buf)
        }
        let keyIdArr = try getKeyshareID()
        var keyIdSlice = keyIdArr.to_dkls_goslice()

        // create setup message and upload it to relay server
        let byteArray = DKLSHelper.arrayToBytes(parties: self.keysignCommittee)
        var ids = byteArray.to_dkls_goslice()

        let decodedMsgData = Data(hexString: message)
        guard let decodedMsgData else {
            throw HelperError.runtimeError("fail to hex decoded the message to sign")
        }
        let msgArr = [UInt8](decodedMsgData)
        var msgSlice = msgArr.to_dkls_goslice()

        let err = schnorr_sign_setupmsg_new(&keyIdSlice, nil, &msgSlice, &ids, &buf)
        if err != .schnorrLibOK {
            throw HelperError.runtimeError("fail to setup keysign message, error:\(err)")
        }

        return Array(UnsafeBufferPointer(start: buf.ptr, count: Int(buf.len)))
    }

    func DKLSDecodeMessage(setupMsg: [UInt8]) throws -> String {
        var buf = goschnorr.tss_buffer()
        defer {
            goschnorr.tss_buffer_free(&buf)
        }
        var setupMsgSlice = setupMsg.to_dkls_goslice()
        let result = schnorr_decode_message(&setupMsgSlice, &buf)
        if result != .schnorrLibOK {
            throw HelperError.runtimeError("fail to extract message from setup message:\(result)")
        }
        return Array(UnsafeBufferPointer(start: buf.ptr, count: Int(buf.len))).toHexString()
    }

    func getOutboundMessageReceiver(handle: goschnorr.Handle, message: goschnorr.go_slice, idx: UInt32) -> [UInt8] {
        var buf_receiver = goschnorr.tss_buffer()
        defer {
            goschnorr.tss_buffer_free(&buf_receiver)
        }
        var mutableMessage = message
        let receiverResult = schnorr_sign_session_message_receiver(handle, &mutableMessage, idx, &buf_receiver)
        if receiverResult != .schnorrLibOK {
            print("fail to get receiver message,error: \(receiverResult)")
            return []
        }
        return Array(UnsafeBufferPointer(start: buf_receiver.ptr, count: Int(buf_receiver.len)))
    }

    func GetSchnorrOutboundMessage(handle: goschnorr.Handle) -> (goschnorr.schnorr_lib_error, [UInt8]) {
        var buf = goschnorr.tss_buffer()
        defer {
            goschnorr.tss_buffer_free(&buf)
        }
        let result = schnorr_sign_session_output_message(handle, &buf)
        if result != .schnorrLibOK {
            print("fail to get outbound message: \(result)")
            return (result, [])
        }
        return (result, Array(UnsafeBufferPointer(start: buf.ptr, count: Int(buf.len))))
    }

    func processSchnorrOutboundMessage(handle: goschnorr.Handle) async throws {
        repeat {
            let (result, outboundMessage) = GetSchnorrOutboundMessage(handle: handle)
            if result != .schnorrLibOK {
                print("fail to get outbound message")
            }
            if outboundMessage.isEmpty {
                return
            }
            let message = outboundMessage.to_dkls_goslice()
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

    func pullInboundMessages(handle: goschnorr.Handle, messageID: String) async throws -> Bool {
        guard let baseURL = URL(string: mediatorURL) else {
            throw HelperError.runtimeError("invalid mediator URL: \(mediatorURL)")
        }
        logger.debug("start pulling inbound messages for session \(self.sessionID), party \(self.localPartyID)")

        var isFinished = false
        let start = DispatchTime.now()
        repeat {
            let response: HTTPResponse<Data>
            do {
                response = try await httpClient.request(TssRelayAPI(
                    baseURL: baseURL,
                    endpoint: .pollInboundMessages(
                        sessionID: sessionID,
                        localPartyID: localPartyID,
                        messageID: messageID
                    )
                ))
            } catch let HTTPError.statusCode(code, _) {
                throw HelperError.runtimeError("invalid status code: \(code)")
            }

            if !response.data.isEmpty {
                isFinished = try await processInboundMessage(handle: handle,
                                                             data: response.data,
                                                             messageID: messageID)
                if isFinished {
                    return true
                }
            } else {
                try await Task.sleep(for: .milliseconds(100))
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

    func processInboundMessage(handle: goschnorr.Handle, data: Data, messageID: String) async throws -> Bool {
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

            // need to have a variable to save the array , otherwise dkls function can't access the memory
            guard let decodedMsg = Data(base64Encoded: decryptedBody) else {
                throw HelperError.runtimeError("fail to decrypted inbound message")
            }

            let descryptedBodyArr = [UInt8](decodedMsg)

            // Validate message data before passing to Rust to prevent panic
            guard !descryptedBodyArr.isEmpty else {
                throw HelperError.runtimeError("Empty decrypted message body")
            }

            var decryptedBodySlice = descryptedBodyArr.to_dkls_goslice()

            // Validate the slice is properly constructed
            guard decryptedBodySlice.len > 0 else {
                throw HelperError.runtimeError("Invalid message slice: length is 0")
            }

            var isFinished: UInt32 = 0
            let result = schnorr_sign_session_input_message(handle, &decryptedBodySlice, &isFinished)
            if result != .schnorrLibOK {
                throw HelperError.runtimeError("fail to apply message to schnorr session, error code: \(result)")
            }
            self.cache.setObject(NSObject(), forKey: key)
            try await deleteMessageFromServer(hash: msg.hash, messageID: messageID)
            try await self.processSchnorrOutboundMessage(handle: handle)
            // local party keysign finished
            if isFinished != 0 {
                return true
            }
        }
        return false
    }

    func deleteMessageFromServer(hash: String, messageID: String) async throws {
        guard let baseURL = URL(string: mediatorURL) else {
            throw HelperError.runtimeError("invalid mediator URL: \(mediatorURL)")
        }
        _ = try await httpClient.request(TssRelayAPI(
            baseURL: baseURL,
            endpoint: .deleteMessage(
                sessionID: sessionID,
                localPartyID: localPartyID,
                hash: hash,
                messageID: messageID
            )
        ))
    }

    func KeysignOneMessageWithRetry(attempt: UInt8, messageToSign: String) async throws {
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
                keysignSetupMsg = try getKeysignSetupMessage(message: messageToSign)
                try await localMessenger.uploadSetupMessage(message: keysignSetupMsg.toBase64(), nil)
            } else {
                // download the setup message from relay server
                let strKeysignSetupMsg = try await localMessenger.downloadSetupMessageWithRetry(nil)
                keysignSetupMsg = Array(base64: strKeysignSetupMsg)
            }

            let signingMsg = try DKLSDecodeMessage(setupMsg: keysignSetupMsg)
            if signingMsg != messageToSign {
                throw HelperError.runtimeError("message doesn't match (\(messageToSign)) vs  (\(signingMsg))")
            }
            let finalSetupMsgArr = keysignSetupMsg
            var decodedSetupMsg = finalSetupMsgArr.to_dkls_goslice()

            var handler = goschnorr.Handle()

            let localPartyIDArr = self.localPartyID.toArray()
            var localPartySlice = localPartyIDArr.to_dkls_goslice()

            let keyShareBytes = try getKeyshareBytes()
            var keyshareSlice = keyShareBytes.to_dkls_goslice()
            var keyshareHandle = goschnorr.Handle()
            let result = schnorr_keyshare_from_bytes(&keyshareSlice, &keyshareHandle)
            if result != .schnorrLibOK {
                throw HelperError.runtimeError("fail to create keyshare handle from bytes, \(result)")
            }

            let sessionResult = schnorr_sign_session_from_setup(&decodedSetupMsg,
                                                             &localPartySlice,
                                                             keyshareHandle,
                                                             &handler)
            if sessionResult != .schnorrLibOK {
                throw HelperError.runtimeError("fail to create sign session from setup message,error:\(sessionResult)")
            }
            // free the handler
            defer {
                schnorr_sign_session_free(&handler)
            }
            let h = handler

            try await processSchnorrOutboundMessage(handle: h)
            let isFinished = try await pullInboundMessages(handle: h, messageID: msgHash)
            if isFinished {
                try await processSchnorrOutboundMessage(handle: h)
                let sig = try SignSessionFinish(handle: h)
                let resp = TssKeysignResponse()
                resp.msg = messageToSign
                // Here we reverse the sig , because those in GG20 is reversed
                // TssExtension.swift when getSignature will get it convert back
                // doing it this way thus we don't need to provide special method for Schnorr signature
                let r = Array(Array(sig.prefix(32)).reversed())
                let s = Array(Array(sig[32..<64]).reversed())
                resp.r = r.toHexString()
                resp.s = s.toHexString()
                resp.derSignature = encodeCanonicalDERSignature(r: r, s: s).toHexString()

                let keySignVerify = KeysignVerify(serverAddr: self.mediatorURL,
                                                  sessionID: self.sessionID)
                await keySignVerify.markLocalPartyKeysignComplete(message: msgHash, sig: resp)
                self.signatures[messageToSign] = resp
            }
        } catch {
            print("Failed to sign message (\(messageToSign)), error: \(error.localizedDescription)")
            if attempt < 3 {
                try await KeysignOneMessageWithRetry(attempt: attempt+1, messageToSign: messageToSign)
            }
        }
    }

    func SignSessionFinish(handle: goschnorr.Handle) throws -> [UInt8] {
        var buf = goschnorr.tss_buffer()
        defer {
            goschnorr.tss_buffer_free(&buf)
        }
        let result = schnorr_sign_session_finish(handle, &buf)
        if result != .schnorrLibOK {
            throw HelperError.runtimeError("fail to get keysign signature \(result)")
        }
        return Array(UnsafeBufferPointer(start: buf.ptr, count: Int(buf.len)))
    }

    func KeysignWithRetry() async throws {
        // get keyshare
        for msg in self.messsageToSign {
            try await KeysignOneMessageWithRetry(attempt: 0, messageToSign: msg)
        }
    }

}
