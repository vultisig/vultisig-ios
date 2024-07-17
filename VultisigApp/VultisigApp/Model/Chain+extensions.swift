//
//  Chain+extensions.swift
//  VultisigApp
//
//  Created by Johnny Luo on 17/7/2024.
//

import Foundation

extension Chain{
    init?(name: String){
        for chain in Chain.allCases {
            if chain.name == name  {
                self = chain
                return
            }
        }
        return nil
    }
}
