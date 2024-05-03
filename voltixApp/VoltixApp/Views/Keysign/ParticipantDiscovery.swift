//
//  ParticipantDiscovery.swift
//  VoltixApp
//
//  Created by Johnny Luo on 15/3/2024.
//

import Foundation
import OSLog

class ParticipantDiscovery: ObservableObject {
    let isKeygen: Bool
    private let logger = Logger(subsystem: "participant-discovery", category: "communication")
    @Published var peersFound = [String]()
    var task: Task<Void,Error>? = nil
    
    init(isKeygen: Bool) {
        self.isKeygen = isKeygen
    }
    
    func stop() {
        self.task?.cancel()
    }

    func getParticipants(serverAddr: String, sessionID: String, localParty: String, pubKeyECDSA: String) {
        let urlString = "\(serverAddr)/\(sessionID)"
        let headers =  isKeygen ? TssHelper.getKeygenRequestHeader() : TssHelper.getKeysignRequestHeader(pubKey: pubKeyECDSA)
        
        self.task = Task.detached {
            repeat {
                if Task.isCancelled {
                    return
                }
                Utils.getRequest(urlString: urlString, headers: headers, completion: { result in
                    switch result {
                    case .success(let data):
                        if data.isEmpty {
                            self.logger.error("No participants available yet")
                            return
                        }
                        do {
                            let decoder = JSONDecoder()
                            let peers = try decoder.decode([String].self, from: data)
                            DispatchQueue.main.async {
                                for peer in peers {
                                    if peer == localParty {
                                        continue
                                    }
                                    if !self.peersFound.contains(peer) {
                                        self.peersFound.append(peer)
                                    }
                                }
                            }
                        } catch {
                            self.logger.error("Failed to decode response to JSON: \(error)")
                        }
                    case .failure(let error):
                        self.logger.error("Failed to start session, error: \(error)")
                    }
                })
                try await Task.sleep(for: .seconds(1)) // wait for a second to continue
            } while !Task.isCancelled
        }
    }
}
