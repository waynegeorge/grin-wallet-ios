// This file is part of Grin Wallet iOS.
//
// Copyright (C) 2026 Grin Works
//
// Grin Wallet iOS is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Grin Wallet iOS is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with Grin Wallet iOS. If not, see <https://www.gnu.org/licenses/>.

//
//  NodeConnection.swift
//  grin-ios
//

import Foundation

actor NodeConnection {
    private var baseURL: URL
    private var apiSecret: String?
    private let session: URLSession

    init(url: String = "http://grin-node.example.com:3413/v2/owner", apiSecret: String? = nil) {
        self.baseURL = URL(string: url)!
        self.apiSecret = apiSecret
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        self.session = URLSession(configuration: config)
    }

    func updateURL(_ url: String) {
        if let newURL = URL(string: url) {
            self.baseURL = newURL
        }
    }

    func updateSecret(_ secret: String?) {
        self.apiSecret = secret
    }

    // MARK: - JSON-RPC Call

    private func call<P: Encodable, R: Decodable>(method: String, params: P) async throws -> R {
        var request = URLRequest(url: baseURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let secret = apiSecret, !secret.isEmpty {
            let credentials = "grin:\(secret)"
            if let data = credentials.data(using: .utf8) {
                request.setValue("Basic \(data.base64EncodedString())", forHTTPHeaderField: "Authorization")
            }
        }

        let rpcRequest = JSONRPCRequest(id: 1, method: method, params: params)
        request.httpBody = try JSONEncoder().encode(rpcRequest)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw NodeError.httpError
        }

        let rpcResponse = try JSONDecoder().decode(JSONRPCResponse<R>.self, from: data)

        if let error = rpcResponse.error {
            throw NodeError.rpcError(code: error.code, message: error.message)
        }

        guard let result = rpcResponse.result else {
            throw NodeError.noResult
        }

        return result
    }

    // MARK: - Wallet Owner API

    func getWalletInfo() async throws -> [String: Any] {
        // Mock for now — returns empty dict
        return [:]
    }

    func initSendTx(amount: UInt64, minimumConfirmations: UInt64 = 10) async throws -> String {
        // Mock: return a fake slatepack string
        return Slatepack.mock(length: 300).fullString
    }

    func finalizeTx(slatepack: String) async throws -> String {
        // Mock: return finalized slatepack
        return Slatepack.mock(length: 200).fullString
    }

    func cancelTx(txId: UUID) async throws {
        // Mock: no-op
    }

    func retrieveTxs() async throws -> [String: Any] {
        // Mock
        return [:]
    }

    func checkNodeStatus() async -> NodeStatus {
        // Mock: always connected
        return .connected
    }
}

enum NodeError: Error, LocalizedError {
    case httpError
    case rpcError(code: Int, message: String)
    case noResult
    case invalidURL

    var errorDescription: String? {
        switch self {
        case .httpError: return "HTTP request failed"
        case .rpcError(_, let message): return "RPC error: \(message)"
        case .noResult: return "No result in response"
        case .invalidURL: return "Invalid node URL"
        }
    }
}
