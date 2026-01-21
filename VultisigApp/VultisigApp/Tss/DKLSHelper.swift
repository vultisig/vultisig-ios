//
//  DKLSHelper.swift
//  VultisigApp
//
//  Created by Johnny Luo on 9/12/2024.
//
import Foundation
import godkls

class DKLSHelper {
    static func getThreshod(input: Int) -> UInt32 {
        let threshold = Int(ceil(Double(input) * 2.0 / 3.0))
        return UInt32(threshold)
    }
    
    static func arrayToBytes(parties: [String]) -> [UInt8] {
        if parties.count == 0 {
            return []
        }
        var byteArray: [UInt8] = []
        for item in parties {
            if let utf8Bytes = item.data(using: .utf8) {
                byteArray.append(contentsOf: utf8Bytes)
                byteArray.append(0)
            }
        }
        
        if byteArray.last == 0 {
            byteArray.removeLast()
        }
        return byteArray
    }
}

extension Array where Element == UInt8 {
    
    func to_dkls_goslice() -> go_slice {
        let result = self.withUnsafeBufferPointer { bp in
            return go_slice(
                ptr: UnsafePointer(bp.baseAddress),
                len: UInt(bp.count),
                cap: UInt(bp.count))
        }
        return result.self
    }
    func toTssBuf() -> godkls.tss_buffer {
        let result = self.withUnsafeBufferPointer { bp in
            return godkls.tss_buffer(
                ptr: UnsafePointer(bp.baseAddress),
                len: UInt(bp.count))
        }
        return result.self
    }
}
extension String {
    func toArray() -> [UInt8] {
        guard let utf8Bytes = self.data(using: .utf8) else {
            return []
        }
        
        return [UInt8](utf8Bytes)
    }
}
