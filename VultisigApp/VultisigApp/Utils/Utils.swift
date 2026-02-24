//
//  Utils.swift
//  VultisigApp
//

import BigInt
import CoreImage.CIFilterBuiltins
import CryptoKit
import Foundation
import OSLog
import SwiftUI

enum Utils {
    static let logger = Logger(subsystem: "util", category: "network")
    static let context = CIContext()
    static func sendRequest<T: Codable>(urlString: String, method: String, headers: [String: String]? = nil, body: T?, completion: @escaping (Bool) -> Void) {
        logger.debug("url:\(urlString)")
        guard let url = URL(string: urlString) else {
            logger.error("URL can't be constructed from: \(urlString)")
            completion(false)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        if let headers = headers {
            for item in headers {
                request.setValue(item.value, forHTTPHeaderField: item.key)
            }
        }
        if let body = body {
            do {
                let jsonData = try JSONEncoder().encode(body)
                request.httpBody = jsonData
            } catch {
                logger.error("Failed to encode body into JSON string: \(error)")
                completion(false)
                return
            }
        }

        URLSession.shared.dataTask(with: request) { _, response, error in
            if let error = error {
                self.logger.error("Failed to send request, error: \(error)")
                completion(false)
                return
            }

            guard let httpResponse = response as? HTTPURLResponse, (200 ... 299).contains(httpResponse.statusCode) else {
                self.logger.error("Invalid response code")
                completion(false)
                return
            }

            completion(true)
        }.resume()
    }

    static func deleteFromServer(urlString: String, headers: [String: String]) {
        guard let url = URL(string: urlString) else {
            logger.error("URL can't be constructed from: \(urlString)")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        for item in headers {
            request.setValue(item.value, forHTTPHeaderField: item.key)
        }

        URLSession.shared.dataTask(with: request) { _, response, error in
            if let error = error {
                self.logger.error("Failed to send request, error: \(error)")
                return
            }

            guard let httpResponse = response as? HTTPURLResponse, (200 ... 299).contains(httpResponse.statusCode) else {
                self.logger.error("Invalid response code")
                return
            }

        }.resume()
    }

    static func getRequest(urlString: String, headers: [String: String]?, completion: @escaping (Result<Data, Error>) -> Void) {
        guard let url = URL(string: urlString) else {
            completion(.failure(NSError(domain: "Invalid URL", code: 0, userInfo: nil)))
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let headers = headers {
            for item in headers {
                request.setValue(item.value, forHTTPHeaderField: item.key)
            }
        }
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                completion(.failure(NSError(domain: "Invalid response", code: 0, userInfo: nil)))
                return
            }
            switch httpResponse.statusCode {
            case 200 ... 299:
                guard let data = data else {
                    completion(.failure(NSError(domain: "No data available", code: 0, userInfo: nil)))
                    return
                }
                completion(.success(data))
            case 404: // success
                completion(.failure(NSError(domain: "Invalid response code", code: httpResponse.statusCode, userInfo: nil)))
                return
            default:
                completion(.failure(NSError(domain: "Invalid response code", code: httpResponse.statusCode, userInfo: nil)))
                return
            }

        }.resume()
    }

    static func fetchArray<T: Decodable>(from urlString: String) async throws -> [T] {
        do {
            let data = try await Utils.asyncGetRequest(urlString: urlString, headers: [:])
            return try JSONDecoder().decode([T].self, from: data)
        } catch let error as DecodingError {
            let errorDescription = handleJsonDecodingError(error)
            throw DecodingError.custom(description: errorDescription)
        } catch {
            throw error
        }
    }

    static func fetchObject<T: Decodable>(from urlString: String) async throws -> T {
        do {
            let data = try await Utils.asyncGetRequest(urlString: urlString, headers: [:])
            return try JSONDecoder().decode(T.self, from: data)
        } catch let error as DecodingError {
            let errorDescription = handleJsonDecodingError(error)
            throw DecodingError.custom(description: errorDescription)
        } catch {
            throw error
        }
    }

    static func asyncGetRequest(urlString: String, headers: [String: String]? = nil) async throws -> Data {
        guard let url = URL(string: urlString) else {
            throw NSError(domain: "Invalid URL", code: 0, userInfo: nil)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        if let headers = headers {
            for (key, value) in headers {
                request.addValue(value, forHTTPHeaderField: key)
            }
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "Invalid response", code: 0, userInfo: nil)
        }
        switch httpResponse.statusCode {
        case 200...299:
            return data
        case 404:
            throw NSError(domain: "Resource not found", code: httpResponse.statusCode, userInfo: nil)
        default:
            throw NSError(domain: "Invalid response code", code: httpResponse.statusCode, userInfo: nil)
        }
    }

    static func asyncPostRequest(urlString: String, headers: [String: String]?, body: Data) async throws -> Data {
        guard let url = URL(string: urlString) else {
            throw NSError(domain: "Invalid URL", code: 0, userInfo: nil)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        if let headers = headers {
            for (key, value) in headers {
                request.addValue(value, forHTTPHeaderField: key)
            }
        }
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "Invalid response", code: 0, userInfo: nil)
        }
        switch httpResponse.statusCode {
        case 200...299:
            return data
        case 404: // Consider if 404 should really be considered a success or not.
            throw NSError(domain: "Resource not found", code: httpResponse.statusCode, userInfo: nil)
        default:
            throw NSError(domain: "Unexpected response code", code: httpResponse.statusCode, userInfo: nil)
        }
    }

    static func getMessageBodyHash(msg: String) -> String {
        let digest = Insecure.MD5.hash(data: Data(msg.utf8))
        return digest.map {
            String(format: "%02hhx", $0)
        }.joined()
    }

    static func stringToHex(_ input: String) -> String {
        input.utf8.map { String(format: "%02x", $0) }.joined()
    }

    static func getQrImage(data: Any?, size: CGFloat) -> Image {
        let context = CIContext()
        guard let qrFilter = CIFilter(name: "CIQRCodeGenerator") else {
            return Image(systemName: "xmark")
        }
        qrFilter.setValue(data, forKey: "inputMessage")
        guard let qrCodeImage = qrFilter.outputImage else {
            return Image(systemName: "xmark")
        }

        let transformedImage = qrCodeImage.transformed(by: CGAffineTransform(scaleX: size, y: size))
        guard let cgImage = context.createCGImage(transformedImage, from: transformedImage.extent) else {
            return Image(systemName: "xmark")
        }

        return Image(cgImage, scale: 1.0, orientation: .up, label: Text("QRCode"))
    }

    static func parseCryptoURI(_ uri: String) -> (address: String, amount: String, message: String) {

        var address: String = .empty
        var amount: String = .empty
        var message: String = .empty

        if uri.hasPrefix("ton://") {
            guard let url = URLComponents(string: uri) else {
                print("invalid URI")
                return (.empty, .empty, .empty)
            }

            if url.host == "transfer" {
                let path = url.path
                address = path.hasPrefix("/") ? String(path.dropFirst()) : path
            } else {
                address = url.host ?? ""
            }

            url.queryItems?.forEach { item in
                switch item.name {
                case "text":
                    if let value = item.value, !value.isEmpty {
                        message = value
                    }
                case "amount":
                    amount = item.value ?? ""
                default:
                    print("Unknown query item: \(item.name)")
                }
            }
        } else {

            guard let url = URLComponents(string: uri) else {
                print("Invalid URI")
                return (.empty, .empty, .empty)
            }

            address = url.host ?? url.path

            url.queryItems?.forEach { item in
                switch item.name {
                case "amount":
                    amount = item.value ?? ""
                case "label", "message":
                    if let value = item.value, !value.isEmpty {
                        message += (message.isEmpty ? "" : " ") + value
                    }
                default:
                    print("Unknown query item: \(item.name)")
                }
            }
        }
        return (address, amount, message)
    }

    static func isIOS() -> Bool {
        return true
    }

    static func handleJsonDecodingError(_ error: Error) -> String {
        let errorDescription: String
        switch error {
        case let DecodingError.dataCorrupted(context):
            errorDescription = "Data corrupted: \(context)"
        case let DecodingError.keyNotFound(key, context):
            errorDescription = "Key '\(key)' not found: \(context.debugDescription), path: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))"
        case let DecodingError.valueNotFound(value, context):
            errorDescription = "Value '\(value)' not found: \(context.debugDescription), path: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))"
        case let DecodingError.typeMismatch(type, context):
            let path = context.codingPath.map { $0.stringValue }.joined(separator: ".")
            errorDescription = "Type '\(type)' mismatch: \(context.debugDescription), path: \(path)"
        default:
            errorDescription = "Error: \(error.localizedDescription)"
        }

        return errorDescription
    }

    static func getChainCode() -> String? {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)

        guard status == errSecSuccess else {
            print("Error generating random bytes: \(status)")
            return nil
        }

        return bytesToHexString(bytes)
    }

    static func bytesToHexString(_ bytes: [UInt8]) -> String {
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    static func extractResultFromJson<T: Decodable>(fromData data: Data, path: String) -> T? {
        do {
            let json = try JSONSerialization.jsonObject(with: data, options: []) as? NSDictionary
            if let result = getValueFromJson(for: path, in: json) {
                let resultData = try JSONSerialization.data(withJSONObject: result)
                return try JSONDecoder().decode(T.self, from: resultData)
            }
        } catch {
            print("Error processing JSON: \(error)")
        }
        return nil
    }

    static func extractResultFromJson<T: Decodable>(fromData data: Data, path: String, type: T.Type, mustHaveFields: [String] = []) -> [T]? {
        do {
            let json = try JSONSerialization.jsonObject(with: data, options: []) as? NSDictionary
            if let result = getValueFromJson(for: path, in: json) as? [NSDictionary] {
                var filteredResults: [T] = []
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .secondsSince1970
                decoder.nonConformingFloatDecodingStrategy = .convertFromString(
                    positiveInfinity: "Infinity",
                    negativeInfinity: "-Infinity",
                    nan: "NaN"
                )

                for item in result {
                    var hasAllFields = true
                    for field in mustHaveFields {
                        if let value = item.value(forKeyPath: field) as? String, value.isEmpty {
                            hasAllFields = false
                            break
                        } else if item.value(forKeyPath: field) == nil {
                            hasAllFields = false
                            break
                        }
                    }
                    if hasAllFields {
                        let resultData = try JSONSerialization.data(withJSONObject: item)
                        if let decodedItem = try? decoder.decode(T.self, from: resultData) {
                            filteredResults.append(decodedItem)
                        }
                    }
                }
                return filteredResults
            }
        } catch let DecodingError.dataCorrupted(context) {
            print("Error processing JSON: dataCorrupted \(context)")
        } catch let DecodingError.keyNotFound(key, context) {
            print("Error processing JSON: keyNotFound \(key) \(context)")
        } catch let DecodingError.typeMismatch(type, context) {
            print("Error processing JSON: typeMismatch \(type) \(context)")
        } catch let DecodingError.valueNotFound(value, context) {
            print("Error processing JSON: valueNotFound \(value) \(context)")
        } catch {
            print("Error processing JSON: \(error)")
        }
        return nil
    }

    static func extractResultFromJson(fromData data: Data, path: String) -> Any? {
        do {
            let json = try JSONSerialization.jsonObject(with: data, options: []) as? NSDictionary
            return getValueFromJson(for: path, in: json)
        } catch {
            print("JSON decoding error: \(error)")
        }
        return nil
    }

    static func getValueFromJson(for path: String, in dictionary: NSDictionary?) -> Any? {
        guard let dictionary = dictionary else { return nil }

        if path.contains(".") {
            let keys = path.components(separatedBy: ".")

            var currentResult: Any? = dictionary
            for key in keys {
                if let dict = currentResult as? NSDictionary {
                    currentResult = dict[key]
                } else {
                    return nil
                }
            }
            return currentResult
        } else {
            return dictionary[path]
        }
    }

    static func isCacheValid<T>(for key: String, in cache: [String: (data: T, timestamp: Date)], timeInSeconds: Double) -> Bool {
        guard let cacheEntry = cache[key] else { return false }
        let elapsedTime = Date().timeIntervalSince(cacheEntry.timestamp)
        return elapsedTime <= timeInSeconds
    }

    static func getCachedData<T>(cacheKey: String, cache: [String: (data: T, timestamp: Date)], timeInSeconds: TimeInterval) -> T? {
        if let cacheEntry = cache[cacheKey], isCacheValid(for: cacheKey, in: cache, timeInSeconds: timeInSeconds) {
            return cacheEntry.data
        } else {
            return nil
        }
    }

    static func getCachedData<T>(cacheKey: String, cache: ThreadSafeDictionary<String, (data: T, timestamp: Date)>, timeInSeconds: TimeInterval) -> T? {
        if let cacheEntry = cache.get(cacheKey), isCacheValid(entry: cacheEntry, timeInSeconds: timeInSeconds) {
            return cacheEntry.data
        } else {
            return nil
        }
    }

    static func isCacheValid<T>(entry: (data: T, timestamp: Date), timeInSeconds: TimeInterval) -> Bool {
        let elapsedTime = Date().timeIntervalSince(entry.timestamp)
        return elapsedTime < timeInSeconds
    }

    static func PostRequestRpc(rpcURL: URL, method: String, params: [Any?]) async throws -> Data {
        var request = URLRequest(url: rpcURL)
        request.httpMethod = "POST"

        let requestBody: [String: Any] = [
            "jsonrpc": "2.0",
            "id": 1,
            "method": method,
            "params": params
        ]

        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody, options: [])
        let (data, _) = try await URLSession.shared.data(for: request)
        return data
    }

    static func generateQRCodeImage(from string: String, tint: Color = .white, background: Color = .clear) -> Image {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        defer {
            context.clearCaches()
        }

#if os(iOS)
        let tintColor = UIColor(tint)
        let backgroundColor = UIColor(background)

        if let outputImage = filter.outputImage?.applyingFilter("CIFalseColor", parameters: [
            "inputColor0": CIColor(color: tintColor),
            "inputColor1": CIColor(color: backgroundColor)
        ]) {
            if let cgImage = context.createCGImage(outputImage, from: outputImage.extent) {
                return Image(uiImage: UIImage(cgImage: cgImage))
                    .interpolation(.none)

            }
        }

        let image = UIImage(systemName: "xmark.circle") ?? UIImage()
        return Image(uiImage: image)
            .interpolation(.none)
#elseif os(macOS)
        let tintColor = NSColor(tint)
        let backgroundColor = NSColor(background)

        let scale = 1024 / filter.outputImage!.extent.size.width
        let transform = CGAffineTransform(scaleX: scale, y: scale)

        if let outputImage = filter.outputImage?.samplingNearest()
            .applyingFilter("CIFalseColor", parameters: [
                "inputColor0": CIColor(color: tintColor) ?? .black,
                "inputColor1": CIColor(color: backgroundColor) ?? .white
            ])
                .transformed(by: transform) {
            if let cgImage = context.createCGImage(outputImage, from: outputImage.extent) {
                return Image(nsImage: NSImage(cgImage: cgImage, size: CGSize(width: 1024, height: 1024)))
                    .interpolation(.none)
            }
        }

        let image = NSImage(systemSymbolName: "xmark.circle", accessibilityDescription: nil) ?? NSImage()
        return Image(nsImage: image)
            .interpolation(.none)
#endif
    }

#if os(iOS)
    static func handleQrCodeFromImage(image: UIImage) -> Data {
        let qrStrings = detectQRCode(image)
        if qrStrings.isEmpty {
            print("No QR codes detected.")
            return Data()
        } else {
            for qrString in qrStrings {
                if let data = qrString.data(using: .utf8) {
                    return data
                }
            }
        }
        return Data()
    }

    static func detectQRCode(_ image: UIImage?) -> [String] {
        var detectedStrings = [String]()
        guard let image = image, let ciImage = CIImage(image: image) else { return detectedStrings }

        let context = CIContext()
        let options = [CIDetectorAccuracy: CIDetectorAccuracyHigh]
        let qrDetector = CIDetector(ofType: CIDetectorTypeQRCode, context: context, options: options)

        if let features = qrDetector?.features(in: ciImage) {
            for feature in features as! [CIQRCodeFeature] {
                if let decodedString = feature.messageString {
                    detectedStrings.append(decodedString)
                }
            }
        }

        return detectedStrings
    }

#elseif os(macOS)
    static func handleQrCodeFromImage(image: NSImage) -> Data {
        let qrStrings = detectQRCode(image)
        if qrStrings.isEmpty {
            print("No QR codes detected.")
            return Data()
        } else {
            for qrString in qrStrings {
                if let data = qrString.data(using: .utf8) {
                    return data
                }
            }
        }
        return Data()
    }

    static func detectQRCode(_ image: NSImage?) -> [String] {
        var detectedStrings = [String]()

        guard let image = image else {
            return detectedStrings
        }

        var imageRect = CGRect(x: 0, y: 0, width: image.size.width, height: image.size.height)
        let imageRef = image.cgImage(forProposedRect: &imageRect, context: nil, hints: nil)

        guard let ciImage = imageRef else {
            return detectedStrings
        }

        let context = CIContext()
        let options = [CIDetectorAccuracy: CIDetectorAccuracyHigh]
        let qrDetector = CIDetector(ofType: CIDetectorTypeQRCode, context: context, options: options)

        if let features = qrDetector?.features(in: CIImage(cgImage: ciImage)) {
            for feature in features as! [CIQRCodeFeature] {
                if let decodedString = feature.messageString {
                    detectedStrings.append(decodedString)
                }
            }
        }

        return detectedStrings
    }

    static func getUniqueIdentifier() -> String {
        let userDefaults = UserDefaults.standard
        let uuidKey = "com.vultisig.wallet"

        // Check if a UUID already exists in UserDefaults
        if let uuid = userDefaults.string(forKey: uuidKey) {
            return uuid
        } else {
            // Generate a new UUID and store it in UserDefaults
            let newUUID = NSUUID().uuidString
            userDefaults.set(newUUID, forKey: uuidKey)
            return newUUID
        }
    }
#endif

    static func handleQrCodeFromImage(result: Result<[URL], Error>) throws -> Data {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return Data() }
            let success = url.startAccessingSecurityScopedResource()
            defer { url.stopAccessingSecurityScopedResource() }

#if os(iOS)
            guard success else {
                print("Failed to access URL")
                throw UtilsQrCodeFromImageError.URLInaccessible
            }

            if let imageData = try? Data(contentsOf: url), let selectedImage = UIImage(data: imageData) {
                let qrStrings = Utils.detectQRCode(selectedImage)

                if qrStrings.isEmpty {
                    print("No QR codes detected.")
                    throw UtilsQrCodeFromImageError.NoQRCodesDetected
                } else {
                    for qrString in qrStrings {
                        return qrString.data(using: .utf8) ?? Data()
                    }
                }
            } else {
                print("Failed to load image from URL")
                throw UtilsQrCodeFromImageError.FailedToLoadImage
            }
#elseif os(macOS)
            if let imageData = try? Data(contentsOf: url), let selectedImage = NSImage(data: imageData) {
                let qrStrings = Utils.detectQRCode(selectedImage)

                if qrStrings.isEmpty {
                    print("No QR codes detected.")
                    throw UtilsQrCodeFromImageError.NoQRCodesDetected
                } else {
                    for qrString in qrStrings {
                        return qrString.data(using: .utf8) ?? Data()
                    }
                }
            } else {
                print("Failed to load image from URL")
                throw UtilsQrCodeFromImageError.FailedToLoadImage
            }
#endif

        case .failure(let error):
            print("Error selecting file: \(error.localizedDescription)")
        }
        return Data()
    }

    static func getLocalDeviceIdentity() -> String {
#if os(iOS)
        let identifierForVendor = UIDevice.current.identifierForVendor?.uuidString
        let parts = identifierForVendor?.components(separatedBy: "-")
        return "\(getDeviceName())-\(parts?.last?.suffix(3) ?? "N/A")"
#elseif os(macOS)
        let identifierForVendor = Utils.getUniqueIdentifier()
        return "\(getDeviceName())-\(identifierForVendor.suffix(3))"
#endif
    }

    static func getDeviceName() -> String {
#if os(iOS)
        return UIDevice.current.name
#elseif os(macOS)
        return Host.current().localizedName ?? "Mac"
#endif
    }

    static func sanitizeAddress(address: String) -> String {
        let sanitizedAddress = address
        if sanitizedAddress.hasPrefix("ethereum:") {
            return String(sanitizedAddress.dropFirst(9))
        }

        return sanitizedAddress
    }
}
