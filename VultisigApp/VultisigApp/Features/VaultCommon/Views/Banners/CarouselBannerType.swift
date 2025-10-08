//
//  CarouselBannerType.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 07/10/2025.
//

import Foundation

protocol CarouselBannerType: Identifiable, Hashable {
    var title: String { get }
    var subtitle: String { get }
    var buttonTitle: String { get }
}
