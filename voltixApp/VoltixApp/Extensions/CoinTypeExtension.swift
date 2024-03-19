//
//  CoinTypeExtension.swift
//  VoltixApp
//
//  Created by Enrique Souza Soares on 19/03/2024.
//

import Foundation
import WalletCore

extension CoinType {
	static func from(string: String) -> CoinType? {
		for coinType in CoinType.allCases {
			if String(describing: coinType).lowercased() == string.lowercased() {
				return coinType
			}
		}
		return nil
	}
}

