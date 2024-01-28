//
//  Chain.swift
//  VoltixApp

import Foundation
import SwiftData

@Model
final class Chain {
    let name: String
    let ticker: String
    
    init(name: String, ticker: String) {
        self.name = name
        self.ticker = ticker
    }
}
