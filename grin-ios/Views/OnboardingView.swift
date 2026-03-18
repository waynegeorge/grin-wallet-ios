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
//  OnboardingView.swift
//  grin-ios
//

import SwiftUI
import LocalAuthentication

struct OnboardingView: View {
    @Binding var isOnboarded: Bool
    let settings: AppSettings
    var nearbyService: NearbyService?

    @State private var step: OnboardingStep = .welcome
    @State private var walletName: String = "default"
    @State private var password: String = ""
    @State private var confirmPassword: String = ""
    @State private var showPassword: Bool = false
    @State private var showConfirmPassword: Bool = false
    @State private var mnemonic: String = ""
    @State private var restoreMnemonic: String = ""
    @State private var showMnemonic: Bool = false
    @State private var errorMessage: String?
    @State private var isLoading: Bool = false
    @State private var hasBackedUp: Bool = false
    @State private var enableBiometric: Bool = true
    @State private var biometricsAvailable: Bool = false
    @State private var displayName: String = ""
    @State private var isRestoreFlow: Bool = false
    @State private var showNetworkExplanation: Bool = false

    enum OnboardingStep {
        case welcome
        case setPassword
        case chooseName
        case creating
        case showSeed
        case restoreEntry
        case restoring
        case done
    }

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            switch step {
            case .welcome:
                welcomeView
            case .setPassword:
                setPasswordView
            case .chooseName:
                chooseNameView
            case .creating:
                loadingView("Creating wallet…")
            case .showSeed:
                seedPhraseView
            case .restoreEntry:
                restoreView
            case .restoring:
                loadingView("Restoring wallet…")
            case .done:
                doneView
            }

            Spacer()
        }
        .padding(24)
        .preferredColorScheme(.dark)
    }

    // MARK: - Welcome

    private var welcomeView: some View {
        VStack(spacing: 32) {
            Image("GrinLogo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 120, height: 120)

            VStack(spacing: 8) {
                Text("Welcome to Grin")
                    .font(.system(size: 28, weight: .bold))

                Text("Private digital cash, powered by Mimblewimble")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            // Testnet warning
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("This wallet is for testnet Grin only. Sending mainnet Grin to this wallet will result in errors and potential loss of funds.")
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

            VStack(spacing: 12) {
                Button {
                    withAnimation { step = .setPassword }
                } label: {
                    Text("Create New Wallet")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .tint(.white)
                .foregroundStyle(.black)

                Button {
                    isRestoreFlow = true
                    withAnimation { step = .setPassword }
                } label: {
                    Text("Restore from Seed Phrase")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Set Password

    private var setPasswordView: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Text("Set a Password")
                    .font(.system(size: 24, weight: .bold))

                Text(isRestoreFlow
                     ? "This password will encrypt your restored wallet on this device."
                     : "This password encrypts your wallet on this device.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 16) {
                // Password field with show/hide
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        if showPassword {
                            TextField("Password", text: $password)
                                .textContentType(.newPassword)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                        } else {
                            SecureField("Password", text: $password)
                                .textContentType(.newPassword)
                        }
                        Button {
                            showPassword.toggle()
                        } label: {
                            Image(systemName: showPassword ? "eye.slash" : "eye")
                                .foregroundStyle(.secondary)
                                .font(.system(size: 15))
                        }
                    }
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.white.opacity(0.06))
                    )

                    // Strength meter
                    if !password.isEmpty {
                        let strength = PasswordStrength.evaluate(password)
                        VStack(alignment: .leading, spacing: 4) {
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(.white.opacity(0.08))
                                        .frame(height: 4)
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(strength.colour)
                                        .frame(width: geo.size.width * strength.fraction, height: 4)
                                        .animation(.easeOut(duration: 0.3), value: strength.fraction)
                                }
                            }
                            .frame(height: 4)

                            HStack {
                                Text(strength.label)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(strength.colour)
                                Spacer()
                                if password.count < 8 {
                                    Text("\(8 - password.count) more characters needed")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(.horizontal, 4)
                    }
                }

                // Confirm password field with show/hide
                HStack {
                    if showConfirmPassword {
                        TextField("Confirm Password", text: $confirmPassword)
                            .textContentType(.newPassword)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    } else {
                        SecureField("Confirm Password", text: $confirmPassword)
                            .textContentType(.newPassword)
                    }
                    Button {
                        showConfirmPassword.toggle()
                    } label: {
                        Image(systemName: showConfirmPassword ? "eye.slash" : "eye")
                            .foregroundStyle(.secondary)
                            .font(.system(size: 15))
                    }
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.white.opacity(0.06))
                )

                // Password match indicator
                if !confirmPassword.isEmpty && password != confirmPassword {
                    HStack(spacing: 4) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                        Text("Passwords do not match")
                            .font(.system(size: 12))
                    }
                    .foregroundStyle(.red)
                    .padding(.horizontal, 4)
                }
            }

            // Face ID / Touch ID toggle
            if biometricsAvailable {
                let context = LAContext()
                let _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
                let isFaceID = context.biometryType == .faceID

                Toggle(isOn: $enableBiometric) {
                    HStack(spacing: 10) {
                        Image(systemName: isFaceID ? "faceid" : "touchid")
                            .font(.system(size: 20))
                        Text("Enable \(isFaceID ? "Face ID" : "Touch ID")")
                            .font(.system(size: 15))
                    }
                }
                .tint(.green)
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.white.opacity(0.04))
                )
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
                    .fill(.white.opacity(0.04))
            )

            if let error = errorMessage {
                Text(error)
                    .font(.system(size: 13))
                    .foregroundStyle(.red)
            }

            Button {
                guard password.count >= 8 else {
                    errorMessage = "Password must be at least 8 characters"
                    return
                }
                guard password == confirmPassword else {
                    errorMessage = "Passwords do not match"
                    return
                }
                errorMessage = nil

                let nextStep: OnboardingStep = isRestoreFlow ? .restoreEntry : .chooseName
                if enableBiometric && biometricsAvailable {
                    let context = LAContext()
                    context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics,
                                           localizedReason: "Enable biometric unlock for your Grin wallet") { success, _ in
                        DispatchQueue.main.async {
                            WalletStore.shared.biometricEnabled = success
                            withAnimation { step = nextStep }
                        }
                    }
                } else {
                    WalletStore.shared.biometricEnabled = false
                    withAnimation { step = nextStep }
                }
            } label: {
                Text(isRestoreFlow ? "Continue" : "Create Wallet")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(.white)
            .foregroundStyle(.black)
            .disabled(password.count < 8 || confirmPassword.isEmpty || password != confirmPassword)

            Button {
                isRestoreFlow = false
                withAnimation { step = .welcome }
            } label: {
                Text("Back")
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear {
            let context = LAContext()
            var error: NSError?
            biometricsAvailable = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
        }
    }

    // MARK: - Choose Name

    private var chooseNameView: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Image(systemName: "person.crop.circle")
                    .font(.system(size: 36))
                    .foregroundStyle(.yellow)

                Text("Choose a Wallet Name")
                    .font(.system(size: 24, weight: .bold))

                Text("This name will be visible to nearby devices during peer-to-peer transactions.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

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
                        .fill(.white.opacity(0.06))
                )

                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 12))
                    Text("Other Grin users nearby will see this name")
                        .font(.system(size: 12))
                }
                .foregroundStyle(.secondary)
            }

            Button {
                showNetworkExplanation = true
            } label: {
                Text("Continue")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(.white)
            .foregroundStyle(.black)
            .disabled(displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            Button {
                withAnimation { step = isRestoreFlow ? .restoreEntry : .setPassword }
            } label: {
                Text("Back")
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear {
            if displayName.isEmpty {
                displayName = AppSettings.generateRandomName()
            }
        }
        .alert("Local Network Access", isPresented: $showNetworkExplanation) {
            Button("Continue") {
                nearbyService?.startAdvertising()
                saveNameAndProceed()
            }
        } message: {
            Text("Grin uses Bluetooth and local networking to discover nearby wallets for peer-to-peer transactions. You will be asked to allow local network access next.")
        }
    }

    private func saveNameAndProceed() {
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        walletName = name.isEmpty ? AppSettings.generateRandomName() : name
        if isRestoreFlow {
            withAnimation { step = .restoring }
            restoreWallet()
        } else {
            withAnimation { step = .creating }
            createWallet()
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

            // Warning
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

            // Seed phrase (hidden/revealed)
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
                                    .fill(.white.opacity(0.04))
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
                                .fill(.white.opacity(0.04))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(.white.opacity(0.08), lineWidth: 1)
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
                completeOnboarding()
            } label: {
                Text(hasBackedUp ? "Continue" : "Skip — I'll back up later")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(hasBackedUp ? .white : .gray)
            .foregroundStyle(.black)

            if !hasBackedUp {
                Text("⚠️ Wallets without a backup cannot be recovered if you lose this device.")
                    .font(.system(size: 12))
                    .foregroundStyle(.orange.opacity(0.8))
                    .multilineTextAlignment(.center)
            }
        }
    }

    // MARK: - Restore

    private var restoreView: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Text("Restore Wallet")
                    .font(.system(size: 24, weight: .bold))

                Text("Enter your recovery phrase to restore an existing wallet.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            TextEditor(text: $restoreMnemonic)
                .font(.system(size: 14, design: .monospaced))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .frame(minHeight: 100)
                .scrollContentBackground(.hidden)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.white.opacity(0.04))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(.white.opacity(0.08), lineWidth: 1)
                        )
                )
                .overlay(alignment: .topLeading) {
                    if restoreMnemonic.isEmpty {
                        Text("word1 word2 word3 ...")
                            .font(.system(size: 14, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 16)
                            .allowsHitTesting(false)
                    }
                }

            // Word count indicator
            let enteredWordCount = restoreMnemonic
                .components(separatedBy: .whitespacesAndNewlines)
                .filter { !$0.isEmpty }
                .count
            if enteredWordCount > 0 {
                let isValid = AppSettings.validWordCounts.contains(enteredWordCount)
                HStack(spacing: 6) {
                    Image(systemName: isValid ? "checkmark.circle.fill" : "info.circle")
                        .font(.system(size: 12))
                    Text("\(enteredWordCount) word\(enteredWordCount == 1 ? "" : "s") entered")
                        .font(.system(size: 12))
                    if !isValid && enteredWordCount < 24 {
                        let nextValid = AppSettings.validWordCounts.first(where: { $0 > enteredWordCount }) ?? 24
                        Text("(next valid: \(nextValid))")
                            .font(.system(size: 12))
                    }
                }
                .foregroundStyle(isValid ? .green : .secondary)
            }

            if let error = errorMessage {
                Text(error)
                    .font(.system(size: 13))
                    .foregroundStyle(.red)
            }

            Button {
                let words = restoreMnemonic
                    .components(separatedBy: .whitespacesAndNewlines)
                    .filter { !$0.isEmpty }
                guard !words.isEmpty else {
                    errorMessage = "Enter your recovery phrase"
                    return
                }
                guard AppSettings.validWordCounts.contains(words.count) else {
                    errorMessage = "Recovery phrase must be 12, 15, 18, 21, or 24 words (you entered \(words.count))"
                    return
                }
                errorMessage = nil
                withAnimation { step = .chooseName }
            } label: {
                Text("Restore Wallet")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(.white)
            .foregroundStyle(.black)
            .disabled(restoreMnemonic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            Button {
                withAnimation { step = .setPassword }
            } label: {
                Text("Back")
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Loading

    private func loadingView(_ message: String) -> some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
                .tint(.white)
            Text(message)
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Done

    private var doneView: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.green)

            Text("Wallet Ready")
                .font(.system(size: 24, weight: .bold))

            Text("Your Grin wallet has been set up successfully.")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button {
                isOnboarded = true
            } label: {
                Text("Open Wallet")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(.white)
            .foregroundStyle(.black)
        }
    }

    // MARK: - Actions

    private func createWallet() {
        Task {
            let bridge = GrinWalletBridge(
                walletName: walletName,
                nodeURL: "http://\(settings.nodeURL):\(settings.nodePort)",
                password: password
            )

            // If wallet already exists on disk (e.g. reinstall wiped UserDefaults but not files),
            // try to open it instead of creating
            var result: [String: Any]
            if bridge.walletExists() {
                result = bridge.openWallet()
                if !GrinWalletBridge.isError(result) {
                    // Wallet opened successfully — skip seed display, just save and proceed
                    await MainActor.run {
                        WalletStore.shared.addWallet(name: walletName, password: password)
                        WalletStore.shared.activeWallet = walletName
                        isOnboarded = true
                    }
                    return
                }
            }

            result = bridge.createWallet(wordCount: UInt16(settings.seedWordCount))

            await MainActor.run {
                if let error = GrinWalletBridge.errorMessage(result) {
                    errorMessage = error
                    withAnimation { step = .setPassword }
                } else {
                    mnemonic = result["mnemonic"] as? String ?? ""
                    // Save wallet config
                    WalletStore.shared.addWallet(name: walletName, password: password)
                    WalletStore.shared.activeWallet = walletName
                    withAnimation { step = .showSeed }
                }
            }
        }
    }

    private func restoreWallet() {
        Task {
            let bridge = GrinWalletBridge(
                walletName: walletName,
                nodeURL: "http://\(settings.nodeURL):\(settings.nodePort)",
                password: password
            )
            // Normalize the mnemonic: lowercase, collapse all whitespace/newlines into
            // single spaces, and strip anything that isn't a lowercase letter or space.
            // BIP39 English words are strictly a-z; this removes smart quotes,
            // non-breaking spaces, and other invisible characters iOS may insert.
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
                    withAnimation { step = .restoreEntry }
                } else {
                    WalletStore.shared.addWallet(name: walletName, password: password)
                    WalletStore.shared.activeWallet = walletName
                    completeOnboarding()
                }
            }
        }
    }

    private func completeOnboarding() {
        withAnimation { step = .done }
    }
}

#Preview {
    OnboardingView(isOnboarded: .constant(false), settings: AppSettings())
}
