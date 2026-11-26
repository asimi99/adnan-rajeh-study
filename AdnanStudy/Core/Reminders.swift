import Foundation
import UserNotifications
import Observation

/// Daily study reminders and one-off "finish this later" nudges, all local to the phone.
@MainActor
@Observable
final class Reminders {
    private var storedEnabled: Bool
    private var storedHour: Int
    private var storedMinute: Int
    private var storedWeekdays: Set<Int>

    var enabled: Bool {
        get { storedEnabled }
        set { storedEnabled = newValue; changed() }
    }
    var hour: Int {
        get { storedHour }
        set { storedHour = newValue; changed() }
    }
    var minute: Int {
        get { storedMinute }
        set { storedMinute = newValue; changed() }
    }
    /// 1 = Sunday ... 7 = Saturday
    var weekdays: Set<Int> {
        get { storedWeekdays }
        set { storedWeekdays = newValue; changed() }
    }
    private(set) var authorized = false

    @ObservationIgnored weak var store: UserStore?
    @ObservationIgnored weak var library: Library?

    @ObservationIgnored private let center = UNUserNotificationCenter.current()
    @ObservationIgnored private let d = UserDefaults.standard

    init() {
        let defaults = UserDefaults.standard
        storedEnabled = defaults.bool(forKey: "rem.enabled")
        storedHour = defaults.object(forKey: "rem.hour") as? Int ?? 20
        storedMinute = defaults.object(forKey: "rem.minute") as? Int ?? 30
        let w = defaults.array(forKey: "rem.days") as? [Int] ?? [1, 2, 3, 4, 5, 6, 7]
        storedWeekdays = Set(w)
        Task { await refreshAuthorization() }
    }

    private func changed() {
        save()
        reschedule()
    }

    private func save() {
        d.set(enabled, forKey: "rem.enabled")
        d.set(hour, forKey: "rem.hour")
        d.set(minute, forKey: "rem.minute")
        d.set(Array(weekdays).sorted(), forKey: "rem.days")
    }

    func refreshAuthorization() async {
        let s = await center.notificationSettings()
        authorized = s.authorizationStatus == .authorized || s.authorizationStatus == .provisional
    }

    @discardableResult
    func requestPermission() async -> Bool {
        let ok = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        await refreshAuthorization()
        return ok
    }

    var time: Date {
        get { Calendar.current.date(from: DateComponents(hour: hour, minute: minute)) ?? Date() }
        set {
            let c = Calendar.current.dateComponents([.hour, .minute], from: newValue)
            hour = c.hour ?? 20
            minute = c.minute ?? 30
        }
    }

    /// Rebuilds the daily reminders. The text points to what you were last in the middle of.
    func reschedule() {
        let ids = (1...7).map { "daily-\($0)" }
        center.removePendingNotificationRequests(withIdentifiers: ids)
        guard enabled else { return }
        let content = UNMutableNotificationContent()
        content.title = "Time to study"
        if let lib = library, let store, let next = store.continueWatching(lib).first {
            content.body = "Pick up \(next.lecture.title) at \(Fmt.time(Double(next.progress.t)))."
            content.userInfo = ["lecture": next.lecture.id]
        } else {
            content.body = "A few minutes with Sh. Adnan's lessons."
        }
        content.sound = .default
        for day in weekdays {
            var dc = DateComponents()
            dc.weekday = day
            dc.hour = hour
            dc.minute = minute
            let trigger = UNCalendarNotificationTrigger(dateMatching: dc, repeats: true)
            center.add(UNNotificationRequest(identifier: "daily-\(day)", content: content, trigger: trigger))
        }
    }

    /// One reminder to come back to a lecture at a chosen time.
    func remind(lecture: Lecture, at date: Date, from t: Double) async -> Bool {
        if !authorized { _ = await requestPermission() }
        guard authorized else { return false }
        let content = UNMutableNotificationContent()
        content.title = "Finish this lecture"
        content.body = t > 30 ? "\(lecture.title), from \(Fmt.time(t))." : lecture.title
        content.sound = .default
        content.userInfo = ["lecture": lecture.id]
        let dc = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: dc, repeats: false)
        do {
            try await center.add(UNNotificationRequest(identifier: "lec-\(lecture.id)", content: content, trigger: trigger))
            return true
        } catch { return false }
    }
}

/// Opens the lecture a notification points to.
final class NotificationRouter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationRouter()
    var open: ((String) -> Void)?

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        if let id = response.notification.request.content.userInfo["lecture"] as? String {
            await MainActor.run { open?(id) }
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
