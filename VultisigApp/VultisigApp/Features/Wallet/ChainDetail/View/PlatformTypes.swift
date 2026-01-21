//
//  PlatformTypes.swift
//  VultisigApp
//
//  Created by Assistant on 23/09/2025.
//

import Foundation

#if os(iOS)
import UIKit
public typealias PlatformImage = UIImage
#elseif os(macOS)
import AppKit
public typealias PlatformImage = NSImage
#endif
