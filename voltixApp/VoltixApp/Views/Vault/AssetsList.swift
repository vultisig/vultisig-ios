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
        Asset(ticker: "BTC", chainName: "Bitcoin", image: "btc"),
        Asset(ticker: "ETH", chainName: "Ethereum", image: "eth"),
        Asset(ticker: "RUNE", chainName: "THORChain", image: "rune"),
        Asset(ticker: "USDC", chainName: "Ethereum", image: "usdc")
    ]
    @State private var selection = Set<Asset>()
    @State var editMode = EditMode.active
    var body: some View {
        List(assets, id: \.self, selection: $selection) { c in
            HStack {
                Text("\(c.chainName) - \(c.ticker)")
            }
        }
        .environment(\.editMode, $editMode)
        .navigationTitle("select assets")
        .onAppear {
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
                                        let newCoin = Coin(chain: coin.chain, ticker: item.ticker, logo: item.image, address: coin.address, hexPublicKey: coin.hexPublicKey)
                                        vault.coins.append(newCoin)
                                    }
                                case .failure(let error):
                                    logger.info("fail to get ethereum address,error:\(error.localizedDescription)")
                            }
                        case Chain.Bitcoin.name:
                            let coinResult = BitcoinHelper.getBitcoin(hexPubKey: vault.pubKeyECDSA, hexChainCode: vault.hexChainCode)
                            switch coinResult {
                                case .success(let btc):
                                    vault.coins.append(btc)
                                case .failure(let err):
                                    logger.info("fail to get bitcoin address,error:\(err.localizedDescription)")
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

#Preview {
    AssetsList()
}
