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
//  TransactionRow.swift
//  grin-ios
//

import SwiftUI

struct TransactionRow: View {
    let transaction: Transaction
    let decimalPlaces: Int
    let advancedMode: Bool
    let dateFormat: DateFormatStyle
    var onCancel: (() -> Void)? = nil
    @State private var isExpanded = false
    @State private var showDeleteConfirmation = false

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

    private var fullDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: transaction.date)
    }

    var body: some View {
        VStack(spacing: 0) {
            Button {
                isExpanded.toggle()
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(transaction.direction == .sent ? "Sent" : "Received")
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

                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
                .padding(.vertical, 10)
                .contentShape(Rectangle())
                .animation(nil, value: isExpanded)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 10) {
                Divider().overlay(.primary.opacity(0.1))

                DetailRow(label: "Date", value: fullDate)
                DetailRow(label: "Amount", value: "\(String(format: "%.4f", transaction.amount)) ツ")
                if transaction.direction == .sent {
                    DetailRow(label: "Fee", value: "\(String(format: "%.4f", transaction.fee)) ツ")
                }
                DetailRow(label: "Status", value: transaction.status.rawValue)

                if transaction.status != .incomplete {
                    DetailRow(label: "Confirmations", value: "\(transaction.confirmations)")
                }

                if let blockHeight = transaction.blockHeight {
                    DetailRow(label: "Block Height", value: "\(blockHeight)")
                }

                if let slateId = transaction.slateId {
                    DetailRow(label: "Slate ID", value: slateId, monospace: true, copyable: true)
                }

                if let kernelExcess = transaction.kernelExcess, !kernelExcess.isEmpty {
                    DetailRow(label: "Kernel", value: kernelExcess, monospace: true, copyable: true)

                    if transaction.status == .incomplete {
                        Button(role: .destructive) {
                            showDeleteConfirmation = true
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "trash")
                                    .font(.system(size: 12))
                                Text("Delete Transaction")
                                    .font(.system(size: 12, weight: .medium))
                            }
                        }
                    } else {
                        Link(destination: URL(string: "https://testnet.grincoin.org/kernel/\(kernelExcess)")!) {
                            HStack(spacing: 6) {
                                Image(systemName: "safari")
                                    .font(.system(size: 12))
                                Text("View on Explorer")
                                    .font(.system(size: 12, weight: .medium))
                            }
                            .foregroundStyle(.blue)
                        }
                    }
                } else if transaction.status == .incomplete {
                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "trash")
                                .font(.system(size: 12))
                            Text("Delete Transaction")
                                .font(.system(size: 12, weight: .medium))
                        }
                    }
                }

                if advancedMode {
                    DetailRow(label: "Tx ID", value: transaction.txId, monospace: true)
                    if let txType = transaction.txType {
                        DetailRow(label: "Type", value: txType, monospace: true)
                    }
                }
            }
            .padding(.leading, 0)
            .padding(.bottom, 12)
            .allowsHitTesting(isExpanded)
            .frame(maxHeight: isExpanded ? nil : 0, alignment: .top)
            .clipped()
            .animation(.easeInOut(duration: 0.2), value: isExpanded)
        }
        .alert(
            "Delete Transaction",
            isPresented: $showDeleteConfirmation
        ) {
            Button("Delete", role: .destructive) {
                onCancel?()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This incomplete transaction will be removed from your wallet.")
        }
    }
}

private struct DetailRow: View {
    let label: String
    let value: String
    var monospace: Bool = false
    var copyable: Bool = false

    @State private var copied = false

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Spacer()
            if copyable {
                Button {
                    UIPasteboard.general.string = value
                    withAnimation { copied = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        withAnimation { copied = false }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(value.count > 20 ? String(value.prefix(10)) + "…" + String(value.suffix(8)) : value)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 10))
                            .foregroundStyle(copied ? .green : .secondary)
                    }
                }
                .buttonStyle(.plain)
            } else {
                Text(value)
                    .font(.system(size: 12, design: monospace ? .monospaced : .default))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
        }
    }
}

#Preview {
    VStack {
        TransactionRow(
            transaction: Transaction(
                numericId: 1, direction: .received, amount: 1.0,
                date: Date(), status: .confirmed, confirmations: 10, blockHeight: 100
            ),
            decimalPlaces: 2, advancedMode: true, dateFormat: .dmy
        )
    }
    .padding()
    .background(.black)
    .preferredColorScheme(.dark)
}
