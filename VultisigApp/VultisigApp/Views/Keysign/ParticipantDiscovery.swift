//
//  ParticipantDiscovery.swift
//  VultisigApp
//
//  Created by Johnny Luo on 15/3/2024.
//

import Foundation
import OSLog

class ParticipantDiscovery: ObservableObject {
    private let logger = Logger(subsystem: "participant-discovery", category: "communication")
    @Published var peersFound = [String]()
    var task: Task<Void, Error>? = nil

    func stop() {
        self.task?.cancel()
        self.task = nil
        self.peersFound = []
    }

    func getParticipants(serverAddr: String, sessionID: String, localParty: String, pubKeyECDSA: String) {
        let urlString = "\(serverAddr)/\(sessionID)"
        guard let url = URL(string: urlString) else {
            self.logger.error("Invalid URL: \(urlString)")
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        self.task?.cancel() // cancel any existing task
        self.task = Task.detached {
            repeat {
                if Task.isCancelled {
                    return
                }
                do {
                    let (data, resp) = try await URLSession.shared.data(for: request)
                    guard let httpResponse = resp as? HTTPURLResponse else {
                        self.logger.error("Invalid response from server")
                        try await Task.sleep(for: .seconds(1)) // wait for a second to continue
                        continue
                    }

                    switch httpResponse.statusCode {
                    case 200 ... 299:
                        if data.isEmpty {
                            self.logger.error("No participants available yet")
                            try await Task.sleep(for: .seconds(1)) // wait for a second to continue
                            continue
                        }
                        do {
                            print("Response data: \(String(data: data, encoding: .utf8) ?? "")")
                            let decoder = JSONDecoder()
                            let peers = try decoder.decode([String].self, from: data)
                            await MainActor.run {
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
                    case 404: // success
                        self.logger.error("Session not found, maybe it is not started yet")
                    default:
                        self.logger.error("Server returned status code \(httpResponse.statusCode)")
                    }

                    try await Task.sleep(for: .seconds(1)) // wait for a second to continue
                } catch {
                    self.logger.error("Error during participant discovery: \(error.localizedDescription)")
                    return
                }
            } while !Task.isCancelled
        }
    }
}
