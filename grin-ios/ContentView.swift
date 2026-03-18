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
//  ContentView.swift
//  grin-ios
//

import SwiftUI

struct ContentView: View {
    @State private var settings = AppSettings()
    @State private var walletStore = WalletStore.shared
    @State private var walletService: WalletService?
    @State private var nearbyService = NearbyService()
    @State private var selectedTab = 0
    @State private var showGrinAsPrimary = true
    @State private var isOnboarded = WalletStore.shared.isOnboarded
    @State private var isUnlocked = false
    @State private var showNearbyApproval = false
    @State private var capturedRequest: NearbyService.NearbyRequest?

    var body: some View {
        Group {
            if !isOnboarded {
                OnboardingView(isOnboarded: Binding(
                    get: { isOnboarded },
                    set: { newValue in
                        if newValue {
                            walletStore.isOnboarded = true
                            isUnlocked = true
                            isOnboarded = true
                            setupWalletService()
                        }
                    }
                ), settings: settings, nearbyService: nearbyService)
            } else if !isUnlocked {
                UnlockView(isUnlocked: $isUnlocked, walletStore: walletStore)
                    .onChange(of: isUnlocked) { _, newValue in
                        if newValue {
                            setupWalletService()
                        }
                    }
            } else if let walletService {
                TabView(selection: $selectedTab) {
                    Tab("Home", systemImage: "house.fill", value: 0) {
                        HomeView(
                            walletService: walletService,
                            settings: settings,
                            nearbyService: nearbyService,
                            showGrinAsPrimary: $showGrinAsPrimary
                        )
                        .overlay {
                            if walletService.scanInProgress {
                                ScanLockOverlay(walletService: walletService) {
                                    cancelScanFromOverlay(walletService: walletService)
                                }
                            }
                        }
                    }

                    Tab("Transactions", systemImage: "list.bullet", value: 1) {
                        TransactionsView(walletService: walletService, settings: settings)
                            .overlay {
                                if walletService.scanInProgress {
                                    ScanLockOverlay(walletService: walletService) {
                                        cancelScanFromOverlay(walletService: walletService)
                                    }
                                }
                            }
                    }

                    Tab("Settings", systemImage: "gearshape.fill", value: 2) {
                        SettingsView(settings: settings, walletService: walletService, nearbyService: nearbyService)
                    }
                }
            } else {
                ProgressView("Loading wallet…")
                    .onAppear { setupWalletService() }
            }
        }
        .onAppear {
            // Recover wallet state if UserDefaults were wiped but files exist
            walletStore.recoverIfNeeded()
            isOnboarded = walletStore.isOnboarded
        }
        .preferredColorScheme(settings.appearanceMode.colorScheme)
        .tint(.primary)
        .onChange(of: nearbyService.pendingRequest != nil) { _, hasPending in
            if hasPending {
                capturedRequest = nearbyService.pendingRequest
                showNearbyApproval = true
            }
        }
        .alert(
            capturedRequest?.type == .incomingInvoice
                ? "Payment Request"
                : "Incoming Transaction",
            isPresented: $showNearbyApproval
        ) {
            Button("Decline", role: .cancel) {
                nearbyService.rejectPendingRequest()
                capturedRequest = nil
            }
            Button(capturedRequest?.type == .incomingInvoice ? "Pay" : "Accept") {
                // Capture before alert dismisses and clears state
                let request = capturedRequest
                capturedRequest = nil
                guard request != nil else { return }
                Task { await nearbyService.approvePendingRequest() }
            }
        } message: {
            if let request = capturedRequest {
                let amountText = request.amount.map { String(format: "%.4f", $0) + " ツ" } ?? "grin"
                switch request.type {
                case .incomingSend:
                    Text("\(request.peerName) wants to send you \(amountText). Accept this transaction?")
                case .incomingInvoice:
                    Text("\(request.peerName) is requesting \(amountText). Approve this payment?")
                }
            }
        }
    }

    private func cancelScanFromOverlay(walletService: WalletService) {
        walletService.cancelScan()
        settings.lastScanDate = Date()
        settings.lastScanResult = "cancelled"
    }

    private func setupWalletService() {
        let service = WalletService(settings: settings)
        walletService = service
        // Wire wallet into nearby for auto-signing incoming slatepacks
        nearbyService.walletService = service
        // Use the active wallet name for peer discovery
        if let walletName = WalletStore.shared.activeWallet {
            nearbyService.updateDisplayName(walletName)
        }
        // Start advertising so other devices can find us (if enabled)
        if settings.nearbyEnabled {
            nearbyService.startAdvertising()
        }
        // Wire up Watch connectivity so it can respond to pull-requests
        PhoneToWatchService.shared.configure(walletService: service, settings: settings)
    }
}

// MARK: - Scan Lock Overlay

private struct ScanLockOverlay: View {
    var walletService: WalletService
    var onCancel: () -> Void

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 40))
                    .foregroundStyle(.green)
                    .symbolEffect(.rotate)

                Text("Scan & Repair in Progress")
                    .font(.system(size: 20, weight: .bold))

                ProgressView(value: Double(walletService.scanProgress), total: 100)
                    .tint(.green)
                    .frame(width: 200)

                Text("\(walletService.scanProgress)%")
                    .font(.system(size: 15, design: .monospaced))
                    .foregroundStyle(.secondary)

                Text("Wallet operations are locked while the scan is running. Please do not close the app.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)

                Button {
                    onCancel()
                } label: {
                    Text("Cancel Scan")
                        .frame(minWidth: 140)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }
        }
    }
}

#Preview {
    ContentView()
}
