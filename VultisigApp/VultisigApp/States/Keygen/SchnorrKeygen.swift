//
//  SchnorrKeygen.swift
//  VultisigApp
//
//  Created by Johnny Luo on 11/12/2024.
//

import Foundation
import goschnorr
import OSLog
import Mediator

final class SchnorrKeygen {
    let vault: Vault
    let tssType: TssType
    let keygenCommittee: [String]
    let vaultOldCommittee: [String]
    let mediatorURL: String
    let sessionID: String
    let encryptionKeyHex: String
    let isInitiateDevice: Bool
    var messenger: DKLSMessenger
    var keygenDoneIndicator = false
    let keyGenLock = NSLock()
    let localPartyID: String
    let setupMessage: [UInt8]
    var cache = NSCache<NSString, AnyObject>()
    var keyshare: DKLSKeyshare?
    let publicKeyEdDSA: String
    let localUI: String?
    let hexChainCode: String
    
    init(vault: Vault,
         tssType: TssType,
         keygenCommittee: [String],
         vaultOldCommittee: [String],
         mediatorURL: String,
         sessionID: String,
         encryptionKeyHex: String,
         isInitiatedDevice: Bool,
         setupMessage: [UInt8],
         localUI: String?) {
        self.vault = vault
        self.tssType = tssType
        self.keygenCommittee = keygenCommittee
        self.vaultOldCommittee = vaultOldCommittee
        self.mediatorURL = mediatorURL
        self.sessionID = sessionID
        self.encryptionKeyHex = encryptionKeyHex
        self.isInitiateDevice = isInitiatedDevice
        self.setupMessage = setupMessage
        self.messenger = DKLSMessenger(mediatorUrl: self.mediatorURL,
                                       sessionID: self.sessionID,
                                       messageID: nil,
                                       encryptionKeyHex: self.encryptionKeyHex)
        self.localPartyID = vault.localPartyID
        self.publicKeyEdDSA = vault.pubKeyEdDSA
        self.localUI = localUI
        self.hexChainCode = vault.hexChainCode
    }
    
    func getKeyshare() -> DKLSKeyshare? {
        return self.keyshare
    }
    
    func GetSchnorrOutboundMessage(handle: goschnorr.Handle) -> (goschnorr.schnorr_lib_error,[UInt8]) {
        var buf = goschnorr.tss_buffer()
        defer {
            goschnorr.tss_buffer_free(&buf)
        }
        var result: goschnorr.schnorr_lib_error
        switch self.tssType {
        case .Keygen,.Migrate:
            result = schnorr_keygen_session_output_message(handle,&buf)
        case .Reshare:
            result = schnorr_qc_session_output_message(handle,&buf)
        }
        
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
    
    func getOutboundMessageReceiver(handle: goschnorr.Handle, message: goschnorr.go_slice,idx: UInt32) -> [UInt8] {
        var buf_receiver = goschnorr.tss_buffer()
        defer {
            goschnorr.tss_buffer_free(&buf_receiver)
        }
        var mutableMessage = message
        var receiverResult: goschnorr.schnorr_lib_error
        switch self.tssType {
        case .Keygen,.Migrate:
            receiverResult = schnorr_keygen_session_message_receiver(handle, &mutableMessage, idx, &buf_receiver)
        case .Reshare:
            receiverResult = schnorr_qc_session_message_receiver(handle, &mutableMessage, idx, &buf_receiver)
        }
        if receiverResult != LIB_OK {
            print("fail to get receiver message,error: \(receiverResult)")
            return []
        }
        return Array(UnsafeBufferPointer(start: buf_receiver.ptr, count: Int(buf_receiver.len)))
    }
    
    func processSchnorrOutboundMessage(handle: goschnorr.Handle) async throws  {
        repeat {
            let (result,outboundMessage) = GetSchnorrOutboundMessage(handle: handle)
            if result != LIB_OK {
                print("fail to get outbound message")
            }
            if outboundMessage.count == 0 {
                if self.isKeygenDone() {
                    print("DKLS EdDSA keygen finished")
                    return
                }
                // back off 100ms and continue
                try await Task.sleep(for: .milliseconds(100))
                continue
            }
            
            let message = outboundMessage.to_dkls_goslice()
            let encodedOutboundMessage = Data(outboundMessage).base64EncodedString()
            for i in 0..<self.keygenCommittee.count {
                let receiverArray = getOutboundMessageReceiver(handle:handle,
                                                               message: message,
                                                               idx: UInt32(i))
                
                if receiverArray.count == 0 {
                    continue
                }
                let receiverString = String(bytes:receiverArray,encoding: .utf8)!
                print("sending message from \(self.localPartyID) to: \(receiverString)")
                try self.messenger.send(self.localPartyID, to: receiverString, body: encodedOutboundMessage)
            }
        } while 1 > 0
        
    }
    
    func pullInboundMessages(handle: goschnorr.Handle) async throws -> Bool {
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
    
    func processInboundMessage(handle: goschnorr.Handle,data:Data) async throws -> Bool {
        if data.count == 0 {
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
            var result: goschnorr.schnorr_lib_error
            switch self.tssType {
            case .Keygen,.Migrate:
                result = schnorr_keygen_session_input_message(handle, &decryptedBodySlice, &isFinished)
            case .Reshare:
                result = schnorr_qc_session_input_message(handle, &decryptedBodySlice, &isFinished)
            }
            
            if result != LIB_OK {
                throw HelperError.runtimeError("fail to apply message to dkls,\(result)")
            }
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
    
    func SchnorrKeygenWithRetry(attempt: UInt8) async throws {
        self.setKeygenDone(status: false)
        defer {
            self.setKeygenDone(status: true)
        }
        var task: Task<(), any Error>? = nil
        do {
            var decodedSetupMsg = self.setupMessage.to_dkls_goslice()
            var handler = goschnorr.Handle()
            let localPartyIDArr = self.localPartyID.toArray()
            var localPartySlice = localPartyIDArr.to_dkls_goslice()
            if self.tssType == .Keygen{
                let result = schnorr_keygen_session_from_setup(&decodedSetupMsg,&localPartySlice, &handler)
                if result != LIB_OK {
                    throw HelperError.runtimeError("fail to create session from setup message,error:\(result)")
                }
            } else {
                guard let localUI = self.localUI else {
                    throw HelperError.runtimeError("can't migrate , local UI is empty")
                }
                let publicKeyArray = Array(hex: self.publicKeyEdDSA)
                var publicKeySlice = publicKeyArray.to_dkls_goslice()
                let chainCodeArray = Array(hex: self.hexChainCode)
                var chainCodeSlice = chainCodeArray.to_dkls_goslice()
                let localUIArray = Array(hex: localUI)
                var localUISlice = localUIArray.to_dkls_goslice()
                let result = schnorr_key_migration_session_from_setup(&decodedSetupMsg,
                                                                   &localPartySlice,
                                                                   &publicKeySlice,
                                                                   &chainCodeSlice,
                                                                   &localUISlice,
                                                                   &handler)
                if result != LIB_OK {
                    throw HelperError.runtimeError("fail to create migration session from setup message,error:\(result)")
                }
            }
            // free the handler
            defer {
                schnorr_keygen_session_free(&handler)
            }
            let h = handler
            task = Task{
                try await processSchnorrOutboundMessage(handle: h)
            }
            defer {
                task?.cancel()
            }
            let isFinished = try await pullInboundMessages(handle: h)
            if isFinished {
                var keyshareHandler = goschnorr.Handle()
                let keyShareResult = schnorr_keygen_session_finish(handler,&keyshareHandler)
                if keyShareResult != LIB_OK {
                    throw HelperError.runtimeError("fail to get keyshare,\(keyShareResult)")
                }
                let keyshareBytes = try getKeyshareBytes(handle: keyshareHandler)
                let publicKeyEdDSA = try getPublicKeyBytes(handle: keyshareHandler)
                self.keyshare = DKLSKeyshare(PubKey: publicKeyEdDSA.toHexString(),
                                             Keyshare: keyshareBytes.toBase64(),
                                             chaincode: "")
                print("publicKeyEdDSA:\(publicKeyEdDSA.toHexString())")
                try await Task.sleep(for: .milliseconds(500))
            }
        }
        catch {
            print("Failed to generate key, error: \(error.localizedDescription)")
            task?.cancel()
            if attempt < 3 { // let's retry
                print("keygen/reshare retry, attemp: \(attempt)")
                try await SchnorrKeygenWithRetry(attempt: attempt + 1)
            } else {
                throw error
            }
        }
    }
    
    func getKeyshareBytes(handle: goschnorr.Handle) throws  -> [UInt8] {
        var buf = goschnorr.tss_buffer()
        defer {
            goschnorr.tss_buffer_free(&buf)
        }
        let result = schnorr_keyshare_to_bytes(handle,&buf)
        if result != LIB_OK {
            throw HelperError.runtimeError("fail to get keyshare from handler, \(result)")
        }
        return Array(UnsafeBufferPointer(start: buf.ptr, count: Int(buf.len)))
    }
    
    func getPublicKeyBytes(handle: goschnorr.Handle) throws  -> [UInt8] {
        var buf = goschnorr.tss_buffer()
        defer {
            goschnorr.tss_buffer_free(&buf)
        }
        let result =  schnorr_keyshare_public_key(handle,&buf)
        if result != LIB_OK {
            throw HelperError.runtimeError("fail to get ECDSA public key from handler, \(result)")
        }
        return Array(UnsafeBufferPointer(start: buf.ptr, count: Int(buf.len)))
    }
    
    // processReshareCommittee combine old keygen party and new keygen party into the same array , and return two seperate index array
    func processReshareCommittee(oldCommittee: [String],newCommittee: [String]) -> ([String],[UInt8],[UInt8]) {
        var allParties = oldCommittee
        var oldPartiesIdx = [UInt8]()
        var newPartiesIdx = [UInt8]()
        
        for item in newCommittee {
            if !allParties.contains(item) {
                allParties.append(item)
            }
        }
        
        for(idx,item) in allParties.enumerated() {
            if oldCommittee.contains(item){
                oldPartiesIdx.append(UInt8(idx))
            }
            if newCommittee.contains(item){
                newPartiesIdx.append(UInt8(idx))
            }
        }
        return (allParties,newPartiesIdx,oldPartiesIdx)
    }
    
    func getKeyshareString() -> String? {
        for ks in vault.keyshares {
            if ks.pubkey == self.publicKeyEdDSA {
                return ks.keyshare
            }
        }
        return nil
    }
    
    func getKeyshareBytesFromVault() throws -> [UInt8] {
        guard let localKeyshare = getKeyshareString() else {
            throw HelperError.runtimeError("fail to get local keyshare")
        }
        let keyshareData = Data(base64Encoded: localKeyshare)
        guard let keyshareData else {
            throw HelperError.runtimeError("fail to decode keyshare")
        }
        return [UInt8](keyshareData)
    }
    
    private func getSchnorrReshareSetupMessage(keyshareHandle: goschnorr.Handle) throws ->[UInt8] {
        var buf = goschnorr.tss_buffer()
        defer {
            goschnorr.tss_buffer_free(&buf)
        }
        let threshold = DKLSHelper.getThreshod(input: self.keygenCommittee.count)
        let (allParties,newPartiesIdx,oldPartiesIdx) = processReshareCommittee(oldCommittee: self.vaultOldCommittee, newCommittee: self.keygenCommittee)
        let byteArray = DKLSHelper.arrayToBytes(parties: allParties)
        var ids = byteArray.to_dkls_goslice()
        var newPartiesIdxSlice = newPartiesIdx.to_dkls_goslice()
        var oldPartiesIdxSlice = oldPartiesIdx.to_dkls_goslice()
        let result = schnorr_qc_setupmsg_new(keyshareHandle, &ids, &oldPartiesIdxSlice ,threshold,&newPartiesIdxSlice,&buf)
        if result != LIB_OK {
            throw HelperError.runtimeError("fail to get qc setup message, \(result)")
        }
        return Array(UnsafeBufferPointer(start: buf.ptr,count: Int(buf.len)))
    }
    
    func SchnorrReshareWithRetry(attempt: UInt8) async throws {
        self.setKeygenDone(status: false)
        defer {
            self.setKeygenDone(status: true)
        }
        var task: Task<(), any Error>? = nil
        do {
            var keyshareHandle = goschnorr.Handle()
            if !self.publicKeyEdDSA.isEmpty {
                // we are part of the old keygen committee, let's load existing keyshare
                let keyshare = try getKeyshareBytesFromVault()
                var keyshareSlice = keyshare.to_dkls_goslice()
                let result = schnorr_keyshare_from_bytes(&keyshareSlice,&keyshareHandle)
                if result != LIB_OK {
                    throw HelperError.runtimeError("fail to get keyshare, \(result)")
                }
            }
            
            var reshareSetupMsg:[UInt8]
            // currently reshare Schnorr need to have it's own setup message, let's set it up
            //it might not needed
            if self.isInitiateDevice {
                // DKLS/Schnorr reshare need to upload different setup message , thus here pass in an additional header as "eddsa" to make sure
                // dkls and schnorr setup message will be saved differently
                reshareSetupMsg = try getSchnorrReshareSetupMessage(keyshareHandle: keyshareHandle)
                try await messenger.uploadSetupMessage(message: Data(reshareSetupMsg).base64EncodedString(),"eddsa")
            } else {
                // download the setup message from relay server
                // backoff for 500ms so the initiate device will upload the setup message correctly
                try await Task.sleep(for: .milliseconds(500))
                let strReshareSetupMsg = try await messenger.downloadSetupMessageWithRetry("eddsa")
                reshareSetupMsg = Array(base64: strReshareSetupMsg)
            }
            var decodedSetupMsg = reshareSetupMsg.to_dkls_goslice()
            var handler = goschnorr.Handle()
            let localPartyIDArr = self.localPartyID.toArray()
            var localPartySlice = localPartyIDArr.to_dkls_goslice()
            
            let result = schnorr_qc_session_from_setup(&decodedSetupMsg,&localPartySlice, keyshareHandle,&handler)
            if result != LIB_OK {
                throw HelperError.runtimeError("fail to create session from reshare setup message,error:\(result)")
            }
            // free the handler
            defer {
                let sessionFreeResult = schnorr_qc_session_free(&handler)
                if sessionFreeResult != LIB_OK {
                    print("fail to free reshare session \(sessionFreeResult)")
                }
            }
            let h = handler
            task = Task{
                try await processSchnorrOutboundMessage(handle: h)
            }
            defer {
                task?.cancel()
            }
            let isFinished = try await pullInboundMessages(handle: h)
            if isFinished {
                var newKeyshareHandler = goschnorr.Handle()
                let keyShareResult = schnorr_qc_session_finish(handler,&newKeyshareHandler)
                if keyShareResult != LIB_OK {
                    throw HelperError.runtimeError("fail to get new keyshare,\(keyShareResult)")
                }
                
                let keyshareBytes = try getKeyshareBytes(handle: newKeyshareHandler)
                let publicKeyEdDSA = try getPublicKeyBytes(handle: newKeyshareHandler)
                
                self.keyshare = DKLSKeyshare(PubKey: publicKeyEdDSA.toHexString(),
                                             Keyshare: keyshareBytes.toBase64(),
                                             chaincode: "")
                print("publicKeyEdDSA:\(publicKeyEdDSA.toHexString())")
                try await Task.sleep(for: .milliseconds(500))
            }
        }
        catch {
            print("Failed to reshare key, error: \(error.localizedDescription)")
            task?.cancel()
            if attempt < 3 { // let's retry
                print("keygen/reshare retry, attemp: \(attempt)")
                try await SchnorrReshareWithRetry(attempt: attempt + 1)
            } else {
                throw error
            }
        }
    }
}
