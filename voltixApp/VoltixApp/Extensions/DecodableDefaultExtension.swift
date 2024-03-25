//
//  DecodableDefaultExtensions.swift
//  VoltixApp
//
//  Created by Amol Kumar on 2024-03-04.
//

import Foundation
import Foundation
import BigInt // Ensure this import is correct for BigInt support


extension DecodableDefault {
    typealias Source = DecodableDefaultSource
    typealias List = Decodable & ExpressibleByArrayLiteral
    typealias Map = Decodable & ExpressibleByDictionaryLiteral
    typealias True = Wrapper<Sources.True>
    typealias False = Wrapper<Sources.False>
    typealias EmptyString = Wrapper<Sources.EmptyString>
    typealias EmptyList<T: List> = Wrapper<Sources.EmptyList<T>>
    typealias EmptyMap<T: Map> = Wrapper<Sources.EmptyMap<T>>
    
    enum Sources {
        enum True: Source {
            static var defaultValue: Bool { true }
        }
        
        enum False: Source {
            static var defaultValue: Bool { false }
        }
        
        enum EmptyString: Source {
            static var defaultValue: String { "" }
        }
        
        enum EmptyList<T: List>: Source {
            static var defaultValue: T { [] }
        }
        
        enum EmptyMap<T: Map>: Source {
            static var defaultValue: T { [:] }
        }
    }
    
    @propertyWrapper
    struct Wrapper<Source: DecodableDefaultSource> {
        typealias Value = Source.Value
        var wrappedValue = Source.defaultValue
    }
}

extension DecodableDefault.Wrapper: Decodable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        wrappedValue = try container.decode(Value.self)
    }
}

extension KeyedDecodingContainer {
    func decode<T>(_ type: DecodableDefault.Wrapper<T>.Type, forKey key: Key) throws -> DecodableDefault.Wrapper<T> {
        try decodeIfPresent(type, forKey: key) ?? .init()
    }
}

extension DecodableDefault.Wrapper: Encodable where Value: Encodable {
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(wrappedValue)
    }
}

extension DecodableDefault.Wrapper: Equatable where Value: Equatable {}

extension DecodableDefault.Wrapper: Hashable where Value: Hashable {}

@propertyWrapper
struct DecodableDefaultDouble {
	var wrappedValue: Double
}

@propertyWrapper
struct DecodableDefaultInt32 {
	var wrappedValue: Int32
}

@propertyWrapper
struct DecodableDefaultBigInt {
	var wrappedValue: BigInt
}

@propertyWrapper
struct DecodableDefaultInt64 {
	var wrappedValue: Int64
}

extension DecodableDefaultDouble: Codable {
	init(from decoder: Decoder) throws {
		let container = try decoder.singleValueContainer()
		wrappedValue = (try? container.decode(Double.self)) ?? 0.0
	}
}

extension DecodableDefaultInt32: Codable {
	init(from decoder: Decoder) throws {
		let container = try decoder.singleValueContainer()
		wrappedValue = (try? container.decode(Int32.self)) ?? 0
	}
}

extension DecodableDefaultBigInt: Codable {
	init(from decoder: Decoder) throws {
		let container = try decoder.singleValueContainer()
		let stringValue = (try? container.decode(String.self)) ?? "0"
		wrappedValue = BigInt(stringValue) ?? BigInt(0)
	}
}

extension DecodableDefaultInt64: Codable {
	init(from decoder: Decoder) throws {
		let container = try decoder.singleValueContainer()
		wrappedValue = (try? container.decode(Int64.self)) ?? 0
	}
}
