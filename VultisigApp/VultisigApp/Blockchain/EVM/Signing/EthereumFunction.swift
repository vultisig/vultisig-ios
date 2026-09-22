//
//  EthereumFunction.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 29/07/2025.
//

import BigInt
import WalletCore

enum EthereumFunction {
    static func transferErc20Encoder(address: String, amount: BigInt) throws -> String {
        guard amount >= .zero else { throw HelperError.runtimeError("Amount must be non-negative") }
        guard address.isNotEmpty, let destinationAddress = AnyAddress(string: address, coin: CoinType.ethereum) else {
            throw HelperError.runtimeError("Address is not valid")
        }

        let amountOut = amount.serializeForEvm()
        let encodedFunction = EthereumAbiFunction(name: "transfer")
        encodedFunction.addParamAddress(val: destinationAddress.data, isOutput: false)
        encodedFunction.addParamUInt256(val: amountOut, isOutput: false)
        return EthereumAbi.encode(fn: encodedFunction).toHexString().add0x
    }

    static func approvalErc20Encoder(address: String, amount: BigInt) throws -> String {
        guard amount >= .zero else { throw HelperError.runtimeError("Amount must be non-negative") }
        guard address.isNotEmpty, let destinationAddress = AnyAddress(string: address, coin: CoinType.ethereum) else {
            throw HelperError.runtimeError("Address is not valid")
        }

        let amountOut = amount.serializeForEvm()
        let encodedFunction = EthereumAbiFunction(name: "approve")
        encodedFunction.addParamAddress(val: destinationAddress.data, isOutput: false)
        encodedFunction.addParamUInt256(val: amountOut, isOutput: false)
        return EthereumAbi.encode(fn: encodedFunction).toHexString().add0x
    }

    static func allowanceErc20Encoder(owner: String, spender: String) throws -> String {
        guard owner.isNotEmpty, let ownerAddress = AnyAddress(string: owner, coin: CoinType.ethereum),
              spender.isNotEmpty, let spenderAddress = AnyAddress(string: spender, coin: CoinType.ethereum) else {
            throw HelperError.runtimeError("Address is not valid")
        }

        let encodedFunction = EthereumAbiFunction(name: "allowance")
        encodedFunction.addParamAddress(val: ownerAddress.data, isOutput: false)
        encodedFunction.addParamAddress(val: spenderAddress.data, isOutput: false)
        return EthereumAbi.encode(fn: encodedFunction).toHexString().add0x
    }
}
