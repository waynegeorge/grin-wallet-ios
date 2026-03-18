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
//  UnlockView.swift
//  grin-ios
//
//  Unlock screen with password entry and Face ID support.
//

import SwiftUI
import LocalAuthentication

struct UnlockView: View {
    @Binding var isUnlocked: Bool
    let walletStore: WalletStore

    @State private var password: String = ""
    @State private var errorMessage: String?
    @State private var isAuthenticating = false
    @State private var showPassword = false
    @FocusState private var passwordFocused: Bool

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            // Logo
            Image("GrinLogo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 100, height: 100)

            Text("Welcome Back")
                .font(.system(size: 28, weight: .bold))

            Text("Unlock your wallet to continue")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)

            // Password field
            VStack(spacing: 12) {
                HStack {
                    if showPassword {
                        TextField("Password", text: $password)
                            .textContentType(.password)
                            .focused($passwordFocused)
                    } else {
                        SecureField("Password", text: $password)
                            .textContentType(.password)
                            .focused($passwordFocused)
                    }

                    Button {
                        showPassword.toggle()
                    } label: {
                        Image(systemName: showPassword ? "eye.slash" : "eye")
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
                .background(.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 12))

                if let errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 13))
                        .foregroundStyle(.red)
                }

                Button {
                    unlockWithPassword()
                } label: {
                    Text("Unlock")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .tint(.white)
                .foregroundStyle(.black)
                .disabled(password.isEmpty)
            }
            .padding(.horizontal, 40)

            // Face ID button
            if walletStore.biometricEnabled {
                Button {
                    authenticateWithBiometrics()
                } label: {
                    VStack(spacing: 8) {
                        Image(systemName: biometricIcon)
                            .font(.system(size: 40))
                            .foregroundStyle(.white.opacity(0.7))
                        Text(biometricLabel)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 8)
            }

            Spacer()
            Spacer()
        }
        .onAppear {
            if walletStore.biometricEnabled {
                authenticateWithBiometrics()
            } else {
                passwordFocused = true
            }
        }
        .onSubmit {
            unlockWithPassword()
        }
    }

    // MARK: - Biometric helpers

    private var biometricIcon: String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        return context.biometryType == .faceID ? "faceid" : "touchid"
    }

    private var biometricLabel: String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        return context.biometryType == .faceID ? "Use Face ID" : "Use Touch ID"
    }

    // MARK: - Auth

    private func unlockWithPassword() {
        guard let walletName = walletStore.activeWallet ?? walletStore.wallets.first else {
            errorMessage = "No wallet found"
            return
        }

        // Verify password by checking Keychain
        if let storedPassword = walletStore.password(for: walletName), storedPassword == password {
            isUnlocked = true
        } else {
            errorMessage = "Incorrect password"
            password = ""
        }
    }

    private func authenticateWithBiometrics() {
        let context = LAContext()
        var error: NSError?

        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            errorMessage = "Biometrics not available"
            return
        }

        isAuthenticating = true
        context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics,
                               localizedReason: "Unlock your Grin wallet") { success, authError in
            DispatchQueue.main.async {
                isAuthenticating = false
                if success {
                    isUnlocked = true
                } else if let authError = authError as? LAError, authError.code != .userCancel {
                    errorMessage = "Authentication failed"
                }
            }
        }
    }
}
