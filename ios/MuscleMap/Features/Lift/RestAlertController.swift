import AVFoundation
import Foundation
import LiftCore
import SwiftUI
import UIKit
import UserNotifications

/// The rest countdown outside the rest strip (specs/lift-feedback.llm.md, Decided 1 and 2).
///
/// While the app is open, it plays a short beep and a tap each second for the last 10 s, and
/// a long beep and a stronger tap at 0, on any screen. It also keeps the local notices planned
/// ("10 seconds left" and "Rest is over"), but hides them while the app is open, so a lock
/// needs no background time (Q-8). On leaving the app with 10 s or less left, it sends the
/// countdown for the seconds left at once. Back in the app it removes what is pending or shown
/// and plans again. The rules live in LiftCore (`countdownCues`, `restNotices`).
///
/// `MuscleMapApp` makes one, sets it as the notification delegate at launch, and calls
/// `update(endsAt:)` and `scenePhaseChanged(_:)`.
final class RestAlertController: NSObject {
    private let center = UNUserNotificationCenter.current()
    private var endsAt: Date?
    private var isInApp = true
    private var beepTask: Task<Void, Never>?
    /// The last planning run. Each run waits for the one before, so an old plan never lands
    /// after a newer one (a Skip right after a set).
    private var planTask: Task<Void, Never>?
    private var askedPermission = false
    private var shortBeep: AVAudioPlayer?
    private var longBeep: AVAudioPlayer?
    private let tickTap = UIImpactFeedbackGenerator(style: .medium)
    private let endTap = UIImpactFeedbackGenerator(style: .heavy)

    override init() {
        super.init()
        // Ambient: the beeps mix over music without lowering it, and the silent switch mutes
        // them; the taps still work (Q-6).
        try? AVAudioSession.sharedInstance().setCategory(.ambient)
        shortBeep = Self.player("beep_short")
        longBeep = Self.player("beep_long")
    }

    private static func player(_ name: String) -> AVAudioPlayer? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "caf") else { return nil }
        let player = try? AVAudioPlayer(contentsOf: url)
        player?.prepareToPlay()
        return player
    }

    // MARK: Inputs

    /// The open workout's rest timer changed: started, −30s, +30s, Skip, a new set, Finish or
    /// Discard (nil). Restarts the beeps and plans the notices again.
    func update(endsAt newEndsAt: Date?) {
        endsAt = newEndsAt
        if let newEndsAt, newEndsAt > Date() { askPermissionOnce() }
        guard isInApp else { return }
        startBeeps()
        replan(leavingApp: false, clearShown: false)
    }

    /// The app went to the background, or came back.
    func scenePhaseChanged(_ phase: ScenePhase) {
        switch phase {
        case .background:
            guard isInApp else { return }
            isInApp = false
            beepTask?.cancel()
            replan(leavingApp: true, clearShown: false)
        case .active:
            guard !isInApp else { return }
            isInApp = true
            startBeeps()
            replan(leavingApp: false, clearShown: true)
        default:
            break
        }
    }

    // MARK: Beeps and taps (app open)

    private func startBeeps() {
        beepTask?.cancel()
        let cues = countdownCues(endsAt: endsAt, after: Date())
        guard !cues.isEmpty else { return }
        tickTap.prepare()
        beepTask = Task { [weak self] in
            for cue in cues {
                let wait = cue.at.timeIntervalSinceNow
                if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
                guard !Task.isCancelled, let self else { return }
                self.play(cue.cue)
            }
        }
    }

    private func play(_ cue: CountdownCue) {
        switch cue {
        case .tick:
            shortBeep?.currentTime = 0
            shortBeep?.play()
            tickTap.impactOccurred()
            tickTap.prepare()
        case .end:
            longBeep?.currentTime = 0
            longBeep?.play()
            endTap.impactOccurred()
        }
    }

    // MARK: Notices (app closed or locked)

    /// Asks for notifications the first time a rest timer starts, not at launch (Decided 3).
    /// If the user says no, the beeps and taps still work.
    private func askPermissionOnce() {
        guard !askedPermission else { return }
        askedPermission = true
        Task {
            let settings = await center.notificationSettings()
            guard settings.authorizationStatus == .notDetermined else { return }
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
            // The first plan may have been refused before the answer; plan again.
            replan(leavingApp: !isInApp, clearShown: false)
        }
    }

    private func replan(leavingApp: Bool, clearShown: Bool) {
        let previous = planTask
        planTask = Task {
            await previous?.value
            await plan(leavingApp: leavingApp, clearShown: clearShown)
        }
    }

    /// Replaces the planned notices with the plan for the current timer. The fixed ids make a
    /// new plan replace the old one.
    private func plan(leavingApp: Bool, clearShown: Bool) async {
        let ids = [RestNoticeID.tenLeft, RestNoticeID.over]
        center.removePendingNotificationRequests(withIdentifiers: ids)
        if clearShown { center.removeDeliveredNotifications(withIdentifiers: ids) }
        for notice in restNotices(endsAt: endsAt, now: Date(), leavingApp: leavingApp) {
            try? await center.add(Self.request(for: notice))
        }
    }

    private static func request(for notice: RestNotice) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = notice.title
        content.sound = notice.sound.map { UNNotificationSound(named: UNNotificationSoundName($0)) }
        // Time Sensitive, so a Focus mode can let it through (Decided 3).
        content.interruptionLevel = .timeSensitive
        // A nil trigger sends it at once; a time trigger needs at least a little time.
        let trigger = notice.fireAt.map {
            UNTimeIntervalNotificationTrigger(timeInterval: max(0.1, $0.timeIntervalSinceNow), repeats: false)
        }
        return UNNotificationRequest(identifier: notice.id, content: content, trigger: trigger)
    }
}

extension RestAlertController: UNUserNotificationCenterDelegate {
    /// While the app is open, the rest notices stay hidden: the app beeps by itself (AC-8).
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions {
        let id = notification.request.identifier
        return id == RestNoticeID.tenLeft || id == RestNoticeID.over ? [] : [.banner, .sound]
    }
}
