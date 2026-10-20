// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// A one-time note for the launch after update, separate from release notes.
struct UpdateSupportIntroView: View {
    var onFinish: () -> Void

    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            UpdateSupportContent()
                .padding(.horizontal, 34)
            Spacer(minLength: 0)

            Divider()

            HStack {
                Spacer()
                Button(l10n.s.supportIntroDoneButton, action: onFinish)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
            .padding(16)
        }
        .frame(width: 560, height: 420)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct UpdateSupportContent: View {
    @ObservedObject private var l10n = L10n.shared
    @Environment(\.openURL) private var openURL
    @Environment(\.colorScheme) private var colorScheme

    private var donateThanksText: String {
        let thanks = l10n.s.donateThanks
        return colorScheme == .dark
            ? thanks.replacingOccurrences(of: "🖤", with: "🤍")
            : thanks
    }

    var body: some View {
        VStack(spacing: 13) {
            ZStack {
                Circle()
                    .fill(Theme.spaceGradient)
                    .frame(width: 74, height: 74)
                Image(systemName: "heart.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.white)
            }

            Text(l10n.s.supportIntroTitle)
                .font(.system(size: 22, weight: .bold))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Text(l10n.s.supportIntroMessage)
                .font(.system(size: 13.5))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 440)

            Button {
                openURL(AppInfo.coffeeURL)
            } label: {
                Label(l10n.s.supportIntroCoffeeButton,
                      systemImage: "cup.and.saucer.fill")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Text(donateThanksText)
                .font(.caption)
                .foregroundStyle(.tertiary)

            Button {
                openURL(AppInfo.repositoryURL)
            } label: {
                Label(l10n.s.supportIntroStarHint, systemImage: "star")
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .frame(maxWidth: 440)
            .padding(.top, 4)
            .help(l10n.s.supportIntroStarButton)
            .accessibilityLabel(l10n.s.supportIntroStarButton)
        }
    }
}

/// The X (Twitter) logo as a vector path in a 24x24 design box, scaled to the
/// given rect. Fill with `FillStyle(eoFill: true)` so the inner slash cuts out.
struct XLogoShape: Shape {
    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / 24
        let originX = rect.midX - 12 * scale
        let originY = rect.midY - 12 * scale
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: originX + x * scale, y: originY + y * scale)
        }
        var path = Path()
        path.move(to: point(18.244, 2.25))
        path.addLine(to: point(21.552, 2.25))
        path.addLine(to: point(14.325, 10.51))
        path.addLine(to: point(22.827, 21.75))
        path.addLine(to: point(16.17, 21.75))
        path.addLine(to: point(10.956, 14.933))
        path.addLine(to: point(4.99, 21.75))
        path.addLine(to: point(1.68, 21.75))
        path.addLine(to: point(9.41, 12.915))
        path.addLine(to: point(1.254, 2.25))
        path.addLine(to: point(8.08, 2.25))
        path.addLine(to: point(12.793, 8.481))
        path.closeSubpath()
        path.move(to: point(17.083, 19.77))
        path.addLine(to: point(18.916, 19.77))
        path.addLine(to: point(7.084, 4.126))
        path.addLine(to: point(5.117, 4.126))
        path.closeSubpath()
        return path
    }
}
