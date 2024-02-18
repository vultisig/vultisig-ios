//
//  Utils.swift
//  VoltixApp
//

import CryptoKit
import Foundation
import OSLog
#if os(iOS)
import UIKit
#endif

enum Utils {
    static let logger = Logger(subsystem: "util", category: "network")
    public static func sendRequest<T: Codable>(urlString: String, method: String, body: T?, completion: @escaping (Bool) -> Void) {
        logger.debug("url:\(urlString)")
        guard let url = URL(string: urlString) else {
            logger.error("URL can't be constructed from: \(urlString)")
            completion(false)
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
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

    public static func deleteFromServer(urlString: String) {
        guard let url = URL(string: urlString) else {
            logger.error("URL can't be constructed from: \(urlString)")
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        
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
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        for item in headers {
            request.addValue(item.key, forHTTPHeaderField: item.value)
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
    
    public static func getMessageBodyHash(msg: String) -> String {
        let digest = Insecure.MD5.hash(data: Data(msg.utf8))
        return digest.map {
            String(format: "%02hhx", $0)
        }.joined()
    }
    
    public static func isIOS() -> Bool {
        #if os(iOS)
        return true
        #else
        return false
        #endif
    }
    
    public static func getLocalDeviceIdentity() -> String {
        #if os(iOS)
        return UIDevice.current.name
        #else
        return ProcessInfo.processInfo.hostName
        #endif
    }
}
