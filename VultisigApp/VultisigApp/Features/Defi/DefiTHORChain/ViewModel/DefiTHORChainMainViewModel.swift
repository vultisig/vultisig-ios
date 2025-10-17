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
    
    func moveToNextPosition() {
        let allPositions = THORChainPositionType.allCases
        let currentIndex = allPositions.firstIndex(of: selectedPosition) ?? 0
        let nextIndex = (currentIndex + 1) % allPositions.count
        selectedPosition = allPositions[nextIndex]
    }
    
    func moveToPreviousPosition() {
        let allPositions = THORChainPositionType.allCases
        let currentIndex = allPositions.firstIndex(of: selectedPosition) ?? 0
        let previousIndex = currentIndex == 0 ? allPositions.count - 1 : currentIndex - 1
        selectedPosition = allPositions[previousIndex]
    }
}
