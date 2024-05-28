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
import UIKit

enum Utils {
    static let logger = Logger(subsystem: "util", category: "network")
    public static func sendRequest<T: Codable>(urlString: String, method: String,headers: [String: String], body: T?, completion: @escaping (Bool) -> Void) {
        logger.debug("url:\(urlString)")
        guard let url = URL(string: urlString) else {
            logger.error("URL can't be constructed from: \(urlString)")
            completion(false)
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        for item in headers {
            request.setValue(item.value, forHTTPHeaderField: item.key)
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
    
    public static func deleteFromServer(urlString: String, headers: [String: String]) {
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
    
    public static func getRequest(urlString: String, headers: [String: String], completion: @escaping (Result<Data, Error>) -> Void) {
        guard let url = URL(string: urlString) else {
            completion(.failure(NSError(domain: "Invalid URL", code: 0, userInfo: nil)))
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for item in headers {
            request.setValue(item.value, forHTTPHeaderField: item.key)
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
    
    
    public static func asyncGetRequest(urlString: String, headers: [String: String]) async throws -> Data {
        guard let url = URL(string: urlString) else {
            throw NSError(domain: "Invalid URL", code: 0, userInfo: nil)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        for (key, value) in headers {
            request.addValue(value, forHTTPHeaderField: key)
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
    
    public static func asyncPostRequest(urlString: String, headers: [String: String], body: Data) async throws -> Data {
        guard let url = URL(string: urlString) else {
            throw NSError(domain: "Invalid URL", code: 0, userInfo: nil)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        for (key, value) in headers {
            request.addValue(value, forHTTPHeaderField: key)
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
    
    public static func getMessageBodyHash(msg: String) -> String {
        let digest = Insecure.MD5.hash(data: Data(msg.utf8))
        return digest.map {
            String(format: "%02hhx", $0)
        }.joined()
    }
    
    public static func stringToHex(_ input: String) -> String {
        input.utf8.map { String(format: "%02x", $0) }.joined()
    }
    
    public static func generateQRCodeImage(from string: String) -> Image {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        
        if let outputImage = filter.outputImage {
            if let cgImage = context.createCGImage(outputImage, from: outputImage.extent) {
                return Image(uiImage: UIImage(cgImage: cgImage))
                    .interpolation(.none)
            }
        }
        
        let image = UIImage(systemName: "xmark.circle") ?? UIImage()
        return Image(uiImage: image)
            .interpolation(.none)
    }
    
    public static func getQrImage(data: Any?, size: CGFloat) -> Image {
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
    
    public static func parseCryptoURI(_ uri: String) -> (address: String, amount: String, message: String){
        
        var address: String = .empty
        var amount: String = .empty
        var message: String = .empty
        
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
        return (address, amount, message)
    }
    
    public static func handleQrCodeFromImage(result: Result<[URL], Error>) -> Data{
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return Data() }
            let success = url.startAccessingSecurityScopedResource()
            defer { url.stopAccessingSecurityScopedResource() }
            
            guard success else {
                print("Failed to access URL")
                return Data()
            }
            
            if let imageData = try? Data(contentsOf: url),
               let selectedImage = UIImage(data: imageData) {
                let qrStrings = Utils.detectQRCode(selectedImage)
                if qrStrings.isEmpty {
                    print("No QR codes detected.")
                } else {
                    for qrString in qrStrings {
                        return qrString.data(using: .utf8) ?? Data()
                    }
                }
            } else {
                print("Failed to load image from URL")
            }
            
        case .failure(let error):
            print("Error selecting file: \(error.localizedDescription)")
        }
        return Data()
    }
    
    public static func handleQrCodeFromImage(image: UIImage) -> Data {
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
    
    public static func detectQRCode(_ image: UIImage?) -> [String] {
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
    
    public static func isIOS() -> Bool {
        return true
    }
    
    public static func getLocalDeviceIdentity() -> String {
        let identifierForVendor = UIDevice.current.identifierForVendor?.uuidString
        let parts = identifierForVendor?.components(separatedBy: "-")
        return "\(getDeviceName())-\(parts?.last?.suffix(3) ?? "N/A")"
    }
    
    public static func getDeviceName() -> String {
        let device = UIDevice.current.name
        let deviceName: String
        
        if ProcessInfo.processInfo.isiOSAppOnMac {
            deviceName = "Mac"
        }
        else {
            deviceName = device
        }
        return deviceName
    }
    
    public static func handleJsonDecodingError(_ error: Error) -> String {
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
    
    public static func getChainCode() -> String? {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        
        guard status == errSecSuccess else {
            print("Error generating random bytes: \(status)")
            return nil
        }
        
        return bytesToHexString(bytes)
    }
    
    public static func bytesToHexString(_ bytes: [UInt8]) -> String {
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
    
    public static func extractResultFromJson<T: Decodable>(fromData data: Data, path: String, type: T.Type) -> T? {
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
    
    public static func extractResultFromJson(fromData data: Data, path: String) -> Any? {
        do {
            let json = try JSONSerialization.jsonObject(with: data, options: []) as? NSDictionary
            return getValueFromJson(for: path, in: json)
        } catch {
            print("JSON decoding error: \(error)")
        }
        return nil
    }
    
    public static func getValueFromJson(for path: String, in dictionary: NSDictionary?) -> Any? {
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
    
    
    public static func isCacheValid<T>(for key: String, in cache: [String: (data: T, timestamp: Date)], timeInSeconds: Double) -> Bool {
        guard let cacheEntry = cache[key] else { return false }
        let elapsedTime = Date().timeIntervalSince(cacheEntry.timestamp)
        return elapsedTime <= timeInSeconds
    }
    
    public static func getCachedData<T>(cacheKey: String, cache: [String: (data: T, timestamp: Date)], timeInSeconds: TimeInterval) async  -> T? {
        if let cacheEntry = cache[cacheKey], isCacheValid(for: cacheKey, in: cache, timeInSeconds: timeInSeconds) {
            return cacheEntry.data
        } else {
            return nil
        }
    }
    
    public static func getCachedData<T>(cacheKey: String, cache: ThreadSafeDictionary<String, (data: T, timestamp: Date)>, timeInSeconds: TimeInterval) async -> T? {
        if let cacheEntry = cache.get(cacheKey), isCacheValid(for: cacheKey, entry: cacheEntry, timeInSeconds: timeInSeconds) {
            return cacheEntry.data
        } else {
            return nil
        }
    }
    
    public static func isCacheValid<T>(for cacheKey: String, entry: (data: T, timestamp: Date), timeInSeconds: TimeInterval) -> Bool {
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
    //RPC
    
    
    
}
