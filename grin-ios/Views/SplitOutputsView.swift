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
//  SplitOutputsView.swift
//  grin-ios
//

import SwiftUI

struct SplitOutputsView: View {
    let walletService: WalletService

    @State private var pieces = 2
    @State private var isSplitting = false
    @State private var resultMessage: String?
    @State private var outputs: [WalletOutput] = []

    private var largestOutput: WalletOutput? {
        outputs.filter { $0.status == .unspent }.max(by: { $0.value < $1.value })
    }

    var body: some View {
        Form {
            Section {
                if let largest = largestOutput {
                    LabeledContent("Largest Output") {
                        Text(String(format: "%.4f", largest.amountGrin) + " ツ")
                            .font(.system(size: 15, weight: .medium, design: .monospaced))
                    }
                    LabeledContent("Total Unspent") {
                        Text("\(outputs.filter { $0.status == .unspent }.count)")
                            .font(.system(size: 15, design: .monospaced))
                    }
                } else {
                    Text("No spendable outputs")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Current Outputs")
            }

            Section {
                Picker("Split Into", selection: $pieces) {
                    Text("2 pieces").tag(2)
                    Text("4 pieces").tag(4)
                    Text("8 pieces").tag(8)
                }

                Button {
                    Task { await performSplit() }
                } label: {
                    HStack {
                        Spacer()
                        if isSplitting {
                            ProgressView()
                                .controlSize(.small)
                            Text("Splitting…")
                        } else {
                            Text("Split Outputs")
                        }
                        Spacer()
                    }
                }
                .disabled(isSplitting || largestOutput == nil)
            } header: {
                Text("Split")
            } footer: {
                Text("Splits your largest output into smaller pieces via self-send. Each split costs a standard fee (~0.023 ツ). Useful for enabling parallel transactions.")
            }

            if let message = resultMessage {
                Section {
                    Text(message)
                        .font(.system(size: 13))
                        .foregroundStyle(message.contains("failed") ? .red : .green)
                }
            }
        }
        .navigationTitle("Split Outputs")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            outputs = await walletService.getOutputs(includeSpent: false)
        }
    }

    private func performSplit() async {
        isSplitting = true
        resultMessage = nil
        let success = await walletService.splitOutputs(pieces: pieces)
        outputs = await walletService.getOutputs(includeSpent: false)
        resultMessage = success ? "Split completed successfully." : "Split failed. \(walletService.errorMessage ?? "")"
        isSplitting = false
    }
}
