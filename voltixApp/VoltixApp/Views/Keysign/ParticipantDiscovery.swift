//
//  ParticipantDiscovery.swift
//  VoltixApp
//
//  Created by Johnny Luo on 15/3/2024.
//

import Foundation
import OSLog

class ParticipantDiscovery: ObservableObject {
    private let logger = Logger(subsystem: "participant-discovery", category: "communication")
    @Published var peersFound = [String]()
    var discoverying = true
    
    func stop() {
        self.discoverying = false
    }
    
    func getParticipants(serverAddr: String, sessionID: String) {
        let urlString = "\(serverAddr)/\(sessionID)"
        Task.detached {
            repeat {
                Utils.getRequest(urlString: urlString, headers: [String: String](), completion: { result in
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
            } while self.discoverying
        }
    }
}
