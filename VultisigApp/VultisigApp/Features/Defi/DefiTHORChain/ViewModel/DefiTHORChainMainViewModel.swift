//
//  DefiTHORChainMainViewModel.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 17/10/2025.
//

import Foundation

final class DefiTHORChainMainViewModel: ObservableObject {
    @Published var selectedPosition: THORChainPositionType = .bond
    private(set) lazy var positions: [SegmentedControlItem<THORChainPositionType>] = THORChainPositionType.allCases.map { SegmentedControlItem(value: $0, title: $0.segmentedControlTitle) }
}
