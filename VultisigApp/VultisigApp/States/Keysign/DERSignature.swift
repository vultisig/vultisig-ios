//
//  DERSignature.swift
//  VultisigApp
//
//  Created by Johnny Luo on 11/12/2024.
//

import Foundation

// Function to encode an integer as ASN.1 DER
func encodeASN1Integer(_ value: [UInt8]) -> [UInt8] {
    var encoded = [UInt8]()
    encoded.append(0x02) // ASN.1 INTEGER tag
    if value.first! >= 0x80 {
        encoded.append(UInt8(value.count + 1))
        encoded.append(0x00)
    } else {
        encoded.append(UInt8(value.count))
    }
    encoded.append(contentsOf: value)
    return encoded
}

// Function to create a DER-encoded ECDSA signature
func createDERSignature(r: [UInt8], s: [UInt8]) -> [UInt8] {
    let encodedR = encodeASN1Integer(r)
    let encodedS = encodeASN1Integer(s)
    
    var derSignature = [UInt8]()
    derSignature.append(0x30) // ASN.1 SEQUENCE tag
    derSignature.append(UInt8(encodedR.count + encodedS.count))
    derSignature.append(contentsOf: encodedR)
    derSignature.append(contentsOf: encodedS)
    
    return derSignature
}
