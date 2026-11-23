#if os(iOS)
import CoreHaptics
import Observation
import os
import SwiftUI

struct FolderPullScrollFeedback: ViewModifier {
    let feedback: FolderPullFeedback?
    let enabled: Bool

    @Environment(\.scenePhase) private var scenePhase
    private var isActive: Bool { enabled && scenePhase == .active }

    func body(content: Content) -> some View {
        if let feedback {
            content
                .scrollBounceBehavior(enabled ? .always : .automatic)
                .onScrollGeometryChange(for: CGFloat.self, of: Self.overscroll) { _, distance in
                    if isActive { feedback.scroll(to: distance) }
                }
                .onScrollPhaseChange { _, phase, context in
                    if isActive {
                        feedback.phaseChanged(
                            to: phase,
                            at: Self.overscroll(context.geometry),
                            viewportHeight: context.geometry.containerSize.height
                        )
                    }
                }
                .onChange(of: isActive) { _, active in
                    if !active { feedback.reset() }
                }
                .onDisappear(perform: feedback.reset)
        } else {
            content
        }
    }

    private nonisolated static func overscroll(_ geometry: ScrollGeometry) -> CGFloat {
        max(0, -(geometry.contentOffset.y + geometry.contentInsets.top))
    }
}

struct FolderPullIndicator: View {
    let feedback: FolderPullFeedback
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let progress = feedback.progress
        let fill = min(progress, 1)
        let extraPull = max(progress - 1, 0)
        let stretch = 1.6 * (1 - exp(-extraPull / 0.47))
        let reveal = min(max((fill - 0.10) / 0.18, 0), 1)
        let atThreshold = progress >= 1
        let accent = Color(.folderAccent)

        FolderPullArc(fill: fill, stretch: stretch)
            .stroke(
                LinearGradient(
                    stops: [
                        .init(color: accent.opacity(0), location: 0),
                        .init(color: accent.opacity(0.36), location: 0.16),
                        .init(color: accent, location: 0.40),
                        .init(color: accent, location: 0.60),
                        .init(color: accent.opacity(0.36), location: 0.84),
                        .init(color: accent.opacity(0), location: 1),
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                style: StrokeStyle(lineWidth: atThreshold ? 2.9 : 2.4, lineCap: .round)
            )
            .frame(width: 152 - 46 * fill - 14 * stretch, height: 104)
            .compositingGroup()
            .opacity(reveal * reveal * (3 - 2 * reveal) * (atThreshold ? 1 : 0.82))
            .padding(.top, 30)
            .frame(maxWidth: .infinity)
            .onLeadingPage()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .transaction { transaction in
                if reduceMotion { transaction.animation = nil }
            }
    }
}

private nonisolated struct FolderPullArc: Shape {
    var fill: CGFloat
    var stretch: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(fill, stretch) }
        set {
            fill = newValue.first
            stretch = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let halfSpan = rect.width / 2
        let endY = rect.minY + 25 + 7 * fill + 2 * stretch
        let drop = 3 + 41 * fill + 12 * stretch
        let centerY = endY + drop
        let shoulderOffset = halfSpan * 0.64
        let shoulderY = endY + drop * 0.095
        let tipRadius = 7 - 4.6 * fill - 0.8 * stretch
        let tipSlope = 0.23 + 0.65 * fill + 0.10 * stretch
        let joinY = centerY - tipRadius * tipSlope
        let innerOffset = halfSpan * 0.37
        let innerY = joinY - (innerOffset - tipRadius) * tipSlope

        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: endY))
        path.addCurve(
            to: CGPoint(x: rect.midX - tipRadius, y: joinY),
            control1: CGPoint(x: rect.midX - shoulderOffset, y: shoulderY),
            control2: CGPoint(x: rect.midX - innerOffset, y: innerY)
        )
        path.addQuadCurve(
            to: CGPoint(x: rect.midX + tipRadius, y: joinY),
            control: CGPoint(x: rect.midX, y: centerY)
        )
        path.addCurve(
            to: CGPoint(x: rect.maxX, y: endY),
            control1: CGPoint(x: rect.midX + innerOffset, y: innerY),
            control2: CGPoint(x: rect.midX + shoulderOffset, y: shoulderY)
        )
        return path
    }
}

@Observable
final class FolderPullFeedback {
    static let revealDistance: CGFloat = 12
    private static let maximumThreshold: CGFloat = 156

    private(set) var threshold = maximumThreshold
    private(set) var distance: CGFloat = 0
    @ObservationIgnored private var isDragging = false
    private let haptics = PullHaptics()

    var progress: CGFloat {
        max(0, (distance - Self.revealDistance) / (threshold - Self.revealDistance))
    }

    func phaseChanged(to phase: ScrollPhase, at distance: CGFloat, viewportHeight: CGFloat) {
        if phase == .interacting {
            guard !isDragging else { return }
            isDragging = true
            // Keep the longer pull reachable in short iPad windows and stable during a drag.
            threshold = min(Self.maximumThreshold, max(60, viewportHeight * 0.25))
            self.distance = 0
            updateDrag(to: distance)
            return
        }

        guard isDragging else { return }
        isDragging = false
        guard phase == .decelerating || phase == .idle else {
            self.distance = 0
            return
        }

        // Use the last actively dragged position before the scroll view rebounds.
        let tension = progress
        let duration = 0.095 - 0.060 * Double(min(tension / 1.4, 1))
        withAnimation(.easeOut(duration: duration)) {
            self.distance = 0
        }
        if tension >= 1 {
            haptics.playLaunch(tension: tension)
        }
    }

    func scroll(to distance: CGFloat) {
        if isDragging {
            updateDrag(to: distance)
        }
    }

    func reset() {
        distance = 0
        isDragging = false
    }

    private func updateDrag(to distance: CGFloat) {
        let previousDistance = self.distance
        let previousStep = Int(progress * 100)
        self.distance = distance

        if previousDistance <= Self.revealDistance && distance > Self.revealDistance {
            haptics.prepare()
        }

        haptics.playProgress(from: previousStep, to: Int(progress * 100))
    }
}

private final class PullHaptics {
    private static let stepWindow: TimeInterval = 0.008

    private let log = Logger(subsystem: "mfsaglam.Mindrop", category: "folder-pull-haptics")
    private var engine: CHHapticEngine?
    private var softenStepsUntil: ContinuousClock.Instant = .now

    func prepare() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }

        do {
            let engine = try self.engine ?? CHHapticEngine()
            if self.engine == nil {
                engine.playsHapticsOnly = true
                engine.isAutoShutdownEnabled = true
            }
            try engine.start()
            self.engine = engine
        } catch {
            self.engine = nil
            log.error("Could not start folder pull haptics: \(error.localizedDescription, privacy: .public)")
        }
    }

    func playProgress(from previous: Int, to current: Int) {
        guard let engine, previous != current else { return }
        let direction = previous < current ? 1 : -1
        let steps = stride(from: previous + direction, through: current, by: direction).filter { $0 > 0 }
        guard !steps.isEmpty else { return }

        let now = ContinuousClock.now
        if previous < 100 && current >= 100 {
            softenStepsUntil = now.advanced(by: .milliseconds(35))
        }
        let stepGain: Float = now < softenStepsUntil ? 0.25 : 1

        // Keep steps crossed in a single scroll sample together without queuing a pulse train.
        let spacing = min(0.004, Self.stepWindow / Double(max(steps.count - 1, 1)))
        let events = steps.enumerated().map { index, step in
            let strength = Float(min(step, 100)) / 100
            let isThreshold = direction > 0 && step == 100
            let intensity: Float = isThreshold ? 0.72 : (0.02 + 0.30 * strength) * stepGain
            return CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: isThreshold ? 1 : 0),
                ],
                relativeTime: Double(index) * spacing
            )
        }

        do {
            let pattern = try CHHapticPattern(events: events, parameters: [])
            try engine.makePlayer(with: pattern).start(atTime: CHHapticTimeImmediate)
        } catch {
            log.error("Could not play folder pull steps: \(error.localizedDescription, privacy: .public)")
        }
    }

    func playLaunch(tension: CGFloat) {
        guard let engine else { return }
        let overshoot = Float(min((tension - 1) / 0.5, 1))
        let intensity = 0.80 + 0.20 * overshoot
        let events = [
            CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.72),
                ],
                relativeTime: 0
            ),
            CHHapticEvent(
                eventType: .hapticContinuous,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity * 0.45),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.20),
                    CHHapticEventParameter(parameterID: .sustained, value: 1),
                ],
                relativeTime: 0.010,
                duration: 0.060
            ),
        ]
        let decay = CHHapticParameterCurve(
            parameterID: .hapticIntensityControl,
            controlPoints: [
                .init(relativeTime: 0, value: 1),
                .init(relativeTime: 0.010, value: 1),
                .init(relativeTime: 0.070, value: 0),
            ],
            relativeTime: 0
        )

        do {
            let pattern = try CHHapticPattern(events: events, parameterCurves: [decay])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: engine.currentTime + Self.stepWindow)
        } catch {
            log.error("Could not play folder pull launch: \(error.localizedDescription, privacy: .public)")
        }
    }
}
#endif
