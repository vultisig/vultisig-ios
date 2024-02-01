//
//  PeerDiscoveryView.swift
//  VoltixApp
//

import SwiftUI
import Mediator
import OSLog
import CoreImage
import CoreImage.CIFilterBuiltins

struct PeerDiscoveryView: View {
    private let logger = Logger(subsystem: "peers-discory", category: "communication")
    @Binding var presentationStack: Array<CurrentScreen>
    @State private var peersFound = [String]()
    @State private var selections = Set<String>()
    private let mediator = Mediator.shared
    // it should be ok to hardcode here , as this view start the mediator server itself
    private let serverAddr = "http://127.0.0.1:8080"
    private let sessionID = UUID().uuidString
    @State private var discoverying = true
    
    var body: some View {
        VStack {
            Text("Scan the following QR code to join keygen session")
            Image(uiImage: self.getQrImage(size:100))
                .resizable()
                .scaledToFit()
                .padding()
            Text("Available devices")
            List(peersFound, id: \.self, selection: $selections) { peer in
                HStack {
                    if selections.contains(peer) {
                        Image(systemName: "checkmark.circle")
                    } else {
                        Image(systemName: "circle")
                    }
                    Text(peer)
                }
                .onTapGesture {
                    if selections.contains(peer) {
                        selections.remove(peer)
                    } else {
                        selections.insert(peer)
                    }
                }
            }
            Button("Create Wallet >") {
                
            }
            .disabled(selections.count != 2)
        }
        .task {
            Task{
                repeat{
                    self.getParticipants()
                    try await Task.sleep(nanoseconds: 1_000_000_000) // wait for a second to continue
                }while(self.discoverying)
            }
        }
        .onAppear(){ // start the mediator server
            self.mediator.start()
            logger.info("mediator server started")
            startSession()
        }
        .onDisappear(){
            logger.info("mediator server stopped")
            self.discoverying = false
            self.mediator.stop()
        }
    }
    
    private func getQrImage(size: CGFloat) -> UIImage {
        let context = CIContext()
        let qrFilter = CIFilter.qrCodeGenerator()
        qrFilter.setValue(self.sessionID.data(using: .utf8), forKey: "inputMessage")
        if let qrCodeImage = qrFilter.outputImage {
            let qrCodeImage = qrCodeImage.transformed(by: CGAffineTransform(scaleX: size, y: size))
            if let qrCodeCGImage = context.createCGImage(qrCodeImage, from: qrCodeImage.extent) {
                return UIImage(cgImage: qrCodeCGImage)
            }
        }
        return UIImage(systemName: "xmark") ?? UIImage()
        
    }
    
    private func startSession() {
        let deviceName = UIDevice.current.name
        let urlString = "\(self.serverAddr)/\(self.sessionID)"
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
                logger.error("fail to start session,error:\(err)")
                return
            }
            guard let resp = resp as? HTTPURLResponse, (200...299).contains(resp.statusCode) else {
                logger.error("invalid response code")
                return
            }
            logger.info("start session successfully.")
        }.resume()
    }
    
    private func getParticipants() {
        let urlString = "\(self.serverAddr)/\(self.sessionID)"
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
                let peers = try decoder.decode([String].self, from: data)
                for peer in peers {
                    if !self.peersFound.contains(where:{$0 == peer}){
                        self.peersFound.append(peer)
                    }
                }
            } catch {
                logger.error("fail to decode response to json,\(data)")
            }
            
        }.resume()
    }
}

#Preview {
    PeerDiscoveryView(presentationStack: .constant([]))
}
