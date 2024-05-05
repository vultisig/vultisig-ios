//
//  DecodingErrorExtension.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 22/03/2024.
//

import Foundation

extension DecodingError {
	static func custom(description: String) -> DecodingError {
		return .dataCorrupted(.init(codingPath: [], debugDescription: description))
	}
}
