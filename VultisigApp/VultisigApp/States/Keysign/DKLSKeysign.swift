//
//  DKLSKeysign.swift
//  VultisigApp
//
//  Created by Johnny Luo on 11/12/2024.
//

import Foundation
import godkls
import OSLog
import Mediator
import Tss

final class DKLSKeysign {
    let keysignCommittee: [String]
    let mediatorURL: String
    let sessionID: String
    let messsageToSign: [String]
    let vault: Vault
    let encryptionKeyHex: String
    let isInitiateDevice: Bool
    let localPartyID: String
    let chainPath: String
    let publicKeyECDSA: String
    var messenger: DKLSMessenger? = nil
    var cache = NSCache<NSString, AnyObject>()
    var signatures = [String: TssKeysignResponse]()
    let DKLS_LIB_OK: godkls.lib_error = .init(0)
    
    init(keysignCommittee: [String],
         mediatorURL: String,
         sessionID: String,
         messsageToSign: [String],
         vault: Vault,
         encryptionKeyHex: String,
         chainPath: String,
         isInitiateDevice: Bool,
         publicKeyECDSA: String) {
        self.keysignCommittee = keysignCommittee
        self.mediatorURL = mediatorURL
        self.sessionID = sessionID
        self.messsageToSign = messsageToSign
        self.vault = vault
        self.encryptionKeyHex = encryptionKeyHex
        self.chainPath = chainPath
        self.isInitiateDevice = isInitiateDevice
        self.localPartyID = vault.localPartyID
        self.publicKeyECDSA = publicKeyECDSA
    }
    
    func getSignatures() -> [String: TssKeysignResponse] {
        return self.signatures
    }
    
    func getKeyshareString() -> String? {
        for ks in vault.keyshares {
            if ks.pubkey == self.publicKeyECDSA {
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
    
    func getDKLSKeyshareID() throws -> [UInt8] {
        var buf = godkls.tss_buffer()
        defer {
            godkls.tss_buffer_free(&buf)
        }
        let keyShareBytes = try getKeyshareBytes()
        var keyshareSlice = keyShareBytes.to_dkls_goslice()
        var h = godkls.Handle()
        let result = dkls_keyshare_from_bytes(&keyshareSlice,&h)
        if result != DKLS_LIB_OK {
            throw HelperError.runtimeError("fail to create keyshare handle from bytes, \(result)")
        }
        
        defer {
            let freeResult = dkls_keyshare_free(&h)
            if freeResult != DKLS_LIB_OK {
                print("fail to free keyshare \(freeResult)")
            }
        }
        let keyIDResult = dkls_keyshare_key_id(h, &buf)
        if keyIDResult != DKLS_LIB_OK {
            throw HelperError.runtimeError("fail to get key id from keyshare: \(keyIDResult)")
        }
        return Array(UnsafeBufferPointer(start: buf.ptr, count: Int(buf.len)))
    }
    
    func getDKLSKeysignSetupMessage(message: String) throws -> [UInt8] {
        var buf = godkls.tss_buffer()
        defer {
            godkls.tss_buffer_free(&buf)
        }
        let keyIdArr = try getDKLSKeyshareID()
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
        let err: godkls.lib_error
        // For multi-chain vaults using DKLS keys, only unhardened HD derivation is supported.
        // For vaults imported from a seed phrase/private key, only a single chain is supported (no derivation path).
        if !self.chainPath.isEmpty {
            guard let chainPathData = self.chainPath.replacingOccurrences(of: "'", with: "").data(using: .utf8) else {
                throw HelperError.runtimeError("fail to encode chainPath to UTF-8")
            }
            let chainPathArr = [UInt8](chainPathData)
            var chainPathSlice = chainPathArr.to_dkls_goslice()
            err = dkls_sign_setupmsg_new(&keyIdSlice,&chainPathSlice,&msgSlice,&ids,&buf)
            
        } else {
            err = dkls_sign_setupmsg_new(&keyIdSlice,nil,&msgSlice,&ids,&buf)
        }
        if err != DKLS_LIB_OK {
            throw HelperError.runtimeError("fail to setup keysign message, dkls error:\(err)")
        }
        return Array(UnsafeBufferPointer(start: buf.ptr, count: Int(buf.len)))
    }
    
    func DKLSDecodeMessage(setupMsg: [UInt8]) throws -> String {
        var buf = godkls.tss_buffer()
        
        defer {
            godkls.tss_buffer_free(&buf)
        }
        var setupMsgSlice = setupMsg.to_dkls_goslice()
        let result = dkls_decode_message(&setupMsgSlice,&buf)
        if result != DKLS_LIB_OK {
            throw HelperError.runtimeError("fail to extract message from setup message:\(result)")
        }
        return Array(UnsafeBufferPointer(start: buf.ptr, count: Int(buf.len))).toHexString()
    }
    
    
    func getOutboundMessageReceiver(handle: godkls.Handle,message: godkls.go_slice,idx: UInt32) -> [UInt8] {
        var buf_receiver = tss_buffer()
        defer {
            tss_buffer_free(&buf_receiver)
        }
        var mutableMessage = message
        let receiverResult = dkls_sign_session_message_receiver(handle, &mutableMessage, idx, &buf_receiver)
        if receiverResult != DKLS_LIB_OK {
            print("fail to get receiver message,error: \(receiverResult)")
            return []
        }
        return Array(UnsafeBufferPointer(start: buf_receiver.ptr, count: Int(buf_receiver.len)))
    }
    
    func GetDKLSOutboundMessage(handle: godkls.Handle) -> (godkls.lib_error,[UInt8]) {
        var buf = godkls.tss_buffer()
        defer {
            godkls.tss_buffer_free(&buf)
        }
        let result = dkls_sign_session_output_message(handle,&buf)
        if result != DKLS_LIB_OK {
            print("fail to get outbound message: \(result)")
            return (result,[])
        }
        return (result,Array(UnsafeBufferPointer(start: buf.ptr, count: Int(buf.len))))
    }
    
    func processDKLSOutboundMessage(handle: godkls.Handle) async throws  {
        repeat {
            let (result,outboundMessage) = GetDKLSOutboundMessage(handle: handle)
            if result != DKLS_LIB_OK {
                print("fail to get outbound message,\(result)")
            }
            if outboundMessage.count == 0 {
                return
            }
            let message = outboundMessage.to_dkls_goslice()
            let encodedOutboundMessage = outboundMessage.toBase64()
            for i in 0..<self.keysignCommittee.count {
                let receiverArray = getOutboundMessageReceiver(handle:handle,
                                                               message: message,
                                                               idx: UInt32(i))
                
                if receiverArray.count == 0 {
                    break
                }
                let receiverString = String(bytes:receiverArray,encoding: .utf8)!
                print("sending message from \(self.localPartyID) to: \(receiverString), content length:\(encodedOutboundMessage.count)")
                try await self.messenger?.send(self.localPartyID,
                                         to: receiverString,
                                         body: encodedOutboundMessage)
            }
        } while 1 > 0
        
    }
    
    func pullInboundMessages(handle: godkls.Handle,messageID: String) async throws -> Bool {
        let urlString = "\(mediatorURL)/message/\(sessionID)/\(self.localPartyID)"
        print("start pulling inbound messages from:\(urlString)")
        guard let url = URL(string: urlString) else {
            throw HelperError.runtimeError("invalid url string: \(urlString)")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(messageID,forHTTPHeaderField: "message_id")
        var isFinished = false
        let start = DispatchTime.now()
        repeat {
            let (data,resp) = try await URLSession.shared.data(for: request)
            guard let httpResp = resp as? HTTPURLResponse else {
                throw HelperError.runtimeError("fail to convert resp to http url response")
            }
            switch httpResp.statusCode {
            case 200 ... 299:
                if data.count > 0 {
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
    
    func processInboundMessage(handle: godkls.Handle,data:Data,messageID: String) async throws -> Bool {
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
            
            var decryptedBodySlice = descryptedBodyArr.to_dkls_goslice()
            var isFinished:UInt32 = 0
            let result = dkls_sign_session_input_message(handle, &decryptedBodySlice, &isFinished)
            if result != DKLS_LIB_OK {
                throw HelperError.runtimeError("fail to apply message to dkls,\(result)")
            }
            
            self.cache.setObject(NSObject(), forKey: key)
            try await deleteMessageFromServer(hash: msg.hash,messageID:messageID)
            try await self.processDKLSOutboundMessage(handle: handle)
            // local party keysign finished
            if isFinished != 0 {
                return true
            }
        }
        return false
    }
    
    func deleteMessageFromServer(hash: String,messageID: String) async throws {
        let urlString = "\(mediatorURL)/message/\(self.sessionID)/\(self.localPartyID)/\(hash)"
        guard let url = URL(string: urlString) else {
            throw HelperError.runtimeError("invalid url string: \(urlString)")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.addValue(messageID, forHTTPHeaderField: "message_id")
        let (_,_) = try await URLSession.shared.data(for: request)
    }
    
    func DKLSKeysignOneMessageWithRetry(attempt: UInt8, messageToSign: String) async throws {
        self.cache.removeAllObjects()
        let msgHash = Utils.getMessageBodyHash(msg: messageToSign)
        let localMessenger = DKLSMessenger(mediatorUrl: self.mediatorURL,
                                           sessionID: self.sessionID,
                                           messageID: msgHash,
                                           encryptionKeyHex: self.encryptionKeyHex)
        self.messenger = localMessenger
        do {
            var keysignSetupMsg:[UInt8]
            if self.isInitiateDevice && attempt == 0 {
                keysignSetupMsg = try getDKLSKeysignSetupMessage(message: messageToSign)
                try await localMessenger.uploadSetupMessage(message:keysignSetupMsg.toBase64(),nil)
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
            
            var handler = godkls.Handle()
            
            let localPartyIDArr = self.localPartyID.toArray()
            var localPartySlice = localPartyIDArr.to_dkls_goslice()
            
            let keyShareBytes = try getKeyshareBytes()
            var keyshareSlice = keyShareBytes.to_dkls_goslice()
            var keyshareHandle = godkls.Handle()
            let result = dkls_keyshare_from_bytes(&keyshareSlice,&keyshareHandle)
            if result != DKLS_LIB_OK {
                throw HelperError.runtimeError("fail to create keyshare handle from bytes, \(result)")
            }
            
            defer {
                dkls_keyshare_free(&keyshareHandle)
            }
            let sessionResult = dkls_sign_session_from_setup(&decodedSetupMsg,
                                                             &localPartySlice,
                                                             keyshareHandle,
                                                             &handler)
            if sessionResult != DKLS_LIB_OK {
                throw HelperError.runtimeError("fail to create sign session from setup message,error:\(sessionResult)")
            }
            // free the handler
            defer {
                dkls_sign_session_free(&handler)
            }
            let h = handler
            
            let isFinished = try await pullInboundMessages(handle: h, messageID: msgHash)
            if isFinished {
                let sig = try dklsSignSessionFinish(handle: h)
                let resp = TssKeysignResponse()
                resp.msg = messageToSign
                let r = Array(sig.prefix(32))
                let s = Array(sig[32..<64])
                resp.r = r.toHexString()
                resp.s = s.toHexString()
                resp.recoveryID = String(format:"%02x",sig[64])
                resp.derSignature = encodeCanonicalDERSignature(r: r, s: s).toHexString()
                let keySignVerify = KeysignVerify(serverAddr: self.mediatorURL,
                                                  sessionID: self.sessionID)
                await keySignVerify.markLocalPartyKeysignComplete(message: msgHash, sig:resp)
                self.signatures[messageToSign] = resp
                try await Task.sleep(for: .milliseconds(500))
            }
            try await processDKLSOutboundMessage(handle: h)
        }
        catch {
            print("Failed to sign message (\(messageToSign)), error: \(error.localizedDescription)")
            if attempt < 3 {
                try await DKLSKeysignOneMessageWithRetry(attempt: attempt+1, messageToSign: messageToSign)
            }
        }
    }
    
    func dklsSignSessionFinish(handle: godkls.Handle) throws -> [UInt8]{
        var buf = godkls.tss_buffer()
        defer {
            godkls.tss_buffer_free(&buf)
        }
        let result = dkls_sign_session_finish(handle,&buf)
        if result != DKLS_LIB_OK {
            throw HelperError.runtimeError("fail to get keysign signature \(result)")
        }
        return Array(UnsafeBufferPointer(start: buf.ptr, count: Int(buf.len)))
    }
    
    func DKLSKeysignWithRetry() async throws {
        for msg in self.messsageToSign {
            try await DKLSKeysignOneMessageWithRetry(attempt: 0, messageToSign: msg)
        }
    }
    
}

