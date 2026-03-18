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
//  Transaction.swift
//  grin-ios
//

import Foundation

enum TransactionDirection: String, Codable {
    case sent
    case received
}

enum TransactionStatus: String, Codable {
    case confirmed = "Confirmed"
    case confirming = "Confirming"
    case incomplete = "Incomplete"
}

struct Transaction: Identifiable, Codable {
    var id: Int { numericId }
    let numericId: Int
    let direction: TransactionDirection
    let amount: Double
    let date: Date
    let status: TransactionStatus
    let confirmations: Int
    let blockHeight: Int?
    let txId: String
    let fee: Double
    let kernelExcess: String?
    let slateId: String?
    let txType: String?
    let isInvoice: Bool

    var directionLabel: String {
        let base = direction == .sent ? "Sent" : "Received"
        return isInvoice ? "\(base) (Invoice)" : base
    }

    init(
        numericId: Int = -1,
        direction: TransactionDirection,
        amount: Double,
        date: Date,
        status: TransactionStatus,
        confirmations: Int,
        blockHeight: Int?,
        fee: Double = 0.001,
        txId: String? = nil,
        kernelExcess: String? = nil,
        slateId: String? = nil,
        txType: String? = nil,
        isInvoice: Bool = false
    ) {
        self.numericId = numericId
        self.direction = direction
        self.amount = amount
        self.date = date
        self.status = status
        self.confirmations = confirmations
        self.blockHeight = blockHeight
        self.fee = fee
        self.txId = txId ?? String(UUID().uuidString.prefix(16).lowercased())
        self.kernelExcess = kernelExcess
        self.slateId = slateId
        self.txType = txType
        self.isInvoice = isInvoice
    }
}

// MARK: - Wallet Output

enum OutputStatus: String {
    case unconfirmed = "Unconfirmed"
    case unspent = "Unspent"
    case locked = "Locked"
    case spent = "Spent"
    case reverted = "Reverted"
}

struct WalletOutput: Identifiable {
    var id: String { commit }
    let commit: String
    let value: UInt64
    let status: OutputStatus
    let height: UInt64
    let lockHeight: UInt64
    let isCoinbase: Bool
    let txLogEntry: Int?
    let nChild: Int
    let mmrIndex: UInt64?

    var amountGrin: Double {
        Double(value) / 1_000_000_000.0
    }
}

// MARK: - Transaction Date Formatting

func formatTransactionDate(_ date: Date, style: DateFormatStyle) -> String {
    let calendar = Calendar.current
    let now = Date()

    if calendar.isDateInToday(date) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    if calendar.isDateInYesterday(date) {
        return "Yesterday"
    }

    let daysAgo = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day ?? 0
    if daysAgo >= 2 && daysAgo <= 6 {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        return formatter.string(from: date)
    }

    let formatter = DateFormatter()
    formatter.dateFormat = style == .dmy ? "dd/MM/yyyy" : "MM/dd/yyyy"
    return formatter.string(from: date)
}
