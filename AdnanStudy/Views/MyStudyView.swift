import SwiftUI
import AuthenticationServices

struct MyStudyView: View {
    @Environment(Library.self) private var lib
    @Environment(UserStore.self) private var store
    @Environment(Account.self) private var account
    @State private var showSignIn = false

    var body: some View {
        List {
            Section {
                if account.session != nil {
                    Label("Synced to your account (\(account.displayName)).", systemImage: "checkmark.icloud")
                        .font(.callout)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Saved on this phone. Sign in to keep it on every device and on the website.").font(.callout)
                        Button("Sign in") { showSignIn = true }.buttonStyle(.borderedProminent).tint(Palette.accent)
                    }
                    .padding(.vertical, 4)
                }
            }

            let cont = Array(store.continueWatching(lib).prefix(12))
            if !cont.isEmpty {
                Section("Continue watching") {
                    ForEach(cont) { e in
                        NavigationLink(value: Route.lecture(e.lecture.id, Double(e.progress.t))) { LectureRow(lecture: e.lecture, progress: e.progress) }
                    }
                }
            }

            Section {
                let notes = store.reflections.filter { lib.byId[$0.id] != nil }
                if notes.isEmpty {
                    Text("Write a reflection on any lecture page and it collects here.").foregroundStyle(.secondary)
                }
                ForEach(notes) { n in
                    NavigationLink(value: Route.lecture(n.id, 0)) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(lib.title(for: n.id)).font(.subheadline.weight(.semibold)).lineLimit(2)
                                Spacer()
                                Text(Date(timeIntervalSince1970: n.note.at / 1000).formatted(date: .abbreviated, time: .omitted))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Text(n.note.text).font(.footnote).foregroundStyle(.secondary).lineLimit(3)
                        }
                    }
                }
            } header: {
                Text("My reflections")
            }

            let recent = Array(store.recent(lib).prefix(30))
            if !recent.isEmpty {
                Section("Recently watched") {
                    ForEach(recent) { e in
                        NavigationLink(value: Route.lecture(e.lecture.id, Double(e.progress.t))) { LectureRow(lecture: e.lecture, progress: e.progress) }
                    }
                }
            }
        }
        .navigationTitle("My study")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink { SettingsView() } label: { Image(systemName: "gearshape") }
            }
        }
        .sheet(isPresented: $showSignIn) { SignInView() }
        .refreshable { await store.pull() }
    }
}

struct SettingsView: View {
    @Environment(Library.self) private var lib
    @Environment(UserStore.self) private var store
    @Environment(Account.self) private var account
    @Environment(Reminders.self) private var reminders
    @Environment(HalaqahPlayer.self) private var halaqah
    @State private var showSignIn = false
    @State private var confirmErase = false
    @State private var confirmDelete = false
    @State private var cacheSize: Int64 = 0
    @State private var message: String?

    var body: some View {
        @Bindable var rem = reminders
        Form {
            Section("Account") {
                if account.session != nil {
                    LabeledContent("Signed in", value: account.displayName)
                    Button("Sign out") {
                        Task {
                            await store.push()
                            await account.signOut()
                            store.clearLocal()
                        }
                    }
                    Button("Delete account", role: .destructive) { confirmDelete = true }
                } else {
                    Button("Sign in or create an account") { showSignIn = true }
                }
            }

            Section {
                Toggle("Daily study reminder", isOn: Binding(
                    get: { rem.enabled },
                    set: { on in
                        Task {
                            if on, !reminders.authorized { await reminders.requestPermission() }
                            reminders.enabled = on && reminders.authorized
                            if on && !reminders.authorized { message = "Allow notifications for this app in iPhone Settings to get reminders." }
                        }
                    }))
                if rem.enabled {
                    DatePicker("Time", selection: $rem.time, displayedComponents: .hourAndMinute)
                    WeekdayPicker(selection: $rem.weekdays)
                }
            } header: {
                Text("Reminders")
            } footer: {
                Text("The reminder points to the lecture you were last in the middle of.")
            }

            Section {
                if let p = lib.offlineProgress {
                    ProgressView(value: p) { Text("Saving the library…") }
                } else {
                    Button("Save the whole library for offline") { Task { await lib.downloadEverything(); await refreshSize() } }
                }
                LabeledContent("Saved on this phone", value: ByteCountFormatter.string(fromByteCount: cacheSize, countStyle: .file))
                LabeledContent("Halaqah lessons downloaded", value: "\(halaqah.downloaded.count)")
            } header: {
                Text("Offline")
            } footer: {
                Text("Notes, transcripts and search work without a connection once saved. Videos still need the internet.")
            }

            Section("Your data") {
                Button("Erase my progress and reflections", role: .destructive) { confirmErase = true }
                Link("Privacy", destination: Remote.privacy)
                Link("Terms", destination: Remote.terms)
                Link("How data deletion works", destination: Remote.dataDeletion)
            }

            if let message {
                Section { Text(message).font(.footnote).foregroundStyle(.secondary) }
            }

            Section {
                Text("Quran translation: Saheeh International").font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Settings")
        .task { await refreshSize() }
        .sheet(isPresented: $showSignIn) { SignInView() }
        .confirmationDialog("Erase everything you've saved?", isPresented: $confirmErase, titleVisibility: .visible) {
            Button("Erase", role: .destructive) { Task { await store.eraseAll() } }
        } message: {
            Text("Progress and reflections are removed here and from your account. This can't be undone.")
        }
        .confirmationDialog("Delete your account?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete account", role: .destructive) {
                Task {
                    do {
                        try await account.deleteAccount()
                        store.clearLocal()
                        message = "Your account and everything saved with it were deleted."
                    } catch {
                        message = error.localizedDescription
                    }
                }
            }
        } message: {
            Text("Your account, progress and reflections are permanently deleted. This can't be undone.")
        }
    }

    private func refreshSize() async { cacheSize = await DataCache.shared.sizeOnDisk() }
}

struct WeekdayPicker: View {
    @Binding var selection: Set<Int>
    private let symbols = Calendar.current.veryShortWeekdaySymbols

    var body: some View {
        HStack {
            ForEach(1...7, id: \.self) { d in
                let on = selection.contains(d)
                Button {
                    if on { selection.remove(d) } else { selection.insert(d) }
                } label: {
                    Text(symbols[d - 1])
                        .font(.footnote.weight(.semibold))
                        .frame(width: 34, height: 34)
                        .background(on ? Palette.accent : Palette.soft, in: Circle())
                        .foregroundStyle(on ? Color.white : Palette.accent)
                }
                .buttonStyle(.plain)
                if d < 7 { Spacer(minLength: 0) }
            }
        }
    }
}

struct SignInView: View {
    @Environment(Account.self) private var account
    @Environment(UserStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.webAuthenticationSession) private var webAuth
    @Environment(\.colorScheme) private var scheme

    @State private var email = ""
    @State private var password = ""
    @State private var creating = false
    @State private var error: String?
    @State private var busy = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SignInWithAppleButton(.continue) { req in
                        req.requestedScopes = [.email]
                        req.nonce = account.newAppleNonce()
                    } onCompletion: { result in
                        switch result {
                        case .success(let auth):
                            guard let cred = auth.credential as? ASAuthorizationAppleIDCredential,
                                  let tokenData = cred.identityToken,
                                  let token = String(data: tokenData, encoding: .utf8) else {
                                error = "Apple sign in didn't return a token."
                                return
                            }
                            run { try await account.signInWithApple(idToken: token) }
                        case .failure(let e):
                            if (e as? ASAuthorizationError)?.code != .canceled { error = e.localizedDescription }
                        }
                    }
                    .signInWithAppleButtonStyle(scheme == .dark ? .white : .black)
                    .frame(height: 46)

                    Button { oauth("google") } label: {
                        Label("Continue with Google", systemImage: "globe").frame(maxWidth: .infinity)
                    }
                    Button { oauth("facebook") } label: {
                        Label("Continue with Facebook", systemImage: "person.2").frame(maxWidth: .infinity)
                    }
                }

                Section(creating ? "Create an account" : "Sign in with email") {
                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Password", text: $password)
                        .textContentType(creating ? .newPassword : .password)
                    Button(creating ? "Create account" : "Sign in") {
                        let e = email.trimmingCharacters(in: .whitespaces), p = password
                        run {
                            if creating { try await account.signUp(email: e, password: p) }
                            else { try await account.signIn(email: e, password: p) }
                        }
                    }
                    .disabled(email.isEmpty || password.count < 6 || busy)
                    Button(creating ? "Have an account? Sign in" : "New here? Create an account") { creating.toggle() }
                        .font(.footnote)
                }

                if let error {
                    Section { Text(error).foregroundStyle(.red).font(.footnote) }
                }

                Section {
                    Text(consent).font(.footnote).foregroundStyle(.secondary)
                }
            }
            .disabled(busy)
            .overlay { if busy { ProgressView() } }
            .navigationTitle("Sign in")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
    }

    private var consent: AttributedString {
        let md = "By continuing you agree to the [Terms](\(Remote.terms.absoluteString)) and [Privacy Policy](\(Remote.privacy.absoluteString))."
        return (try? AttributedString(markdown: md)) ?? AttributedString(md)
    }

    private func run(_ work: @escaping () async throws -> Void) {
        error = nil
        busy = true
        Task {
            do {
                try await work()
                await store.pull()
                busy = false
                dismiss()
            } catch {
                self.error = error.localizedDescription
                busy = false
            }
        }
    }

    private func oauth(_ provider: String) {
        let url = account.oauthURL(provider: provider)
        run {
            let callback = try await webAuth.authenticate(using: url, callbackURLScheme: Account.callbackScheme, preferredBrowserSession: .ephemeral)
            try await account.finishOAuth(callback: callback)
        }
    }
}
