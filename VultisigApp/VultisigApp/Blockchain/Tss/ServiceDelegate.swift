//
//  ServiceDelegate.swift
//  VultisigApp
//
//  Created by Johnny Luo on 18/3/2024.
//
import OSLog
import SwiftUI

final class ServiceDelegate: NSObject, NetServiceDelegate, ObservableObject {
    private let logger = Logger(subsystem: "service-delegate", category: "communication")
    @Published var serverURL: String?

    public func netServiceDidResolveAddress(_ sender: NetService) {
        var ipAddress: String?
        if let addresses = sender.addresses {
            for addressData in addresses {
                addressData.withUnsafeBytes { (pointer: UnsafeRawBufferPointer) in
                    guard let baseAddress = pointer.baseAddress else {
                        return
                    }
                    let sockaddrPtr = baseAddress.assumingMemoryBound(to: sockaddr.self)
                    if sockaddrPtr.pointee.sa_family == sa_family_t(AF_INET) {
                        var hostBuffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                        if getnameinfo(sockaddrPtr, socklen_t(addressData.count), &hostBuffer, socklen_t(hostBuffer.count), nil, 0, NI_NUMERICHOST) == 0 {
                            ipAddress = String(cString: hostBuffer)
                        }
                    }
                }
                if ipAddress != nil { break }
            }
        }
        print("Resolved service address: \(ipAddress ?? "unknown")")
        logger.info("Service found: \(sender.name), \(sender.hostName ?? ""), port \(sender.port) in domain \(sender.domain)")
        serverURL = "http://\(ipAddress ?? sender.hostName ?? ""):\(sender.port)"
    }

    public func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {
        logger.error("Failed to resolve service: \(sender.name) with error: \(errorDict)")
    }
}
