//
//  AgentLogging.swift
//  VultisigApp
//

import Foundation
import OSLog

protocol AgentLogging {
    var logger: Logger { get }
}

extension AgentLogging {
    func debugLog(_ message: String) {
        #if DEBUG
        logger.debug("\(message, privacy: .public)")
        #endif
    }

    func warningLog(_ message: String) {
        #if DEBUG
        logger.warning("\(message, privacy: .public)")
        #endif
    }

    func errorLog(_ message: String) {
        #if DEBUG
        logger.error("\(message, privacy: .public)")
        #endif
    }
}
