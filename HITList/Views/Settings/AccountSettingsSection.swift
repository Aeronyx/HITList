import SwiftUI
import SwiftData
import PhotosUI
import CloudKit
#if os(iOS)
import UIKit
#else
import AppKit
#endif

// Settings → Account (brief 34). HITList has no sign-in of its own: the account is the Apple account the
// device uses for iCloud, whose private database already keeps each person's tasks to themselves. This
// screen shows who that is (a profile: name and picture, synced like the tasks), whether iCloud is healthy,
// how to sign out, and how to delete data. The first group on the iPhone sheet; its own section on the Mac.

/// What Settings says about the iCloud account: the Account screen's status row and the iCloud screen's
/// environment line use the same words. Pure, so tests pin every state.
enum AccountState: Equatable {
    /// The status hasn't come back from CloudKit yet.
    case checking
    case signedIn
    /// Signed in, but to another Apple account than the last launch (`AccountWatch.Notice.switched`).
    case switched
    /// No iCloud account now, after one was used here before (`AccountWatch.everSignedInKey`).
    case signedOut
    /// No iCloud account, and none was ever used here: a new tester without iCloud.
    case neverSignedIn
    case restricted
    /// iCloud wants the Apple account password again.
    case needsSignInAgain
    case couldNotDetermine
    /// The store opened without CloudKit (`ModelContainerFactory.localOnlyReason`).
    case localOnly(String)

    static func derive(cloudKitEnabled: Bool, localOnlyReason: String, status: CKAccountStatus?,
                       notice: AccountWatch.Notice?, everSignedIn: Bool) -> AccountState {
        guard cloudKitEnabled else { return .localOnly(localOnlyReason) }
        switch status {
        case nil: return .checking
        case .available: return notice == .switched ? .switched : .signedIn
        case .noAccount: return everSignedIn ? .signedOut : .neverSignedIn
        case .restricted: return .restricted
        case .temporarilyUnavailable: return .needsSignInAgain
        default: return .couldNotDetermine
        }
    }

    /// The live state, from `CloudSyncMonitor` and `AccountWatch`'s memory in the app group.
    @MainActor
    static var current: AccountState {
        let monitor = CloudSyncMonitor.shared
        return derive(cloudKitEnabled: ModelContainerFactory.isCloudKitEnabled,
                      localOnlyReason: ModelContainerFactory.localOnlyReason,
                      status: monitor.accountStatus, notice: monitor.accountNotice,
                      everSignedIn: AppGroup.defaults.bool(forKey: AccountWatch.everSignedInKey))
    }

    /// "Signed in", the words after "iCloud: ".
    var label: String {
        switch self {
        case .checking: "Checking…"
        case .signedIn: "Signed in"
        case .switched: "Signed in to another account"
        case .signedOut: "Signed out"
        case .neverSignedIn: "Not signed in"
        case .restricted: "Restricted"
        case .needsSignInAgain: "Sign in again"
        case .couldNotDetermine: "Couldn't check"
        case .localOnly: "Not in use"
        }
    }

    /// "iCloud: Signed in".
    var title: String { "iCloud: \(label)" }

    /// What it means and, when something is wrong, what to do.
    var detail: String {
        switch self {
        case .checking:
            "Asking iCloud which account this device uses."
        case .signedIn:
            "Your tasks are stored in your iCloud account and sync to every device signed in to it."
        case .switched:
            "This device now uses a different Apple account, so it shows that account's tasks. The other account's tasks are safe in its iCloud and come back if you sign in to it again."
        case .signedOut:
            "Your tasks are safe in iCloud and come back when you sign in again (\(Self.signInPath)). Until then, new tasks stay on this device."
        case .neverSignedIn:
            "Tasks stay on this device. To sync them to your other devices, sign in to iCloud: \(Self.signInPath)."
        case .restricted:
            "iCloud is turned off for this device (Screen Time or a device profile), so tasks stay on this device. Check Screen Time → Content & Privacy Restrictions, or ask whoever manages the device."
        case .needsSignInAgain:
            "iCloud needs your Apple account password again before it can sync: \(Self.accountPath)."
        case .couldNotDetermine:
            "HITList couldn't get the iCloud account's status. Nothing is lost; it checks again when you come back to the app. Settings → iCloud → Check iCloud… tells more."
        case .localOnly(let reason):
            "Sync is off on this device: \(reason). Tasks stay on this device."
        }
    }

    var systemImage: String {
        switch self {
        case .signedIn: "checkmark.icloud"
        case .switched: "person.2.circle"
        case .checking: "icloud"
        case .signedOut, .neverSignedIn, .localOnly: "icloud.slash"
        case .restricted, .needsSignInAgain, .couldNotDetermine: "exclamationmark.icloud"
        }
    }

    /// Whether the row should draw attention (the warning colour). Never for someone who never used iCloud.
    var isWarning: Bool {
        switch self {
        case .signedIn, .checking, .neverSignedIn, .switched: false
        case .signedOut, .restricted, .needsSignInAgain, .couldNotDetermine, .localOnly: true
        }
    }

    #if os(macOS)
    static let accountPath = "System Settings → your name"
    static let signInPath = "System Settings → Sign in"
    #else
    static let accountPath = "Settings → your name"
    static let signInPath = "Settings → Sign in to your iPhone"
    #endif
}

/// The words of the Account screen that don't depend on state. Pure, so tests pin the paths.
enum AccountCopy {
    /// Under the Account group. The status row above it says where the tasks are right now.
    static let storage = "HITList has no sign-in of its own: your Apple account is your account, and your tasks live in its private iCloud database, which the app's developer can't see."

    #if os(macOS)
    static let signOutTitle = "Sign out in System Settings"
    static let signOut = "To sign out, use System Settings → [your name] → Sign Out. Signing out never deletes your tasks: they stay in iCloud and come back when you sign in again."
    static let deleteAll = "To delete everything HITList keeps in iCloud, on every device: System Settings → [your name] → iCloud → Manage → HITList → Delete from iCloud. HITList never deletes in bulk itself. This can't be undone, so export your tasks first if you might want them."
    #else
    static let signOutTitle = "Sign out in the Settings app"
    static let signOut = "To sign out, use the Settings app → [your name] → Sign Out. Signing out never deletes your tasks: they stay in iCloud and come back when you sign in again."
    static let deleteAll = "To delete everything HITList keeps in iCloud, on every device: the Settings app → [your name] → iCloud → Storage (on iOS 18: Manage Account Storage) → HITList → Delete Data from iCloud. HITList never deletes in bulk itself. This can't be undone, so export your tasks first if you might want them."
    #endif

    static let deleteProfile = "Removes your name and picture from every device. Your tasks, Groups and settings stay."
}

/// Settings → Account.
struct AccountSettingsSection: View {
    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query private var profiles: [Profile]

    @State private var draftName = ""
    /// The stored name the draft was last loaded from, so a name arriving from another device replaces
    /// the draft only while it hasn't been edited.
    @State private var loadedName = ""
    @State private var pickedPhoto: PhotosPickerItem?
    @State private var isLoadingPhoto = false
    @State private var message: String?
    @State private var confirmDeleteProfile = false
    @State private var showDeleteAll = false
    @State private var exportDocument: SnapshotDocument?

    private var profile: Profile? { profiles.sorted(by: ProfileStore.precedes).first }
    private var store: ProfileStore { ProfileStore(context: context) }
    private var storedName: String { profile?.displayName ?? "" }
    private var nameIsDirty: Bool { ProfileStore.cleanName(draftName) != storedName }

    var body: some View {
        HITGroup("Account", footer: AccountCopy.storage) {
            profileRow
            AccountStatusRow(state: AccountState.current)
            if let message { SettingsMessage(text: message) }
        }
        .onAppear { loadDraft(force: true) }
        .onChange(of: storedName) { _, _ in loadDraft(force: false) }
        .onChange(of: pickedPhoto) { _, item in if let item { loadPhoto(item) } }
        .onDisappear { saveName() }
        .accessibilityIdentifier("settings-account")

        HITGroup("Signing out") {
            HITMenuRowLabel(AccountCopy.signOutTitle, subtitle: AccountCopy.signOut, systemImage: "rectangle.portrait.and.arrow.right")
                .frame(maxWidth: .infinity, alignment: .leading)
                .hitRowPadding()
        }

        HITGroup("Your data", footer: AccountCopy.deleteProfile) {
            HITMenuRow("Export your tasks…", systemImage: "square.and.arrow.up", accessory: .none) {
                if let snap = try? SnapshotBuilder.build(from: context) { exportDocument = SnapshotDocument(snapshot: snap) }
            }
            .accessibilityIdentifier("settings-account-export")
            HITMenuRow("Delete all data from iCloud", systemImage: "trash.slash",
                       accessory: .expand(isExpanded: showDeleteAll)) {
                withAnimation(HITMotion.standard(reduceMotion: reduceMotion)) { showDeleteAll.toggle() }
            }
            .accessibilityIdentifier("settings-account-delete-all")
            if showDeleteAll {
                Text(AccountCopy.deleteAll)
                    .font(HITType.caption)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .hitRowPadding()
                    .textSelection(.enabled)
            }
            HITMenuRow("Delete profile…", systemImage: "person.crop.circle.badge.xmark", role: .destructive, accessory: .none) {
                confirmDeleteProfile = true
            }
            .disabled(profiles.isEmpty)
            .accessibilityIdentifier("settings-account-delete-profile")
        }
        .confirmationDialog("Delete your profile?", isPresented: $confirmDeleteProfile, titleVisibility: .visible) {
            Button("Delete Profile", role: .destructive) { deleteProfile() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(AccountCopy.deleteProfile)
        }
        .fileExporter(isPresented: Binding(get: { exportDocument != nil }, set: { if !$0 { exportDocument = nil } }),
                      document: exportDocument, contentType: .json,
                      defaultFilename: "HITList-\(Date().formatted(.iso8601.year().month().day()))") { _ in }
    }

    private var profileRow: some View {
        HStack(alignment: .center, spacing: HITSpacing.m) {
            ProfileAvatarView(imageData: profile?.avatarData, name: draftName, size: 64)
                .overlay { if isLoadingPhoto { ProgressView().controlSize(.small) } }
            VStack(alignment: .leading, spacing: HITSpacing.s) {
                HStack(spacing: HITSpacing.s) {
                    HITField("Your name", text: $draftName, systemImage: "person")
                        .onSubmit(saveName)
                        .accessibilityIdentifier("settings-account-name")
                    if nameIsDirty {
                        Button("Save", action: saveName)
                            .buttonStyle(HITButtonStyle(.primary, size: .small))
                            .accessibilityIdentifier("settings-account-name-save")
                    }
                }
                HStack(spacing: HITSpacing.s) {
                    PhotosPicker(selection: $pickedPhoto, matching: .images, photoLibrary: .shared()) {
                        Text(profile?.avatarData == nil ? "Choose picture…" : "Change picture…")
                    }
                    .buttonStyle(HITButtonStyle(.secondary, size: .small))
                    .disabled(isLoadingPhoto)
                    .accessibilityIdentifier("settings-account-choose-picture")
                    if profile?.avatarData != nil {
                        Button("Remove") { removePicture() }
                            .buttonStyle(HITButtonStyle(.ghost, size: .small))
                            .accessibilityIdentifier("settings-account-remove-picture")
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .hitRowPadding()
    }

    // MARK: Actions

    private func loadDraft(force: Bool) {
        // Another device's new name replaces the draft only when the draft is what was loaded last.
        if force || ProfileStore.cleanName(draftName) == loadedName { draftName = storedName }
        loadedName = storedName
    }

    private func saveName() {
        guard nameIsDirty else { return }
        do {
            try store.setName(draftName)
            draftName = storedName
            loadedName = storedName
            message = nil
        } catch {
            message = "Couldn't save your name: \(error.localizedDescription)"
        }
    }

    private func loadPhoto(_ item: PhotosPickerItem) {
        isLoadingPhoto = true
        Task {
            defer { isLoadingPhoto = false; pickedPhoto = nil }
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else { throw ProfileStore.ProfileError.unreadablePicture }
                try store.setAvatar(imageData: data)
                message = nil
            } catch {
                message = "Couldn't use that picture: \(error.localizedDescription)"
            }
        }
    }

    private func removePicture() {
        do {
            try store.setAvatar(imageData: nil)
        } catch {
            message = "Couldn't remove the picture: \(error.localizedDescription)"
        }
    }

    private func deleteProfile() {
        do {
            try store.delete()
            draftName = ""
            loadedName = ""
            message = "Profile deleted."
        } catch {
            message = "Couldn't delete the profile: \(error.localizedDescription)"
        }
    }
}

/// The iCloud account's state, as a row: "iCloud: Signed in" and what it means.
struct AccountStatusRow: View {
    let state: AccountState

    var body: some View {
        HITMenuRowLabel(state.title, subtitle: state.detail, systemImage: state.systemImage,
                        iconTint: state.isWarning ? HITColor.dueTomorrow : Theme.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .hitRowPadding()
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("settings-account-icloud")
    }
}

/// The profile picture in a circle, or the name's initials in an accent circle, or a person symbol when
/// there is no name either.
struct ProfileAvatarView: View {
    let imageData: Data?
    let name: String
    var size: CGFloat = 40

    var body: some View {
        Group {
            if let image = imageData.flatMap(Self.image(from:)) {
                image.resizable().scaledToFill()
            } else if let initials = ProfileAvatar.initials(for: name) {
                Text(initials)
                    .font(HITFont.inter(size * 0.4, .semibold))
                    .foregroundStyle(HITColor.onAccent)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.accent)
            } else {
                Image(systemName: "person.fill")
                    .font(.system(size: size * 0.45, weight: .medium))
                    .foregroundStyle(Theme.secondaryText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.elevated)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(Theme.separator, lineWidth: 0.5))
        .accessibilityLabel(name.isEmpty ? "Profile picture" : "Profile picture of \(name)")
    }

    static func image(from data: Data) -> Image? {
        #if os(iOS)
        UIImage(data: data).map(Image.init(uiImage:))
        #else
        NSImage(data: data).map(Image.init(nsImage:))
        #endif
    }
}

/// The profile's avatar and name, small, for a list header (Browse, the Mac sidebar). Not placed yet:
/// session 35 owns Browse and the supervisor decides where it goes. Shows nothing without a profile.
struct ProfileBadge: View {
    @Query private var profiles: [Profile]
    var avatarSize: CGFloat = 28

    var body: some View {
        if let profile = profiles.sorted(by: ProfileStore.precedes).first {
            HStack(spacing: HITSpacing.s) {
                ProfileAvatarView(imageData: profile.avatarData, name: profile.displayName, size: avatarSize)
                if !profile.displayName.isEmpty {
                    Text(profile.displayName)
                        .font(HITType.callout)
                        .foregroundStyle(HITColor.text)
                        .lineLimit(1)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("profile-badge")
        }
    }
}

#Preview("Account") {
    ScrollView {
        VStack(spacing: HITSpacing.xl) { AccountSettingsSection() }.padding()
    }
    .background(Theme.background)
    .modelContainer(ModelContainerFactory.preview())
    .preferredColorScheme(.dark)
}
