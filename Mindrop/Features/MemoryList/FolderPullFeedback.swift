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
        let distance = feedback.distance
        if distance > FolderPullFeedback.revealDistance {
            let progress = min(feedback.progress, 1)
            let accent = Color(.folderAccent)
            ZStack {
                Circle().fill(accent.opacity(progress == 1 ? 0.20 : 0.09))
                Circle()
                    .inset(by: 1)
                    .trim(from: 0, to: progress)
                    .stroke(accent, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image("ix.add.linear")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(accent)
            }
            .frame(width: 36, height: 36)
            .compositingGroup()
            .scaleEffect(reduceMotion ? 1 : 0.70 + 0.30 * progress)
            .opacity(min((distance - FolderPullFeedback.revealDistance) / 24, 1))
            .padding(.top, 30 + progress * 36)
            .frame(maxWidth: .infinity)
            .onLeadingPage()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
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

        let released = isDragging && (phase == .decelerating || phase == .idle)
        isDragging = false
        // Use the last actively dragged position before the scroll view rebounds.
        if released && progress >= 1 {
            haptics.playLaunch(tension: progress)
        }
        if phase == .idle { self.distance = 0 }
    }

    func scroll(to distance: CGFloat) {
        if isDragging {
            updateDrag(to: distance)
        } else if self.distance > 0 {
            // Follow the native rebound without rearming the haptics.
            self.distance = min(self.distance, distance)
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
