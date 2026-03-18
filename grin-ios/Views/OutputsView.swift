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
//  OutputsView.swift
//  grin-ios
//

import SwiftUI

struct OutputsView: View {
    let walletService: WalletService
    let decimalPlaces: Int

    @State private var outputs: [WalletOutput] = []
    @State private var isLoading = true
    @State private var showSpent = false

    private var filteredOutputs: [WalletOutput] {
        if showSpent {
            return outputs
        }
        return outputs.filter { $0.status != .spent }
    }

    private var statusSummary: (unspent: Int, locked: Int, unconfirmed: Int, spent: Int) {
        var u = 0, l = 0, c = 0, s = 0
        for o in outputs {
            switch o.status {
            case .unspent: u += 1
            case .locked: l += 1
            case .unconfirmed: c += 1
            case .spent: s += 1
            case .reverted: break
            }
        }
        return (u, l, c, s)
    }

    var body: some View {
        List {
            Section {
                let summary = statusSummary
                HStack(spacing: 16) {
                    summaryItem(count: summary.unspent, label: "Unspent", color: .green)
                    summaryItem(count: summary.locked, label: "Locked", color: .orange)
                    summaryItem(count: summary.unconfirmed, label: "Pending", color: .yellow)
                    if showSpent {
                        summaryItem(count: summary.spent, label: "Spent", color: .gray)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)

                Toggle("Show Spent", isOn: $showSpent)
                    .tint(.green)
                    .onChange(of: showSpent) { _, newValue in
                        if newValue && outputs.filter({ $0.status == .spent }).isEmpty {
                            Task { await loadOutputs(includeSpent: true) }
                        }
                    }
            }

            if isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .listRowBackground(Color.clear)
            } else if filteredOutputs.isEmpty {
                Text("No outputs found")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
            } else {
                Section("Outputs (\(filteredOutputs.count))") {
                    ForEach(filteredOutputs) { output in
                        OutputRow(output: output, decimalPlaces: decimalPlaces)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Wallet Outputs")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadOutputs(includeSpent: false)
        }
        .refreshable {
            await loadOutputs(includeSpent: showSpent)
        }
    }

    private func loadOutputs(includeSpent: Bool) async {
        isLoading = true
        outputs = await walletService.getOutputs(includeSpent: includeSpent)
        isLoading = false
    }

    private func summaryItem(count: Int, label: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text("\(count)")
                .font(.system(size: 20, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }
}

private struct OutputRow: View {
    let output: WalletOutput
    let decimalPlaces: Int

    private var statusColor: Color {
        switch output.status {
        case .unspent: return .green
        case .locked: return .orange
        case .unconfirmed: return .yellow
        case .spent: return .gray
        case .reverted: return .red
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(String(format: "%.\(decimalPlaces)f", output.amountGrin))
                    .font(.system(size: 15, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.primary)

                Text("ツ")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)

                Spacer()

                Text(output.status.rawValue)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(statusColor)
            }

            HStack {
                Text("Height: \(output.height)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.tertiary)

                if output.isCoinbase {
                    Text("Coinbase")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule().fill(.orange.opacity(0.15))
                        )
                }

                Spacer()

                if let txLog = output.txLogEntry {
                    Text("Tx #\(txLog)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            }

            if !output.commit.isEmpty {
                Text(output.commit.count > 20
                     ? String(output.commit.prefix(10)) + "…" + String(output.commit.suffix(8))
                     : output.commit)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.quaternary)
            }
        }
        .padding(.vertical, 4)
    }
}
