//
//  DKLSKeygen.swift
//  VultisigApp
//
//  Created by Johnny Luo on 9/12/2024.
//
import Foundation
import godkls
import goschnorr
import OSLog
import Mediator


final class DKLSKeygen {
    private let logger = Logger(subsystem: "keygen", category: "dkls")
    let vault: Vault
    let tssType: TssType
    let keygenCommittee: [String]
    let vaultOldCommittee: [String]
    let mediatorURL: String
    let sessionID: String
    let encryptionKeyHex: String
    let oldResharePrefix: String
    let isInitiateDevice: Bool
    var messenger: DKLSMessenger
    var keygenDoneIndicator = false
    let keyGenLock = NSLock()
    let localPartyID: String
    var cache = NSCache<NSString, AnyObject>()
    
    init(vault: Vault,
         tssType: TssType,
         keygenCommittee: [String],
         vaultOldCommittee: [String],
         mediatorURL: String,
         sessionID: String,
         encryptionKeyHex: String,
         oldResharePrefix: String,
         isInitiateDevice: Bool) {
        self.vault = vault
        self.tssType = tssType
        self.keygenCommittee = keygenCommittee
        self.vaultOldCommittee = vaultOldCommittee
        self.mediatorURL = mediatorURL
        self.sessionID = sessionID
        self.encryptionKeyHex = encryptionKeyHex
        self.oldResharePrefix = oldResharePrefix
        self.isInitiateDevice = isInitiateDevice
        self.messenger = DKLSMessenger(mediatorUrl: self.mediatorURL, sessionID: self.sessionID, messageID: nil, encryptionKeyHex: self.encryptionKeyHex)
        self.localPartyID = vault.localPartyID
    }
    
    private func getDklsSetupMessage() throws -> [UInt8]  {
        var buf = tss_buffer()
        defer {
            tss_buffer_free(&buf)
        }
        let threshold = DKLSHelper.getThreshod(input: self.keygenCommittee.count)
        // create setup message and upload it to relay server
        let byteArray = DKLSHelper.arrayToBytes(parties: self.keygenCommittee)
        var ids = byteArray.to_dkls_goslice()
        let err = dkls_keygen_setupmsg_new(threshold, nil, &ids, &buf)
        if err != LIB_OK {
            throw HelperError.runtimeError("fail to setup keygen message, dkls error:\(err)")
        }
        return Array(UnsafeBufferPointer(start: buf.ptr, count: Int(buf.len)))
    }
    
    func GetDKLSOutboundMessage(handle: godkls.Handle) -> (godkls.lib_error,[UInt8]) {
        var buf = tss_buffer()
        defer {
            tss_buffer_free(&buf)
        }
        let result = dkls_keygen_session_output_message(handle,&buf)
        if result != LIB_OK {
            print("fail to get outbound message: \(result)")
            return (result,[])
        }
        return (result,Array(UnsafeBufferPointer(start: buf.ptr, count: Int(buf.len))))
    }
    
    func isKeygenDone() -> Bool {
        self.keyGenLock.lock()
        defer {
            self.keyGenLock.unlock()
        }
        return self.keygenDoneIndicator
    }
    
    func setKeygenDone(status: Bool){
        self.keyGenLock.lock()
        defer {
            self.keyGenLock.unlock()
        }
        self.keygenDoneIndicator = status
    }
    
    func getOutboundMessageReceiver(handle: godkls.Handle,message: godkls.go_slice,idx: UInt32) -> [UInt8] {
        var buf_receiver = tss_buffer()
        defer {
            tss_buffer_free(&buf_receiver)
        }
        var mutableMessage = message
        let receiverResult = dkls_keygen_session_message_receiver(handle, &mutableMessage, idx, &buf_receiver)
        if receiverResult != LIB_OK {
            print("fail to get receiver message,error: \(receiverResult)")
            return []
        }
        return Array(UnsafeBufferPointer(start: buf_receiver.ptr, count: Int(buf_receiver.len)))
    }
    
    func processDKLSOutboundMessage(handle: godkls.Handle) async throws  {
        repeat {
            let (result,outboundMessage) = GetDKLSOutboundMessage(handle: handle)
            if result != LIB_OK {
                self.logger.error("fail to get outbound message")
            }
            if outboundMessage.count == 0 {
                if self.isKeygenDone() {
                    return
                }
                // back off 100ms and continue
                try await Task.sleep(for: .milliseconds(100))
                continue
            }
            
            var message = outboundMessage.to_dkls_goslice()
            let encodedOutboundMessage = Data(outboundMessage).base64EncodedString()
            for i in 0..<self.keygenCommittee.count {
                let receiverArray = getOutboundMessageReceiver(handle:handle,
                                                               message: message, idx: UInt32(i))
                
                if receiverArray.count == 0 {
                    break
                }
                let receiverString = String(bytes:receiverArray,encoding: .utf8)!
                print("sending message from \(self.localPartyID) to: \(receiverString)")
                try self.messenger.send(self.localPartyID, to: receiverString, body: encodedOutboundMessage)
            }
        } while 1 > 0
        
    }
    
    func pullInboundMessages(handle: godkls.Handle) async throws -> Bool {
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
            let (data,resp) = try await URLSession.shared.data(for: request)
            guard let httpResp = resp as? HTTPURLResponse else {
                throw HelperError.runtimeError("fail to convert resp to http url response")
            }
            switch httpResp.statusCode {
            case 200 ... 299:
                if data.count > 0 {
                    isFinished = try await processInboundMessage(handle: handle, data: data)
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
                throw HelperError.runtimeError("timeout: failed to create vault within 60 seconds")
            }
        } while !isFinished
        
        return false
    }
    
    func processInboundMessage(handle: godkls.Handle,data:Data) async throws -> Bool {
        print("inbound message: \(String(data:data,encoding: .utf8) ?? "")")
        if data.count == 0 {
            return false
        }
        let decoder = JSONDecoder()
        let msgs = try decoder.decode([Message].self, from: data)
        let sortedMsgs = msgs.sorted(by: { $0.sequence_no < $1.sequence_no })
        for msg in sortedMsgs {
            let key = "\(self.sessionID)-\(self.localPartyID)-\(msg.hash)" as NSString
            if self.cache.object(forKey: key) != nil {
                self.logger.info("message with key:\(key) has been applied before")
                // message has been applied before
                continue
            }
            self.logger.debug("Got message from: \(msg.from), to: \(msg.to), key:\(key)")
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
            let result = dkls_keygen_session_input_message(handle, &decryptedBodySlice, &isFinished)
            if result != LIB_OK {
                throw HelperError.runtimeError("fail to apply message to dkls,\(result)")
            }
            print("apply message to local successfully")
            self.cache.setObject(NSObject(), forKey: key)
            try await deleteMessageFromServer(hash: msg.hash)
            // local party keygen finished
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
        let (_,_) = try await URLSession.shared.data(for: request)
    }
    
    func DKLSKeygenWithRetry(attempt: UInt8) async throws {
        let messenger = DKLSMessenger(mediatorUrl: self.mediatorURL, sessionID: self.sessionID, messageID: nil, encryptionKeyHex: self.encryptionKeyHex)
        do {
            var keygenSetupMsg:[UInt8]
            if self.isInitiateDevice {
                keygenSetupMsg = try getDklsSetupMessage()
                try await messenger.uploadSetupMessage(message: Data(keygenSetupMsg).base64EncodedString())
            } else {
                // download the setup message from relay server
                let strKeygenSetupMsg = try await messenger.downloadSetupMessageWithRetry()
                keygenSetupMsg = Array(base64: strKeygenSetupMsg)
            }
            var decodedSetupMsg = keygenSetupMsg.to_dkls_goslice()
            var handler = godkls.Handle(_0: 0)
            let localPartyIDArr = self.localPartyID.toArray()
            var localPartySlice = localPartyIDArr.to_dkls_goslice()
            let result = dkls_keygen_session_from_setup(&decodedSetupMsg,&localPartySlice, &handler)
            if result != LIB_OK {
                throw HelperError.runtimeError("fail to create session from setup message,error:\(result)")
            }
            let task = Task{
                try await processDKLSOutboundMessage(handle: handler)
            }
            let isFinished = try await pullInboundMessages(handle: handler)
            if isFinished {
                var keyshareHandler = godkls.Handle(_0: 0)
                let keyShareResult = dkls_keygen_session_finish(handler,&keyshareHandler)
                if keyShareResult != LIB_OK {
                    throw HelperError.runtimeError("fail to get keyshare,\(keyShareResult)")
                }
                let keyshareBytes = try getKeyshareBytes(handle: keyshareHandler)
                let publicKeyECDSA = try getPublicKeyBytes(handle: keyshareHandler)
                let chainCodeBytes = try getChainCode(handle: keyshareHandler)
                dkls_keyshare_free(&keyshareHandler)
            }
        }
        catch{
            self.logger.error("Failed to generate key, error: \(error.localizedDescription)")
            if attempt < 3 { // let's retry
                logger.info("keygen/reshare retry, attemp: \(attempt)")
                try await DKLSKeygenWithRetry(attempt: attempt + 1)
            } else {
                throw error
            }
        }
    }
    
    func getKeyshareBytes(handle: godkls.Handle) throws  -> [UInt8] {
        var buf = tss_buffer()
        defer {
            tss_buffer_free(&buf)
        }
        let result = dkls_keyshare_to_bytes(handle,&buf)
        if result != LIB_OK {
            throw HelperError.runtimeError("fail to get keyshare from handler, \(result)")
        }
        return Array(UnsafeBufferPointer(start: buf.ptr, count: Int(buf.len)))
    }
    
    func getPublicKeyBytes(handle: godkls.Handle) throws  -> [UInt8] {
        var buf = tss_buffer()
        defer {
            tss_buffer_free(&buf)
        }
        let result =  dkls_keyshare_public_key(handle,&buf)
        if result != LIB_OK {
            throw HelperError.runtimeError("fail to get ECDSA public key from handler, \(result)")
        }
        return Array(UnsafeBufferPointer(start: buf.ptr, count: Int(buf.len)))
    }
    func getChainCode(handle: godkls.Handle) throws -> [UInt8] {
        var buf = tss_buffer()
        defer {
            tss_buffer_free(&buf)
        }
        let result =  dkls_keyshare_chaincode(handle,&buf)
        if result != LIB_OK {
            throw HelperError.runtimeError("fail to get ECDSA chaincode from handler, \(result)")
        }
        return Array(UnsafeBufferPointer(start: buf.ptr, count: Int(buf.len)))
    }
}
