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
    private let httpClient: HTTPClientProtocol

    @Published var peersFound = [String]()
    var task: Task<Void, Error>? = nil

    init(httpClient: HTTPClientProtocol = HTTPClient()) {
        self.httpClient = httpClient
    }

    func stop() {
        self.task?.cancel()
        self.task = nil
        self.peersFound = []
    }

    func getParticipants(serverAddr: String, sessionID: String, localParty: String) {
        guard let baseURL = URL(string: serverAddr) else {
            self.logger.error("Invalid server address: \(serverAddr)")
            return
        }

        self.task?.cancel()
        self.task = Task.detached { [httpClient] in
            repeat {
                if Task.isCancelled {
                    return
                }
                do {
                    // Keep the raw-data path so empty bodies (session warming
                    // up) and decode failures both short-circuit with a log +
                    // retry, matching the original polling behavior.
                    let response = try await httpClient.request(
                        RelayServerAPI(baseURL: baseURL, endpoint: .getParticipants(sessionID: sessionID))
                    )

                    if response.response.statusCode == 404 {
                        self.logger.error("Session not found, maybe it is not started yet")
                    } else if response.data.isEmpty {
                        self.logger.error("No participants available yet")
                    } else {
                        do {
                            let peers = try JSONDecoder().decode([String].self, from: response.data)
                            // The detached task can outlive a stop()/restart;
                            // bail before mutating peersFound so a stale poll
                            // can't leak peers into a fresh session.
                            guard !Task.isCancelled else { return }
                            await MainActor.run {
                                guard !Task.isCancelled else { return }
                                for peer in peers where peer != localParty && !self.peersFound.contains(peer) {
                                    self.peersFound.append(peer)
                                }
                            }
                        } catch {
                            self.logger.error("Failed to decode response to JSON: \(error.localizedDescription)")
                        }
                    }

                    try await Task.sleep(for: .seconds(1))
                } catch is CancellationError {
                    return
                } catch let HTTPError.statusCode(code, _) {
                    // Transient relay errors (5xx, etc.) shouldn't kill the
                    // polling loop — the keysign session would silently never
                    // discover the other participants. Log and retry.
                    self.logger.error("Relay returned status code \(code); retrying")
                    try? await Task.sleep(for: .seconds(1))
                } catch HTTPError.timeout, HTTPError.networkError(_) {
                    self.logger.error("Relay request failed transiently; retrying")
                    try? await Task.sleep(for: .seconds(1))
                } catch {
                    self.logger.error("Error during participant discovery: \(error.localizedDescription)")
                    return
                }
            } while !Task.isCancelled
        }
    }
}
