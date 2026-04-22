//
//  ContractCallExtractorTests.swift
//  VultisigAppTests
//

@testable import VultisigApp
import XCTest

final class ContractCallExtractorTests: XCTestCase {

    // MARK: - sentinelLabelFor

    func test_sentinelLabel_forApprove_isNonNil() {
        XCTAssertNotNil(ContractCallExtractor.sentinelLabelFor(funcName: "approve"))
    }

    func test_sentinelLabel_forPermitFamily_isNonNil() {
        XCTAssertNotNil(ContractCallExtractor.sentinelLabelFor(funcName: "permit"))
        XCTAssertNotNil(ContractCallExtractor.sentinelLabelFor(funcName: "permitSingle"))
        XCTAssertNotNil(ContractCallExtractor.sentinelLabelFor(funcName: "permitBatch"))
    }

    /// `increaseAllowance(MAX_UINT256)` raises the allowance by 2^256-1, it does
    /// not grant unlimited approval. Labeling it "Unlimited" would misstate what
    /// the user is signing.
    func test_sentinelLabel_forIncreaseAllowance_isNil() {
        XCTAssertNil(ContractCallExtractor.sentinelLabelFor(funcName: "increaseAllowance"))
    }

    func test_sentinelLabel_forDecreaseAllowance_isNil() {
        XCTAssertNil(ContractCallExtractor.sentinelLabelFor(funcName: "decreaseAllowance"))
    }

    func test_sentinelLabel_forNonApprovalFunctions_isNil() {
        XCTAssertNil(ContractCallExtractor.sentinelLabelFor(funcName: "transfer"))
        XCTAssertNil(ContractCallExtractor.sentinelLabelFor(funcName: "transferFrom"))
        XCTAssertNil(ContractCallExtractor.sentinelLabelFor(funcName: "withdraw"))
        XCTAssertNil(ContractCallExtractor.sentinelLabelFor(funcName: "repay"))
        XCTAssertNil(ContractCallExtractor.sentinelLabelFor(funcName: "supply"))
    }

    func test_sentinelLabel_forUnknownFunction_isNil() {
        XCTAssertNil(ContractCallExtractor.sentinelLabelFor(funcName: "doSomething"))
        XCTAssertNil(ContractCallExtractor.sentinelLabelFor(funcName: ""))
    }

    // MARK: - evmFunctionName

    func test_evmFunctionName_extractsName() {
        XCTAssertEqual(
            ContractCallExtractor.evmFunctionName(from: "approve(address,uint256)"),
            "approve"
        )
    }

    func test_evmFunctionName_trimsWhitespace() {
        XCTAssertEqual(
            ContractCallExtractor.evmFunctionName(from: "  supply (address,uint256,address,uint16)"),
            "supply"
        )
    }

    func test_evmFunctionName_returnsNil_whenNoParen() {
        XCTAssertNil(ContractCallExtractor.evmFunctionName(from: "approve"))
    }

    // MARK: - extract (strategy coverage)

    func test_extract_contractIsToken_transfer() {
        let result = ContractCallExtractor.extract(
            signature: "transfer(address,uint256)",
            argsJson: #"["0xRecipient","1000000"]"#,
            toAddress: "0xTokenContract"
        )
        XCTAssertEqual(result?.tokenAddress, "0xTokenContract")
        XCTAssertEqual(result?.rawAmount, "1000000")
    }

    func test_extract_firstAddressBeforeFirstUint_supply() {
        let result = ContractCallExtractor.extract(
            signature: "supply(address,uint256,address,uint16)",
            argsJson: #"["0xAsset","500","0xReceiver","0"]"#,
            toAddress: "0xAavePool"
        )
        XCTAssertEqual(result?.tokenAddress, "0xAsset")
        XCTAssertEqual(result?.rawAmount, "500")
    }

    func test_extract_nthAddress_supplyTo() {
        let result = ContractCallExtractor.extract(
            signature: "supplyTo(address,address,uint256)",
            argsJson: #"["0xDst","0xAsset","777"]"#,
            toAddress: "0xCompound"
        )
        XCTAssertEqual(result?.tokenAddress, "0xAsset")
        XCTAssertEqual(result?.rawAmount, "777")
    }

    func test_extract_returnsNil_forUnknownFunction() {
        let result = ContractCallExtractor.extract(
            signature: "mystery(address,uint256)",
            argsJson: #"["0xFoo","1"]"#,
            toAddress: "0xBar"
        )
        XCTAssertNil(result)
    }

    func test_extract_returnsNil_whenAmountNotNumeric() {
        let result = ContractCallExtractor.extract(
            signature: "transfer(address,uint256)",
            argsJson: #"["0xRecipient","not-a-number"]"#,
            toAddress: "0xToken"
        )
        XCTAssertNil(result)
    }

    func test_extract_returnsNil_forContractIsToken_whenNoToAddress() {
        let result = ContractCallExtractor.extract(
            signature: "approve(address,uint256)",
            argsJson: #"["0xSpender","1"]"#,
            toAddress: nil
        )
        XCTAssertNil(result)
    }

    // Guard against ERC-4626-style collisions: when a registered
    // `firstAddressBeforeFirstUint` function name is paired with a signature
    // whose address parameter appears *after* the uint256, extraction must
    // return nil rather than picking a wrong address.
    func test_extract_returnsNil_whenUintAppearsBeforeAddress() {
        let result = ContractCallExtractor.extract(
            signature: "withdraw(uint256,address)",
            argsJson: #"["1000","0xReceiver"]"#,
            toAddress: "0xVault"
        )
        XCTAssertNil(result)
    }
}
