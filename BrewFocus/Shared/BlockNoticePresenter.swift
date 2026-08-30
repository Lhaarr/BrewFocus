import AppKit
import SwiftUI

@MainActor
protocol BlockNoticePresenting: AnyObject {
    func show(applicationName: String, coffee: CoffeeKind, remainingSeconds: Int)
    func showRestrictionFailure(applicationName: String, coffee: CoffeeKind)
}

@MainActor
final class AppKitBlockNoticePresenter: BlockNoticePresenting {
    private var panel: NSPanel?
    private var dismissalWorkItem: DispatchWorkItem?

    func show(applicationName: String, coffee: CoffeeKind, remainingSeconds: Int) {
        present(
            icon: "cup.and.saucer.fill",
            tint: coffee.accentColor,
            title: "Not with this coffee.",
            message: restrictionMessage(applicationName: applicationName, coffee: coffee),
            detail: "\(DurationFormatting.timerText(seconds: remainingSeconds)) left"
        )
    }

    func showRestrictionFailure(applicationName: String, coffee: CoffeeKind) {
        present(
            icon: "exclamationmark.triangle.fill",
            tint: .orange,
            title: "Couldn’t hide \(applicationName).",
            message: "Return to an allowed app manually.",
            detail: "Your \(coffee.name) is still running"
        )
    }

    private func restrictionMessage(applicationName: String, coffee: CoffeeKind) -> String {
        if coffee.restrictionMode == .blockList {
            return "\(applicationName) is blocked by your \(coffee.name)."
        }
        return "\(applicationName) is outside your \(coffee.name)."
    }

    private func present(
        icon: String,
        tint: Color,
        title: String,
        message: String,
        detail: String
    ) {
        dismissalWorkItem?.cancel()
        panel?.orderOut(nil)

        let contentView = BlockNoticeView(
            icon: icon,
            tint: tint,
            title: title,
            message: message,
            detail: detail
        )
        let hostingView = NSHostingView(rootView: contentView)
        hostingView.frame = NSRect(x: 0, y: 0, width: 360, height: 126)

        let panel = NSPanel(
            contentRect: hostingView.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = hostingView
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovable = false

        if let visibleFrame = NSScreen.main?.visibleFrame {
            let origin = NSPoint(
                x: visibleFrame.midX - hostingView.frame.width / 2,
                y: visibleFrame.maxY - hostingView.frame.height - 52
            )
            panel.setFrameOrigin(origin)
        } else {
            panel.center()
        }

        panel.orderFrontRegardless()
        self.panel = panel

        let workItem = DispatchWorkItem { [weak self, weak panel] in
            panel?.orderOut(nil)
            if self?.panel === panel {
                self?.panel = nil
            }
        }
        dismissalWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4, execute: workItem)
    }
}

private struct BlockNoticeView: View {
    let icon: String
    let tint: Color
    let title: String
    let message: String
    let detail: String

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(tint)

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.headline)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(detail)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(width: 360, height: 126)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .stroke(.white.opacity(0.14), lineWidth: 1)
        }
    }
}
