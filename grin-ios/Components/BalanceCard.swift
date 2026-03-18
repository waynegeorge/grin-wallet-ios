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
//  BalanceCard.swift
//  grin-ios
//

import SwiftUI

struct BalanceCard: View {
    let balance: Double
    let balanceFiat: Double
    let currency: Currency
    let decimalPlaces: Int
    @Binding var showGrinAsPrimary: Bool

    private var formattedBalance: String {
        String(format: "%.\(decimalPlaces)f", balance)
    }

    var body: some View {
        VStack(spacing: 8) {
            Text("TESTNET")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .tracking(2)

            if showGrinAsPrimary {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(formattedBalance)
                        .font(.system(size: 42, weight: .bold, design: .monospaced))
                        .foregroundStyle(.primary)
                    Text("TGRIN")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.secondary)
                }

                Text("≈ \(currency.symbol)\(String(format: "%.2f", balanceFiat)) \(currency.rawValue)")
                    .font(.system(size: 14))
                    .foregroundStyle(.tertiary)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(currency.symbol)
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(.primary)
                    Text(String(format: "%.2f", balanceFiat))
                        .font(.system(size: 42, weight: .bold, design: .monospaced))
                        .foregroundStyle(.primary)
                    Text(currency.rawValue)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.secondary)
                }

                Text("≈ \(formattedBalance) GRIN")
                    .font(.system(size: 14))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .padding(.horizontal, 16)
        .overlay(alignment: .bottomTrailing) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showGrinAsPrimary.toggle()
                }
            } label: {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(10)
            }
        }
        .background {
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(.secondarySystemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(.primary.opacity(0.1), lineWidth: 1)
                )
        }
    }
}

#Preview {
    BalanceCard(
        balance: 2.5,
        balanceFiat: 0.14,
        currency: .gbp,
        decimalPlaces: 2,
        showGrinAsPrimary: .constant(true)
    )
    .padding()
    .background(.black)
    .preferredColorScheme(.dark)
}
