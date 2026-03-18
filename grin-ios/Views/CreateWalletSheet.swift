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
//  CreateWalletSheet.swift
//  grin-ios
//

import SwiftUI

struct CreateWalletSheet: View {
    let settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    @State private var step: Step = .setup
    @State private var walletName = ""
    @State private var displayName = ""
    @State private var mnemonic = ""
    @State private var showMnemonic = false
    @State private var hasBackedUp = false
    @State private var errorMessage: String?

    private enum Step {
        case setup
        case creating
        case showSeed
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                switch step {
                case .setup:
                    setupView
                case .creating:
                    ProgressView("Creating wallet…")
                        .tint(.primary)
                case .showSeed:
                    seedPhraseView
                }

                Spacer()
            }
            .padding(24)
            .navigationTitle("New Wallet")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    // MARK: - Setup (Name + Recovery Phrase Length)

    private var setupView: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Image(systemName: "wallet.pass.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(.yellow)

                Text("New Wallet")
                    .font(.system(size: 24, weight: .bold))

                Text("Choose a name and recovery phrase length for your new wallet.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            // Wallet name
            VStack(spacing: 12) {
                HStack {
                    TextField("Wallet name", text: $displayName)
                        .font(.system(size: 16))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)

                    if !displayName.isEmpty {
                        Button {
                            displayName = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                                .font(.system(size: 16))
                        }
                    }
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.primary.opacity(0.06))
                )

                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 12))
                    Text("Other Grin users nearby will see this name")
                        .font(.system(size: 12))
                }
                .foregroundStyle(.secondary)
            }

            // Seed phrase length picker
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "key.horizontal")
                        .font(.system(size: 16))
                    Text("Recovery Phrase Length")
                        .font(.system(size: 15))
                    Spacer()
                    Text("\(settings.seedWordCount) words")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }

                Picker("Word Count", selection: Binding(
                    get: { settings.seedWordCount },
                    set: { settings.seedWordCount = $0 }
                )) {
                    ForEach(AppSettings.validWordCounts, id: \.self) { count in
                        Text("\(count)").tag(count)
                    }
                }
                .pickerStyle(.segmented)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(.primary.opacity(0.06))
            )

            if let error = errorMessage {
                Text(error)
                    .font(.system(size: 13))
                    .foregroundStyle(.red)
            }

            Button {
                createWallet()
            } label: {
                Text("Create Wallet")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(.primary)
            .foregroundStyle(Color(.systemBackground))
            .disabled(displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .onAppear {
            if displayName.isEmpty {
                displayName = AppSettings.generateRandomName()
            }
        }
    }

    // MARK: - Seed Phrase

    private var seedPhraseView: some View {
        VStack(spacing: 20) {
            VStack(spacing: 8) {
                Image(systemName: "key.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(.yellow)

                Text("Your Recovery Phrase")
                    .font(.system(size: 24, weight: .bold))

                Text("This is the only way to recover your wallet. Write it down and store it safely.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("Anyone with this phrase can access your funds. Never share it.")
                    .font(.system(size: 13))
                    .foregroundStyle(.orange)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(.orange.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(.orange.opacity(0.3), lineWidth: 1)
                    )
            )

            VStack(spacing: 8) {
                if showMnemonic {
                    let words = mnemonic.split(separator: " ")
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        ForEach(Array(words.enumerated()), id: \.offset) { index, word in
                            HStack(spacing: 4) {
                                Text("\(index + 1).")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.tertiary)
                                    .frame(width: 20, alignment: .trailing)
                                Text(String(word))
                                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                            }
                            .padding(.vertical, 6)
                            .padding(.horizontal, 8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(.primary.opacity(0.06))
                            )
                        }
                    }
                } else {
                    Button {
                        withAnimation { showMnemonic = true }
                    } label: {
                        VStack(spacing: 8) {
                            Image(systemName: "eye.slash.fill")
                                .font(.system(size: 24))
                            Text("Tap to reveal seed phrase")
                                .font(.system(size: 14))
                        }
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 120)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(.primary.opacity(0.06))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(.primary.opacity(0.1), lineWidth: 1)
                                )
                        )
                    }
                }
            }

            if showMnemonic {
                Toggle("I have written down my recovery phrase", isOn: $hasBackedUp)
                    .font(.system(size: 14))
                    .tint(.green)
            }

            Button {
                dismiss()
            } label: {
                Text(hasBackedUp ? "Done" : "Skip — I'll back up later")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(hasBackedUp ? .primary : .gray)
            .foregroundStyle(Color(.systemBackground))

            if !hasBackedUp {
                Text("Wallets without a backup cannot be recovered if you lose this device.")
                    .font(.system(size: 12))
                    .foregroundStyle(.orange.opacity(0.8))
                    .multilineTextAlignment(.center)
            }
        }
    }

    // MARK: - Actions

    private func createWallet() {
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        walletName = name.isEmpty ? AppSettings.generateRandomName() : name
        // Check for duplicate wallet name
        guard !WalletStore.shared.wallets.contains(walletName) else {
            errorMessage = "A wallet with this name already exists"
            return
        }

        errorMessage = nil

        // Reuse the active wallet's password since user is already authenticated
        let activePassword: String
        if let activeWallet = WalletStore.shared.activeWallet,
           let stored = WalletStore.shared.password(for: activeWallet) {
            activePassword = stored
        } else {
            errorMessage = "Could not retrieve wallet credentials"
            return
        }

        withAnimation { step = .creating }

        Task {
            let bridge = GrinWalletBridge(
                walletName: walletName,
                nodeURL: settings.nodeBaseURL,
                password: activePassword
            )
            let result = bridge.createWallet(wordCount: UInt16(settings.seedWordCount))

            await MainActor.run {
                if let error = GrinWalletBridge.errorMessage(result) {
                    errorMessage = error
                    withAnimation { step = .setup }
                } else {
                    mnemonic = result["mnemonic"] as? String ?? ""
                    WalletStore.shared.addWallet(name: walletName, password: activePassword)
                    withAnimation { step = .showSeed }
                }
            }
        }
    }
}
