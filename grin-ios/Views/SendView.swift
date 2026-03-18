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
//  SendView.swift
//  grin-ios
//

import SwiftUI

struct SendView: View {
    @Environment(\.dismiss) private var dismiss
    let walletService: WalletService
    let settings: AppSettings
    let nearbyService: NearbyService

    @State private var amount: Double = 0.0
    @State private var showNearbySearch = false
    @State private var selectedPeer: NearbyPeer?
    @State private var nearbyTransferStatus: String = ""
    @State private var showQRCode = false
    @State private var qrVisible = false
    @State private var showQRScanner = false
    @State private var manualEntry: String = ""
    @State private var isEditingAmount: Bool = false
    @FocusState private var amountFieldFocused: Bool
    @State private var generatedSlatepack: Slatepack?
    @State private var step: SendStep = .enterAmount
    @State private var responseSlatepack: String = ""
    @State private var finalized: Bool = false
    @State private var errorMessage: String?
    @State private var txFee: Double = 0.023

    // Invoice mode state
    @State private var invoiceInput: String = ""
    @State private var invoiceAmount: Double = 0.0
    @State private var invoiceResponseSlatepack: Slatepack?

    enum SendStep {
        // SRS mode (existing)
        case enterAmount
        case shareSlatepack
        case pasteResponse
        case nearbyConfirm
        case finalized

        // RSR mode (new)
        case invoicePaste
        case invoiceConfirm
        case invoiceShareResponse
        case invoiceFinalized
    }

    private var amountFormat: String {
        "%.\(settings.grinDecimalPlaces)f"
    }

    private var maxSendable: Double {
        max(walletService.spendableBalance - txFee, 0)
    }

    private var canSend: Bool {
        amount > 0 && (amount + txFee) <= walletService.spendableBalance
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                stepIndicator

                switch step {
                case .enterAmount:
                    enterAmountView
                case .shareSlatepack:
                    shareSlatepackView
                case .pasteResponse:
                    pasteResponseView
                case .nearbyConfirm:
                    nearbyConfirmView
                case .finalized:
                    finalizedView
                case .invoicePaste:
                    invoicePasteView
                case .invoiceConfirm:
                    invoiceConfirmView
                case .invoiceShareResponse:
                    invoiceShareResponseView
                case .invoiceFinalized:
                    invoiceFinalizedView
                }

                Spacer()
            }
            .padding(20)
            .navigationTitle("Send")
            .navigationBarTitleDisplayMode(.inline)
            .onDisappear {
                // If view dismissed without finalizing, unlock wallet refreshes
                if step != .finalized && step != .invoiceFinalized {
                    walletService.sendInProgress = false
                }
                // Reset nearby send flow flag so auto-receive works again
                nearbyService.isSendFlowActive = false
                nearbyService.resetSendingStatus()
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if step == .enterAmount {
                        Button("Cancel") { dismiss() }
                            .foregroundStyle(.secondary)
                    } else if step != .finalized && step != .invoiceFinalized {
                        Button {
                            withAnimation {
                                switch step {
                                case .shareSlatepack: step = .enterAmount
                                case .pasteResponse: step = .shareSlatepack
                                case .invoiceConfirm: step = .invoicePaste
                                case .invoiceShareResponse: step = .invoiceConfirm
                                default: break
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 14, weight: .medium))
                                Text("Back")
                            }
                            .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .sheet(isPresented: $showQRScanner) {
                QRScannerView { scannedText in
                    showQRScanner = false
                    if step == .invoicePaste {
                        invoiceInput = scannedText
                    } else {
                        responseSlatepack = scannedText
                    }
                }
            }
        }
    }

    // MARK: - Step Indicator

    private var stepIndicator: some View {
        HStack(spacing: 8) {
            ForEach(0..<3) { i in
                Capsule()
                    .fill(i <= stepIndex ? .white : .white.opacity(0.15))
                    .frame(height: 3)
                    .onTapGesture {
                        // Only allow going back
                        if i < stepIndex {
                            withAnimation {
                                switch i {
                                case 0: step = .enterAmount
                                case 1: step = .shareSlatepack
                                default: break
                                }
                            }
                        }
                    }
            }
        }
    }

    private var stepIndex: Int {
        switch step {
        case .enterAmount: return 0
        case .shareSlatepack: return 1
        case .pasteResponse, .nearbyConfirm, .finalized: return 2
        case .invoicePaste: return 0
        case .invoiceConfirm: return 1
        case .invoiceShareResponse, .invoiceFinalized: return 2
        }
    }

    // MARK: - Enter Amount

    private var enterAmountView: some View {
        VStack(spacing: 16) {
            // Amount display above dial (tap to edit)
            VStack(spacing: 4) {
                ZStack {
                    // Hidden text field for keyboard input
                    TextField("", text: $manualEntry)
                        .keyboardType(.decimalPad)
                        .focused($amountFieldFocused)
                        .opacity(0)
                        .frame(width: 0, height: 0)
                        .toolbar {
                            ToolbarItemGroup(placement: .keyboard) {
                                Spacer()
                                Button("Done") {
                                    if let val = Double(manualEntry) {
                                        amount = min(max(val, 0), maxSendable)
                                    }
                                    isEditingAmount = false
                                    amountFieldFocused = false
                                }
                                .fontWeight(.semibold)
                            }
                        }
                        .onChange(of: manualEntry) { _, newValue in
                            if let val = Double(newValue), val > maxSendable {
                                manualEntry = String(format: amountFormat, maxSendable)
                            }
                        }
                        .onChange(of: amountFieldFocused) { _, focused in
                            if !focused, let val = Double(manualEntry) {
                                amount = min(max(val, 0), maxSendable)
                                isEditingAmount = false
                            }
                        }

                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        if isEditingAmount {
                            Text(manualEntry.isEmpty ? "0" : manualEntry)
                                .font(.system(size: 42, weight: .bold, design: .monospaced))
                                .foregroundStyle(.primary)
                        } else {
                            Text(String(format: amountFormat, amount))
                                .font(.system(size: 42, weight: .bold, design: .monospaced))
                                .foregroundStyle(.primary)
                                .contentTransition(.numericText())
                        }
                        Text("ツ")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .onTapGesture {
                        manualEntry = amount > 0 ? String(format: amountFormat, amount) : ""
                        isEditingAmount = true
                        amountFieldFocused = true
                    }
                }

                Text("Available: \(String(format: amountFormat, maxSendable)) ツ (fee: \(String(format: "%.3f", txFee)))")
                    .font(.system(size: 13))
                    .foregroundStyle(.tertiary)
            }

            // Rotating dial
            AmountDial(amount: $amount, maxAmount: maxSendable)
                .frame(width: 200, height: 200)

            // Quick adjust buttons
            if settings.showQuickButtons {
                let buttons = [settings.quickButton1, settings.quickButton2, settings.quickButton3, settings.quickButton4]
                HStack(spacing: 10) {
                    ForEach(Array(buttons.enumerated()), id: \.offset) { _, val in
                        Button {
                            withAnimation(.interactiveSpring) {
                                amount = min(max(amount + val, 0), maxSendable)
                            }
                        } label: {
                            Text(val >= 0 ? "+\(formatButton(val))" : "−\(formatButton(abs(val)))")
                                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                                .frame(width: 52, height: 38)
                        }
                        .buttonStyle(.bordered)
                        .tint(.white)
                    }
                }
            }

            if let error = errorMessage {
                Text(error)
                    .font(.system(size: 13))
                    .foregroundStyle(.red)
            }

            Button {
                Task {
                    if let estimatedFee = await walletService.estimateFee(amount: amount) {
                        txFee = estimatedFee
                        // If amount + real fee exceeds spendable, reduce amount
                        // Use a small tolerance (1 nanogrin) to avoid floating-point edge cases at max
                        let spendable = walletService.spendableBalance
                        let tolerance = 1.0 / 1_000_000_000.0
                        if amount + txFee > spendable + tolerance {
                            amount = max(spendable - txFee, 0)
                        }
                    }
                    guard amount > 0 else {
                        errorMessage = "Insufficient balance after fee"
                        return
                    }
                    generatedSlatepack = await walletService.initiateSend(amount: amount)
                    if generatedSlatepack != nil {
                        withAnimation { step = .shareSlatepack }
                    } else {
                        errorMessage = walletService.errorMessage ?? "Failed to create slatepack"
                    }
                }
            } label: {
                Text("Generate Slatepack")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(.white)
            .foregroundStyle(.black)
            .disabled(!canSend)

            nearbySearchSection

            Button {
                withAnimation { step = .invoicePaste }
            } label: {
                Text("Pay an Invoice instead?")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Nearby Search

    @ViewBuilder
    private var nearbySearchSection: some View {
        if settings.nearbyEnabled {
        VStack(spacing: 12) {
            Button {
                showNearbySearch.toggle()
                if showNearbySearch {
                    nearbyService.startSearching()
                } else {
                    nearbyService.stopSearching()
                }
            } label: {
                Label("Find Nearby Device", systemImage: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 15, weight: .medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.bordered)
            .tint(.white)
            .disabled(!canSend)

            if showNearbySearch {
                nearbyPeerList
            }
        }
        }
    }

    private var nearbyPeerList: some View {
        VStack(spacing: 0) {
            if nearbyService.isSearching && nearbyService.peers.isEmpty {
                HStack(spacing: 10) {
                    ProgressView()
                        .tint(.white)
                    Text("Searching…")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
            }

            ForEach(nearbyService.peers) { peer in
                nearbyPeerButton(for: peer)

                if peer.id != nearbyService.peers.last?.id {
                    Divider().overlay(.white.opacity(0.06))
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(.white.opacity(0.08), lineWidth: 1)
                )
        )
    }

    private func nearbyPeerButton(for peer: NearbyPeer) -> some View {
        HStack {
            Image(systemName: peer.status == .connected ? "iphone.radiowaves.left.and.right" : "iphone")
                .foregroundStyle(peer.status == .connected ? .green : .secondary)
            Text(peer.displayName)
                .font(.system(size: 15))
                .foregroundStyle(.primary)
            Spacer()
            if selectedPeer?.id == peer.id {
                VStack(alignment: .trailing, spacing: 4) {
                    ProgressView()
                        .tint(.primary)
                    Text(nearbyTransferStatus)
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            } else if peer.status == .connecting {
                HStack(spacing: 8) {
                    ProgressView()
                        .tint(.secondary)
                        .controlSize(.small)
                    Text("Connecting…")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
            } else {
                Button {
                    selectedPeer = peer
                    nearbyTransferStatus = "Generating slatepack…"
                    Task { await sendViaNearby(to: peer) }
                } label: {
                    Text("Send")
                        .font(.system(size: 14, weight: .semibold))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(selectedPeer != nil)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 16)
    }

    private func sendViaNearby(to peer: NearbyPeer) async {
        nearbyService.isSendFlowActive = true
        if let estimatedFee = await walletService.estimateFee(amount: amount) {
            txFee = estimatedFee
            let spendable = walletService.spendableBalance
            if amount + txFee > spendable {
                amount = max(spendable - txFee, 0)
            }
        }
        guard amount > 0 else {
            nearbyTransferStatus = "Insufficient balance after fee"
            return
        }
        generatedSlatepack = await walletService.initiateSend(amount: amount)
        guard let slatepack = generatedSlatepack else {
            nearbyTransferStatus = "Failed to create slatepack"
            return
        }

        nearbyTransferStatus = "Sending to \(peer.displayName)…"
        // Send the raw FFI string — never a reconstructed version
        await nearbyService.sendSlatepack(slatepack.fullString, amount: amount, to: peer)

        nearbyTransferStatus = "Waiting for \(peer.displayName) to sign…"

        var attempts = 0
        while nearbyService.receivedSlatepack == nil && attempts < 60 {
            try? await Task.sleep(for: .seconds(1))
            attempts += 1
        }

        if nearbyService.receivedSlatepack != nil {
            nearbyTransferStatus = "Response received — finalising…"
            // Use the raw slatepack string to preserve exact FFI formatting
            responseSlatepack = nearbyService.receivedRawSlatepack ?? nearbyService.receivedSlatepack!.fullString
            nearbyService.receivedSlatepack = nil
            nearbyService.receivedRawSlatepack = nil
            // Don't reset sendingStatus or isSendFlowActive here — keep them active
            // until the send sheet is dismissed to prevent auto-receive of late data
            withAnimation { step = .nearbyConfirm }
        } else {
            nearbyTransferStatus = "Timed out waiting for response"
        }
    }

    // MARK: - Share Slatepack

    private var shareSlatepackView: some View {
        VStack(spacing: 20) {
            Text("Share This Slatepack")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(1.2)

            Text("Send this to the recipient. They will sign it and return a response slatepack.")
                .font(.system(size: 14))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)

            if let slatepack = generatedSlatepack {
                if showQRCode {
                    QRCodeView(data: slatepack.fullString)
                        .frame(width: 200, height: 200)
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(.white)
                        )
                        .opacity(qrVisible ? 1 : 0)
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                withAnimation(.easeIn(duration: 0.25)) {
                                    qrVisible = true
                                }
                            }
                        }
                } else {
                    SlatepackDisplay(slatepack: slatepack, advancedMode: settings.advancedMode)

                    ShareLink(item: slatepack.fullString) {
                        Label("Share", systemImage: "square.and.arrow.up")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.white)
                    .foregroundStyle(.black)
                }
            }

            // Show as QR Code
            Button {
                qrVisible = false
                showQRCode.toggle()
            } label: {
                Label(showQRCode ? "Show Slatepack" : "Show as QR Code", systemImage: showQRCode ? "doc.plaintext" : "qrcode")
                    .font(.system(size: 15, weight: .medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.bordered)
            .tint(.white)

            Button {
                withAnimation { step = .pasteResponse }
            } label: {
                Text("I Have the Response")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Paste Response

    private var pasteResponseView: some View {
        VStack(spacing: 20) {
            Text("Paste Response Slatepack")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(1.2)

            Text("Paste the signed slatepack from the recipient to finalise the transaction.")
                .font(.system(size: 14))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)

            TextEditor(text: $responseSlatepack)
                .font(.system(size: 13, design: .monospaced))
                .frame(minHeight: 120)
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

            HStack(spacing: 12) {
                Button {
                    if let pasted = UIPasteboard.general.string {
                        responseSlatepack = pasted
                    }
                } label: {
                    Label("Paste", systemImage: "doc.on.clipboard")
                        .font(.system(size: 14, weight: .medium))
                }
                .buttonStyle(.bordered)
                .tint(.white)

                Button {
                    showQRScanner = true
                } label: {
                    Label("Scan", systemImage: "qrcode.viewfinder")
                        .font(.system(size: 14, weight: .medium))
                }
                .buttonStyle(.bordered)
                .tint(.white)

                Button {
                    Task {
                        errorMessage = nil
                        let success = await walletService.finalizeTransaction(responseSlatepack)
                        if success {
                            withAnimation { step = .finalized }
                        } else {
                            errorMessage = walletService.errorMessage ?? "Finalisation failed"
                        }
                    }
                } label: {
                    if walletService.isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    } else {
                        Text("Finalise")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.white)
                .foregroundStyle(.black)
                .disabled(responseSlatepack.isEmpty || walletService.isLoading)
            }

            if let error = errorMessage {
                Text(error)
                    .font(.system(size: 13))
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
        }
    }

    // MARK: - Nearby Confirm

    private var nearbyConfirmView: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 48))
                .foregroundStyle(.green)

            Text("Ready to Finalise")
                .font(.system(size: 20, weight: .semibold))

            if let peer = selectedPeer {
                Text("\(peer.displayName) has signed the transaction.")
                    .font(.system(size: 14))
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 8) {
                HStack {
                    Text("Amount")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(String(format: amountFormat, amount)) ツ")
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                }
                HStack {
                    Text("Fee")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(String(format: "%.3f", txFee)) ツ")
                        .font(.system(size: 14, design: .monospaced))
                }
                Divider().overlay(.white.opacity(0.1))
                HStack {
                    Text("Total")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(String(format: amountFormat, amount + txFee)) ツ")
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(.white.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(.white.opacity(0.08), lineWidth: 1)
                    )
            )

            // Testnet warning
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("This wallet is for testnet Grin only. Sending mainnet Grin will result in errors and potential loss of funds.")
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

            if let error = errorMessage {
                Text(error)
                    .font(.system(size: 13))
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            Button {
                Task {
                    errorMessage = nil
                    let success = await walletService.finalizeTransaction(responseSlatepack)
                    if success {
                        withAnimation { step = .finalized }
                    } else {
                        errorMessage = walletService.errorMessage ?? "Finalization failed"
                    }
                }
            } label: {
                Text("Confirm & Send")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(.white)
            .foregroundStyle(.black)
        }
    }

    // MARK: - Finalized

    private var finalizedView: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)

            Text("Transaction Sent")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.primary)

            Text("\(String(format: amountFormat, amount)) ツ")
                .font(.system(size: 28, weight: .bold, design: .monospaced))
                .foregroundStyle(.primary)

            Text("The transaction has been finalised and broadcast to the network.")
                .font(.system(size: 14))
                .foregroundStyle(.tertiary)
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
            .tint(.white)
            .foregroundStyle(.black)
        }
    }

    // MARK: - Invoice: Paste Invoice

    private var invoicePasteView: some View {
        VStack(spacing: 20) {
            Text("Paste Invoice Slatepack")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(1.2)

            Text("Paste the invoice slatepack from the receiver to pay their request.")
                .font(.system(size: 14))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)

            TextEditor(text: $invoiceInput)
                .font(.system(size: 13, design: .monospaced))
                .frame(minHeight: 140)
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

            HStack(spacing: 12) {
                Button {
                    if let pasted = UIPasteboard.general.string {
                        invoiceInput = pasted
                    }
                } label: {
                    Label("Paste", systemImage: "doc.on.clipboard")
                        .font(.system(size: 14, weight: .medium))
                }
                .buttonStyle(.bordered)
                .tint(.white)

                Button {
                    showQRScanner = true
                } label: {
                    Label("Scan", systemImage: "qrcode.viewfinder")
                        .font(.system(size: 14, weight: .medium))
                }
                .buttonStyle(.bordered)
                .tint(.white)

                Button {
                    withAnimation { step = .invoiceConfirm }
                } label: {
                    Text("Review")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .tint(.white)
                .foregroundStyle(.black)
                .disabled(invoiceInput.isEmpty)
            }

            Button {
                withAnimation { step = .enterAmount }
            } label: {
                Text("Send normally instead?")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Invoice: Confirm Payment

    private var invoiceConfirmView: some View {
        VStack(spacing: 20) {
            Image(systemName: "doc.text.fill")
                .font(.system(size: 48))
                .foregroundStyle(Color(red: 1.0, green: 0.76, blue: 0.03))

            Text("Pay Invoice")
                .font(.system(size: 20, weight: .semibold))

            Text("Confirm payment for this invoice request.")
                .font(.system(size: 14))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)

            VStack(spacing: 8) {
                HStack {
                    Text("Available")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(String(format: amountFormat, walletService.spendableBalance)) ツ")
                        .font(.system(size: 14, design: .monospaced))
                }
                HStack {
                    Text("Est. Fee")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(String(format: "%.3f", txFee)) ツ")
                        .font(.system(size: 14, design: .monospaced))
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(.white.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(.white.opacity(0.08), lineWidth: 1)
                    )
            )

            // Testnet warning
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("This wallet is for testnet Grin only. Sending mainnet Grin will result in errors and potential loss of funds.")
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

            if let error = errorMessage {
                Text(error)
                    .font(.system(size: 13))
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            Button {
                Task {
                    errorMessage = nil
                    invoiceResponseSlatepack = await walletService.processInvoice(invoiceInput)
                    if invoiceResponseSlatepack != nil {
                        withAnimation { step = .invoiceShareResponse }
                    } else {
                        errorMessage = walletService.errorMessage ?? "Failed to process invoice"
                    }
                }
            } label: {
                if walletService.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                } else {
                    Text("Pay Invoice")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(.white)
            .foregroundStyle(.black)
            .disabled(walletService.isLoading)
        }
    }

    // MARK: - Invoice: Share Response

    private var invoiceShareResponseView: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 48))
                .foregroundStyle(.green)

            Text("Invoice Processed")
                .font(.system(size: 18, weight: .semibold))

            Text("Share this response with the invoicer so they can finalise the transaction.")
                .font(.system(size: 14))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)

            if let slatepack = invoiceResponseSlatepack {
                SlatepackDisplay(slatepack: slatepack, advancedMode: settings.advancedMode)

                AnimatedQRCodeView(data: slatepack.fullString)
                    .frame(width: 220, height: 260)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 12).fill(.white))

                ShareLink(item: slatepack.fullString) {
                    Label("Share", systemImage: "square.and.arrow.up")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .tint(.white)
                .foregroundStyle(.black)
            }

            Button {
                walletService.sendInProgress = false
                withAnimation { step = .invoiceFinalized }
            } label: {
                Text("Done")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Invoice: Finalized

    private var invoiceFinalizedView: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)

            Text("Invoice Paid")
                .font(.system(size: 20, weight: .semibold))

            Text("Your response has been shared. The invoicer will finalise and broadcast the transaction.")
                .font(.system(size: 14))
                .foregroundStyle(.tertiary)
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
            .tint(.white)
            .foregroundStyle(.black)
        }
    }

    private func formatButton(_ val: Double) -> String {
        val == val.rounded() ? "\(Int(val))" : String(format: "%g", val)
    }
}

#Preview {
    SendView(walletService: WalletService(settings: AppSettings()), settings: AppSettings(), nearbyService: NearbyService())
        .preferredColorScheme(.dark)
}
