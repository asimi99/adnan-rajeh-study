import SwiftUI
import AVFoundation
import UserNotifications

@main
struct AdnanStudyApp: App {
    @State private var library = Library()
    @State private var store = UserStore()
    @State private var account = Account()
    @State private var reminders = Reminders()
    @State private var halaqah = HalaqahPlayer()

    init() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        UNUserNotificationCenter.current().delegate = NotificationRouter.shared
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(library)
                .environment(store)
                .environment(account)
                .environment(reminders)
                .environment(halaqah)
                .tint(Palette.accent)
                .onAppear {
                    store.account = account
                    reminders.store = store
                    reminders.library = library
                    halaqah.store = store
                }
        }
    }
}

enum AppTab: Hashable { case home, browse, themes, search, mine }

struct RootView: View {
    @Environment(Library.self) private var lib
    @Environment(UserStore.self) private var store
    @Environment(Account.self) private var account
    @Environment(Reminders.self) private var reminders
    @Environment(\.scenePhase) private var phase

    @State private var tab: AppTab = .home
    @State private var homePath = NavigationPath()
    @State private var browsePath = NavigationPath()
    @State private var themesPath = NavigationPath()
    @State private var searchPath = NavigationPath()
    @State private var minePath = NavigationPath()

    var body: some View {
        Group {
            switch lib.state {
            case .ready:
                tabs
            case .failed(let msg):
                ContentUnavailableView {
                    Label("Offline", systemImage: "wifi.slash")
                } description: {
                    Text(msg)
                } actions: {
                    Button("Try again") { Task { await lib.load() } }.buttonStyle(.borderedProminent)
                }
            default:
                ProgressView("Loading the library…")
            }
        }
        .task {
            await lib.load()
            if account.session != nil { await store.pull() }
            reminders.reschedule()
            #if DEBUG
            await runTour()
            #endif
        }
        .onChange(of: phase) { _, p in
            if p == .active, account.session != nil { Task { await store.pull() } }
            if p == .background { reminders.reschedule() }
        }
        .onAppear {
            NotificationRouter.shared.open = { id in open(.lecture(id, 0)) }
        }
    }

    private var tabs: some View {
        TabView(selection: $tab) {
            NavigationStack(path: $homePath) { HomeView().withRoutes() }
                .tabItem { Label("Home", systemImage: "house") }.tag(AppTab.home)
            NavigationStack(path: $browsePath) { BrowseView().withRoutes() }
                .tabItem { Label("Browse", systemImage: "books.vertical") }.tag(AppTab.browse)
            NavigationStack(path: $themesPath) { ThemesView().withRoutes() }
                .tabItem { Label("Themes", systemImage: "square.grid.2x2") }.tag(AppTab.themes)
            NavigationStack(path: $searchPath) { SearchView().withRoutes() }
                .tabItem { Label("Search", systemImage: "magnifyingglass") }.tag(AppTab.search)
            NavigationStack(path: $minePath) { MyStudyView().withRoutes() }
                .tabItem { Label("My study", systemImage: "bookmark") }.tag(AppTab.mine)
        }
        .overlay(alignment: .bottom) {
            MiniPlayer { n in open(.halaqahLesson(n)) }
                .padding(.bottom, 54)
        }
    }

    #if DEBUG
    private func runTour() async {
        guard Tour.requested, lib.state == .ready else { return }
        try? FileManager.default.removeItem(at: Tour.requestFile)
        try? FileManager.default.removeItem(at: Tour.outDir)
        UserDefaults.standard.set(true, forKey: "tzok")
        Tour.log("start")
        func step(_ name: String, wait: Double = 3, _ action: () -> Void) async {
            action()
            try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            Tour.snap(name)
            Tour.log(name)
        }
        await step("01-home") { tab = .home; homePath = NavigationPath() }
        await step("02-browse") { tab = .browse; browsePath = NavigationPath() }
        await step("03-category") { browsePath.append(Route.category("khutbah")) }
        await step("04-series") { browsePath.append(Route.series(Fmt.slug("Essentials and Pet Peeves"))) }
        await step("05-lecture", wait: 6) { browsePath.append(Route.lecture("thfqFaRysbE", 0)) }
        await step("06-themes", wait: 5) { tab = .themes; themesPath = NavigationPath() }
        await step("07-topic", wait: 4) { themesPath.append(Route.theme("humility")) }
        await step("08-search", wait: 8) { Tour.pendingSearch = "patience"; tab = .search }
        await step("09-who", wait: 5) { tab = .browse; browsePath = NavigationPath(); browsePath.append(Route.who) }
        await step("10-halaqah", wait: 4) { browsePath = NavigationPath(); browsePath.append(Route.halaqahLessons) }
        await step("11-halaqah-lesson", wait: 3) { browsePath.append(Route.halaqahLesson(2)) }
        await step("12-mine") { tab = .mine; minePath = NavigationPath() }
        await step("13-settings") { minePath.append(Route.settings) }
        await step("14-year") { tab = .browse; browsePath = NavigationPath(); browsePath.append(Route.year(2024)) }
        await step("15-tafseer") { browsePath = NavigationPath(); browsePath.append(Route.category("tafseer")) }
        tab = .home
        Tour.log("done")
    }
    #endif

    private func open(_ r: Route) {
        switch tab {
        case .home: homePath.append(r)
        case .browse: browsePath.append(r)
        case .themes: themesPath.append(r)
        case .search: searchPath.append(r)
        case .mine: minePath.append(r)
        }
    }
}
