//
//  DilithiumHelper.swift
//  VultisigApp
//
//  Created by Johnny Luo on 10/2/2026.
//

import Foundation
import vscore

extension Array where Element == UInt8 {
    func to_mldsa_goslice() -> vscore.go_slice {
        let result = self.withUnsafeBufferPointer { bp in
            return vscore.go_slice(
                ptr: UnsafePointer(bp.baseAddress),
                len: UInt(bp.count),
                cap: UInt(bp.count)
            )
        }
        return result
    }
}
