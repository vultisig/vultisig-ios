//
//  BitcoinTransactionExtension.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-03-04.
//

import Foundation

extension UTXOTransactionMempool {
    var opReturnData: String? {
        for output in vout {
            let asm = output.scriptpubkey_asm
           
            if asm.hasPrefix("OP_RETURN") {
                let components = asm.components(separatedBy: " ")
                
                if components.count > 1 {
                    let dataHex = components.dropFirst().joined()
                    return hexStringToString(dataHex)
                }
            }
        }
        
        return nil
    }
    
    private func hexStringToString(_ hex: String) -> String? {
        var data = Data()
        var hexIndex = hex.startIndex
        
        while hexIndex < hex.endIndex {
            let nextIndex = hex.index(hexIndex, offsetBy: 2)
            
            if nextIndex <= hex.endIndex {
                let byteString = hex[hexIndex..<nextIndex]
                
                if let byte = UInt8(byteString, radix: 16) {
                    data.append(byte)
                }
            }
            
            hexIndex = nextIndex
        }
        
        return String(data: data, encoding: .utf8)
    }
}

