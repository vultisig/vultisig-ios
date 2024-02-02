//
//  Keygen.swift
//  VoltixApp
//

import SwiftUI
import Tss
import OSLog
import Mediator
import Foundation

private let logger = Logger(subsystem: "keygen", category: "tss")
struct KeygenView: View {
    enum KeygenStatus{
        case CreatingInstance
        case KeygenECDSA
        case KeygenEdDSA
        case KeygenFinished
    }
    @State private var currentStatus = KeygenStatus.CreatingInstance
    @Binding var presentationStack: Array<CurrentScreen>
    let keygenCommittee: [String]
    let mediatorURL: String
    let sessionID: String
    private let localPartyKey = UIDevice.current.name
    @State private var isCreatingTss = false
    @State private var keygenInProgressECDSA = false
    @State private var pubKeyECDSA: String? = nil
    @State private var keygenInProgressEDDSA = false
    @State private var pubKeyEdDSA: String? = nil
    @State private var keygenDone = false
    @State private var tssService: TssServiceImpl? = nil
    @State private var failToCreateTssInstance = false
    @State private var tssMessenger: TssMessengerImpl? = nil
    private let stateAccess = LocalStateAccessorImpl()
    
    var body: some View {
        VStack{
            switch currentStatus {
            case .CreatingInstance:
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
            case .KeygenECDSA:
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
                }
            case .KeygenEdDSA:
                HStack{
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
            case .KeygenFinished:
                Text("keygen finished")
            }
        }.onAppear(){
            
            // create keygen instance , it takes time to generate the preparams
            isCreatingTss = true
            tssMessenger = TssMessengerImpl(mediatorUrl: self.mediatorURL,sessionID: self.sessionID)
            var err: NSError?
            self.tssService = TssNewService(tssMessenger,stateAccess,&err)
            if let err {
                logger.error("fail to create TSS instance,error:\(err.localizedDescription )")
                failToCreateTssInstance = true
                return
            }
            self.currentStatus = .KeygenECDSA
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
            self.currentStatus = .KeygenEdDSA
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
                repeat{
                    pollInboundMessages()
                    try await Task.sleep(nanoseconds: 1_000_000_000) //back off 1s
                } while(self.tssService != nil)
            }
        }
    }
    
    private func pollInboundMessages(){
        let urlString = "\(self.mediatorURL)/message/\(self.sessionID)/\(self.localPartyKey)"
        logger.debug("url:\(urlString)")
        let url = URL(string: urlString)
        guard let url else{
            logger.error("URL can't be construct from: \(urlString)")
            return
        }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        URLSession.shared.dataTask(with: req){data,resp,err in
            if let err {
                logger.error("fail to start session,error:\(err)")
                return
            }
            guard let resp = resp as? HTTPURLResponse, (200...299).contains(resp.statusCode) else {
                logger.error("invalid response code")
                return
            }
            guard let data else {
                logger.error("no participants available yet")
                return
            }
            do{
                let decoder = JSONDecoder()
                let msgs = try decoder.decode([Message].self, from: data)
                for msg in msgs {
                    try self.tssService?.applyData(msg.body)
                }
            } catch {
                logger.error("fail to decode response to json,\(data),error:\(error)")
            }
            
        }.resume()
    }
    
}

final class TssMessengerImpl : NSObject,TssMessengerProtocol {
    let mediatorUrl: String
    let sessionID: String
    
    init(mediatorUrl: String, sessionID: String) {
        self.mediatorUrl = mediatorUrl
        self.sessionID = sessionID
    }
    
    func send(_ fromParty: String?, to: String?, body: String?) throws {
        guard let fromParty else {
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
        let urlString = "\(self.mediatorUrl)/message/\(self.sessionID)"
        logger.debug("url:\(urlString)")
        let url = URL(string: urlString)
        guard let url else{
            logger.error("URL can't be construct from: \(urlString)")
            return
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        let msg = Message(session_id: sessionID,from: fromParty, to: [to],body: body)
        do{
            let jsonEncode = JSONEncoder()
            let encodedBody = try jsonEncode.encode(msg)
            req.httpBody = encodedBody
        } catch {
            logger.error("fail to encode body into json string,\(error)")
            return
        }
        URLSession.shared.dataTask(with: req){data,resp,err in
            if let err {
                logger.error("fail to send message,error:\(err)")
                return
            }
            guard let resp = resp as? HTTPURLResponse, (200...299).contains(resp.statusCode) else {
                logger.error("invalid response code")
                return
            }
        }.resume()
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
    KeygenView(presentationStack: .constant([]), keygenCommittee: [], mediatorURL:"", sessionID: "")
}
