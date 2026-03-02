//
//  PlatformTypes.swift
//  VultisigApp
//
//  Created by Assistant on 23/09/2025.
//

import Foundation

#if os(iOS)
import UIKit
typealias PlatformImage = UIImage
#elseif os(macOS)
import AppKit
typealias PlatformImage = NSImage
#endif
