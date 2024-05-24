//
//  DepositStore.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 20/05/24.
//

import Foundation

class DepositStore {
    static let PREFIXES: [String] = [
        "SWAP:", "s:", "=",
        "ADD:", "+:", "a:",
        "WITHDRAW:", "-", "wd:",
        "LOAN+:", "$+",
        "LOAN-:", "$-",
        "TRADE+:",
        "TRADE-:",
        "DONATE:", "d:",
        "RESERVE:",
        "BOND:", "UNBOND:", "LEAVE:",
        "MIGRATE:",
        "NOOP:",
        "consolidate", "limito", "lo", "name", "n", "~", "out", "ragnarok", "switch", "yggdrasil+", "yggdrasil-"
    ]
}
