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
//  NearbyView.swift
//  grin-ios
//

import SwiftUI

struct NearbyView: View {
    let nearbyService: NearbyService
    let walletService: WalletService
    let settings: AppSettings

    @State private var selectedPeer: NearbyPeer?
    @State private var showSlatepackSheet = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if nearbyService.isSearching {
                        HStack(spacing: 12) {
                            ProgressView()
                                .tint(.white)
                            Text("Searching for nearby wallets…")
                                .font(.system(size: 14))
                                .foregroundStyle(.secondary)
                        }
                        .listRowBackground(Color.clear)
                    }

                    if nearbyService.peers.isEmpty && nearbyService.isSearching {
                        ContentUnavailableView {
                            Label("No Peers Found", systemImage: "antenna.radiowaves.left.and.right")
                        } description: {
                            Text("Make sure other Grin wallets are nearby with discovery enabled.")
                        }
                        .listRowBackground(Color.clear)
                    }

                    ForEach(nearbyService.peers) { peer in
                        NearbyPeerRow(peer: peer) {
                            selectedPeer = peer
                            showSlatepackSheet = true
                        }
                        .listRowBackground(Color.clear)
                    }
                } header: {
                    Text("Nearby Wallets")
                }

                if let received = nearbyService.receivedSlatepack {
                    Section {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Image(systemName: "envelope.fill")
                                    .foregroundStyle(.green)
                                Text("Received Slatepack")
                                    .font(.system(size: 15, weight: .medium))
                            }

                            SlatepackDisplay(slatepack: received, advancedMode: settings.advancedMode)
                        }
                        .listRowBackground(Color.clear)
                    } header: {
                        Text("Received")
                    }
                }
            }
            .listStyle(.plain)
            .navigationTitle("Nearby")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        if nearbyService.isSearching {
                            nearbyService.stopSearching()
                        } else {
                            nearbyService.startSearching()
                        }
                    } label: {
                        Image(systemName: nearbyService.isSearching ? "stop.fill" : "antenna.radiowaves.left.and.right")
                    }
                    .foregroundStyle(.primary)
                }
            }
            .sheet(isPresented: $showSlatepackSheet) {
                if let peer = selectedPeer {
                    NearbyTransferSheet(peer: peer, nearbyService: nearbyService, walletService: walletService, settings: settings)
                }
            }
        }
        .onAppear {
            if !nearbyService.isSearching {
                nearbyService.startSearching()
            }
        }
        .onDisappear {
            nearbyService.stopSearching()
            // Keep advertising (always-on receive mode)
        }
    }
}

// MARK: - Transfer Sheet

private struct NearbyTransferSheet: View {
    let peer: NearbyPeer
    let nearbyService: NearbyService
    let walletService: WalletService
    let settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    @State private var amountString = ""
    @State private var sending = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text("Send to \(peer.displayName)")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.primary)

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    TextField("0", text: $amountString)
                        .font(.system(size: 42, weight: .bold, design: .monospaced))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.center)
                    Text("ツ")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.secondary)
                }

                if sending {
                    ProgressView("Sending…")
                        .tint(.white)
                } else if nearbyService.sendingStatus == .sent {
                    Label("Sent!", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }

                Button {
                    Task {
                        sending = true
                        let sendAmount = Double(amountString) ?? 0
                        if let slatepack = await walletService.initiateSend(amount: sendAmount) {
                            await nearbyService.sendSlatepack(slatepack.fullString, amount: sendAmount, to: peer)
                        }
                        sending = false
                    }
                } label: {
                    Text("Send via Nearby")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .tint(.white)
                .foregroundStyle(.black)
                .disabled(amountString.isEmpty || sending)

                Spacer()
            }
            .padding(20)
            .navigationTitle("Nearby Transfer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

#Preview {
    NearbyView(
        nearbyService: NearbyService(),
        walletService: WalletService(settings: AppSettings()),
        settings: AppSettings()
    )
    .preferredColorScheme(.dark)
}
