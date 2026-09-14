import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif
@testable import VultisigUIResources

final class RemoteImageFaviconTests: XCTestCase {
    func testICOLargestValidFrameIsNormalized() throws {
        let data = try ico(sizes: [16, 128, 32])
        assertNativeImage(data)
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        XCTAssertEqual(CGImageSourceGetCount(source), 3)
        XCTAssertEqual(data[6], 16) // The ICO directory deliberately lists the smallest frame first.
        let widths = try (0..<3).map { try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, $0, nil)).width }
        XCTAssertEqual(Set(widths), [16, 32, 128])
        let png = try RemoteImageLoader.thumbnail(data)
        try assertPNG(png, size: 128)
        try assertPNG(RemoteImageLoader.thumbnail(data, maximumPixelSize: 120), size: 120)
    }

    func testBMPIsNormalized() throws {
        let data = try raster(size: 64, type: .bmp)
        assertNativeImage(data)
        try assertPNG(RemoteImageLoader.thumbnail(data), size: 64)
    }

    func testBMPSourcePixelLimitIsPreserved() throws {
        let data = try raster(size: 2_001, type: .bmp)
        XCTAssertThrowsError(try RemoteImageLoader.thumbnail(data)) {
            XCTAssertEqual($0 as? RemoteImageError, .invalidImage)
        }
    }

    private func assertPNG(_ data: Data, size: Int) throws {
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        XCTAssertEqual(CGImageSourceGetType(source) as String?, UTType.png.identifier)
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertEqual(image.width, size)
        XCTAssertEqual(image.height, size)
        XCTAssertEqual(image.bitsPerComponent, 8)
        XCTAssertLessThanOrEqual(data.count, RemoteImageCache.maximumImageBytes)
    }

    private func assertNativeImage(_ data: Data) {
        #if canImport(UIKit)
        XCTAssertNotNil(UIImage(data: data))
        #elseif canImport(AppKit)
        XCTAssertNotNil(NSImage(data: data))
        #endif
    }

    private func ico(sizes: [Int]) throws -> Data {
        let frames = try sizes.map { try raster(size: $0, type: .png) }
        var data = Data([0, 0, 1, 0])
        append(UInt16(frames.count), to: &data)
        var offset = 6 + frames.count * 16
        for (size, frame) in zip(sizes, frames) {
            data.append(contentsOf: [UInt8(size == 256 ? 0 : size), UInt8(size == 256 ? 0 : size), 0, 0])
            append(UInt16(1), to: &data)
            append(UInt16(32), to: &data)
            append(UInt32(frame.count), to: &data)
            append(UInt32(offset), to: &data)
            offset += frame.count
        }
        for frame in frames { data.append(frame) }
        return data
    }

    private func append<Value: FixedWidthInteger>(_ value: Value, to data: inout Data) {
        var littleEndian = value.littleEndian
        withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
    }

    private func raster(size: Int, type: UTType) throws -> Data {
        let context = try XCTUnwrap(CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                                             bytesPerRow: size * 4, space: CGColorSpaceCreateDeviceRGB(),
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: size, height: size))
        let image = try XCTUnwrap(context.makeImage())
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }
}
