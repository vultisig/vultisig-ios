//
//  JoinKeygen.swift
//  VoltixApp

import SwiftUI
import OSLog
import CodeScanner

struct JoinKeygenView: View {
    private let logger = Logger(subsystem: "peers-discory", category: "communication")
    @Binding var presentationStack: Array<CurrentScreen>
    @State private var isShowingScanner = false
    @State private var qrCodeResult: String? = nil
    @State private var waitingForKeygenStart = false
    @State private var seesionIDAcquired = false
    private let ns = NetService(domain: "local.", type: "_http._tcp.", name: "VoltixApp")
    private let sd = ServiceDelegate()
    
    var body: some View {
        VStack{
            if !seesionIDAcquired {
                Button("Scan"){
                    isShowingScanner = true
                }
                .sheet(isPresented: $isShowingScanner, content: {
                    CodeScannerView(codeTypes: [.qr], completion: self.handleScan)
                })
            }
            
            if sd.serverUrl != nil && qrCodeResult != nil {
                if let serverUrl = sd.serverUrl {
                    Text(serverUrl)
                }
                Text(qrCodeResult ?? "")
                Button("Join"){
                    // send request to keygen server
                    joinKeygenCommittee()
                }
            }
            
        }.onAppear(){
            // start to discover service
            ns.delegate = self.sd
            ns.resolve(withTimeout: TimeInterval(10))
        }
        .task {
            // keep polling to decide whether keygen start or not
        }
    }
    private func joinKeygenCommittee() {
        let deviceName = UIDevice.current.name
        guard let serverUrl = sd.serverUrl else {
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
            logger.info("\(result.string)")
            seesionIDAcquired = true
        case .failure(let err):
            logger.error("fail to scan QR code,error:\(err.localizedDescription)")
        }
        isShowingScanner = false
    }
}

final class ServiceDelegate : NSObject , NetServiceDelegate , ObservableObject {
    @Published var serverUrl: String?
    public func netServiceDidResolveAddress(_ sender: NetService) {
        serverUrl = "http://\(sender.hostName ?? ""):\(sender.port)"
    }
}

#Preview {
    JoinKeygenView(presentationStack: .constant([]))
}
