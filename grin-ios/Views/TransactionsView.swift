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
//  TransactionsView.swift
//  grin-ios
//

import SwiftUI

struct TransactionsView: View {
    let walletService: WalletService
    let settings: AppSettings

    @State private var searchText = ""
    @State private var filterDirection: TransactionDirection? = nil

    private var filteredTransactions: [Transaction] {
        var txs = walletService.transactions

        if let filter = filterDirection {
            txs = txs.filter { $0.direction == filter }
        }

        if !searchText.isEmpty {
            txs = txs.filter { tx in
                tx.txId.localizedCaseInsensitiveContains(searchText) ||
                String(format: "%.4f", tx.amount).contains(searchText) ||
                tx.status.rawValue.localizedCaseInsensitiveContains(searchText) ||
                (tx.blockHeight.map { String($0) }?.contains(searchText) ?? false) ||
                (tx.slateId?.localizedCaseInsensitiveContains(searchText) ?? false) ||
                (tx.kernelExcess?.localizedCaseInsensitiveContains(searchText) ?? false)
            }
        }

        return txs
    }

    var body: some View {
        NavigationStack {
            List {
                if settings.advancedMode {
                    Section {
                        Picker("Filter", selection: $filterDirection) {
                            Text("All").tag(nil as TransactionDirection?)
                            Text("Sent").tag(TransactionDirection.sent as TransactionDirection?)
                            Text("Received").tag(TransactionDirection.received as TransactionDirection?)
                        }
                        .pickerStyle(.segmented)
                    }
                    .listRowBackground(Color.clear)
                }

                ForEach(filteredTransactions) { tx in
                    NavigationLink {
                        TransactionDetailView(
                            transaction: tx,
                            decimalPlaces: settings.grinDecimalPlaces,
                            advancedMode: settings.advancedMode,
                            dateFormat: settings.dateFormat,
                            walletService: walletService,
                            settings: settings,
                            onCancel: tx.status == .incomplete || tx.status == .confirming ? {
                                Task {
                                    await walletService.cancelTransaction(numericId: tx.numericId)
                                }
                            } : nil
                        )
                    } label: {
                        TransactionRowSimple(
                            transaction: tx,
                            decimalPlaces: settings.grinDecimalPlaces,
                            dateFormat: settings.dateFormat
                        )
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.visible)
                    .listRowSeparatorTint(.primary.opacity(0.06))
                    .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
                }
            }
            .listStyle(.plain)
            .environment(\.defaultMinListRowHeight, 0)
            .searchable(text: $searchText, prompt: "Search transactions")
            .navigationTitle("Transactions")
            .task {
                await walletService.refresh()
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(5))
                    guard !Task.isCancelled else { break }
                    await walletService.refresh()
                }
            }
            .refreshable {
                await walletService.refresh()
            }
        }
    }
}

#Preview {
    TransactionsView(walletService: WalletService(settings: AppSettings()), settings: AppSettings())
        .preferredColorScheme(.dark)
}
