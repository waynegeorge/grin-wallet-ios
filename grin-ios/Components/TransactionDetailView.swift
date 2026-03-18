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
//  TransactionDetailView.swift
//  grin-ios
//

import SwiftUI

struct TransactionDetailView: View {
    let transaction: Transaction
    let decimalPlaces: Int
    let advancedMode: Bool
    let dateFormat: DateFormatStyle
    var walletService: WalletService? = nil
    var settings: AppSettings? = nil
    var onCancel: (() -> Void)? = nil

    @State private var showDeleteConfirmation = false
    @State private var showResumeSheet = false

    /// Live transaction from walletService (updates on refresh), falling back to the initial snapshot.
    private var tx: Transaction {
        walletService?.transactions.first(where: { $0.numericId == transaction.numericId }) ?? transaction
    }

    private var hasStoredSlatepack: Bool {
        if tx.isInvoice {
            if tx.direction == .received {
                return SlatepackStore.shared.get(txId: tx.numericId, type: .invoice) != nil
            } else {
                return SlatepackStore.shared.get(txId: tx.numericId, type: .invoiceResponse) != nil
            }
        } else {
            if tx.direction == .sent {
                return SlatepackStore.shared.get(txId: tx.numericId, type: .initial) != nil
            } else {
                return SlatepackStore.shared.get(txId: tx.numericId, type: .response) != nil
            }
        }
    }

    private var fullDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: tx.date)
    }

    var body: some View {
        List {
            // Header
            Section {
                VStack(spacing: 4) {
                    Image(systemName: tx.direction == .received ? "arrow.down.left.circle.fill" : "arrow.up.right.circle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(tx.direction == .received ? .green : .primary)

                    Text(tx.directionLabel)
                        .font(.system(size: 22, weight: .bold))

                    Text("\(tx.direction == .received ? "+" : "")\(String(format: "%.\(decimalPlaces)f", tx.amount)) ツ")
                        .font(.system(size: 28, weight: .semibold, design: .monospaced))
                        .foregroundStyle(tx.direction == .received ? .green : .primary)
                }
                .frame(maxWidth: .infinity)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }

            // Details
            Section {
                DetailRow(label: "Date", value: fullDate)
                DetailRow(label: "Amount", value: "\(String(format: "%.4f", tx.amount)) ツ")
                if tx.direction == .sent {
                    DetailRow(label: "Fee", value: "\(String(format: "%.4f", tx.fee)) ツ")
                }
                DetailRow(label: "Status", value: tx.status.rawValue)

                if tx.status != .incomplete {
                    DetailRow(label: "Confirmations", value: "\(tx.confirmations)")
                }

                if let blockHeight = tx.blockHeight {
                    DetailRow(label: "Block Height", value: "\(blockHeight)")
                }
            }

            // Identifiers & Explorer
            if tx.slateId != nil || tx.kernelExcess != nil {
                Section {
                    if let slateId = tx.slateId {
                        DetailRow(label: "Slate ID", value: slateId, monospace: true, copyable: true)
                    }

                    if let kernelExcess = tx.kernelExcess, !kernelExcess.isEmpty {
                        DetailRow(label: "Kernel", value: kernelExcess, monospace: true, copyable: true)

                        if tx.status != .incomplete {
                            Link(destination: URL(string: "https://testnet.grincoin.org/kernel/\(kernelExcess)")!) {
                                Label("View on Explorer", systemImage: "safari")
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
                }
            }

            // Advanced
            if advancedMode {
                Section("Advanced") {
                    DetailRow(label: "Tx ID", value: tx.txId, monospace: true)
                    if let txType = tx.txType {
                        DetailRow(label: "Type", value: txType, monospace: true)
                    }
                }
            }

            // Actions
            if tx.status == .incomplete || tx.status == .confirming {
                Section {
                    if tx.status == .incomplete && hasStoredSlatepack {
                        Button {
                            showResumeSheet = true
                        } label: {
                            Label("Resume Transaction", systemImage: "arrow.clockwise")
                                .foregroundStyle(.green)
                        }
                    }

                    if onCancel != nil {
                        Button(role: .destructive) {
                            showDeleteConfirmation = true
                        } label: {
                            Label(tx.status == .confirming ? "Cancel Transaction" : "Delete Transaction", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Transaction")
        .navigationBarTitleDisplayMode(.inline)
        .alert(
            tx.status == .confirming ? "Cancel Transaction" : "Delete Transaction",
            isPresented: $showDeleteConfirmation
        ) {
            Button(tx.status == .confirming ? "Cancel" : "Delete", role: .destructive) {
                onCancel?()
            }
            Button("Go Back", role: .cancel) { }
        } message: {
            Text(tx.status == .confirming
                 ? "This transaction has been broadcast. Cancelling unlocks your outputs, but the transaction may still confirm on-chain."
                 : "This incomplete transaction will be removed from your wallet.")
        }
        .sheet(isPresented: $showResumeSheet) {
            if let walletService, let settings {
                ResumeTransactionView(
                    transaction: tx,
                    walletService: walletService,
                    settings: settings
                )
            }
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
                .font(.system(size: 14))
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
                            .font(.system(size: 13, design: .monospaced))
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
                    .font(.system(size: 13, design: monospace ? .monospaced : .default))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
        }
    }
}
