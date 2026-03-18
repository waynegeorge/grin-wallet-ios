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
//  NearbyPeerRow.swift
//  grin-ios
//

import SwiftUI

struct NearbyPeerRow: View {
    let peer: NearbyPeer
    var onTap: (() -> Void)? = nil

    private var statusColor: Color {
        switch peer.status {
        case .found: return .gray
        case .connecting: return .orange
        case .connected: return .green
        case .transferring: return .orange
        }
    }

    private var statusIcon: String {
        switch peer.status {
        case .found: return "circle.dotted"
        case .connecting: return "arrow.triangle.2.circlepath"
        case .connected: return "checkmark.circle.fill"
        case .transferring: return "arrow.left.arrow.right"
        }
    }

    var body: some View {
        Button {
            onTap?()
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "iphone")
                    .font(.system(size: 20, weight: .light))
                    .foregroundStyle(.secondary)
                    .frame(width: 40, height: 40)
                    .background(.white.opacity(0.08), in: Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text(peer.displayName)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.primary)
                    Text(peer.status.rawValue)
                        .font(.system(size: 12))
                        .foregroundStyle(statusColor)
                }

                Spacer()

                Image(systemName: statusIcon)
                    .font(.system(size: 14))
                    .foregroundStyle(statusColor)
                    .symbolEffect(.pulse, isActive: peer.status == .connecting || peer.status == .transferring)
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    VStack {
        NearbyPeerRow(peer: NearbyPeer(id: "1", displayName: "Wayne's iPhone", status: .connected))
        NearbyPeerRow(peer: NearbyPeer(id: "2", displayName: "Alice's iPad", status: .found))
    }
    .padding()
    .background(.black)
    .preferredColorScheme(.dark)
}
