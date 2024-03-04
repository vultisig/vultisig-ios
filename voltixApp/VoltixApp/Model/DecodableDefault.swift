//
//  DecodableDefault.swift
//  VoltixApp
//


import Foundation

protocol DecodableDefaultSource {
    associatedtype Value: Decodable
    static var defaultValue: Value { get }
}

enum DecodableDefault {}
