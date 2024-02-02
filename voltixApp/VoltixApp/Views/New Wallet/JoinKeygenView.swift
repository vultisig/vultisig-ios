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
        case KeygenStarted
    }
    @Binding var presentationStack: Array<CurrentScreen>
    @State private var isShowingScanner = false
    @State private var qrCodeResult: String? = nil
    @State private var waitingForKeygenStart = false
    @State private var seesionIDAcquired = false
    private let serviceBrowser = NetServiceBrowser()
    private let serviceDelegate = ServiceDelegate()
    private let netService = NetService(domain: "local.", type: "_http._tcp.", name: "VoltixApp")
    @State private var currentStatus = JoinKeygenStatus.DiscoverService
    
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
                Text("discovering mediator service")
                if serviceDelegate.serverUrl == nil {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.blue)
                        .padding(2)
                } else {
                    Image(systemName: "checkmark").foregroundColor(/*@START_MENU_TOKEN@*/.blue/*@END_MENU_TOKEN@*/).onAppear(){
                        currentStatus = .DiscoverSessionID
                    }
                }
            case .JoinKeygen:
                Button("Join Keygen to create a new wallet"){
                    // send request to keygen server
                    joinKeygenCommittee()
                }
            case .KeygenStarted:
                Text("Keygen start")
            }
            
        }.onAppear(){
            logger.info("start to discover service")
            netService.delegate = self.serviceDelegate
            netService.resolve(withTimeout: TimeInterval(10))
        }
        .task {
            // keep polling to decide whether keygen start or not
        }
    }
    
    private func checkKeygenStarted() {
        let deviceName = UIDevice.current.name
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
            self.waitingForKeygenStart = true
        }.resume()
    }
    
    private func handleScan(result: Result<ScanResult,ScanError>) {
        switch result{
        case .success(let result):
            qrCodeResult = result.string
            logger.info("\(result.string)")
            seesionIDAcquired = true
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
    public func netServiceWillResolve(_ sender: NetService) {
        logger.debug("will find service:\(sender.name) , \(sender.hostName ?? "") , \(sender.port) \(sender.domain) \(sender)")
    }
}

#Preview {
    JoinKeygenView(presentationStack: .constant([]))
}
