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
//  SettingsView.swift
//  grin-ios
//

import SwiftUI
import LocalAuthentication

enum NodeCheckStatus: Equatable {
    case idle
    case checking
    case connected(height: UInt64)
    case failed(String)

    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }
}

struct SettingsView: View {
    @Bindable var settings: AppSettings
    var walletService: WalletService?
    var nearbyService: NearbyService?

    @State private var showSeedPhrase = false
    @State private var showCreateWallet = false
    @State private var showRestoreWallet = false
    @State private var showScanConfirm = false
    @State private var showScanResult = false
    @State private var scanStartTime: Date?
    @State private var scanFromDate: Bool = false
    @State private var scanDate: Date = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    @State private var nodeCheckStatus: NodeCheckStatus = .idle


    @State private var biometricError: String?
    @State private var showPasswordPrompt = false
    @State private var seedPhrasePassword = ""
    @State private var seedPhrase: String?
    @State private var seedPhraseError: String?
    @State private var seedPhraseLoading = false

    private var scanResultTitle: String {
        if case .success = walletService?.lastScanResult {
            return "Scan Complete"
        }
        return "Scan Failed"
    }

    private var scanResultMessage: String {
        switch walletService?.lastScanResult {
        case .success(let duration):
            return "Scan completed successfully in \(duration). Your wallet balance has been updated."
        case .failed(let duration, let error):
            return "Scan failed after \(duration).\n\n\(error)"
        case nil:
            return ""
        }
    }

    private var biometricLabel: String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        return context.biometryType == .faceID ? "Face ID" : "Touch ID"
    }

    var body: some View {
        NavigationStack {
            Form {
                // MARK: - General
                Section("General") {
                    Toggle("Advanced Mode", isOn: $settings.advancedMode)
                        .tint(.green)

                    Picker("Currency", selection: $settings.currency) {
                        ForEach(Currency.allCases, id: \.self) { currency in
                            Text("\(currency.symbol) \(currency.rawValue)")
                                .tag(currency)
                        }
                    }

                    Picker("Appearance", selection: $settings.appearanceMode) {
                        ForEach(AppearanceMode.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }

                    Picker("Date Format", selection: $settings.dateFormat) {
                        ForEach(DateFormatStyle.allCases, id: \.self) { style in
                            Text(style.rawValue).tag(style)
                        }
                    }

                    NavigationLink {
                        DecimalPlacesView(settings: settings)
                    } label: {
                        HStack {
                            Label("Decimal Places", systemImage: "number")
                                .foregroundStyle(.primary)
                            Spacer()
                            Text("\(settings.grinDecimalPlaces)")
                                .foregroundStyle(.secondary)
                        }
                    }

                    NavigationLink {
                        SendShortcutsView(settings: settings)
                    } label: {
                        Label("Send Shortcuts", systemImage: "bolt.fill")
                            .foregroundStyle(.primary)
                    }
                }

                // MARK: - Nearby
                Section {
                    Toggle("Nearby Communications", isOn: Binding(
                        get: { settings.nearbyEnabled },
                        set: { newValue in
                            settings.nearbyEnabled = newValue
                            if newValue {
                                if let name = WalletStore.shared.activeWallet {
                                    nearbyService?.updateDisplayName(name)
                                }
                                nearbyService?.startAdvertising()
                            } else {
                                nearbyService?.disconnect()
                            }
                        }
                    ))
                    .tint(.green)

                    if settings.nearbyEnabled, let name = WalletStore.shared.activeWallet {
                        LabeledContent("Discovery Name", value: name)
                            .font(.system(size: 15))
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Nearby")
                } footer: {
                    if settings.nearbyEnabled {
                        Text("Your active wallet name is used for nearby peer discovery.")
                    } else {
                        Text("Enable to discover nearby wallets for peer-to-peer transactions via Bluetooth.")
                    }
                }

                // MARK: - Node
                Section {
                    LabeledContent("Node URL") {
                        Text(settings.nodeURL)
                            .font(.system(size: 15, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }

                    LabeledContent("Port") {
                        Text(settings.nodePort)
                            .font(.system(size: 15, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("Use TLS (HTTPS)")
                        Spacer()
                        Image(systemName: settings.nodeUseTLS ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(settings.nodeUseTLS ? .green : .secondary)
                    }

                    if settings.advancedMode {
                        LabeledContent("Endpoint") {
                            Text(settings.fullNodeURL)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }

                    // Status + Connect
                    HStack {
                        nodeStatusView
                        Spacer()
                        Button {
                            Task { await checkNodeConnection() }
                        } label: {
                            Group {
                                if nodeCheckStatus == .checking {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Text(nodeCheckStatus.isConnected ? "Reconnect" : "Connect")
                                }
                            }
                            .frame(minWidth: 72)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                        .disabled(nodeCheckStatus == .checking || settings.nodeURL.isEmpty)
                    }
                } header: {
                    Text("Node Connection")
                } footer: {
                    Text("Testnet node is pre-configured. Height updates automatically every 5 seconds.")
                }
                .onChange(of: walletService?.nodeHeight ?? 0) { _, newHeight in
                    if newHeight > 0, nodeCheckStatus != .checking {
                        nodeCheckStatus = .connected(height: newHeight)
                    }
                }
                .onChange(of: walletService?.nodeStatus) { _, newStatus in
                    guard nodeCheckStatus != .checking else { return }
                    if newStatus == .disconnected {
                        nodeCheckStatus = .failed("Disconnected")
                    }
                }

                // MARK: - Wallet Backup
                Section {
                    Button {
                        if seedPhrase != nil {
                            // Already loaded — toggle visibility
                            showSeedPhrase.toggle()
                            if !showSeedPhrase {
                                seedPhrase = nil
                                seedPhrasePassword = ""
                            }
                        } else {
                            showPasswordPrompt.toggle()
                            seedPhraseError = nil
                        }
                    } label: {
                        Label("Show Recovery Phrase", systemImage: "key.fill")
                            .foregroundStyle(.primary)
                    }

                    if showPasswordPrompt && seedPhrase == nil {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Enter your wallet password to reveal the recovery phrase.")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)

                            SecureField("Wallet Password", text: $seedPhrasePassword)
                                .font(.system(size: 15, design: .monospaced))
                                .textContentType(.password)

                            if let error = seedPhraseError {
                                Text(error)
                                    .font(.system(size: 12))
                                    .foregroundStyle(.red)
                            }

                            Button {
                                Task { await fetchRecoveryPhrase() }
                            } label: {
                                Group {
                                    if seedPhraseLoading {
                                        ProgressView()
                                            .controlSize(.small)
                                    } else {
                                        Text("Reveal")
                                    }
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.orange)
                            .disabled(seedPhrasePassword.isEmpty || seedPhraseLoading)
                        }
                    }

                    if showSeedPhrase, let phrase = seedPhrase {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                                Text("Keep this secret. Anyone with these words can access your wallet.")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.orange)
                            }

                            let words = phrase.split(separator: " ")
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                                ForEach(Array(words.enumerated()), id: \.offset) { index, word in
                                    HStack(spacing: 4) {
                                        Text("\(index + 1).")
                                            .font(.system(size: 10))
                                            .foregroundStyle(.tertiary)
                                            .frame(width: 18, alignment: .trailing)
                                        Text(String(word))
                                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                                    }
                                    .padding(.vertical, 5)
                                    .padding(.horizontal, 6)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(.primary.opacity(0.06))
                                    )
                                }
                            }
                            .textSelection(.enabled)
                        }
                    }

                    if settings.advancedMode {
                        Stepper(value: $settings.minimumConfirmations, in: 1...30) {
                            HStack {
                                Text("Min Confirmations")
                                Spacer()
                                Text("\(settings.minimumConfirmations)")
                                    .foregroundStyle(.secondary)
                                    .font(.system(size: 15, design: .monospaced))
                            }
                        }

                        if let walletService {
                            NavigationLink {
                                OutputsView(walletService: walletService, decimalPlaces: settings.grinDecimalPlaces)
                            } label: {
                                Label("Wallet Outputs", systemImage: "square.stack.3d.up")
                                    .foregroundStyle(.primary)
                            }

                            NavigationLink {
                                SplitOutputsView(walletService: walletService)
                            } label: {
                                Label("Split Outputs", systemImage: "square.split.2x2")
                                    .foregroundStyle(.primary)
                            }
                        }
                    }
                } header: {
                    Text("Wallet")
                } footer: {
                    if settings.advancedMode {
                        Text("Outputs require this many block confirmations before they can be spent. Default is 10.")
                    }
                }

                // MARK: - Wallets
                Section {
                    ForEach(WalletStore.shared.wallets, id: \.self) { wallet in
                        HStack {
                            Image(systemName: wallet == WalletStore.shared.activeWallet ? "wallet.pass.fill" : "wallet.pass")
                                .foregroundStyle(wallet == WalletStore.shared.activeWallet ? .primary : .secondary)
                            Text(wallet)
                                .font(.system(size: 15))
                            Spacer()
                            if wallet == WalletStore.shared.activeWallet {
                                Text("Active")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(.green)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            guard wallet != WalletStore.shared.activeWallet else { return }
                            WalletStore.shared.activeWallet = wallet
                            if settings.nearbyEnabled {
                                nearbyService?.updateDisplayName(wallet)
                            }
                            Task {
                                await walletService?.refresh()
                            }
                        }
                    }

                    Button {
                        showCreateWallet = true
                    } label: {
                        Label("Create New Wallet", systemImage: "plus.circle")
                    }

                    Button {
                        showRestoreWallet = true
                    } label: {
                        Label("Restore Wallet", systemImage: "arrow.counterclockwise.circle")
                    }
                    if let walletService {
                        ScanRepairRow(
                            walletService: walletService,
                            settings: settings,
                            showScanConfirm: $showScanConfirm,
                            scanStartTime: $scanStartTime
                        )
                    }
                } header: {
                    Text("Wallets")
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Tap a wallet to switch. Scan & Repair reconciles your wallet against the blockchain.")
                        if let date = settings.lastScanDate, let result = settings.lastScanResult {
                            let duration = settings.lastScanDuration
                            let durationStr = duration >= 60
                                ? String(format: "%dm %ds", Int(duration) / 60, Int(duration) % 60)
                                : String(format: "%ds", Int(duration))
                            Text("Last scan: \(date.formatted(.dateTime.day().month(.abbreviated).hour().minute())) — \(result) (\(durationStr))")
                        }
                        if let error = walletService?.errorMessage, !error.isEmpty {
                            Text(error)
                                .foregroundStyle(.red)
                        }
                    }
                }

                // MARK: - Security
                Section {
                    Toggle(biometricLabel, isOn: Binding(
                        get: { WalletStore.shared.biometricEnabled },
                        set: { newValue in
                            biometricError = nil
                            if newValue {
                                // Prompt biometric authentication before enabling
                                let context = LAContext()
                                var error: NSError?
                                if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
                                    context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics,
                                                           localizedReason: "Enable \(biometricLabel) to unlock your Grin wallet") { success, authError in
                                        DispatchQueue.main.async {
                                            WalletStore.shared.biometricEnabled = success
                                            if !success, let authError = authError as? LAError, authError.code != .userCancel {
                                                biometricError = "Authentication failed. Try again."
                                            }
                                        }
                                    }
                                } else {
                                    WalletStore.shared.biometricEnabled = false
                                    if let error {
                                        switch (error as NSError).code {
                                        case LAError.biometryNotEnrolled.rawValue:
                                            biometricError = "\(biometricLabel) is not set up. Enable it in Settings > \(biometricLabel) & Passcode."
                                        case LAError.biometryNotAvailable.rawValue:
                                            biometricError = "\(biometricLabel) is not available on this device."
                                        default:
                                            biometricError = "\(biometricLabel) is unavailable. Check your device settings."
                                        }
                                    }
                                }
                            } else {
                                WalletStore.shared.biometricEnabled = false
                            }
                        }
                    ))
                    .tint(.green)

                    if let biometricError {
                        Text(biometricError)
                            .font(.system(size: 12))
                            .foregroundStyle(.red)
                    }
                } header: {
                    Text("Security")
                } footer: {
                    Text("Use \(biometricLabel) to unlock your wallet instead of entering your password.")
                }

                // MARK: - About
                Section("About") {
                    LabeledContent("Version", value: "2.0.0")
                    LabeledContent("Build", value: "1")

                    Link(destination: URL(string: "https://grin.mw")!) {
                        Label("Grin Website", systemImage: "globe")
                            .foregroundStyle(.primary)
                    }

                    Link(destination: URL(string: "https://github.com/mimblewimble/grin")!) {
                        Label("GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                            .foregroundStyle(.primary)
                    }

                    if settings.advancedMode {
                        Link(destination: URL(string: "https://github.com/mimblewimble/grin-wallet")!) {
                            Label("Wallet API Docs", systemImage: "doc.text")
                                .foregroundStyle(.primary)
                        }
                    }
                }

                // MARK: - Debug (temporary)
                if settings.advancedMode {
                    Section("Debug: Raw TX Data") {
                        if let log = walletService?.debugTxLog, !log.isEmpty {
                            ShareLink(item: log) {
                                Label("Export Raw TX Data", systemImage: "square.and.arrow.up")
                            }
                        }

                        Text(walletService?.debugTxLog ?? "(no wallet service)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
            }
            .navigationTitle("Settings")
            .sheet(isPresented: $showCreateWallet) {
                CreateWalletSheet(settings: settings)
            }
            .sheet(isPresented: $showRestoreWallet) {
                RestoreWalletSheet(settings: settings)
            }
            .sheet(isPresented: $showScanConfirm) {
                ScanConfirmSheet(
                    scanFromDate: $scanFromDate,
                    scanDate: $scanDate,
                    nodeHeight: walletService?.nodeHeight ?? 0,
                    settings: settings,
                    walletName: WalletStore.shared.activeWallet ?? "default"
                ) { startHeight in
                    showScanConfirm = false
                    scanStartTime = Date()
                    Task {
                        let success = await walletService?.scanAndRepair(startHeight: startHeight) ?? false
                        let wasCancelled = walletService?.scanCancelled == true

                        if !wasCancelled {
                            let duration = Date().timeIntervalSince(scanStartTime ?? Date())
                            settings.lastScanDate = Date()
                            settings.lastScanResult = success ? "completed" : "failed"
                            settings.lastScanDuration = duration
                            showScanResult = true
                        }
                        scanStartTime = nil
                    }
                }
            }
            .alert(scanResultTitle, isPresented: $showScanResult) {
                Button("OK") { }
            } message: {
                Text(scanResultMessage)
            }

            .onAppear {
                // Auto-check on appear if we haven't checked yet
                if nodeCheckStatus == .idle && !settings.nodeURL.isEmpty {
                    Task { await checkNodeConnection() }
                }
            }
            .toolbar {
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

    // MARK: - Node Status View

    @ViewBuilder
    private var nodeStatusView: some View {
        switch nodeCheckStatus {
        case .idle:
            HStack(spacing: 6) {
                Image(systemName: "circle.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(.gray)
                Text("Not checked")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
        case .checking:
            HStack(spacing: 6) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
                    .symbolEffect(.rotate)
                Text("Connecting…")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
        case .connected(let height):
            HStack(spacing: 6) {
                Image(systemName: "circle.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(.green)
                Text("Connected")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.green)
                Text("(\(height))")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        case .failed(let message):
            HStack(spacing: 6) {
                Image(systemName: "circle.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(.red)
                Text(message)
                    .font(.system(size: 13))
                    .foregroundStyle(.red)
                    .lineLimit(1)
            }
        }
    }

    // MARK: - Recovery Phrase

    private func fetchRecoveryPhrase() async {
        seedPhraseLoading = true
        seedPhraseError = nil

        // Verify password matches the stored password first
        guard let walletName = WalletStore.shared.activeWallet,
              let storedPassword = WalletStore.shared.password(for: walletName) else {
            seedPhraseError = "No active wallet"
            seedPhraseLoading = false
            return
        }

        guard seedPhrasePassword == storedPassword else {
            seedPhraseError = "Incorrect password"
            seedPhraseLoading = false
            return
        }

        if let phrase = await walletService?.getRecoveryPhrase() {
            seedPhrase = phrase
            showSeedPhrase = true
            showPasswordPrompt = false
            seedPhrasePassword = ""
        } else {
            seedPhraseError = walletService?.errorMessage ?? "Failed to retrieve recovery phrase"
        }
        seedPhraseLoading = false
    }

    // MARK: - Node Check (pure HTTP, no FFI)

    private func checkNodeConnection() async {
        nodeCheckStatus = .checking

        let endpoint = settings.foreignNodeURL

        guard let url = URL(string: endpoint) else {
            nodeCheckStatus = .failed("Invalid URL")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 8

        let body: [String: Any] = [
            "jsonrpc": "2.0",
            "id": 1,
            "method": "get_tip",
            "params": []
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                nodeCheckStatus = .failed("No response")
                return
            }

            guard httpResponse.statusCode == 200 else {
                nodeCheckStatus = .failed("HTTP \(httpResponse.statusCode)")
                return
            }

            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let result = json["result"] as? [String: Any],
               let ok = result["Ok"] as? [String: Any],
               let height = ok["height"] as? UInt64 {
                nodeCheckStatus = .connected(height: height)
                walletService?.nodeStatus = .connected
            } else {
                // Still got a 200 response — node is reachable
                nodeCheckStatus = .connected(height: 0)
                walletService?.nodeStatus = .connected
            }
        } catch let error as URLError {
            walletService?.nodeStatus = .disconnected
            switch error.code {
            case .timedOut:
                nodeCheckStatus = .failed("Timed out")
            case .cannotConnectToHost:
                nodeCheckStatus = .failed("Can't connect")
            case .notConnectedToInternet:
                nodeCheckStatus = .failed("No internet")
            default:
                nodeCheckStatus = .failed("Network error")
            }
        } catch {
            walletService?.nodeStatus = .disconnected
            nodeCheckStatus = .failed("Failed")
        }
    }
}

// MARK: - Scan & Repair Row

private struct ScanRepairRow: View {
    var walletService: WalletService
    var settings: AppSettings
    @Binding var showScanConfirm: Bool
    @Binding var scanStartTime: Date?

    var body: some View {
        HStack {
            Label("Scan & Repair", systemImage: "arrow.triangle.2.circlepath")
            Spacer()
            if walletService.scanInProgress {
                ProgressView()
                    .controlSize(.small)
                Button {
                    walletService.cancelScan()
                    settings.lastScanDate = Date()
                    settings.lastScanResult = "cancelled"
                    settings.lastScanDuration = Date().timeIntervalSince(scanStartTime ?? Date())
                    scanStartTime = nil
                } label: {
                    Text("Cancel")
                        .frame(minWidth: 72)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            } else {
                Button {
                    showScanConfirm = true
                } label: {
                    Text("Start")
                        .frame(minWidth: 72)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
            }
        }

        if walletService.scanInProgress {
            VStack(spacing: 6) {
                if let name = WalletStore.shared.activeWallet {
                    Text("Scanning \"\(name)\"")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                ProgressView(value: Double(walletService.scanProgress), total: 100)
                    .tint(.green)
                Text("\(walletService.scanProgress)%")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            if !walletService.scanNodeReachable {
                HStack(spacing: 6) {
                    Image(systemName: "wifi.exclamationmark")
                        .foregroundStyle(.red)
                        .font(.system(size: 12))
                    Text("Node connection lost — scan may be stalled")
                        .font(.system(size: 12))
                        .foregroundStyle(.red)
                }
            }
        }
    }
}

// MARK: - Scan Confirm Sheet

private struct ScanConfirmSheet: View {
    @Binding var scanFromDate: Bool
    @Binding var scanDate: Date
    var nodeHeight: UInt64
    var settings: AppSettings
    var walletName: String
    var onStart: (UInt64) -> Void
    @Environment(\.dismiss) private var dismiss

    /// Grin mainnet genesis: 2019-01-15 16:01:26 UTC
    private static let genesisDate: Date = {
        var c = DateComponents()
        c.year = 2019; c.month = 1; c.day = 15
        c.hour = 16; c.minute = 1; c.second = 26
        c.timeZone = TimeZone(identifier: "UTC")
        return Calendar.current.date(from: c) ?? Date()
    }()

    private var estimatedHeight: UInt64 {
        guard scanFromDate else { return 0 }
        return settings.estimateHeight(for: scanDate, currentHeight: nodeHeight)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Wallet") {
                        Text(walletName)
                            .font(.system(size: 15, weight: .medium))
                    }

                    Text("This will reconcile your wallet against the blockchain. It may take several minutes and will block all wallet operations until complete.")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)

                    Text("Do not close the app while the scan is in progress.")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.orange)
                }

                Section {
                    Toggle("Scan from a specific date", isOn: $scanFromDate.animation())
                        .tint(.green)

                    if scanFromDate {
                        DatePicker(
                            "Start date",
                            selection: $scanDate,
                            in: Self.genesisDate...Date(),
                            displayedComponents: .date
                        )

                        LabeledContent("Estimated block height") {
                            Text("~\(estimatedHeight)")
                                .font(.system(size: 14, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                } footer: {
                    if scanFromDate {
                        Text("Scanning from a later date is faster but may miss older transactions.")
                    } else {
                        Text("A full scan checks from the genesis block. This is thorough but slower.")
                    }
                }

                Section {
                    Button {
                        onStart(estimatedHeight)
                    } label: {
                        HStack {
                            Spacer()
                            Text("Start Scan")
                                .fontWeight(.semibold)
                            Spacer()
                        }
                    }
                    .tint(.green)
                }
            }
            .navigationTitle("Scan & Repair")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Send Shortcuts View

private struct SendShortcutsView: View {
    @Bindable var settings: AppSettings

    var body: some View {
        Form {
            Section {
                Toggle("Show Quick Buttons", isOn: $settings.showQuickButtons)
                    .tint(.green)
            } footer: {
                Text("Show quick adjust buttons on the send page for common amounts.")
            }

            if settings.showQuickButtons {
                Section("Buttons") {
                    QuickButtonRow(label: "Button 1", value: $settings.quickButton1)
                    QuickButtonRow(label: "Button 2", value: $settings.quickButton2)
                    QuickButtonRow(label: "Button 3", value: $settings.quickButton3)
                    QuickButtonRow(label: "Button 4", value: $settings.quickButton4)
                }
            }
        }
        .navigationTitle("Send Shortcuts")
        .toolbar {
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

private struct QuickButtonRow: View {
    let label: String
    @Binding var value: Double

    @State private var isNegative: Bool = false
    @State private var magnitude: String = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack {
            Text(label)

            Spacer()

            Picker("", selection: $isNegative) {
                Text("+").tag(false)
                Text("−").tag(true)
            }
            .pickerStyle(.segmented)
            .frame(width: 80)

            TextField("0", text: $magnitude)
                .font(.system(size: 15, design: .monospaced))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 60)
                .focused($isFocused)
        }
        .onAppear {
            isNegative = value < 0
            magnitude = String(format: "%g", abs(value))
        }
        .onChange(of: isNegative) { _, _ in updateValue() }
        .onChange(of: magnitude) { _, _ in updateValue() }
    }

    private func updateValue() {
        let mag = Double(magnitude) ?? 0
        value = isNegative ? -mag : mag
    }
}

// MARK: - Decimal Places View

private struct DecimalPlacesView: View {
    @Bindable var settings: AppSettings

    private let sampleAmount: Double = 1.23456789

    var body: some View {
        Form {
            Section {
                VStack(spacing: 20) {
                    Text(String(format: "%.\(settings.grinDecimalPlaces)f", sampleAmount))
                        .font(.system(size: 36, weight: .bold, design: .monospaced))
                        .foregroundStyle(.primary)
                        .contentTransition(.numericText())
                        .animation(.default, value: settings.grinDecimalPlaces)

                    HStack(spacing: 24) {
                        Button {
                            if settings.grinDecimalPlaces > 0 {
                                settings.grinDecimalPlaces -= 1
                            }
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .font(.system(size: 36))
                                .foregroundStyle(Color.primary.opacity(settings.grinDecimalPlaces > 0 ? 1 : 0.2))
                        }
                        .disabled(settings.grinDecimalPlaces <= 0)
                        .buttonStyle(.plain)

                        Text("\(settings.grinDecimalPlaces)")
                            .font(.system(size: 28, weight: .bold, design: .monospaced))
                            .frame(minWidth: 40)
                            .contentTransition(.numericText())
                            .animation(.default, value: settings.grinDecimalPlaces)

                        Button {
                            if settings.grinDecimalPlaces < 8 {
                                settings.grinDecimalPlaces += 1
                            }
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 36))
                                .foregroundStyle(Color.primary.opacity(settings.grinDecimalPlaces < 8 ? 1 : 0.2))
                        }
                        .disabled(settings.grinDecimalPlaces >= 8)
                        .buttonStyle(.plain)
                    }

                    Text("decimal place\(settings.grinDecimalPlaces == 1 ? "" : "s")")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            } footer: {
                Text("Grin amounts have up to 8 decimal places (1 nanogrin = 0.000000001). Choose how many to display.")
            }
        }
        .navigationTitle("Decimal Places")
    }
}

#Preview {
    SettingsView(settings: AppSettings(), walletService: nil, nearbyService: nil)
        .preferredColorScheme(.dark)
}
