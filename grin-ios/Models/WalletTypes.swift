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
//  WalletTypes.swift
//  grin-ios
//

import Foundation

// MARK: - Wallet Info

struct WalletInfo {
    let lastConfirmedHeight: UInt64
    let minimumConfirmations: UInt64
    let totalBalance: Double
    let amountAwaitingConfirmation: Double
    let amountAwaitingFinalization: Double
    let amountCurrentlySpendable: Double
    let amountImmature: Double
    let amountLocked: Double
}

// MARK: - Slate

struct Slate: Identifiable, Codable {
    let id: UUID
    let versionInfo: SlateVersionInfo
    let amount: UInt64
    let fee: UInt64
    let height: UInt64
    let lock_height: UInt64
    let participantData: [ParticipantData]
    let status: SlateStatus

    var amountGrin: Double {
        Double(amount) / 1_000_000_000.0
    }

    var feeGrin: Double {
        Double(fee) / 1_000_000_000.0
    }
}

struct SlateVersionInfo: Codable {
    let version: UInt16
    let blockHeaderVersion: UInt16
}

struct ParticipantData: Codable {
    let id: UInt64
    let publicBlindExcess: String
    let publicNonce: String
    let partSig: String?
    let message: String?
}

enum SlateStatus: String, Codable {
    case standard1 = "S1"
    case standard2 = "S2"
    case standard3 = "S3"
    case invoice1 = "I1"
    case invoice2 = "I2"
    case invoice3 = "I3"
}

// MARK: - Slatepack

struct Slatepack {
    let header: String
    let payload: String
    let footer: String
    /// The original, unmodified slatepack string from the FFI or network.
    /// Always use this for FFI calls and sharing — never reconstruct from parts.
    let rawString: String?

    var fullString: String {
        rawString ?? "\(header) \(payload) \(footer)"
    }

    var truncated: String {
        let clean = payload.replacingOccurrences(of: "\n", with: "")
        if clean.count <= 44 {
            return clean
        }
        return String(clean.prefix(20)) + "..." + String(clean.suffix(20))
    }

    static func mock(length: Int = 200) -> Slatepack {
        let chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
        let payload = String((0..<length).map { _ in chars.randomElement()! })
        let raw = "BEGINSLATEPACK. \(payload) . ENDSLATEPACK."
        return Slatepack(
            header: "BEGINSLATEPACK.",
            payload: payload,
            footer: ". ENDSLATEPACK.",
            rawString: raw
        )
    }
}

// MARK: - Node Status

enum NodeStatus: String {
    case connected = "Connected"
    case disconnected = "Disconnected"
    case syncing = "Syncing"

    var iconName: String {
        switch self {
        case .connected: return "circle.fill"
        case .disconnected: return "circle.fill"
        case .syncing: return "arrow.triangle.2.circlepath"
        }
    }
}

// MARK: - Nearby Peer

struct NearbyPeer: Identifiable {
    let id: String
    let displayName: String
    var status: PeerStatus

    enum PeerStatus: String {
        case found = "Found"
        case connecting = "Connecting"
        case connected = "Connected"
        case transferring = "Transferring"
    }
}

// MARK: - JSON-RPC

struct JSONRPCRequest<T: Encodable>: Encodable {
    let jsonrpc: String = "2.0"
    let id: Int
    let method: String
    let params: T
}

struct JSONRPCResponse<T: Decodable>: Decodable {
    let jsonrpc: String
    let id: Int
    let result: T?
    let error: JSONRPCError?
}

struct JSONRPCError: Decodable {
    let code: Int
    let message: String
}
