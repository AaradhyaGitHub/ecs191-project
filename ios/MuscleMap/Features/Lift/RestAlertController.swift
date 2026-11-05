import AVFoundation
import Foundation
import LiftCore
import os
import SwiftUI
import UIKit
import UserNotifications

/// The rest countdown outside the rest strip (specs/lift-feedback.llm.md, Decided 1 and 2).
///
/// While the app is open, it plays a short beep and a tap each second for the last 10 s, and
/// a long beep and a stronger tap at 0, on any screen. It also keeps the local notices planned
/// ("10 seconds left" and "Rest is over"), but hides them while the app is open, so a lock
/// needs no background time (Q-8). On leaving the app with more than 10 s left, it changes
/// nothing: the notices planned in the app stay. With 10 s or less left, it sends the countdown
/// for the seconds left at once. Back in the app it removes what was shown and plans again.
/// The rules live in LiftCore (`countdownCues`, `restNotices`).
///
/// Each plan goes to the system at once, in order, new requests first: a request with a fixed id
/// replaces the pending one, so there is never a moment with nothing planned. The app holds
/// background time until the system has the plan, so iOS can't suspend it in between.
///
/// Debug builds log each step to the Xcode console, with the prefix "RestAlerts:".
///
/// `MuscleMapApp` makes one, sets it as the notification delegate at launch, and calls
/// `update(endsAt:)` and `scenePhaseChanged(_:)`.
final class RestAlertController: NSObject {
    private let center = UNUserNotificationCenter.current()
    private var endsAt: Date?
    private var isInApp = true
    private var beepTask: Task<Void, Never>?
    private var askedPermission = false
    /// Background time held until the system has a plan.
    private var backgroundTasks: Set<UIBackgroundTaskIdentifier> = []
    private var shortBeep: AVAudioPlayer?
    private var longBeep: AVAudioPlayer?
    private let tickTap = UIImpactFeedbackGenerator(style: .medium)
    private let endTap = UIImpactFeedbackGenerator(style: .heavy)

    nonisolated private static let noticeIDs = [RestNoticeID.tenLeft, RestNoticeID.over]

    override init() {
        super.init()
        // Ambient: the beeps mix over music without lowering it, and the silent switch mutes
        // them; the taps still work (Q-6).
        try? AVAudioSession.sharedInstance().setCategory(.ambient)
        shortBeep = Self.player("beep_short")
        longBeep = Self.player("beep_long")
        logSettings("launch")
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
        plan("timer changed", leavingApp: false, clearShown: false)
    }

    /// The app went to the background, or came back.
    func scenePhaseChanged(_ phase: ScenePhase) {
        switch phase {
        case .background:
            guard isInApp else { return }
            isInApp = false
            beepTask?.cancel()
            logSettings("leaving the app")
            let now = Date()
            if restNotices(endsAt: endsAt, now: now, leavingApp: true)
                == restNotices(endsAt: endsAt, now: now, leavingApp: false) {
                // More than 10 s left, or no timer: the plan made in the app is already the
                // plan for a locked or closed app (Q-8). Removing and adding it again here
                // could be cut off by the suspension and leave nothing planned.
                Self.log("leaving the app (\(Self.timeLeft(endsAt, now: now))): the notices planned in the app stay")
                confirmPlan("leaving the app")
            } else {
                plan("leaving the app, \(Self.timeLeft(endsAt, now: now))", leavingApp: true, clearShown: false)
            }
        case .active:
            guard !isInApp else { return }
            isInApp = true
            startBeeps()
            plan("back in the app", leavingApp: false, clearShown: true)
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
            let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
            Self.log("permission answered: \(granted ? "allowed" : "not allowed")")
            // The first plan may have been refused before the answer; plan again. New
            // requests replace the old ones by id, so nothing planned is lost meanwhile.
            plan("permission answered", leavingApp: !isInApp, clearShown: false)
        }
    }

    /// Sends the plan for the current timer to the system now, before this call returns.
    /// It adds the new requests first (a fixed id replaces the pending request), then removes
    /// the pending ids the plan no longer has. The system takes the calls in the order they
    /// were made, so a newer plan always lands after an older one, without waiting for it.
    private func plan(_ reason: String, leavingApp: Bool, clearShown: Bool) {
        let now = Date()
        let notices = restNotices(endsAt: endsAt, now: now, leavingApp: leavingApp)
        let keep = Set(notices.map(\.id))
        let stale = Self.noticeIDs.filter { !keep.contains($0) }
        Self.log("plan (\(reason)): "
                 + (notices.isEmpty ? "nothing" : notices.map { Self.describe($0, now: now) }.joined(separator: ", "))
                 + (stale.isEmpty ? "" : "; remove \(stale.joined(separator: ", "))"))
        for notice in notices {
            center.add(Self.request(for: notice), withCompletionHandler: Self.logIfFailed(notice.id))
        }
        if !stale.isEmpty { center.removePendingNotificationRequests(withIdentifiers: stale) }
        if clearShown { clearShownNotices() }
        confirmPlan(reason)
    }

    /// Holds background time until the system has taken the calls made so far, then logs what
    /// is pending. It asks for the pending list, which the system answers after those calls.
    private func confirmPlan(_ reason: String) {
        let hold = beginBackgroundTime(reason)
        Task {
            let pending = await center.pendingNotificationRequests()
            Self.log("pending after \(reason): " + Self.describe(pending))
            endBackgroundTime(hold)
        }
    }

    /// Removes the rest notices shown while the app was away, so Notification Center doesn't
    /// keep an old "Rest is over".
    private func clearShownNotices() {
        Task {
            let shown = await center.deliveredNotifications()
                .map(\.request.identifier)
                .filter { Self.noticeIDs.contains($0) }
            Self.log("shown while away: " + (shown.isEmpty ? "none" : shown.joined(separator: ", ")))
            if !shown.isEmpty { center.removeDeliveredNotifications(withIdentifiers: shown) }
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

    // MARK: Background time

    private func beginBackgroundTime(_ reason: String) -> UIBackgroundTaskIdentifier {
        let id = UIApplication.shared.beginBackgroundTask(withName: "Rest notices") { [weak self] in
            Self.log("background time ran out (\(reason))")
            self?.endAllBackgroundTime()
        }
        if id != .invalid { backgroundTasks.insert(id) }
        return id
    }

    private func endBackgroundTime(_ id: UIBackgroundTaskIdentifier) {
        guard backgroundTasks.remove(id) != nil else { return }
        UIApplication.shared.endBackgroundTask(id)
    }

    private func endAllBackgroundTime() {
        for id in backgroundTasks { UIApplication.shared.endBackgroundTask(id) }
        backgroundTasks.removeAll()
    }

    // MARK: Debug log

    #if DEBUG
    nonisolated private static let logger = Logger(subsystem: "MuscleMap", category: "RestAlerts")
    #endif

    /// Debug builds only: one line in the Xcode console, "RestAlerts: …".
    nonisolated private static func log(_ message: @autoclosure () -> String) {
        #if DEBUG
        let text = message()
        logger.notice("RestAlerts: \(text, privacy: .public)")
        #endif
    }

    /// Logs the notification permission and settings, so a device run shows them.
    private func logSettings(_ moment: String) {
        #if DEBUG
        Task {
            let settings = await center.notificationSettings()
            Self.log("\(moment): permission \(Self.name(settings.authorizationStatus)), "
                     + "alerts \(Self.name(settings.alertSetting)), sounds \(Self.name(settings.soundSetting)), "
                     + "lock screen \(Self.name(settings.lockScreenSetting)), "
                     + "time sensitive \(Self.name(settings.timeSensitiveSetting))")
            if settings.authorizationStatus == .denied {
                Self.log("notices are off for this app: Settings > Notifications > MuscleMap")
            }
        }
        #endif
    }

    nonisolated private static func logIfFailed(_ id: String) -> @Sendable ((any Error)?) -> Void {
        { error in
            if let error { log("could not plan \(id): \(error.localizedDescription)") }
        }
    }

    nonisolated private static func describe(_ notice: RestNotice, now: Date) -> String {
        let when = notice.fireAt.map { "in \(seconds($0.timeIntervalSince(now)))" } ?? "now"
        return "\(notice.id) \(when) \"\(notice.title)\" sound \(notice.sound ?? "none")"
    }

    nonisolated private static func describe(_ pending: [UNNotificationRequest]) -> String {
        let ours = pending.filter { noticeIDs.contains($0.identifier) }
        guard !ours.isEmpty else { return "none" }
        return ours.map { request in
            let fire = (request.trigger as? UNTimeIntervalNotificationTrigger)?.nextTriggerDate()
            return "\(request.identifier) " + (fire.map { "in \(seconds($0.timeIntervalSinceNow))" } ?? "now")
        }.joined(separator: ", ")
    }

    nonisolated private static func timeLeft(_ endsAt: Date?, now: Date) -> String {
        guard let endsAt, endsAt > now else { return "no timer" }
        return "\(seconds(endsAt.timeIntervalSince(now))) left"
    }

    nonisolated private static func seconds(_ interval: TimeInterval) -> String {
        String(format: "%.1f s", interval)
    }

    nonisolated private static func name(_ status: UNAuthorizationStatus) -> String {
        switch status {
        case .notDetermined: "not asked yet"
        case .denied: "denied"
        case .authorized: "allowed"
        case .provisional: "provisional"
        case .ephemeral: "ephemeral"
        @unknown default: "unknown"
        }
    }

    nonisolated private static func name(_ setting: UNNotificationSetting) -> String {
        switch setting {
        case .notSupported: "not supported"
        case .disabled: "off"
        case .enabled: "on"
        @unknown default: "unknown"
        }
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
