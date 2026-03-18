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
//  RestoreWalletSheet.swift
//  grin-ios
//

import SwiftUI

struct RestoreWalletSheet: View {
    let settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    @State private var step: Step = .setup
    @State private var walletName = ""
    @State private var displayName = ""
    @State private var restoreMnemonic = ""
    @State private var errorMessage: String?

    private enum Step {
        case setup
        case restoring
        case done
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                switch step {
                case .setup:
                    setupView
                case .restoring:
                    ProgressView("Restoring wallet…")
                        .tint(.primary)
                case .done:
                    doneView
                }

                Spacer()
            }
            .padding(24)
            .navigationTitle("Restore Wallet")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if step != .restoring {
                        Button("Cancel") { dismiss() }
                    }
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

    // MARK: - Setup (Name + Mnemonic)

    private var setupView: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Image(systemName: "arrow.counterclockwise.circle.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(.yellow)

                Text("Restore Wallet")
                    .font(.system(size: 24, weight: .bold))

                Text("Enter your recovery phrase and choose a name for the restored wallet.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            // Wallet name
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

            // Mnemonic entry
            VStack(alignment: .leading, spacing: 8) {
                TextEditor(text: $restoreMnemonic)
                    .font(.system(size: 14, design: .monospaced))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 100, maxHeight: 140)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.primary.opacity(0.06))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(.primary.opacity(0.1), lineWidth: 1)
                            )
                    )
                    .overlay(alignment: .topLeading) {
                        if restoreMnemonic.isEmpty {
                            Text("word1 word2 word3 ...")
                                .font(.system(size: 14, design: .monospaced))
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 20)
                                .allowsHitTesting(false)
                        }
                    }

                // Word count indicator
                let enteredWordCount = restoreMnemonic
                    .components(separatedBy: .whitespacesAndNewlines)
                    .filter { !$0.isEmpty }
                    .count
                let isValidCount = AppSettings.validWordCounts.contains(enteredWordCount)

                HStack {
                    Text("\(enteredWordCount) words entered")
                        .font(.system(size: 12))
                        .foregroundColor(enteredWordCount == 0 ? .secondary : (isValidCount ? .green : .orange))

                    Spacer()

                    if enteredWordCount > 0 && !isValidCount {
                        Text("Expected: 12, 15, 18, 21, or 24")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 4)
            }

            if let error = errorMessage {
                Text(error)
                    .font(.system(size: 13))
                    .foregroundStyle(.red)
            }

            Button {
                restoreWallet()
            } label: {
                Text("Restore Wallet")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(.primary)
            .foregroundStyle(Color(.systemBackground))
            .disabled(restoreMnemonic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                      || displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .onAppear {
            if displayName.isEmpty {
                displayName = AppSettings.generateRandomName()
            }
        }
    }

    // MARK: - Done

    private var doneView: some View {
        VStack(spacing: 24) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)

            Text("Wallet Restored")
                .font(.system(size: 24, weight: .bold))

            Text("Your wallet has been restored. It may take a moment for your balance to appear while the wallet syncs with the network.")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button {
                dismiss()
            } label: {
                Text("Done")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(.primary)
            .foregroundStyle(Color(.systemBackground))
        }
    }

    // MARK: - Actions

    private func restoreWallet() {
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        walletName = name.isEmpty ? AppSettings.generateRandomName() : name

        // Check for duplicate wallet name
        guard !WalletStore.shared.wallets.contains(walletName) else {
            errorMessage = "A wallet with this name already exists"
            return
        }

        // Reuse the active wallet's password
        let activePassword: String
        if let activeWallet = WalletStore.shared.activeWallet,
           let stored = WalletStore.shared.password(for: activeWallet) {
            activePassword = stored
        } else {
            errorMessage = "Could not retrieve wallet credentials"
            return
        }

        errorMessage = nil
        withAnimation { step = .restoring }

        Task {
            let bridge = GrinWalletBridge(
                walletName: walletName,
                nodeURL: settings.nodeBaseURL,
                password: activePassword
            )

            // Normalize mnemonic: lowercase, single spaces, only a-z and spaces
            let cleaned = restoreMnemonic
                .lowercased()
                .components(separatedBy: .whitespacesAndNewlines)
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            let normalized = String(cleaned.unicodeScalars.filter {
                CharacterSet.lowercaseLetters.contains($0) || $0 == " "
            })

            let result = bridge.restore(mnemonic: normalized)

            await MainActor.run {
                if let error = GrinWalletBridge.errorMessage(result) {
                    errorMessage = error
                    withAnimation { step = .setup }
                } else {
                    WalletStore.shared.addWallet(name: walletName, password: activePassword)
                    withAnimation { step = .done }
                }
            }
        }
    }
}
