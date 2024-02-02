//
//  JoinKeygen.swift
//  VoltixApp

import SwiftUI
import OSLog
import CodeScanner

private let logger = Logger(subsystem: "join-committee", category: "communication")
struct JoinKeygenView: View {
    enum JoinKeygenStatus{
        case DiscoverSessionID
        case DiscoverService
        case JoinKeygen
        case WaitingForKeygenToStart
        case KeygenStarted
    }
    @Binding var presentationStack: Array<CurrentScreen>
    @State private var isShowingScanner = false
    @State private var qrCodeResult: String? = nil
    private let serviceBrowser = NetServiceBrowser()
    @ObservedObject private var serviceDelegate = ServiceDelegate()
    private let netService = NetService(domain: "local.", type: "_http._tcp.", name: "VoltixApp")
    @State private var currentStatus = JoinKeygenStatus.DiscoverService
    @State private var keygenCommittee =  [String]()
    
    var body: some View {
        VStack{
            switch currentStatus {
            case .DiscoverSessionID:
                Text("Scan the barcode on another VoltixApp")
                Button("Scan"){
                    isShowingScanner = true
                }
                .sheet(isPresented: $isShowingScanner, content: {
                    CodeScannerView(codeTypes: [.qr], completion: self.handleScan)
                })
            case .DiscoverService:
                HStack{
                    Text("discovering mediator service")
                    if serviceDelegate.serverUrl == nil{
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.blue)
                            .padding(2)
                    } else {
                        Image(systemName: "checkmark").foregroundColor(/*@START_MENU_TOKEN@*/.blue/*@END_MENU_TOKEN@*/).onAppear(){
                            currentStatus = .DiscoverSessionID
                        }
                    }
                }
            case .JoinKeygen:
                Button("Join Keygen to create a new wallet"){
                    // send request to keygen server
                    joinKeygenCommittee()
                    currentStatus = .WaitingForKeygenToStart
                }
            case .WaitingForKeygenToStart:
                HStack{
                    Text("Waiting for keygen to start")
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.blue)
                        .padding(2)
                }.onAppear(){
                    Task{
                        repeat{
                            checkKeygenStarted()
                            try await Task.sleep(nanoseconds: 1_000_000_000)
                        }while(self.currentStatus == .WaitingForKeygenToStart)
                    }
                }
            case .KeygenStarted:
                HStack{
                    if serviceDelegate.serverUrl != nil && self.qrCodeResult != nil {
                        // at here we already know these two optional has values
                        KeygenView(presentationStack: $presentationStack, keygenCommittee: keygenCommittee, mediatorURL: serviceDelegate.serverUrl ?? "", sessionID: self.qrCodeResult ?? "")
                    } else {
                        Text("Mediator server url is empty or session id is empty")
                    }
                }
            }
            
        }.onAppear(){
            logger.info("start to discover service")
            netService.delegate = self.serviceDelegate
            netService.resolve(withTimeout: TimeInterval(10))
        }
        
    }
    
    private func checkKeygenStarted() {
        guard let serverUrl = serviceDelegate.serverUrl else {
            logger.error("didn't discover server url")
            return
        }
        guard let sessionID = qrCodeResult else {
            logger.error("session id has not acquired")
            return
        }
        let urlString = "\(serverUrl)/start/\(sessionID)"
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
            if let resp = resp as? HTTPURLResponse, resp.statusCode == 404 {
                logger.error("keygen didn't start yet")
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
                let peers = try decoder.decode([String].self, from: data)
                let deviceName = UIDevice.current.name
                if peers.contains(where: {$0 == deviceName}) {
                    self.keygenCommittee.append(contentsOf: peers)
                    self.currentStatus = .KeygenStarted
                }
            } catch {
                logger.error("fail to decode response to json,\(data)")
            }
            
        }.resume()
    }
    
    private func joinKeygenCommittee() {
        let deviceName = UIDevice.current.name
        guard let serverUrl = serviceDelegate.serverUrl else {
            logger.error("didn't discover server url")
            return
        }
        guard let sessionID = qrCodeResult else {
            logger.error("session id has not acquired")
            return
        }
        let urlString = "\(serverUrl)/\(sessionID)"
        logger.debug("url:\(urlString)")
        let url = URL(string: urlString)
        guard let url else{
            logger.error("URL can't be construct from: \(urlString)")
            return
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        let body = [deviceName]
        do{
            let jsonEncode = JSONEncoder()
            let encodedBody = try jsonEncode.encode(body)
            req.httpBody = encodedBody
        } catch {
            logger.error("fail to encode body into json string,\(error)")
            return
        }
        URLSession.shared.dataTask(with: req){data,resp,err in
            if let err {
                logger.error("fail to join session,error:\(err)")
                return
            }
            guard let resp = resp as? HTTPURLResponse, (200...299).contains(resp.statusCode) else {
                logger.error("invalid response code")
                return
            }
            logger.info("join session successfully.")
        }.resume()
    }
    
    private func handleScan(result: Result<ScanResult,ScanError>) {
        switch result{
        case .success(let result):
            qrCodeResult = result.string
            logger.info("session id: \(result.string)")
        case .failure(let err):
            logger.error("fail to scan QR code,error:\(err.localizedDescription)")
        }
        currentStatus = .JoinKeygen
    }
}

final class ServiceDelegate : NSObject , NetServiceDelegate , ObservableObject {
    @Published var serverUrl: String?
    public func netServiceDidResolveAddress(_ sender: NetService) {
        logger.info("find service:\(sender.name) , \(sender.hostName ?? "") , \(sender.port) \(sender.domain) \(sender)")
        serverUrl = "http://\(sender.hostName ?? ""):\(sender.port)"
    }
}

#Preview {
    JoinKeygenView(presentationStack: .constant([]))
}
