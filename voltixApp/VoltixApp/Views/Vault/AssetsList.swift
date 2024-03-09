    //
    //  CoinsList.swift
    //  VoltixApp
    //

import OSLog
import SwiftData
import SwiftUI

private let logger = Logger(subsystem: "assets-list", category: "view")
struct AssetsList: View {
    @EnvironmentObject var appState: ApplicationState
    @State private var assets = [
        Asset(ticker: "BTC", chainName: "Bitcoin", image: "btc", contractAddress: nil),
        Asset(ticker: "BCH", chainName: "BitcoinCash", image: "bch", contractAddress: nil),
        Asset(ticker: "LTC", chainName: "Litecoin", image: "ltc", contractAddress: nil),
        Asset(ticker: "DOGE", chainName: "Dogecoin", image: "doge", contractAddress: nil),
        Asset(ticker: "RUNE", chainName: "THORChain", image: "rune", contractAddress: nil),
        // Ethereum chain
        Asset(ticker: "ETH", chainName: "Ethereum", image: "eth", contractAddress: nil),
        Asset(ticker: "USDC", chainName: "Ethereum", image: "usdc", contractAddress: "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"),
        Asset(ticker: "USDT", chainName: "Ethereum", image: "usdt", contractAddress: "0xdac17f958d2ee523a2206206994597c13d831ec7"),
        Asset(ticker: "UNI", chainName: "Ethereum", image: "uni", contractAddress: "0x1f9840a85d5af5bf1d1762f925bdaddc4201f984"),
        Asset(ticker: "MATIC", chainName: "Ethereum", image: "matic", contractAddress: "0x7d1afa7b718fb893db30a3abc0cfc608aacfebb0"),
        Asset(ticker: "WBTC", chainName: "Ethereum", image: "wbtc", contractAddress: "0x2260fac5e5542a773aa44fbcfedf7c193bc2c599"),
        Asset(ticker: "LINK", chainName: "Ethereum", image: "link", contractAddress: "0x514910771af9ca656af840dff83e8264ecf986ca"),
        Asset(ticker: "FLIP", chainName: "Ethereum", image: "flip", contractAddress: "0x826180541412d574cf1336d22c0c0a287822678a"),
        // Solana chain
        Asset(ticker: "SOL", chainName: "Solana", image: "solana", contractAddress: nil)
    ]
    @State private var selection = Set<Asset>()
    @State private var expandedGroups: Set<String> = Set()
    @State var editMode = EditMode.active
    
        // Computed property to group assets by chainName
    private var groupedAssets: [String: [Asset]] {
        Dictionary(grouping: assets) { $0.chainName }
    }
    
        // Automatically expand groups that contain selected assets
    private func updateExpandedGroups() {
        for (chainName, assets) in groupedAssets {
            if assets.contains(where: selection.contains) {
                expandedGroups.insert(chainName)
            }
        }
    }
    
    var body: some View {
        List {
            ForEach(groupedAssets.keys.sorted(), id: \.self) { chainName in
                Section(header: HStack {
                    Text(chainName)
                    Spacer()
                    Image(systemName: expandedGroups.contains(chainName) ? "chevron.up" : "chevron.down")
                }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if expandedGroups.contains(chainName) {
                            expandedGroups.remove(chainName)
                        } else {
                            expandedGroups.insert(chainName)
                        }
                    }
                ) {
                    if expandedGroups.contains(chainName) {
                        ForEach(groupedAssets[chainName] ?? [], id: \.self) { asset in
                            HStack {
                                Text("\(asset.chainName) - \(asset.ticker)")
                                Spacer()
                                if selection.contains(asset) {
                                    Image(systemName: "checkmark")
                                }
                            }
                            .padding(.leading, asset.contractAddress != nil ? 20 : 0) // Add padding if it's a child token
                            .onTapGesture {
                                if selection.contains(asset) {
                                    selection.remove(asset)
                                } else {
                                    selection.insert(asset)
                                }
                            }
                        }
                    }
                }
            }
        }
        .environment(\.editMode, $editMode)
        .navigationTitle("select assets")
        .onChange(of: selection) { _ in
            updateExpandedGroups()
        }
        .onAppear {
            updateExpandedGroups()
            guard let vault = appState.currentVault else {
                print("current vault is nil")
                return
            }
            for item in vault.coins {
                let asset = assets.first(where: { $0.ticker == item.ticker })
                if let asset {
                    selection.insert(asset)
                }
            }
        }
        .onDisappear {
                // sync selection
            guard let vault = appState.currentVault else {
                print("current vault is nil")
                return
            }
            for item in selection {
                if vault.coins.contains(where: { $0.ticker == item.ticker }) {
                    print("coin already exists")
                } else {
                    switch item.chainName {
                        case Chain.THORChain.name:
                            let runeCoinResult = THORChainHelper.getRUNECoin(hexPubKey: vault.pubKeyECDSA, hexChainCode: vault.hexChainCode)
                            switch runeCoinResult {
                                case .success(let coin):
                                    vault.coins.append(coin)
                                case .failure(let error):
                                    logger.info("fail to get thorchain address,error:\(error.localizedDescription)")
                            }
                        case Chain.Ethereum.name:
                            let coinResult = EthereumHelper.getEthereum(hexPubKey: vault.pubKeyECDSA, hexChainCode: vault.hexChainCode)
                            switch coinResult {
                                case .success(let coin):
                                        // all coins on Ethereum share the same address
                                    if coin.ticker == "Ethereum" {
                                        vault.coins.append(coin)
                                    } else {
                                        let newCoin = Coin(chain: coin.chain, ticker: item.ticker, logo: item.image, address: coin.address, hexPublicKey: coin.hexPublicKey, feeUnit: "GWEI", contractAddress: item.contractAddress)
                                        vault.coins.append(newCoin)
                                    }
                                case .failure(let error):
                                    logger.info("fail to get ethereum address,error:\(error.localizedDescription)")
                            }
                        case Chain.Bitcoin.name:
                            let coinResult = UTXOChainsHelper(coin: .bitcoin, vaultHexPublicKey: vault.pubKeyECDSA, vaultHexChainCode: vault.hexChainCode).getCoin()
                            switch coinResult {
                                case .success(let btc):
                                    vault.coins.append(btc)
                                case .failure(let err):
                                    logger.info("fail to get bitcoin address,error:\(err.localizedDescription)")
                            }
                        case Chain.BitcoinCash.name:
                            let coinResult = UTXOChainsHelper(coin: .bitcoinCash, vaultHexPublicKey: vault.pubKeyECDSA, vaultHexChainCode: vault.hexChainCode).getCoin()
                            switch coinResult {
                                case .success(let bch):
                                    vault.coins.append(bch)
                                case .failure(let err):
                                    logger.info("fail to get bitcoin bash address,error:\(err.localizedDescription)")
                            }
                        case Chain.Litecoin.name:
                            let coinResult = UTXOChainsHelper(coin: .litecoin, vaultHexPublicKey: vault.pubKeyECDSA, vaultHexChainCode: vault.hexChainCode).getCoin()
                            switch coinResult {
                                case .success(let ltc):
                                    vault.coins.append(ltc)
                                case .failure(let err):
                                    logger.info("fail to get litecoin address,error:\(err.localizedDescription)")
                            }
                        case Chain.Dogecoin.name:
                            let coinResult = UTXOChainsHelper(coin: .dogecoin, vaultHexPublicKey: vault.pubKeyECDSA, vaultHexChainCode: vault.hexChainCode).getCoin()
                            switch coinResult {
                                case .success(let doge):
                                    vault.coins.append(doge)
                                case .failure(let err):
                                    logger.info("fail to get dogecoin address,error:\(err.localizedDescription)")
                            }
                        case Chain.Solana.name:
                            let coinResult = SolanaHelper.getSolana(hexPubKey: vault.pubKeyEdDSA, hexChainCode: vault.hexChainCode)
                            switch coinResult {
                                case .success(let sol):
                                    vault.coins.append(sol)
                                case .failure(let err):
                                    logger.info("fail to get solana address,error:\(err.localizedDescription)")
                            }
                        default:
                            print("do it later")
                    }
                }
            }
            for coin in vault.coins {
                if !selection.contains(where: { $0.ticker == coin.ticker }) {
                    vault.coins = vault.coins.filter { $0 != coin }
                }
            }
        }
    }
}
    //
    //#Preview {
    //    AssetsList()
    //}
