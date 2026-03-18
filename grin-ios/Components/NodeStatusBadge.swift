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
//  NodeStatusBadge.swift
//  grin-ios
//

import SwiftUI

struct NodeStatusBadge: View {
    let status: NodeStatus

    private var color: Color {
        switch status {
        case .connected: return .green
        case .disconnected: return .gray
        case .syncing: return .orange
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: status.iconName)
                .font(.system(size: 8))
                .foregroundStyle(color)
                .symbolEffect(.pulse, isActive: status == .syncing)

            Text(status.rawValue)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(.primary.opacity(0.06), in: Capsule())
    }
}

#Preview {
    VStack(spacing: 12) {
        NodeStatusBadge(status: .connected)
        NodeStatusBadge(status: .syncing)
        NodeStatusBadge(status: .disconnected)
    }
    .padding()
    .background(.black)
    .preferredColorScheme(.dark)
}
