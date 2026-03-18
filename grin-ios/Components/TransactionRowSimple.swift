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
//  TransactionRowSimple.swift
//  grin-ios
//

import SwiftUI

struct TransactionRowSimple: View {
    let transaction: Transaction
    let decimalPlaces: Int
    let dateFormat: DateFormatStyle

    private var amountPrefix: String {
        transaction.direction == .received ? "+" : ""
    }

    private var amountColor: Color {
        transaction.direction == .received ? .green : .primary
    }

    private var formattedAmount: String {
        String(format: "%.\(decimalPlaces)f", transaction.amount)
    }

    private var formattedDate: String {
        formatTransactionDate(transaction.date, style: dateFormat)
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(transaction.directionLabel)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.primary)
                Text(formattedDate)
                    .font(.system(size: 13))
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text("\(amountPrefix)\(formattedAmount)")
                    .font(.system(size: 17, weight: .semibold, design: .monospaced))
                    .foregroundStyle(amountColor)
                Text(transaction.status.rawValue)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.gray)
            }
        }
        .padding(.vertical, 10)
    }
}

#Preview {
    TransactionRowSimple(
        transaction: Transaction(
            numericId: 1, direction: .received, amount: 1.0,
            date: Date(), status: .confirmed, confirmations: 10, blockHeight: 100
        ),
        decimalPlaces: 2,
        dateFormat: .dmy
    )
    .padding()
    .background(.black)
    .preferredColorScheme(.dark)
}
