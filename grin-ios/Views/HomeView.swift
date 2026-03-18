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
//  HomeView.swift
//  grin-ios
//

import SwiftUI

struct HomeView: View {
    let walletService: WalletService
    let settings: AppSettings
    let nearbyService: NearbyService
    @Binding var showGrinAsPrimary: Bool

    @State private var showSend = false
    @State private var showReceive = false

    private var balanceFiat: Double {
        walletService.balanceFiat(currency: settings.currency)
    }

    var body: some View {
        NavigationStack {
        VStack(spacing: 20) {
            // Node status
            HStack {
                NodeStatusBadge(status: walletService.nodeStatus)
                Spacer()
                if settings.advancedMode {
                    Text("Height: \(walletService.nodeHeight)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)

            // Logo
            Image("GrinLogo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 84, height: 84)

            // Balance card
            BalanceCard(
                balance: walletService.balance,
                balanceFiat: balanceFiat,
                currency: settings.currency,
                decimalPlaces: settings.grinDecimalPlaces,
                showGrinAsPrimary: $showGrinAsPrimary
            )
            .padding(.horizontal, 20)

            // Action buttons
            HStack(spacing: 12) {
                Button {
                    showReceive = true
                } label: {
                    Label("Receive", systemImage: "arrow.down.left")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.bordered)
                .tint(.primary)

                Button {
                    showSend = true
                } label: {
                    Label("Send", systemImage: "arrow.up.right")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .tint(.primary)
                .foregroundStyle(Color(.systemBackground))
            }
            .padding(.horizontal, 20)

            // Recent Activity (max 5)
            VStack(alignment: .leading, spacing: 12) {
                Text("Recent Activity")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(1.2)
                    .padding(.horizontal, 20)

                VStack(spacing: 0) {
                    ForEach(Array(walletService.transactions.prefix(5))) { tx in
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
                            HStack {
                                TransactionRowSimple(transaction: tx, decimalPlaces: settings.grinDecimalPlaces, dateFormat: settings.dateFormat)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.horizontal, 20)
                        }
                        .buttonStyle(.plain)
                        if tx.id != walletService.transactions.prefix(5).last?.id {
                            Divider()
                                .overlay(.primary.opacity(0.06))
                                .padding(.leading, 20)
                        }
                    }
                }
            }

            Spacer()
        }
        } // NavigationStack
        .sheet(isPresented: $showSend) {
            SendView(walletService: walletService, settings: settings, nearbyService: nearbyService)
        }
        .sheet(isPresented: $showReceive) {
            ReceiveView(walletService: walletService, settings: settings, nearbyService: nearbyService)
        }
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

#Preview {
    HomeView(
        walletService: WalletService(settings: AppSettings()),
        settings: AppSettings(),
        nearbyService: NearbyService(),
        showGrinAsPrimary: .constant(true)
    )
    .preferredColorScheme(.dark)
}
