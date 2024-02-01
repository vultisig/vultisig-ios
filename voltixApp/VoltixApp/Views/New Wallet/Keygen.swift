//
//  Keygen.swift
//  VoltixApp

import SwiftUI
import Tss
import OSLog

private let logger = Logger(subsystem: "keygen", category: "tss")
struct Keygen: View {
    @Binding var presentationStack: Array<CurrentScreen>
    let keygenCommittee: [String]
    private let localPartyKey = UIDevice.current.name
    @State private var isCreatingTss = false
    @State private var keygenInProgressECDSA = false
    @State private var pubKeyECDSA: String? = nil
    @State private var keygenInProgressEDDSA = false
    @State private var pubKeyEdDSA: String? = nil
    @State private var keygenDone = false
    @State private var tssService: TssServiceImpl? = nil
    @State private var failToCreateTssInstance = false
    private let tssMessenger = TssMessengerImpl()
    private let stateAccess = LocalStateAccessorImpl()
    var body: some View {
        VStack{
                HStack{
                    Text("creating tss instance")
                    if isCreatingTss {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.blue)
                            .padding(2)
                    } else {
                        Image(systemName: "checkmark").foregroundColor(/*@START_MENU_TOKEN@*/.blue/*@END_MENU_TOKEN@*/)
                    }
                }
            
            HStack{
                if keygenInProgressECDSA {
                    Text("Generating ECDSA key")
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.blue)
                        .padding(2)
                }
                if pubKeyECDSA != nil  {
                    Text("ECDSA pubkey:\(pubKeyECDSA ?? "")")
                    Image(systemName: "checkmark").foregroundColor(/*@START_MENU_TOKEN@*/.blue/*@END_MENU_TOKEN@*/)
                }
                if keygenInProgressEDDSA {
                    Text("Generating EdDSA key")
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.blue)
                        .padding(2)
                }
                if pubKeyEdDSA != nil  {
                    Text("EdDSA pubkey:\(pubKeyEdDSA ?? "")")
                    Image(systemName: "checkmark").foregroundColor(/*@START_MENU_TOKEN@*/.blue/*@END_MENU_TOKEN@*/)
                }
            }
            
        }.onAppear(){
            // create keygen instance , it takes time to generate the preparams
            isCreatingTss = true
            var err: NSError?
            self.tssService = TssNewService(tssMessenger,stateAccess,&err)
            if let err {
                logger.error("fail to create TSS instance,error:\(err.localizedDescription )")
                failToCreateTssInstance = true
                return
            }
            let keygenReq = TssKeygenRequest()
            keygenReq.localPartyID = localPartyKey
            keygenReq.allParties = keygenCommittee.joined(separator: ",")
            do{
                if let tssService {
                    let ecdsaResp = try tssService.keygenECDSA(keygenReq)
                    pubKeyECDSA = ecdsaResp.pubKey
                }
            }catch{
                logger.error("fail to create ECDSA key,error:\(error.localizedDescription)")
                return
            }
            do{
                if let tssService {
                    let eddsaResp = try tssService.keygenEDDSA(keygenReq)
                    pubKeyEdDSA = eddsaResp.pubKey
                }
            }catch{
                logger.error("fail to create EdDSA key,error:\(error.localizedDescription)")
                return
            }
        }.task {
            // keep polling in messages
            Task{
                
            }
        }
    }
}

final class TssMessengerImpl : NSObject,TssMessengerProtocol {
    func send(_ from: String?, to: String?, body: String?) throws {
        guard let from else {
            logger.error("from is nil")
            return
        }
        guard let to else {
            logger.error("to is nil")
            return
        }
        guard let body else {
            logger.error("body is nil")
            return
        }
        logger.info("sending messages from:\(from) , to:\(to) , body:\(body)")
    }
}

final class LocalStateAccessorImpl : NSObject, TssLocalStateAccessorProtocol {
    func getLocalState(_ pubKey: String?, error: NSErrorPointer) -> String {
        return ""
    }
    
    func saveLocalState(_ pubkey: String?, localState: String?) throws {
        
    }
    
    
    
}
#Preview("keygen") {
    Keygen(presentationStack: .constant([]),keygenCommittee: [] )
}
