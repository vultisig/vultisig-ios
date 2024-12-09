//
//  DKLSKeygen.swift
//  VultisigApp
//
//  Created by Johnny Luo on 9/12/2024.
//
import Foundation
import godkls
import OSLog

enum DKLSError: Error,LocalizedError{
    case backoff
    case runtimeError(String)
    var errorDescription: String? {
        switch self {
        case .runtimeError(let string):
            return string
        case .backoff:
            return "back off"
        }
    }
}

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
    }
    
    private func getDklsSetupMessage() throws -> String  {
        var buf = tss_buffer()
        defer {
            tss_buffer_free(&buf)
        }
        let threshold = DKLSHelper.getThreshod(input: self.keygenCommittee.count)
        // create setup message and upload it to relay server
        let byteArray = DKLSHelper.arrayToBytes(parties: self.keygenCommittee)
        var ids = byteArray.to_dkls_goslice()
        
        try withUnsafeMutablePointer(to: &buf){ bufferPointer in
            let err = dkls_keygen_setupmsg_new(threshold, nil, &ids, bufferPointer)
            if err != LIB_OK {
                throw DKLSError.runtimeError("fail to setup keygen message, dkls error:\(err)")
            }
        }
        
        let resultArr = Array(UnsafeBufferPointer(start: buf.ptr, count: Int(buf.len)))
        return Data(resultArr).base64EncodedString()
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
    
    func processDKLSOutboundMessage(handle: godkls.Handle) throws  {
        repeat {
            let (result,outboundMessage) = GetDKLSOutboundMessage(handle: handle)
            if outboundMessage.count == 0 {
                if self.isKeygenDone() {
                    return
                }
                // back off 100ms and continue
                sleep(100)
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
                let receiverString = String(bytes:receiverArray,encoding: .utf8)
                try self.messenger.send(self.vault.localPartyID, to: receiverString, body: encodedOutboundMessage)
            }
        } while 1 > 0
        
    }
    

    
    func DKLSKeygenWithRetry(attempt: UInt8) async throws {
        let messenger = DKLSMessenger(mediatorUrl: self.mediatorURL, sessionID: self.sessionID, messageID: nil, encryptionKeyHex: self.encryptionKeyHex)
        do {
            var keygenSetupMsg = ""
            if self.isInitiateDevice {
                keygenSetupMsg = try getDklsSetupMessage()
                try await messenger.uploadSetupMessage(message: keygenSetupMsg)
            } else {
                // download the setup message from relay server
                keygenSetupMsg = try await messenger.downloadSetupMessage()
            }
            var decodedSetupMsg = keygenSetupMsg.to_dkls_goslice()
            guard var decodedSetupMsg else {
                throw HelperError.runtimeError("fail to decode dkls keygen setup message")
            }
            var handler = godkls.Handle(_0: 0)
            guard var localPartyID = vault.localPartyID.to_dkls_goslice() else {
                throw HelperError.runtimeError("fail to convert local party id to go slice")
            }
            
            let result = dkls_keygen_session_from_setup(&decodedSetupMsg , &localPartyID, &handler)
            if result != LIB_OK {
                throw HelperError.runtimeError("fail to create session from setup message")
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
}
