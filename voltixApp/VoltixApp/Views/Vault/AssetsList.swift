	//
	//  CoinsList.swift
	//  VoltixApp
	//

import OSLog
import SwiftData
import SwiftUI
import WalletCore
//TODO: Remove the old view
private let logger = Logger(subsystem: "assets-list", category: "view")
struct AssetsList: View {
	@EnvironmentObject var appState: ApplicationState
	@State private var assets: [Coin] = []
	@State private var selection = Set<Coin>()
	@State private var expandedGroups: Set<String> = Set()
	@State var editMode = EditMode.active
	
		// Computed property to group assets by chainName
	private var groupedAssets: [String: [Coin]] {
		Dictionary(grouping: assets) { $0.chain.name }
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
//			ForEach(groupedAssets.keys.sorted(), id: \.self) { chainName in
//				Section(header: HStack {
//					Text(chainName)
//					Spacer()
//					Image(systemName: expandedGroups.contains(chainName) ? "chevron.up" : "chevron.down")
//				}
//					.contentShape(Rectangle())
//					.onTapGesture {
//						if expandedGroups.contains(chainName) {
//							expandedGroups.remove(chainName)
//						} else {
//							expandedGroups.insert(chainName)
//						}
//					}
//				) {
//					if expandedGroups.contains(chainName) {
//						ForEach(groupedAssets[chainName] ?? [], id: \.self) { asset in
//							HStack {
//								Text("\(asset.chainName) - \(asset.ticker)")
//								Spacer()
//								if selection.contains(asset) {
//									Image(systemName: "checkmark")
//								}
//							}
//							.padding(.leading, asset.contractAddress != nil ? 20 : 0) // Add padding if it's a child token
//							.onTapGesture {
//								if selection.contains(asset) {
//									selection.remove(asset)
//								} else {
//									selection.insert(asset)
//								}
//							}
//						}
//					}
//				}
//			}
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
		
	}
}

#Preview {
	AssetsList()
	.environmentObject(ApplicationState())
}
