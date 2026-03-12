import PhotosUI
import SwiftUI
import UIKit

private enum AppTab: Int {
    case wishlists
    case activity
    case shared
}

private struct SharedDeepLinkRoute: Identifiable, Hashable {
    let token: String
    var id: String { token }
}

private struct SharedItemDeepLinkRoute: Identifiable, Hashable {
    let token: String
    var id: String { token }
}

private struct ToastState: Identifiable {
    let id = UUID()
    let message: String
    let isError: Bool
}

private struct SharePayload: Identifiable {
    let id = UUID()
    let text: String
}

private struct ContributionSummary: Hashable {
    let fundedCents: Int
    let contributorCount: Int
}

private enum AuthMode: String, CaseIterable, Identifiable {
    case signIn = "Sign in"
    case signUp = "Create account"

    var id: String { rawValue }
}

private enum NotificationPreferenceKeys {
    static let ownerReservationAlertsEnabled = "notifications.owner.reservation_alerts_enabled"
    static let guestArchivedItemAlertsEnabled = "notifications.guest.archived_item_alerts_enabled"
}

struct ContentView: View {
    @EnvironmentObject private var auth: AuthStore
    @State private var selectedTab: AppTab = .wishlists
    @State private var signedOutSharedRoute: SharedDeepLinkRoute?
    @State private var sharedItemRoute: SharedItemDeepLinkRoute?

    var body: some View {
        Group {
            if auth.isAuthenticated {
                TabView(selection: $selectedTab) {
                    NavigationStack {
                        WishlistsView()
                    }
                    .tag(AppTab.wishlists)
                    .tabItem {
                        Label("Wishlists", systemImage: "gift")
                    }

                    NavigationStack {
                        ActivityView()
                    }
                    .tag(AppTab.activity)
                    .tabItem {
                        Label("Activity", systemImage: "clock.arrow.circlepath")
                    }

                    NavigationStack {
                        SharedLookupView()
                    }
                    .tag(AppTab.shared)
                    .tabItem {
                        Label("Shared", systemImage: "link")
                    }
                }
                .tint(WishTheme.accentBlue)
            } else {
                NavigationStack {
                    WishlistsView()
                        .navigationDestination(item: $signedOutSharedRoute) { route in
                            PublicWishlistView(shareToken: route.token)
                                .environmentObject(auth)
                        }
                }
                .tint(WishTheme.accentBlue)
            }
        }
        .animation(.easeInOut(duration: 0.22), value: auth.isAuthenticated)
        .sheet(item: $sharedItemRoute) { route in
            SharedItemViewerSheet(
                itemToken: route.token,
                onClose: {
                    sharedItemRoute = nil
                }
            )
        }
        .onOpenURL { url in
            if let itemToken = AppConfig.itemShareToken(from: url.absoluteString), !itemToken.isEmpty {
                sharedItemRoute = SharedItemDeepLinkRoute(token: itemToken)
                return
            }

            guard let token = AppConfig.shareToken(from: url.absoluteString), !token.isEmpty else {
                return
            }

            if auth.isAuthenticated {
                selectedTab = .shared
                return
            }

            signedOutSharedRoute = SharedDeepLinkRoute(token: token)
        }
        .background(WishTheme.background.ignoresSafeArea())
    }
}

private struct WishlistsView: View {
    @EnvironmentObject private var auth: AuthStore
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    private static let isoWithFractionFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let isoDefaultFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    @State private var wishlists: [WishlistPreview] = []
    @State private var isLoading = false
    @State private var hasLoadedInitialWishlists = false
    @State private var loadError: String?
    @State private var search = ""
    @State private var sort = "updated_desc"

    @State private var toast: ToastState?
    @State private var selectedWishlist: WishlistPreview?
    @State private var editingWishlist: WishlistPreview?
    @State private var pendingDeleteWishlist: WishlistPreview?
    @State private var sharePayload: SharePayload?
    @State private var showingAuthSheet = false
    @State private var showingOnboarding = false
    @State private var reloadToken = UUID()
    @State private var isSearchPanelVisible = false

    private var queryPath: String {
        var components = URLComponents()
        var queryItems: [URLQueryItem] = []

        let trimmedSearch = search.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedSearch.isEmpty {
            queryItems.append(URLQueryItem(name: "search", value: trimmedSearch))
        }

        if sort != "updated_desc" {
            queryItems.append(URLQueryItem(name: "sort", value: sort))
        }

        components.queryItems = queryItems.isEmpty ? nil : queryItems
        let query = components.percentEncodedQuery ?? ""

        if query.isEmpty {
            return "/api/wishlists"
        }

        return "/api/wishlists?\(query)"
    }

    var body: some View {
        ZStack {
            if auth.isAuthenticated {
                ScrollView {
                    VStack(spacing: 14) {
                        controls
                        if isSearchPanelVisible {
                            searchPanel
                                .transition(.move(edge: .top).combined(with: .opacity))
                        }
                        content
                    }
                    .wishPageLayout()
                }
                .refreshable {
                    await loadWishlists()
                }
                .task(id: "\(queryPath)-\(auth.email ?? "")-\(reloadToken.uuidString)") {
                    await loadWishlists()
                }

                if !hasLoadedInitialWishlists {
                    initialWishlistLoadingScreen
                }
            } else {
                signedOutLanding
            }

            if let toast {
                VStack {
                    ToastBanner(message: toast.message, isError: toast.isError)
                        .padding(.top, 8)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .navigationTitle(auth.isAuthenticated ? "My wishlists" : "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(auth.isAuthenticated ? .visible : .hidden, for: .navigationBar)
        .toolbar {
            if auth.isAuthenticated {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isSearchPanelVisible.toggle()
                        }
                    } label: {
                        Image(systemName: isSearchPanelVisible ? "xmark.circle.fill" : "magnifyingglass")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(WishTheme.accentBlue)
                    }
                    .accessibilityLabel(isSearchPanelVisible ? "Hide search" : "Show search")
                }
            }
        }
        .background(WishTheme.background.ignoresSafeArea())
        .sheet(isPresented: $showingOnboarding) {
            NavigationStack {
                OnboardingView { created in
                    showingOnboarding = false
                    selectedWishlist = WishlistPreview(
                        id: created.id,
                        title: created.title,
                        occasionDate: created.occasionDate,
                        occasionNote: created.occasionNote,
                        currency: created.currency,
                        updatedAt: created.updatedAt,
                        shareUrlPreview: created.shareUrlPreview,
                        reservedCount: 0
                    )
                    showToast("Wishlist created.", isError: false)
                    reloadToken = UUID()
                }
            }
            .environmentObject(auth)
        }
        .sheet(item: $editingWishlist) { wishlist in
            NavigationStack {
                WishlistEditSheet(wishlist: wishlist) { updated in
                    Task {
                        await saveWishlist(updated)
                    }
                }
            }
            .environmentObject(auth)
        }
        .sheet(item: $sharePayload) { payload in
            ActivityShareSheet(activityItems: [payload.text])
        }
        .sheet(isPresented: $showingAuthSheet) {
            NavigationStack {
                AccountView()
            }
            .environmentObject(auth)
            .environment(\.colorScheme, .light)
            .preferredColorScheme(.light)
        }
        .alert(
            "Delete wishlist?",
            isPresented: Binding(
                get: { pendingDeleteWishlist != nil },
                set: { showing in
                    if !showing {
                        pendingDeleteWishlist = nil
                    }
                }
            ),
            presenting: pendingDeleteWishlist
        ) { wishlist in
            Button("Delete", role: .destructive) {
                Task {
                    await deleteWishlist(wishlist)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { wishlist in
            Text("This removes \"\(wishlist.title)\" and all items.")
        }
        .navigationDestination(item: $selectedWishlist) { wishlist in
            WishlistEditorView(wishlistId: wishlist.id, wishlistTitle: wishlist.title)
                .environmentObject(auth)
        }
        .onChange(of: toast?.id) {
            guard toast != nil else { return }
            Task {
                try? await Task.sleep(nanoseconds: 2_200_000_000)
                if !Task.isCancelled {
                    withAnimation {
                        toast = nil
                    }
                }
            }
        }
        .onChange(of: auth.isAuthenticated) {
            if auth.isAuthenticated {
                showingAuthSheet = false
            } else {
                isSearchPanelVisible = false
                wishlists = []
                loadError = nil
                isLoading = false
                hasLoadedInitialWishlists = false
            }
        }
    }

    private var signedOutLanding: some View {
        GeometryReader { proxy in
            let isPhoneLandscape = UIDevice.current.userInterfaceIdiom == .phone && verticalSizeClass == .compact

            ScrollView {
                Group {
                    if isPhoneLandscape {
                        HStack(alignment: .center, spacing: 22) {
                            Image("LogoWordmark")
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: 220)
                                .accessibilityLabel("I WISH ... Wish List")

                            VStack(spacing: 14) {
                                signedOutPitchCard
                                    .frame(maxWidth: 420)

                                Button("Sign in or create account") {
                                    showingAuthSheet = true
                                }
                                .buttonStyle(WishPillButtonStyle(variant: .main))
                                .frame(maxWidth: 420)
                            }
                            .frame(maxWidth: .infinity, alignment: .center)
                        }
                        .frame(maxWidth: min(820, proxy.size.width - 40), alignment: .center)
                        .frame(maxWidth: .infinity, minHeight: proxy.size.height, alignment: .center)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                    } else {
                        VStack(spacing: 16) {
                            Image("LogoWordmark")
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: 240)
                                .padding(.top, 18)
                                .accessibilityLabel("I WISH ... Wish List")

                            Spacer(minLength: 0)

                            signedOutPitchCard
                                .frame(maxWidth: min(360, proxy.size.width - 24))

                            Button("Sign in or create account") {
                                showingAuthSheet = true
                            }
                            .buttonStyle(WishPillButtonStyle(variant: .main))
                            .frame(width: min(340, proxy.size.width - 32))

                            Spacer(minLength: 0)
                        }
                        .frame(maxWidth: .infinity, minHeight: proxy.size.height, alignment: .top)
                        .padding(.bottom, 16)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
        }
    }

    private var signedOutPitchCard: some View {
        VStack(spacing: 10) {
            Text("Celebrate your moments with gifts chosen from the heart")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(WishTheme.coolGradient)
                .multilineTextAlignment(.center)

            Text("Create a wishlist in minutes, share one link, and let friends reserve gifts or contribute together for one unforgettable surprise.")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color(red: 0.33, green: 0.35, blue: 0.41))
                .multilineTextAlignment(.center)
                .lineSpacing(2)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.98), Color(red: 1.0, green: 0.96, blue: 0.86)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.9), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.07), radius: 12, x: 0, y: 7)
    }

    private var initialWishlistLoadingScreen: some View {
        VStack(spacing: 12) {
            ProgressView()
                .progressViewStyle(.circular)
                .tint(WishTheme.accentBlue)
                .scaleEffect(1.12)

            Text("Loading wishlists...")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WishTheme.background.ignoresSafeArea())
    }

    private var controls: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                if let email = auth.email, !email.isEmpty {
                    Text(email)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()

                Button("Log out") {
                    auth.signOut()
                    showToast("Signed out.", isError: false)
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(WishTheme.accentBlue)
                .buttonStyle(.plain)
            }
        }
        .wishCardStyle()
    }

    private var searchPanel: some View {
        HStack(spacing: 8) {
            searchField
            sortPicker
        }
        .wishCardStyle()
    }

    private var controlHeight: CGFloat { 46 }

    private var searchField: some View {
        TextField("Search by title", text: $search)
            .textInputAutocapitalization(.sentences)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.white)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(red: 0.84, green: 0.85, blue: 0.87), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .frame(height: controlHeight)
            .frame(maxWidth: .infinity)
    }

    private var sortPicker: some View {
        Menu {
            Button("Recent") { sort = "updated_desc" }
            Button("A-Z") { sort = "title_asc" }
        } label: {
            HStack(spacing: 6) {
                Text(sort == "updated_desc" ? "Recent" : "A-Z")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(WishTheme.accentBlue)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(WishTheme.accentBlue)
            }
            .frame(maxWidth: .infinity)
            .frame(height: controlHeight)
        }
        .buttonStyle(.plain)
        .background(Color.white)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(red: 0.84, green: 0.85, blue: 0.87), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private var content: some View {
        if let loadError {
            VStack(alignment: .leading, spacing: 10) {
                Text(loadError)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.red)

                Button("Retry") {
                    reloadToken = UUID()
                }
                .buttonStyle(WishPillButtonStyle(variant: .warm))
            }
            .wishCardStyle()
        } else if wishlists.isEmpty {
            VStack(spacing: 10) {
                Text("No wishlists yet")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(WishTheme.headerBlue)
                Text("Start a new wishlist to copy and share your first public link.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Create wishlist") {
                    showingOnboarding = true
                }
                .buttonStyle(WishPillButtonStyle(variant: .cool))
            }
            .wishCardStyle()
        } else {
            ForEach(wishlists) { wishlist in
                wishlistCard(wishlist)
            }
        }
    }

    private func wishlistShareButton(_ wishlist: WishlistPreview) -> some View {
        Button {
            sharePayload = SharePayload(text: wishlist.shareUrlPreview)
        } label: {
            Image(systemName: "square.and.arrow.up")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(WishTheme.accentBlue)
                .frame(width: 42, height: 42)
                .background(Color.white.opacity(0.68))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Share wishlist")
    }

    private func wishlistCard(_ wishlist: WishlistPreview) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Button {
                    selectedWishlist = wishlist
                } label: {
                    wishlistHeaderAndDescription(wishlist)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                wishlistShareButton(wishlist)
            }
        }
        .wishCardStyle()
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                pendingDeleteWishlist = wishlist
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func wishlistHeaderAndDescription(_ wishlist: WishlistPreview) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            wishlistTextBlock(wishlist)
            updatedAtPill(wishlist.updatedAt)
            reservedCountPill(wishlist.reservedCount)
        }
    }

    private func wishlistTextBlock(_ wishlist: WishlistPreview) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(wishlist.title)
                .font(.system(size: 25, weight: .bold, design: .rounded))
                .foregroundStyle(WishTheme.coolGradient)
                .lineLimit(2)
                .minimumScaleFactor(0.84)

            Text(wishlist.occasionDate.map { "Occasion date: \(formatDateLabel($0))" } ?? "No occasion date")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)

            if let occasionNote = wishlist.occasionNote, !occasionNote.isEmpty {
                Text(occasionNote)
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .minimumScaleFactor(0.9)
            }
        }
    }

    private func updatedAtPill(_ raw: String) -> some View {
        Text("Updated \(formattedUpdatedAt(raw))")
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.white.opacity(0.65))
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func reservedCountPill(_ reservedCount: Int) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "gift.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(WishTheme.accentBlue)
            Text("\(reservedCount) reserved")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.white.opacity(0.65))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func formattedUpdatedAt(_ raw: String) -> String {
        if let parsed = Self.isoWithFractionFormatter.date(from: raw) ?? Self.isoDefaultFormatter.date(from: raw) {
            return parsed.formatted(date: .abbreviated, time: .shortened)
        }

        return formatDateLabel(raw)
    }

    private func loadWishlists() async {
        guard let headers = auth.ownerHeaders else {
            wishlists = []
            loadError = nil
            isLoading = false
            hasLoadedInitialWishlists = false
            return
        }

        isLoading = true
        loadError = nil

        do {
            let response: WishlistListResponse = try await APIClient.shared.request(
                path: queryPath,
                method: "GET",
                headers: headers
            )
            wishlists = response.wishlists
        } catch is CancellationError {
            isLoading = false
            return
        } catch {
            loadError = error.localizedDescription
            wishlists = []
        }

        isLoading = false
        hasLoadedInitialWishlists = true
    }

    private func saveWishlist(_ updated: WishlistUpdatePayloadWithID) async {
        guard var headers = auth.ownerHeaders else {
            showToast("Sign in is required.", isError: true)
            return
        }
        headers["content-type"] = "application/json"

        do {
            let response: WishlistUpdateResponse = try await APIClient.shared.request(
                path: "/api/wishlists/\(updated.id)",
                method: "PATCH",
                headers: headers,
                body: WishlistUpdatePayload(
                    title: updated.title,
                    occasionDate: updated.occasionDate,
                    occasionNote: updated.occasionNote
                )
            )

            if let index = wishlists.firstIndex(where: { $0.id == response.wishlist.id }) {
                wishlists[index] = response.wishlist
            }

            editingWishlist = nil
            showToast("Wishlist details updated.", isError: false)
        } catch {
            showToast(error.localizedDescription, isError: true)
        }
    }

    private func deleteWishlist(_ wishlist: WishlistPreview) async {
        guard let headers = auth.ownerHeaders else {
            showToast("Sign in is required.", isError: true)
            return
        }

        do {
            let response: WishlistDeleteResponse = try await APIClient.shared.request(
                path: "/api/wishlists/\(wishlist.id)",
                method: "DELETE",
                headers: headers
            )

            wishlists.removeAll { $0.id == response.deletedWishlistId }
            pendingDeleteWishlist = nil
            showToast("Wishlist deleted.", isError: false)
        } catch {
            showToast(error.localizedDescription, isError: true)
        }
    }

    private func showToast(_ message: String, isError: Bool) {
        withAnimation {
            toast = ToastState(message: message, isError: isError)
        }
    }
}

private struct WishlistUpdatePayloadWithID: Hashable {
    let id: String
    let title: String
    let occasionDate: String?
    let occasionNote: String?
}

private struct WishlistEditSheet: View {
    @Environment(\.dismiss) private var dismiss

    let wishlist: WishlistPreview
    let onSave: (WishlistUpdatePayloadWithID) -> Void

    @State private var title: String
    @State private var hasOccasionDate: Bool
    @State private var selectedOccasionDate: Date
    @State private var occasionNote: String

    init(wishlist: WishlistPreview, onSave: @escaping (WishlistUpdatePayloadWithID) -> Void) {
        self.wishlist = wishlist
        self.onSave = onSave
        _title = State(initialValue: wishlist.title)
        let parsedDate = wishlist.occasionDate.flatMap { Self.storageDateFormatter.date(from: $0) }
        _hasOccasionDate = State(initialValue: parsedDate != nil)
        _selectedOccasionDate = State(initialValue: parsedDate ?? Date())
        _occasionNote = State(initialValue: wishlist.occasionNote ?? "")
    }

    var body: some View {
        Form {
            Section("Wishlist details") {
                TextField("Title", text: $title)

                if hasOccasionDate {
                    DatePicker("Occasion date", selection: $selectedOccasionDate, displayedComponents: .date)
                        .datePickerStyle(.compact)

                    Button("Remove occasion date", role: .destructive) {
                        hasOccasionDate = false
                    }
                } else {
                    Button("Add occasion date") {
                        hasOccasionDate = true
                    }
                }

                TextEditor(text: $occasionNote)
                    .frame(minHeight: 110)
                    .scrollContentBackground(.hidden)
            }
        }
        .navigationTitle("Edit wishlist")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    onSave(
                        WishlistUpdatePayloadWithID(
                            id: wishlist.id,
                            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                            occasionDate: hasOccasionDate ? Self.storageDateFormatter.string(from: selectedOccasionDate) : nil,
                            occasionNote: occasionNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : occasionNote.trimmingCharacters(in: .whitespacesAndNewlines)
                        )
                    )
                }
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private static let storageDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

private struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var auth: AuthStore

    let onCreated: (WishlistCreatedModel) -> Void

    @State private var title = ""
    @State private var occasionDate = ""
    @State private var occasionNote = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Create your first wishlist")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(WishTheme.headerBlue)

                Text("Set up your list in under a minute, then share one public link with friends.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 10) {
                    TextField("Wishlist title", text: $title)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(Color.white)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color(red: 0.84, green: 0.85, blue: 0.87), lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                    TextField("Occasion date (optional)", text: $occasionDate)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(Color.white)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color(red: 0.84, green: 0.85, blue: 0.87), lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                    TextEditor(text: $occasionNote)
                        .frame(minHeight: 110)
                        .scrollContentBackground(.hidden)
                        .padding(6)
                        .background(Color.white)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color(red: 0.84, green: 0.85, blue: 0.87), lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .wishCardStyle()

                if let errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.red)
                        .wishCardStyle()
                }

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        Button("Back") {
                            dismiss()
                        }
                        .buttonStyle(WishPillButtonStyle(variant: .neutral))

                        Button(isSubmitting ? "Creating..." : "Create wishlist") {
                            Task {
                                await createWishlist()
                            }
                        }
                        .buttonStyle(WishPillButtonStyle(variant: .cool))
                        .disabled(isSubmitting)
                    }

                    VStack(spacing: 8) {
                        Button("Back") {
                            dismiss()
                        }
                        .buttonStyle(WishPillButtonStyle(variant: .neutral))

                        Button(isSubmitting ? "Creating..." : "Create wishlist") {
                            Task {
                                await createWishlist()
                            }
                        }
                        .buttonStyle(WishPillButtonStyle(variant: .cool))
                        .disabled(isSubmitting)
                    }
                }
            }
            .wishPageLayout()
        }
        .background(WishTheme.background.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
    }

    private func createWishlist() async {
        guard var headers = auth.ownerHeaders else {
            errorMessage = "Sign in is required to create a wishlist."
            return
        }

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedTitle.isEmpty {
            errorMessage = "Wishlist title is required."
            return
        }

        headers["content-type"] = "application/json"
        isSubmitting = true
        errorMessage = nil

        do {
            let response: WishlistCreateResponse = try await APIClient.shared.request(
                path: "/api/wishlists",
                method: "POST",
                headers: headers,
                body: WishlistCreatePayload(
                    title: trimmedTitle,
                    occasionDate: occasionDate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : occasionDate.trimmingCharacters(in: .whitespacesAndNewlines),
                    occasionNote: occasionNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : occasionNote.trimmingCharacters(in: .whitespacesAndNewlines),
                    currency: "USD"
                )
            )

            onCreated(response.wishlist)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }

        isSubmitting = false
    }
}

private struct WishlistEditorView: View {
    @EnvironmentObject private var auth: AuthStore
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @AppStorage(NotificationPreferenceKeys.ownerReservationAlertsEnabled) private var ownerReservationAlertsEnabled = true

    let wishlistId: String
    let wishlistTitle: String

    @State private var items: [ItemRecord] = []
    @State private var hasLoadedInitialEditorData = false
    @State private var loadError: String?
    @State private var shareUrlPreview: String?

    @State private var availabilityByItemId: [String: String] = [:]
    @State private var contributionsByItemId: [String: ContributionSummary] = [:]
    @State private var previewImageUrlsByItemId: [String: [String]] = [:]

    @State private var editingItem: ItemRecord?

    @State private var draftText = ""
    @State private var productURL = ""
    @State private var importedImageURLs: [String] = []
    @State private var isGroupFunded = false
    @State private var targetText = ""
    @State private var pendingImages: [PendingImage] = []
    @State private var photoSelections: [PhotosPickerItem] = []

    @State private var isSubmitting = false
    @State private var isUploadingImages = false
    @State private var formError: String?
    @State private var formSuccess: String?
    @State private var metadataMessage: String?
    @State private var priceReviewNotice: String?
    @State private var requiresPriceConfirmation = false
    @State private var hasConfirmedLowConfidencePrice = false

    @State private var shortfallItem: ItemRecord?

    @State private var reviewItem: ItemRecord?
    @State private var reviewImageURLs: [String] = []
    @State private var reviewImageIndex = 0
    @State private var reviewSheetContentHeight: CGFloat = 0
    @State private var reviewSheetDetentSelection: PresentationDetent = {
        let idiom = UIDevice.current.userInterfaceIdiom
        if idiom == .pad || idiom == .mac {
            return .fraction(1.0)
        }
        return .large
    }()

    @State private var shareToast: ToastState?
    @State private var editorSharePayload: SharePayload?
    @State private var isShowingItemForm = false
    @State private var canManageItems = false
    @State private var wishlistPreview: WishlistPreview?
    @State private var editingWishlistDetails: WishlistPreview?
    @State private var showingNotificationSettings = false
    @State private var hasPrimedAvailabilitySnapshot = false
    @State private var archivingItemIds: Set<String> = []

    private var activeItems: [ItemRecord] {
        items.filter { !$0.isArchived }
    }

    private var archivedItems: [ItemRecord] {
        items.filter { $0.isArchived }
    }

    private var activeReservedCount: Int {
        activeItems.reduce(0) { partial, item in
            partial + ((availabilityByItemId[item.id] == "reserved") ? 1 : 0)
        }
    }

    private var activeImageCount: Int {
        importedImageURLs.count + pendingImages.count
    }

    private var displayedWishlistTitle: String {
        wishlistPreview?.title ?? wishlistTitle
    }

    private var reviewSheetDetents: Set<PresentationDetent> {
        [reviewSheetDetentSelection]
    }

    private func resolvedReviewSheetDetentSelection() -> PresentationDetent {
        let idiom = UIDevice.current.userInterfaceIdiom
        if idiom == .pad || idiom == .mac {
            return .fraction(1.0)
        }

        guard horizontalSizeClass == .regular else {
            return .large
        }

        let screenHeight = UIScreen.main.bounds.height
        let minHeight: CGFloat = 360
        let maxHeight = max(minHeight, screenHeight * 0.98)
        let fallbackHeight = min(maxHeight, 740)
        let measuredHeight = reviewSheetContentHeight > 0 ? (reviewSheetContentHeight + 64) : fallbackHeight
        let resolvedHeight = min(max(measuredHeight, minHeight), maxHeight)
        return .height(resolvedHeight)
    }

    private func syncReviewSheetDetentSelection() {
        let desired = resolvedReviewSheetDetentSelection()
        guard desired != reviewSheetDetentSelection else { return }
        reviewSheetDetentSelection = desired
    }

    private var addItemSheetDetents: Set<PresentationDetent> {
        let idiom = UIDevice.current.userInterfaceIdiom
        if horizontalSizeClass == .regular || idiom == .pad || idiom == .mac {
            return [.fraction(1.0)]
        }
        return [.large]
    }

    var body: some View {
        ZStack {
            ScrollView {
                VStack(spacing: 14) {
                    header
                    listSection
                }
                .wishPageLayout()
            }

            if !hasLoadedInitialEditorData {
                initialWishlistEditorLoadingScreen
            }
        }
        .background(WishTheme.background.ignoresSafeArea())
        .navigationTitle("Wishlist editor")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if canManageItems {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        resetForm()
                        formError = nil
                        isShowingItemForm = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(WishTheme.accentBlue)
                    }
                    .accessibilityLabel("Add item")
                }
            }

            if horizontalSizeClass == .compact {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        if canManageItems {
                            Button {
                                if let wishlistPreview {
                                    editingWishlistDetails = wishlistPreview
                                }
                            } label: {
                                Label("Edit wishlist details", systemImage: "pencil")
                            }
                            .disabled(wishlistPreview == nil)
                        }

                        Button {
                            showingNotificationSettings = true
                        } label: {
                            Label("Notification settings", systemImage: "gearshape")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(WishTheme.accentBlue)
                    }
                    .accessibilityLabel("More actions")
                }
            } else {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if canManageItems {
                        Button {
                            if let wishlistPreview {
                                editingWishlistDetails = wishlistPreview
                            }
                        } label: {
                            Image(systemName: "pencil")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(WishTheme.accentBlue)
                        }
                        .disabled(wishlistPreview == nil)
                        .accessibilityLabel("Edit wishlist details")
                    }

                    Button {
                        showingNotificationSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(WishTheme.accentBlue)
                    }
                    .accessibilityLabel("Notification settings")
                }
            }
        }
        .task(id: wishlistId) {
            hasLoadedInitialEditorData = false
            await loadEditorData()
        }
        .task(id: shareUrlPreview ?? "") {
            await pollRealtimeAvailability()
        }
        .sheet(isPresented: $isShowingItemForm, onDismiss: {
            resetForm()
        }) {
            NavigationStack {
                ScrollView {
                    formCard
                        .wishPageLayout()
                }
                .background(WishTheme.background.ignoresSafeArea())
                .navigationTitle(editingItem == nil ? "Add item" : "Edit item")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") {
                            isShowingItemForm = false
                            resetForm()
                        }
                    }
                }
            }
            .presentationDetents(addItemSheetDetents)
            .presentationDragIndicator(.visible)
        }
        .modifier(
            ReviewItemPresentationModifier(
                reviewItem: $reviewItem,
                reviewImageURLs: $reviewImageURLs,
                reviewImageIndex: $reviewImageIndex,
                reviewSheetContentHeight: $reviewSheetContentHeight,
                reviewSheetDetents: reviewSheetDetents,
                reviewSheetDetentSelection: $reviewSheetDetentSelection,
                contributionSummaryForItemId: { itemId in
                    contributionsByItemId[itemId] ?? ContributionSummary(
                        fundedCents: items.first(where: { $0.id == itemId })?.fundedCents ?? 0,
                        contributorCount: items.first(where: { $0.id == itemId })?.contributorCount ?? 0
                    )
                },
                onRestore: { item in
                    Task {
                        await restoreItem(item)
                    }
                }
            )
        )
        .sheet(item: $editorSharePayload) { payload in
            ActivityShareSheet(activityItems: [payload.text])
        }
        .sheet(item: $editingWishlistDetails) { wishlist in
            NavigationStack {
                WishlistEditSheet(wishlist: wishlist) { updated in
                    Task {
                        await saveEditorWishlistDetails(updated)
                    }
                }
            }
        }
        .sheet(item: $shortfallItem) { item in
            ShortfallSheet(item: item) { action in
                Task {
                    await resolveShortfall(item: item, action: action)
                }
            }
        }
        .sheet(isPresented: $showingNotificationSettings) {
            NavigationStack {
                NotificationSettingsSheet()
            }
        }
        .onChange(of: photoSelections) {
            Task {
                await consumePhotoSelections(photoSelections)
            }
        }
        .overlay(alignment: .top) {
            if let shareToast {
                ToastBanner(message: shareToast.message, isError: shareToast.isError)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
            }
        }
        .onChange(of: shareToast?.id) {
            guard shareToast != nil else { return }
            Task {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                if !Task.isCancelled {
                    withAnimation {
                        shareToast = nil
                    }
                }
            }
        }
        .onChange(of: canManageItems) {
            if !canManageItems && isShowingItemForm {
                isShowingItemForm = false
                resetForm()
            }
        }
        .onChange(of: reviewSheetContentHeight) {
            guard reviewItem != nil else { return }
            syncReviewSheetDetentSelection()
        }
    }

    private var initialWishlistEditorLoadingScreen: some View {
        VStack(spacing: 12) {
            ProgressView()
                .progressViewStyle(.circular)
                .tint(WishTheme.accentBlue)
                .scaleEffect(1.12)

            Text("Loading wishlist...")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WishTheme.background.ignoresSafeArea())
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Text(displayedWishlistTitle)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(WishTheme.headerBlue)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Spacer(minLength: 0)

                if canManageItems, let shareUrlPreview {
                    shareWishlistIconButton(shareUrlPreview)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                editorHeaderDetailRow(title: "Occasion", value: formatDateLabel(wishlistPreview?.occasionDate))
                editorHeaderDetailRow(title: "Reserved", value: "\(activeReservedCount) of \(activeItems.count)")
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.45))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.white.opacity(0.75), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))

            if let note = wishlistPreview?.occasionNote, !note.isEmpty {
                Text(note)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let formSuccess {
                Text(formSuccess)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.green)
            }

            if let formError {
                Text(formError)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.red)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(WishTheme.heroGradient)
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.white.opacity(0.65), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private func editorHeaderDetailRow(title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            Spacer(minLength: 6)
            Text(value)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(WishTheme.headerBlue)
                .multilineTextAlignment(.trailing)
        }
    }

    private func shareWishlistIconButton(_ shareUrlPreview: String) -> some View {
        Button {
            editorSharePayload = SharePayload(text: shareUrlPreview)
        } label: {
            Image(systemName: "square.and.arrow.up")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(WishTheme.accentBlue)
                .frame(width: 36, height: 36)
                .background(
                    Circle()
                        .fill(Color.white.opacity(0.95))
                )
                .overlay(
                    Circle()
                        .stroke(Color(red: 0.84, green: 0.85, blue: 0.87), lineWidth: 1)
                )
        }
        .accessibilityLabel("Share wishlist")
    }

    private var formCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(editingItem == nil ? "Add item" : "Edit item")
                    .font(.system(size: 18, weight: .semibold))
                Spacer()
                if editingItem != nil {
                    Button("Cancel") {
                        resetForm()
                    }
                    .buttonStyle(WishPillButtonStyle(variant: .neutral))
                }
            }

            Text("Title, description, and price")
                .font(.system(size: 12, weight: .semibold))
                .textCase(.uppercase)
                .foregroundStyle(WishTheme.headerBlue)

            TextEditor(text: $draftText)
                .frame(minHeight: 120)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(priceReviewNotice == nil ? Color(red: 0.84, green: 0.85, blue: 0.87) : Color.red, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .onChange(of: draftText) { _, _ in
                    clearLowConfidenceConfirmation()
                }

            if let priceReviewNotice {
                Text(priceReviewNotice)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.red)
            }

            if requiresPriceConfirmation {
                Toggle(isOn: $hasConfirmedLowConfidencePrice) {
                    Text("Price confidence is below 90%. I confirmed this price is correct.")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.red)
                }
                .tint(Color.red)
            }

            TextField("Product URL", text: $productURL)
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
                .autocorrectionDisabled()
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color(red: 0.84, green: 0.85, blue: 0.87), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .onChange(of: productURL) { _, _ in
                    clearLowConfidenceConfirmation()
                }

            if let metadataMessage {
                Text(metadataMessage)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Toggle(isOn: $isGroupFunded) {
                Text("Group funded item")
                    .font(.system(size: 14, weight: .medium))
            }

            if isGroupFunded {
                TextField("Funding target (USD)", text: $targetText)
                    .keyboardType(.decimalPad)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color(red: 0.84, green: 0.85, blue: 0.87), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            imageEditor

            VStack(spacing: 8) {
                HStack {
                    Spacer(minLength: 0)
                    Button(isSubmitting ? "Saving..." : (editingItem == nil ? "Add item" : "Save item")) {
                        Task {
                            await submitItem()
                        }
                    }
                    .buttonStyle(WishPillButtonStyle(variant: .main))
                    .disabled(isSubmitting || isUploadingImages)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity)

                if activeImageCount > 0 {
                    HStack {
                        Spacer(minLength: 0)
                        Button("Clear images") {
                            importedImageURLs = []
                            pendingImages = []
                        }
                        .buttonStyle(WishPillButtonStyle(variant: .neutral))
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity)
                }
            }

            if isUploadingImages {
                Text("Uploading selected images...")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .wishCardStyle()
    }

    private var imageEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Item images")
                .font(.system(size: 14, weight: .semibold))

            let previewURL = importedImageURLs.first
            if let previewURL,
               let url = URL(string: previewURL),
               !previewURL.hasPrefix("storage://") {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    ProgressView()
                }
                .frame(height: 140)
                .frame(maxWidth: .infinity)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white)
                    .frame(height: 140)
                    .overlay(
                        Text("No remote image selected")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color(red: 0.84, green: 0.85, blue: 0.87), lineWidth: 1)
                    )
            }

            PhotosPicker(selection: $photoSelections, maxSelectionCount: max(0, 10 - importedImageURLs.count), matching: .images) {
                Text("\(activeImageCount > 0 ? "Add images" : "Upload images")")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(WishPillButtonStyle(variant: .neutral))

            Text("\(activeImageCount)/10 images selected")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            if !importedImageURLs.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(importedImageURLs.enumerated()), id: \.offset) { index, value in
                            HStack(spacing: 4) {
                                Text("Remote \(index + 1)")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.secondary)
                                Button {
                                    importedImageURLs.remove(at: index)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.red)
                                }
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(Color.white)
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(Color(red: 0.84, green: 0.85, blue: 0.87), lineWidth: 1))
                        }
                    }
                }
            }

            if !pendingImages.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(pendingImages) { image in
                            if let uiImage = UIImage(data: image.data) {
                                ZStack(alignment: .topTrailing) {
                                    Image(uiImage: uiImage)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 72, height: 72)
                                        .clipped()
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 10)
                                                .stroke(Color(red: 0.84, green: 0.85, blue: 0.87), lineWidth: 1)
                                        )

                                    Button {
                                        pendingImages.removeAll { $0.id == image.id }
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundStyle(.red)
                                            .background(Color.white.clipShape(Circle()))
                                    }
                                    .offset(x: 6, y: -6)
                                }
                            }
                        }
                    }
                    .padding(.top, 2)
                }
            }
        }
    }

    @ViewBuilder
    private var listSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Items")
                    .font(.system(size: 18, weight: .semibold))
                Spacer()
                if !activeItems.isEmpty {
                    Text("\(activeReservedCount) of \(activeItems.count) reserved")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }

            if let loadError {
                Text(loadError)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.red)
                    .wishCardStyle()
            } else if activeItems.isEmpty {
                Text("No items yet. Tap + to create your first item.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .wishCardStyle()
            } else {
                ForEach(activeItems) { item in
                    itemRow(item)
                }
            }

            if !archivedItems.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Archived items")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)

                    ForEach(archivedItems) { item in
                        Button {
                            Task {
                                await openReview(item)
                            }
                        } label: {
                            Text(item.title)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .wishCardStyle()
            }
        }
    }

    private func itemRow(_ item: ItemRecord) -> some View {
        let liveAvailability = availabilityByItemId[item.id]
        let summary = contributionsByItemId[item.id] ?? ContributionSummary(fundedCents: item.fundedCents, contributorCount: item.contributorCount)
        let target = item.targetCents ?? 0
        let shortfall = item.isGroupFunded ? max(target - summary.fundedCents, 0) : 0
        let isUnderTarget = item.isGroupFunded && item.targetCents != nil && shortfall > 0
        return VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    itemThumbnail(item)

                    VStack(alignment: .leading, spacing: 5) {
                        Text(item.title)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)

                        if let price = item.priceCents {
                            Text(formatMoney(cents: price))
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(WishTheme.headerBlue)
                        }

                        if let liveAvailability {
                            Text(liveAvailability == "reserved" ? "Reserved" : "Available")
                                .font(.system(size: 11, weight: .semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(liveAvailability == "reserved" ? Color.orange.opacity(0.18) : Color.green.opacity(0.2))
                                .foregroundStyle(liveAvailability == "reserved" ? Color.orange : Color.green)
                                .clipShape(Capsule())
                        }
                    }

                    Spacer()
                }

                if let description = item.description, !description.isEmpty {
                    Text(description)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }

                if let url = item.url, !url.isEmpty {
                    Text(url)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if item.isGroupFunded {
                    Text("Group-funded target: \(item.targetCents.map { formatMoney(cents: $0) } ?? "Unset")")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)

                    if summary.contributorCount > 0 {
                        Text("Someone has contributed.")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                Task {
                    await openReview(item)
                }
            }

            if canManageItems {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        Spacer(minLength: 0)

                        Button("Edit") {
                            beginEditing(item)
                            isShowingItemForm = true
                        }
                        .buttonStyle(WishPillButtonStyle(variant: .neutral))

                        if isUnderTarget {
                            Button("Resolve shortfall") {
                                shortfallItem = item
                            }
                            .buttonStyle(WishPillButtonStyle(variant: .neutral))
                        }

                        Spacer(minLength: 0)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Button("Edit") {
                            beginEditing(item)
                            isShowingItemForm = true
                        }
                        .buttonStyle(WishPillButtonStyle(variant: .neutral))

                        if isUnderTarget {
                            Button("Resolve shortfall") {
                                shortfallItem = item
                            }
                            .buttonStyle(WishPillButtonStyle(variant: .neutral))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                }
            }
        }
        .wishCardStyle()
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            if canManageItems {
                Button(role: .destructive) {
                    Task {
                        await triggerArchive(item)
                    }
                } label: {
                    Label("Archive", systemImage: "archivebox.fill")
                }
                .disabled(archivingItemIds.contains(item.id))
            }
        }
    }

    private func triggerArchive(_ item: ItemRecord) async {
        guard canManageItems else { return }
        guard !archivingItemIds.contains(item.id) else { return }

        archivingItemIds.insert(item.id)
        await archiveItem(item)
        _ = await MainActor.run {
            archivingItemIds.remove(item.id)
        }
    }

    @ViewBuilder
    private func itemThumbnail(_ item: ItemRecord) -> some View {
        if let imageURL = preferredItemImageURL(for: item),
           let url = URL(string: imageURL) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .empty:
                    ProgressView()
                        .frame(width: 70, height: 70)
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(width: 70, height: 70)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                case .failure:
                    fallbackThumbnail
                @unknown default:
                    fallbackThumbnail
                }
            }
        } else {
            fallbackThumbnail
        }
    }

    private var fallbackThumbnail: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(Color.white)
            .frame(width: 70, height: 70)
            .overlay(
                Text("No image")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color(red: 0.84, green: 0.85, blue: 0.87), lineWidth: 1)
            )
    }

    private func loadEditorData() async {
        guard let headers = auth.ownerHeaders else {
            canManageItems = false
            loadError = "Sign in is required to manage items."
            items = []
            hasLoadedInitialEditorData = true
            return
        }

        canManageItems = false
        loadError = nil
        formError = nil

        do {
            let itemResponse: ItemsListResponse = try await APIClient.shared.request(
                path: "/api/items?wishlistId=\(wishlistId)",
                method: "GET",
                headers: headers
            )

            items = itemResponse.items
            canManageItems = true
            contributionsByItemId = Dictionary(uniqueKeysWithValues: itemResponse.items.map { item in
                (
                    item.id,
                    ContributionSummary(
                        fundedCents: item.fundedCents,
                        contributorCount: item.contributorCount
                    )
                )
            })

            do {
                let wishlistResponse: WishlistListResponse = try await APIClient.shared.request(
                    path: "/api/wishlists",
                    method: "GET",
                    headers: headers
                )
                if let foundWishlist = wishlistResponse.wishlists.first(where: { $0.id == wishlistId }) {
                    wishlistPreview = foundWishlist
                    shareUrlPreview = foundWishlist.shareUrlPreview
                } else {
                    shareUrlPreview = nil
                    wishlistPreview = nil
                }
            } catch {
                shareUrlPreview = nil
                wishlistPreview = nil
            }

            await hydrateImagePreviews(items: itemResponse.items)
        } catch is CancellationError {
            return
        } catch {
            canManageItems = false
            loadError = error.localizedDescription
            items = []
        }

        hasLoadedInitialEditorData = true
    }

    private func saveEditorWishlistDetails(_ updated: WishlistUpdatePayloadWithID) async {
        guard var headers = auth.ownerHeaders else {
            formError = "Sign in is required to edit wishlist."
            return
        }
        headers["content-type"] = "application/json"

        let trimmedTitle = updated.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            formError = "Wishlist title is required."
            return
        }

        do {
            let response: WishlistUpdateResponse = try await APIClient.shared.request(
                path: "/api/wishlists/\(updated.id)",
                method: "PATCH",
                headers: headers,
                body: WishlistUpdatePayload(
                    title: trimmedTitle,
                    occasionDate: updated.occasionDate,
                    occasionNote: updated.occasionNote
                )
            )

            wishlistPreview = response.wishlist
            shareUrlPreview = response.wishlist.shareUrlPreview
            editingWishlistDetails = nil
            formError = nil
            formSuccess = "Wishlist details updated."
        } catch {
            formError = error.localizedDescription
        }
    }

    private func pollRealtimeAvailability() async {
        guard let token = extractShareToken(from: shareUrlPreview) else {
            availabilityByItemId = [:]
            hasPrimedAvailabilitySnapshot = false
            return
        }

        hasPrimedAvailabilitySnapshot = false

        while !Task.isCancelled {
            do {
                let response: PublicWishlistResponse = try await APIClient.shared.request(
                    path: "/api/public/\(token)/wishlist",
                    method: "GET"
                )

                let nextAvailabilityByItemId = Dictionary(uniqueKeysWithValues: response.items.map { ($0.id, $0.availability) })
                if ownerReservationAlertsEnabled && hasPrimedAvailabilitySnapshot {
                    let justReserved = response.items.filter { item in
                        item.availability == "reserved" && availabilityByItemId[item.id] != "reserved"
                    }

                    if let firstReserved = justReserved.first {
                        if justReserved.count == 1 {
                            shareToast = ToastState(message: "\"\(firstReserved.title)\" was reserved by a guest.", isError: false)
                        } else {
                            shareToast = ToastState(message: "\"\(firstReserved.title)\" was reserved (+\(justReserved.count - 1) more).", isError: false)
                        }
                    }
                }

                availabilityByItemId = nextAvailabilityByItemId
                contributionsByItemId = Dictionary(uniqueKeysWithValues: response.items.map { item in
                    (
                        item.id,
                        ContributionSummary(
                            fundedCents: item.fundedCents,
                            contributorCount: item.contributorCount
                        )
                    )
                })
                hasPrimedAvailabilitySnapshot = true
            } catch {
                // Silent fallback, next poll attempt keeps data fresh when service recovers.
            }

            try? await Task.sleep(nanoseconds: 5_000_000_000)
        }
    }

    private func hydrateImagePreviews(items: [ItemRecord]) async {
        guard let headers = auth.ownerHeaders else {
            previewImageUrlsByItemId = [:]
            return
        }

        var nextMap: [String: [String]] = [:]

        for item in items {
            let urls = item.normalizedImageURLs
            guard !urls.isEmpty else { continue }

            var resolved: [String] = []

            for (index, rawURL) in urls.enumerated() {
                if rawURL.hasPrefix("storage://") {
                    do {
                        let preview: ImagePreviewResponse = try await APIClient.shared.request(
                            path: "/api/items/\(item.id)/image-upload-url",
                            method: "POST",
                            headers: [
                                "content-type": "application/json",
                                "x-owner-email": headers["x-owner-email"] ?? ""
                            ],
                            body: ImagePreviewRequest(mode: "preview", imageIndex: index)
                        )
                        if let previewUrl = preview.previewUrl {
                            resolved.append(previewUrl)
                        }
                    } catch {
                        continue
                    }
                } else {
                    resolved.append(rawURL)
                }
            }

            if !resolved.isEmpty {
                nextMap[item.id] = resolved
            }
        }

        previewImageUrlsByItemId = nextMap
    }

    private func preferredItemImageURL(for item: ItemRecord) -> String? {
        if let fromPreview = previewImageUrlsByItemId[item.id]?.first {
            return fromPreview
        }

        for value in item.normalizedImageURLs {
            if !value.hasPrefix("storage://") {
                return value
            }
        }

        return nil
    }

    private func beginEditing(_ item: ItemRecord) {
        editingItem = item
        draftText = buildDraftText(from: item)
        productURL = item.url ?? ""
        importedImageURLs = item.normalizedImageURLs
        isGroupFunded = item.isGroupFunded
        targetText = item.targetCents.map { String(format: "%.2f", Double($0) / 100.0) } ?? ""
        pendingImages = []
        formError = nil
        formSuccess = nil
        metadataMessage = nil
        priceReviewNotice = nil
        requiresPriceConfirmation = false
        hasConfirmedLowConfidencePrice = false
    }

    private func resetForm() {
        editingItem = nil
        draftText = ""
        productURL = ""
        importedImageURLs = []
        isGroupFunded = false
        targetText = ""
        pendingImages = []
        metadataMessage = nil
        priceReviewNotice = nil
        requiresPriceConfirmation = false
        hasConfirmedLowConfidencePrice = false
    }

    private func clearLowConfidenceConfirmation() {
        if requiresPriceConfirmation || hasConfirmedLowConfidencePrice {
            requiresPriceConfirmation = false
            hasConfirmedLowConfidencePrice = false
            priceReviewNotice = nil
        }
    }

    private func consumePhotoSelections(_ selections: [PhotosPickerItem]) async {
        guard !selections.isEmpty else { return }

        var nextImages = pendingImages
        let maxImages = 10

        for selection in selections {
            if importedImageURLs.count + nextImages.count >= maxImages {
                break
            }

            do {
                guard let data = try await selection.loadTransferable(type: Data.self) else { continue }
                if data.count > 10 * 1024 * 1024 {
                    formError = "One or more files were skipped (max 10 MB each)."
                    continue
                }

                if let image = UIImage(data: data), let jpegData = image.jpegData(compressionQuality: 0.88) {
                    nextImages.append(PendingImage(data: jpegData, filename: "image-\(UUID().uuidString.prefix(8)).jpg", mimeType: "image/jpeg"))
                } else {
                    nextImages.append(PendingImage(data: data, filename: "image-\(UUID().uuidString.prefix(8)).bin", mimeType: "application/octet-stream"))
                }
            } catch {
                formError = "Failed to load one of the selected images."
            }
        }

        pendingImages = nextImages
        photoSelections = []
    }

    private func fallbackParsedDraft(from draftText: String) -> ParsedDraft {
        let lines = draftText
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let titleCandidate = lines
            .map { $0.replacingOccurrences(of: #"(?i)^title\s*:\s*"#, with: "", options: .regularExpression) }
            .first {
                let lower = $0.lowercased()
                return !lower.hasPrefix("price:")
            }

        let descriptionLines = lines
            .map { $0.replacingOccurrences(of: #"(?i)^description\s*:\s*"#, with: "", options: .regularExpression) }
            .filter {
                let lower = $0.lowercased()
                return !lower.hasPrefix("title:") && !lower.hasPrefix("price:")
            }

        let description = descriptionLines.prefix(5).map { "• \($0)" }.joined(separator: "\n")
        let priceCents = extractPriceCents(from: draftText)

        return ParsedDraft(
            title: conciseTitle(from: titleCandidate),
            description: description.isEmpty ? nil : String(description.prefix(600)),
            priceCents: priceCents
        )
    }

    private func conciseTitle(from raw: String?) -> String? {
        guard let raw else { return nil }
        let normalized = raw
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }
        let words = normalized.split(whereSeparator: \.isWhitespace).prefix(6)
        let title = words.joined(separator: " ")
        guard !title.isEmpty else { return nil }
        return String(title.prefix(120))
    }

    private func extractPriceCents(from text: String) -> Int? {
        let pattern = #"(?:US?\$|\$|€|£|USD|EUR|GBP|CAD|AUD|JPY)\s*([0-9]{1,6}(?:[.,][0-9]{3})*(?:[.,][0-9]{2})?)|([0-9]{1,6}(?:[.,][0-9]{3})*(?:[.,][0-9]{2})?)\s*(?:USD|EUR|GBP|CAD|AUD|JPY|€|£)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range) else {
            return nil
        }

        let firstGroup = Range(match.range(at: 1), in: text).map { String(text[$0]) }
        let secondGroup = Range(match.range(at: 2), in: text).map { String(text[$0]) }
        let raw = (firstGroup ?? secondGroup)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !raw.isEmpty else { return nil }
        return parsePriceTokenToCents(raw)
    }

    private func parsePriceTokenToCents(_ raw: String) -> Int? {
        var compact = raw
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
            .replacingOccurrences(of: "[^0-9.,]", with: "", options: .regularExpression)

        guard !compact.isEmpty else { return nil }

        let lastDot = compact.lastIndex(of: ".")
        let lastComma = compact.lastIndex(of: ",")

        if let dot = lastDot, let comma = lastComma {
            let decimalIndex = max(dot, comma)
            let intPart = compact[..<decimalIndex].replacingOccurrences(of: "[.,]", with: "", options: .regularExpression)
            let fracPart = compact[compact.index(after: decimalIndex)...].replacingOccurrences(of: "[.,]", with: "", options: .regularExpression)
            if !intPart.isEmpty, !fracPart.isEmpty, fracPart.count <= 2 {
                compact = "\(intPart).\(fracPart)"
            } else {
                compact = compact.replacingOccurrences(of: "[.,]", with: "", options: .regularExpression)
            }
        } else if let comma = lastComma {
            let intPart = compact[..<comma].replacingOccurrences(of: "[.,]", with: "", options: .regularExpression)
            let fracPart = compact[compact.index(after: comma)...].replacingOccurrences(of: "[.,]", with: "", options: .regularExpression)
            if !intPart.isEmpty, fracPart.count == 2 {
                compact = "\(intPart).\(fracPart)"
            } else {
                compact = compact.replacingOccurrences(of: ",", with: "")
            }
        } else if let dot = lastDot {
            let intPart = compact[..<dot].replacingOccurrences(of: "[.,]", with: "", options: .regularExpression)
            let fracPart = compact[compact.index(after: dot)...].replacingOccurrences(of: "[.,]", with: "", options: .regularExpression)
            if !intPart.isEmpty, fracPart.count <= 2 {
                compact = "\(intPart).\(fracPart)"
            } else {
                compact = "\(intPart)\(fracPart)"
            }
        }

        guard let amount = Double(compact), amount.isFinite, amount >= 0 else { return nil }
        return Int((amount * 100).rounded())
    }

    private func normalizedPriceConfidence(_ value: Double?) -> Double? {
        guard let value, value.isFinite else { return nil }
        return min(1, max(0, value))
    }

    private func submitItem() async {
        guard let ownerHeaders = auth.ownerHeaders else {
            formError = "Sign in is required to save items."
            return
        }

        let ownerEmail = ownerHeaders["x-owner-email"] ?? ""
        if ownerEmail.isEmpty {
            formError = "Sign in is required to save items."
            return
        }

        let urlTrimmed = productURL.trimmingCharacters(in: .whitespacesAndNewlines)
        var workingDraft = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        var workingImageURLs = importedImageURLs
        var reviewNotice: String?
        var metadataPriceConfidence: Double?

        if workingDraft.isEmpty, urlTrimmed.isEmpty {
            formError = "Enter item details or provide a product URL."
            return
        }

        formError = nil
        formSuccess = nil
        metadataMessage = nil
        priceReviewNotice = nil
        requiresPriceConfirmation = false
        isSubmitting = true

        if !urlTrimmed.isEmpty {
            do {
                let metadataResponse: MetadataResponse = try await APIClient.shared.request(
                    path: "/api/items/metadata",
                    method: "POST",
                    headers: [
                        "content-type": "application/json",
                        "x-owner-email": ownerEmail
                    ],
                    body: MetadataRequest(url: urlTrimmed, specNotes: workingDraft.isEmpty ? nil : workingDraft)
                )

                var imported = metadataResponse.metadata.imageUrls ?? []
                if imported.isEmpty, let single = metadataResponse.metadata.imageUrl {
                    imported = [single]
                }

                if !imported.isEmpty {
                    workingImageURLs = dedupedStrings((workingImageURLs + imported)).prefix(10).map { $0 }
                }

                workingDraft = mergeDraftText(
                    currentDraftText: workingDraft,
                    importedTitle: metadataResponse.metadata.title,
                    importedDescription: metadataResponse.metadata.description,
                    importedPriceCents: metadataResponse.metadata.priceCents
                )

                if let maybeReview = metadataResponse.metadata.priceReviewMessage, !maybeReview.isEmpty {
                    reviewNotice = maybeReview
                } else if metadataResponse.metadata.priceNeedsReview == true || metadataResponse.metadata.priceCents == nil {
                    reviewNotice = "Imported price may be missing or inaccurate. Please verify."
                }
                metadataPriceConfidence = normalizedPriceConfidence(metadataResponse.metadata.priceConfidence)

                metadataMessage = "URL details applied before save."

                if isGroupFunded,
                   parseMoneyToCents(targetText) == nil,
                   let importedPrice = metadataResponse.metadata.priceCents,
                   importedPrice > 0 {
                    targetText = String(format: "%.2f", Double(importedPrice) / 100.0)
                }
            } catch {
                metadataMessage = "\(error.localizedDescription) Saved using typed details only."
            }
        }

        if workingDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            formError = "Could not derive item details. Add text manually or try another URL."
            isSubmitting = false
            return
        }

        var parsedDraft = fallbackParsedDraft(from: workingDraft)
        var parsedPriceNeedsReview = parsedDraft.priceCents == nil
        var parsedPriceReviewMessage: String? = parsedPriceNeedsReview ? "Price was not detected. Please verify before saving." : nil
        var parsedPriceConfidence: Double?

        do {
            let parseResponse: DraftParseResponse = try await APIClient.shared.request(
                path: "/api/items/draft-parse",
                method: "POST",
                headers: [
                    "content-type": "application/json",
                    "x-owner-email": ownerEmail
                ],
                body: DraftParseRequest(draftText: workingDraft)
            )

            parsedDraft = parseResponse.parsed
            parsedPriceNeedsReview = parseResponse.priceNeedsReview
            parsedPriceReviewMessage = parseResponse.priceReviewMessage
            parsedPriceConfidence = normalizedPriceConfidence(parseResponse.priceConfidence)
        } catch {
            if let metadataMessage {
                self.metadataMessage = "\(metadataMessage) AI parser unavailable; used local parsing."
            } else {
                metadataMessage = "AI parser unavailable; used local parsing."
            }
        }

        let parsedTitle = parsedDraft.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if parsedTitle.isEmpty {
            formError = "Could not detect item title. Add a product name in your text."
            isSubmitting = false
            return
        }

        var targetCents = parseMoneyToCents(targetText)
        if isGroupFunded,
           (targetCents == nil || targetCents == 0),
           let parsedPrice = parsedDraft.priceCents,
           parsedPrice > 0 {
            targetCents = parsedPrice
        }

        if isGroupFunded, (targetCents == nil || targetCents == 0) {
            formError = "Target must be greater than 0 for group-funded items."
            isSubmitting = false
            return
        }

        let fallbackConfidence = parsedPriceNeedsReview ? 0.75 : 0.95
        let effectivePriceConfidence = normalizedPriceConfidence(parsedPriceConfidence)
            ?? normalizedPriceConfidence(metadataPriceConfidence)
            ?? fallbackConfidence
        let needsManualPriceConfirmation = parsedDraft.priceCents != nil && effectivePriceConfidence < 0.9

        if needsManualPriceConfirmation {
            let confidencePercent = Int((effectivePriceConfidence * 100).rounded())
            let reviewMessage = reviewNotice
                ?? parsedPriceReviewMessage
                ?? "Price confidence is \(confidencePercent)%. Please confirm before saving."
            priceReviewNotice = reviewMessage
            requiresPriceConfirmation = true

            if !hasConfirmedLowConfidencePrice {
                formError = "Please confirm the imported price before saving."
                isSubmitting = false
                return
            }
        } else {
            requiresPriceConfirmation = false
            hasConfirmedLowConfidencePrice = false
        }

        let payload = ItemPayload(
            wishlistId: editingItem == nil ? wishlistId : nil,
            title: parsedTitle,
            description: parsedDraft.description?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true ? nil : parsedDraft.description,
            url: urlTrimmed.isEmpty ? nil : urlTrimmed,
            priceCents: parsedDraft.priceCents,
            imageUrls: dedupedStrings(workingImageURLs).prefix(10).map { $0 },
            isGroupFunded: isGroupFunded,
            targetCents: isGroupFunded ? targetCents : nil
        )

        let endpoint = editingItem == nil ? "/api/items" : "/api/items/\(editingItem?.id ?? "")"
        let method = editingItem == nil ? "POST" : "PATCH"

        let mutation: ItemMutationResponse

        do {
            mutation = try await APIClient.shared.request(
                path: endpoint,
                method: method,
                headers: [
                    "content-type": "application/json",
                    "x-owner-email": ownerEmail
                ],
                body: payload
            )
        } catch {
            formError = error.localizedDescription
            isSubmitting = false
            return
        }

        var latestItem = mutation.item

        if let existingIndex = items.firstIndex(where: { $0.id == latestItem.id }) {
            items[existingIndex] = latestItem
        } else {
            items.insert(latestItem, at: 0)
        }

        if !pendingImages.isEmpty {
            isUploadingImages = true
            for pending in pendingImages {
                do {
                    let prepare: ImagePrepareResponse = try await APIClient.shared.request(
                        path: "/api/items/\(latestItem.id)/image-upload-url",
                        method: "POST",
                        headers: [
                            "content-type": "application/json",
                            "x-owner-email": ownerEmail
                        ],
                        body: ImagePrepareRequest(
                            mode: "prepare-upload",
                            filename: pending.filename,
                            mimeType: pending.mimeType,
                            sizeBytes: pending.data.count
                        )
                    )

                    let uploaded: ImageUploadResponse = try await APIClient.shared.upload(
                        path: prepare.uploadUrl,
                        headers: [
                            "x-owner-email": ownerEmail
                        ],
                        mimeType: pending.mimeType,
                        data: pending.data
                    )

                    latestItem = uploaded.item
                    if let index = items.firstIndex(where: { $0.id == latestItem.id }) {
                        items[index] = latestItem
                    }
                } catch {
                    formError = "Item saved, but at least one image upload failed. \(error.localizedDescription)"
                    isUploadingImages = false
                    isSubmitting = false
                    return
                }
            }
            isUploadingImages = false
        }

        await hydrateImagePreviews(items: [latestItem])

        formSuccess = mutation.warning == "DUPLICATE_URL" ? "Saved. Duplicate URL detected in this wishlist." : (editingItem == nil ? "Item created." : "Item updated.")

        if parsedPriceNeedsReview {
            priceReviewNotice = parsedPriceReviewMessage ?? "Imported price may be inaccurate. Please verify."
        }

        if let reviewNotice {
            priceReviewNotice = reviewNotice
        }

        isShowingItemForm = false
        resetForm()
        isSubmitting = false
    }

    private func archiveItem(_ item: ItemRecord) async {
        guard let ownerEmail = auth.email else {
            formError = "Sign in is required to archive items."
            return
        }

        do {
            let response: ItemArchiveResponse = try await APIClient.shared.request(
                path: "/api/items/\(item.id)/archive",
                method: "POST",
                headers: ["x-owner-email": ownerEmail]
            )

            if let index = items.firstIndex(where: { $0.id == response.item.id }) {
                items[index] = response.item
            }
            formSuccess = "Item archived."
        } catch {
            formError = error.localizedDescription
        }
    }

    private func restoreItem(_ item: ItemRecord) async {
        guard let ownerEmail = auth.email else {
            formError = "Sign in is required to restore items."
            return
        }

        do {
            let response: ItemArchiveResponse = try await APIClient.shared.request(
                path: "/api/items/\(item.id)/archive",
                method: "DELETE",
                headers: ["x-owner-email": ownerEmail]
            )

            if let index = items.firstIndex(where: { $0.id == response.item.id }) {
                items[index] = response.item
            }

            formSuccess = "Item restored to wishlist."
            primeReviewSheetSizing(for: response.item)
            reviewItem = response.item
        } catch {
            formError = error.localizedDescription
        }
    }

    @MainActor
    private func openReview(_ item: ItemRecord) async {
        reviewImageIndex = 0
        primeReviewSheetSizing(for: item)
        let requestItemId = item.id

        var seeded = seededReviewImageURLs(for: item)
        if seeded.isEmpty {
            await hydrateImagePreviews(items: [item])
            seeded = seededReviewImageURLs(for: item)
        }

        reviewImageURLs = seeded
        reviewItem = item

        let resolved = await resolveOwnerReviewImageURLs(for: item)
        guard reviewItem?.id == requestItemId else { return }

        if !resolved.isEmpty {
            reviewImageURLs = resolved
            previewImageUrlsByItemId[item.id] = resolved
        } else if reviewImageURLs.isEmpty {
            reviewImageURLs = seededReviewImageURLs(for: item)
        }
    }

    @MainActor
    private func primeReviewSheetSizing(for item: ItemRecord) {
        let idiom = UIDevice.current.userInterfaceIdiom
        guard horizontalSizeClass == .regular || idiom == .pad || idiom == .mac else {
            reviewSheetContentHeight = 0
            syncReviewSheetDetentSelection()
            return
        }

        let contributionSummary = contributionsByItemId[item.id] ?? ContributionSummary(
            fundedCents: item.fundedCents,
            contributorCount: item.contributorCount
        )

        let sizingView = ItemReviewSizingContent(item: item, contributionSummary: contributionSummary)
            .environment(\.horizontalSizeClass, .regular)

        let controller = UIHostingController(rootView: sizingView)
        controller.view.backgroundColor = .clear

        let screenWidth = UIScreen.main.bounds.width
        let preferredWidth = min(screenWidth * 0.86, WishTheme.contentMaxWidth)
        let width = max(520, preferredWidth)

        let measuredHeight = controller.sizeThatFits(
            in: CGSize(width: width, height: .greatestFiniteMagnitude)
        ).height

        reviewSheetContentHeight = max(0, ceil(measuredHeight))
        syncReviewSheetDetentSelection()
    }

    private func seededReviewImageURLs(for item: ItemRecord) -> [String] {
        var seen = Set<String>()
        var urls: [String] = []

        if let previewed = previewImageUrlsByItemId[item.id] {
            for raw in previewed {
                let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty && !seen.contains(trimmed) {
                    seen.insert(trimmed)
                    urls.append(trimmed)
                }
            }
        }

        for raw in item.normalizedImageURLs where !raw.hasPrefix("storage://") {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty && !seen.contains(trimmed) {
                seen.insert(trimmed)
                urls.append(trimmed)
            }
        }

        if let preferred = preferredItemImageURL(for: item)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !preferred.isEmpty,
           !seen.contains(preferred) {
            urls.insert(preferred, at: 0)
        }

        return urls
    }

    private func resolveOwnerReviewImageURLs(for item: ItemRecord) async -> [String] {
        let normalized = item.normalizedImageURLs
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !normalized.isEmpty else { return [] }

        guard let ownerEmail = auth.email else {
            return normalized.filter { !$0.hasPrefix("storage://") }
        }

        var resolved: [String] = []
        var seen = Set<String>()

        for (index, imageRef) in normalized.enumerated() {
            if imageRef.hasPrefix("storage://") {
                do {
                    let preview: ImagePreviewResponse = try await APIClient.shared.request(
                        path: "/api/items/\(item.id)/image-upload-url",
                        method: "POST",
                        headers: [
                            "content-type": "application/json",
                            "x-owner-email": ownerEmail
                        ],
                        body: ImagePreviewRequest(mode: "preview", imageIndex: index)
                    )

                    if let previewUrl = preview.previewUrl,
                       !previewUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                       !seen.contains(previewUrl) {
                        seen.insert(previewUrl)
                        resolved.append(previewUrl)
                    }
                } catch {
                    continue
                }
            } else if !seen.contains(imageRef) {
                seen.insert(imageRef)
                resolved.append(imageRef)
            }
        }

        return resolved
    }

    private func resolveShortfall(item: ItemRecord, action: String) async {
        guard let ownerHeaders = auth.ownerHeaders else {
            formError = "Sign in is required to resolve shortfall."
            return
        }

        do {
            let response: ShortfallResponse = try await APIClient.shared.request(
                path: "/api/items/\(item.id)/shortfall",
                method: "POST",
                headers: [
                    "content-type": "application/json",
                    "x-owner-email": ownerHeaders["x-owner-email"] ?? "",
                    "authorization": ownerHeaders["authorization"] ?? ""
                ],
                body: ShortfallRequest(action: action)
            )

            if let index = items.firstIndex(where: { $0.id == response.item.id }) {
                items[index] = response.item
            }

            contributionsByItemId[response.item.id] = ContributionSummary(
                fundedCents: response.item.fundedCents,
                contributorCount: response.item.contributorCount
            )

            switch response.appliedAction {
            case "extend_7d":
                formSuccess = "Deadline extended by 7 days."
            case "lower_target_to_funded":
                formSuccess = "Target updated to current contributed amount."
            default:
                formSuccess = "Item archived."
            }

            shortfallItem = nil
        } catch {
            formError = error.localizedDescription
        }
    }
}

private struct ReviewItemPresentationModifier: ViewModifier {
    @Binding var reviewItem: ItemRecord?
    @Binding var reviewImageURLs: [String]
    @Binding var reviewImageIndex: Int
    @Binding var reviewSheetContentHeight: CGFloat
    let reviewSheetDetents: Set<PresentationDetent>
    @Binding var reviewSheetDetentSelection: PresentationDetent
    let contributionSummaryForItemId: (String) -> ContributionSummary
    let onRestore: (ItemRecord) -> Void

    private func makeSheetContent(for item: ItemRecord) -> some View {
        ItemReviewSheet(
            item: item,
            imageURLs: reviewImageURLs,
            currentIndex: $reviewImageIndex,
            contributionSummary: contributionSummaryForItemId(item.id),
            onClose: {
                reviewItem = nil
                reviewImageURLs = []
                reviewImageIndex = 0
                reviewSheetContentHeight = 0
            },
            onRestore: {
                onRestore(item)
            }
        )
    }

    func body(content: Content) -> some View {
        let idiom = UIDevice.current.userInterfaceIdiom

        if idiom == .pad || idiom == .mac {
            content
                .fullScreenCover(item: $reviewItem) { item in
                    makeSheetContent(for: item)
                }
        } else {
            content
                .sheet(item: $reviewItem) { item in
                    makeSheetContent(for: item)
                        .presentationDetents(reviewSheetDetents, selection: $reviewSheetDetentSelection)
                        .presentationDragIndicator(.visible)
                }
        }
    }
}

private struct ReviewImagePane: View {
    let url: URL

    @State private var phase: Phase = .loading

    private enum Phase {
        case loading
        case loaded(UIImage)
        case failed
    }

    var body: some View {
        ZStack {
            switch phase {
            case .loading:
                ProgressView()
            case .loaded(let uiImage):
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
            case .failed:
                Text("Unable to load image")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .task(id: url.absoluteString) {
            await load()
        }
    }

    private func load() async {
        await MainActor.run {
            phase = .loading
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.cachePolicy = .returnCacheDataElseLoad

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200...299).contains(http.statusCode),
                  let image = UIImage(data: data) else {
                await MainActor.run {
                    phase = .failed
                }
                return
            }

            await MainActor.run {
                phase = .loaded(image)
            }
        } catch {
            await MainActor.run {
                phase = .failed
            }
        }
    }
}

private struct GroupFundingSummaryCard: View {
    let item: ItemRecord
    let contributionSummary: ContributionSummary

    private var targetAmountText: String {
        item.targetCents.map { formatMoney(cents: $0) } ?? "Unset"
    }

    private var contributedAmountText: String {
        formatMoney(cents: contributionSummary.fundedCents)
    }

    private var fundingProgress: Double {
        guard let target = item.targetCents, target > 0 else { return 0 }
        return min(Double(contributionSummary.fundedCents) / Double(target), 1)
    }

    private var fundingStatusText: String {
        guard contributionSummary.contributorCount > 0 else {
            return "No contributions yet."
        }
        return "Someone has contributed."
    }

    private var fundingStatusIcon: String {
        if let target = item.targetCents, target > 0, contributionSummary.fundedCents >= target {
            return "checkmark.seal.fill"
        }
        return contributionSummary.contributorCount > 0 ? "person.2.fill" : "hourglass"
    }

    private var fundingStatusBadgeTitle: String {
        if let target = item.targetCents, target > 0, contributionSummary.fundedCents >= target {
            return "Completed"
        }
        return contributionSummary.contributorCount > 0 ? "Active" : "Waiting"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                Label {
                    Text("Group funding")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(WishTheme.headerBlue)
                } icon: {
                    Image(systemName: fundingStatusIcon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(WishTheme.accentBlue)
                }
                .labelStyle(.titleAndIcon)

                Spacer(minLength: 0)

                Text(fundingStatusBadgeTitle)
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.85))
                    .foregroundStyle(WishTheme.headerBlue)
                    .clipShape(Capsule())
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 14) {
                    fundingMetric(label: "Target", value: targetAmountText)
                    fundingMetric(label: "Contributed", value: contributedAmountText)
                    Spacer(minLength: 0)
                }

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.74))
                        Capsule()
                            .fill(WishTheme.mainGradient)
                            .frame(width: proxy.size.width * fundingProgress)
                    }
                }
                .frame(height: 8)

                Text(fundingStatusText)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(
                    WishTheme.heroGradient.opacity(0.48)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color(red: 0.80, green: 0.88, blue: 0.98), lineWidth: 1.1)
        )
        .shadow(color: WishTheme.accentBlue.opacity(0.10), radius: 8, x: 0, y: 4)
    }

    private func fundingMetric(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(WishTheme.headerBlue)
        }
    }
}

private struct ItemReviewSizingContent: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    let item: ItemRecord
    let contributionSummary: ContributionSummary

    private var usesWideMediaLayout: Bool {
        let idiom = UIDevice.current.userInterfaceIdiom
        return horizontalSizeClass == .regular || idiom == .pad || idiom == .mac
    }

    private var hasProductLink: Bool {
        guard let rawURL = item.url?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return false
        }
        return !rawURL.isEmpty
    }

    private var shouldPrioritizeDetails: Bool {
        if !usesWideMediaLayout {
            return false
        }
        if item.isGroupFunded {
            return true
        }
        if hasProductLink {
            return true
        }
        let descriptionLength = item.description?.trimmingCharacters(in: .whitespacesAndNewlines).count ?? 0
        return descriptionLength >= 140
    }

    private var mediaAspectRatio: CGFloat {
        if usesWideMediaLayout {
            if item.isArchived {
                return 2.6
            }
            if shouldPrioritizeDetails {
                return 2.35
            }
            return 1.65
        }
        return 1.0
    }

    private var mediaMaxHeight: CGFloat? {
        if usesWideMediaLayout {
            if item.isArchived {
                return 216
            }
            return shouldPrioritizeDetails ? 240 : 320
        }
        return nil
    }

    private var mediaSideMax: CGFloat? {
        guard usesWideMediaLayout else { return nil }
        if item.isArchived || item.isGroupFunded || shouldPrioritizeDetails {
            return 420
        }
        return 600
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(red: 0.95, green: 0.96, blue: 0.98))
                .frame(maxWidth: mediaSideMax)
                .aspectRatio(1.0, contentMode: .fit)
                .frame(maxWidth: .infinity, alignment: .center)
                .overlay(
                    Text(" ")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                )

            Text(item.title)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(WishTheme.headerBlue)

            if let price = item.priceCents {
                Text(formatMoney(cents: price))
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(WishTheme.headerBlue)
            }

            if let description = item.description, !description.isEmpty {
                Text(description)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }

            if hasProductLink {
                Button {} label: {
                    Label("Open original product page", systemImage: "arrow.up.right.square")
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .buttonStyle(WishPillButtonStyle(variant: .neutral))
            }

            if item.isGroupFunded {
                GroupFundingSummaryCard(item: item, contributionSummary: contributionSummary)
            }

            if item.isArchived {
                HStack {
                    Spacer(minLength: 0)
                    Button("Put back to wishlist") {}
                        .buttonStyle(WishPillButtonStyle(variant: .main))
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity)
                .padding(.bottom, 10)
            }
        }
        .wishPageLayout()
        .padding(.bottom, 16)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct ItemReviewSheet: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var isPresentingFullscreenGallery = false

    let item: ItemRecord
    let imageURLs: [String]
    @Binding var currentIndex: Int
    let contributionSummary: ContributionSummary
    let onClose: () -> Void
    let onRestore: () -> Void

    private var displayImageURLs: [String] {
        var seen = Set<String>()
        var resolved: [String] = []

        for raw in imageURLs {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty && !seen.contains(trimmed) {
                seen.insert(trimmed)
                resolved.append(trimmed)
            }
        }

        if resolved.isEmpty {
            for raw in item.normalizedImageURLs where !raw.hasPrefix("storage://") {
                let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty && !seen.contains(trimmed) {
                    seen.insert(trimmed)
                    resolved.append(trimmed)
                }
            }
        }

        return resolved
    }

    private var usesWideMediaLayout: Bool {
        let idiom = UIDevice.current.userInterfaceIdiom
        return horizontalSizeClass == .regular || idiom == .pad || idiom == .mac
    }

    private var mediaCornerRadius: CGFloat { 14 }

    private var mediaAspectRatio: CGFloat {
        1.0
    }

    private var mediaMaxHeight: CGFloat? {
        nil
    }

    private var mediaSideMax: CGFloat? {
        guard usesWideMediaLayout else { return nil }
        if item.isArchived || item.isGroupFunded || shouldPrioritizeDetails {
            return 420
        }
        return 600
    }

    private var hasProductLink: Bool {
        guard let rawURL = item.url?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return false
        }
        return !rawURL.isEmpty
    }

    private var shouldPrioritizeDetails: Bool {
        if !usesWideMediaLayout {
            return false
        }
        if item.isGroupFunded {
            return true
        }
        if hasProductLink {
            return true
        }
        let descriptionLength = item.description?.trimmingCharacters(in: .whitespacesAndNewlines).count ?? 0
        return descriptionLength >= 140
    }

    private var mediaSection: some View {
        ZStack {
            RoundedRectangle(cornerRadius: mediaCornerRadius, style: .continuous)
                .fill(displayImageURLs.isEmpty ? Color(red: 0.95, green: 0.96, blue: 0.98) : Color.white)

            if displayImageURLs.isEmpty {
                Text("No image preview available")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            } else {
                TabView(selection: $currentIndex) {
                    ForEach(Array(displayImageURLs.enumerated()), id: \.offset) { index, value in
                        if let url = URL(string: value) {
                            ReviewImagePane(url: url)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .background(Color.white)
                                .clipShape(RoundedRectangle(cornerRadius: mediaCornerRadius, style: .continuous))
                                .contentShape(RoundedRectangle(cornerRadius: mediaCornerRadius, style: .continuous))
                                .onTapGesture {
                                    isPresentingFullscreenGallery = true
                                }
                                .tag(index)
                        } else {
                            RoundedRectangle(cornerRadius: mediaCornerRadius, style: .continuous)
                                .fill(Color(red: 0.95, green: 0.96, blue: 0.98))
                                .overlay(
                                    Text("Unable to load image")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(.secondary)
                                )
                                .tag(index)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .tabViewStyle(.page(indexDisplayMode: .automatic))
            }
        }
    }

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(item.title)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(WishTheme.headerBlue)

            if let price = item.priceCents {
                Text(formatMoney(cents: price))
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(WishTheme.headerBlue)
            }

            if let description = item.description, !description.isEmpty {
                Text(description)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }

            if let rawURL = item.url?.trimmingCharacters(in: .whitespacesAndNewlines),
               !rawURL.isEmpty,
               let productURL = URL(string: rawURL) {
                Link(destination: productURL) {
                    Label("Open original product page", systemImage: "arrow.up.right.square")
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .buttonStyle(WishPillButtonStyle(variant: .neutral))
                .accessibilityHint("Opens the original product webpage in your browser")
            }

            if item.isGroupFunded {
                GroupFundingSummaryCard(item: item, contributionSummary: contributionSummary)
            }

            if item.isArchived {
                HStack {
                    Spacer(minLength: 0)
                    Button("Put back to wishlist") {
                        onRestore()
                    }
                    .buttonStyle(WishPillButtonStyle(variant: .main))
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity)
                .padding(.bottom, 10)
            }
        }
    }

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                let interfaceIsLandscape = UIApplication.shared.connectedScenes
                    .compactMap { $0 as? UIWindowScene }
                    .first { $0.activationState == .foregroundActive }?
                    .interfaceOrientation.isLandscape == true
                let isPhoneLandscape = UIDevice.current.userInterfaceIdiom == .phone && (interfaceIsLandscape || UIDevice.current.orientation.isLandscape)
                let isHorizontalLayout = proxy.size.width > proxy.size.height || verticalSizeClass == .compact || isPhoneLandscape
                let layoutMaxWidth: CGFloat = isHorizontalLayout ? 980 : WishTheme.contentMaxWidth
                let availableWidth = max(0, min(proxy.size.width - WishTheme.pageHorizontalPadding * 2, layoutMaxWidth))
                let mediaSide = max(260, min(availableWidth * 0.46, 520, proxy.size.height * 0.78))

                ScrollView {
                    Group {
                        if isHorizontalLayout {
                            HStack(alignment: .top, spacing: 16) {
                                mediaSection
                                    .frame(width: mediaSide, height: mediaSide)
                                    .clipShape(RoundedRectangle(cornerRadius: mediaCornerRadius, style: .continuous))

                                detailsSection
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        } else {
                            VStack(alignment: .leading, spacing: 12) {
                                mediaSection
                                    .frame(maxWidth: mediaSideMax)
                                    .aspectRatio(mediaAspectRatio, contentMode: .fit)
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .clipShape(RoundedRectangle(cornerRadius: mediaCornerRadius, style: .continuous))

                                detailsSection
                            }
                        }
                    }
                    .frame(maxWidth: layoutMaxWidth, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .top)
                    .padding(.horizontal, WishTheme.pageHorizontalPadding)
                    .padding(.vertical, WishTheme.pageVerticalPadding)
                    .padding(.bottom, 16)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .background(WishTheme.background.ignoresSafeArea())
            .navigationTitle("Item review")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") {
                        onClose()
                    }
                }
            }
            .fullScreenCover(isPresented: $isPresentingFullscreenGallery) {
                FullscreenItemGallery(
                    imageURLs: displayImageURLs,
                    currentIndex: $currentIndex
                )
            }
        }
    }

}

private struct FullscreenItemGallery: View {
    @Environment(\.dismiss) private var dismiss

    let imageURLs: [String]
    @Binding var currentIndex: Int

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            if imageURLs.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "photo")
                        .font(.system(size: 34, weight: .medium))
                        .foregroundStyle(.white.opacity(0.85))
                    Text("No image preview available")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.85))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .onTapGesture {
                    dismiss()
                }
            } else {
                TabView(selection: $currentIndex) {
                    ForEach(Array(imageURLs.enumerated()), id: \.offset) { index, value in
                        if let url = URL(string: value) {
                            ReviewImagePane(url: url)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .background(Color.black)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    dismiss()
                                }
                                .tag(index)
                        } else {
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.white.opacity(0.08))
                                .overlay(
                                    Text("Unable to load image")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundStyle(.white.opacity(0.85))
                                )
                                .padding(20)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    dismiss()
                                }
                                .tag(index)
                        }
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .onAppear {
                    if imageURLs.indices.contains(currentIndex) == false {
                        currentIndex = 0
                    }
                }
            }

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))
                    .padding(14)
            }
            .accessibilityLabel("Close full screen image")
        }
    }
}

private struct ShortfallSheet: View {
    @Environment(\.dismiss) private var dismiss

    let item: ItemRecord
    let onAction: (String) -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                Text(item.title)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(WishTheme.headerBlue)

                Text("Choose how to handle this item when contributions have not reached the target.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)

                Button("Extend deadline +7 days") {
                    onAction("extend_7d")
                    dismiss()
                }
                .buttonStyle(WishPillButtonStyle(variant: .main))

                Button("Set target to contributed") {
                    onAction("lower_target_to_funded")
                    dismiss()
                }
                .buttonStyle(WishPillButtonStyle(variant: .neutral))

                Button("Archive item") {
                    onAction("archive_item")
                    dismiss()
                }
                .buttonStyle(WishPillButtonStyle(variant: .warm))

                Spacer()
            }
            .wishPageLayout()
            .background(WishTheme.background.ignoresSafeArea())
            .navigationTitle("Resolve shortfall")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct SharedLookupView: View {
    @State private var shareInput = ""
    @State private var resolvedToken: String?
    @State private var parseError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Open shared wishlist")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(WishTheme.headerBlue)

                Text("Paste a share URL or token to open the public wishlist view.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 10) {
                    TextField("https://.../l/<token> or token", text: $shareInput)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(Color.white)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color(red: 0.84, green: 0.85, blue: 0.87), lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 8) {
                            Button("Paste") {
                                shareInput = UIPasteboard.general.string ?? ""
                            }
                            .buttonStyle(WishPillButtonStyle(variant: .neutral))

                            Button("Open") {
                                openToken()
                            }
                            .buttonStyle(WishPillButtonStyle(variant: .cool))
                        }

                        VStack(spacing: 8) {
                            Button("Paste") {
                                shareInput = UIPasteboard.general.string ?? ""
                            }
                            .buttonStyle(WishPillButtonStyle(variant: .neutral))

                            Button("Open") {
                                openToken()
                            }
                            .buttonStyle(WishPillButtonStyle(variant: .cool))
                        }
                    }

                    if let parseError {
                        Text(parseError)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.red)
                    }

                    if let token = resolvedToken {
                        NavigationLink {
                            PublicWishlistView(shareToken: token)
                        } label: {
                            Text("Open token: \(token)")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(WishPillButtonStyle(variant: .main))
                    }
                }
                .wishCardStyle()
            }
            .wishPageLayout()
        }
        .navigationTitle("Shared")
        .navigationBarTitleDisplayMode(.inline)
        .background(WishTheme.background.ignoresSafeArea())
    }

    private func openToken() {
        guard let token = AppConfig.shareToken(from: shareInput), !token.isEmpty else {
            parseError = "Enter a valid share URL or token."
            resolvedToken = nil
            return
        }

        parseError = nil
        resolvedToken = token
    }
}

private struct NotificationSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(NotificationPreferenceKeys.ownerReservationAlertsEnabled) private var ownerReservationAlertsEnabled = true
    @AppStorage(NotificationPreferenceKeys.guestArchivedItemAlertsEnabled) private var guestArchivedItemAlertsEnabled = true

    var body: some View {
        List {
            Section("Owner notifications") {
                Toggle("Item reserved by a guest", isOn: $ownerReservationAlertsEnabled)
                Text("When enabled, you are notified when a guest reserves a specific item.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Section("Guest notifications") {
                Toggle("Reserved item archived", isOn: $guestArchivedItemAlertsEnabled)
                Text("When enabled, you are notified to pick another item if your reserved item gets archived.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Notification settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    dismiss()
                }
            }
        }
    }
}

private struct SharedItemViewerSheet: View {
    let itemToken: String
    let onClose: () -> Void

    @State private var isLoading = true
    @State private var pageError: String?
    @State private var model: PublicSharedItemResponse?
    @State private var contributionInput = ""

    var body: some View {
        Group {
            if let model = model {
                PublicItemSheet(
                    item: model.item,
                    currency: model.wishlist.currency,
                    isReservedByMe: false,
                    isSignedIn: false,
                    actionError: nil,
                    actionSuccess: nil,
                    contributionInput: $contributionInput,
                    onClose: onClose,
                    onReserve: {},
                    onUnreserve: {},
                    onContribute: {},
                    allowsReservationActions: false,
                    readOnlyNotice: model.message ?? "This shared item link is view-only. Open the full wishlist to reserve or contribute.",
                    onShareItem: nil
                )
            } else {
                NavigationStack {
                    VStack(spacing: 12) {
                        if isLoading {
                            PlaceholderCard(text: "Loading shared item...")
                        } else if let pageError {
                            VStack(spacing: 10) {
                                Text("Shared item unavailable")
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundStyle(WishTheme.headerBlue)
                                Text(pageError)
                                    .font(.system(size: 13))
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                                    .frame(maxWidth: 320)

                                Button("Retry") {
                                    Task {
                                        await load()
                                    }
                                }
                                .buttonStyle(WishPillButtonStyle(variant: .warm))
                            }
                            .wishCardStyle()
                        }
                    }
                    .wishPageLayout()
                    .background(WishTheme.background.ignoresSafeArea())
                    .navigationTitle("Item")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Close") {
                                onClose()
                            }
                        }
                    }
                }
            }
        }
        .task(id: itemToken) {
            await load()
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let response: PublicSharedItemResponse = try await APIClient.shared.request(
                path: "/api/public/item/\(itemToken)",
                method: "GET"
            )
            model = response
            pageError = nil
        } catch {
            model = nil
            pageError = error.localizedDescription
        }
    }
}

private struct PublicWishlistView: View {
    @EnvironmentObject private var auth: AuthStore
    @AppStorage(NotificationPreferenceKeys.guestArchivedItemAlertsEnabled) private var guestArchivedItemAlertsEnabled = true

    let shareToken: String

    @State private var model: PublicWishlistResponse?
    @State private var isLoading = true
    @State private var pageError: String?

    @State private var search = ""
    @State private var availabilityFilter = "all"
    @State private var fundingFilter = "all"
    @State private var minBudgetInput = ""
    @State private var maxBudgetInput = ""
    @State private var isFilterPanelVisible = false

    @State private var activeItem: PublicItem?
    @State private var contributionInput = ""
    @State private var actionError: String?
    @State private var actionSuccess: String?
    @State private var showingAuthSheet = false

    @State private var myReservedItemIds = Set<String>()
    @State private var archiveAlert: ArchiveAlert?
    @State private var trackedOpenKey: String?
    @State private var showingNotificationSettings = false

    private var minBudgetCents: Int? {
        parseBudgetInput(minBudgetInput)
    }

    private var maxBudgetCents: Int? {
        parseBudgetInput(maxBudgetInput)
    }

    private var availabilityFilterTitle: String {
        switch availabilityFilter {
        case "available":
            return "Available"
        case "reserved":
            return "Reserved"
        default:
            return "All"
        }
    }

    private var fundingFilterTitle: String {
        switch fundingFilter {
        case "group":
            return "Group funded"
        case "single":
            return "Single gift"
        default:
            return "All items"
        }
    }

    private var filteredItems: [PublicItem] {
        guard let model = model else { return [] }
        let needle = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let minBudget = minBudgetCents
        let maxBudget = maxBudgetCents

        var output = model.items.filter { item in
            if !needle.isEmpty && !item.title.lowercased().contains(needle) {
                return false
            }
            if availabilityFilter != "all" && item.availability != availabilityFilter {
                return false
            }
            if fundingFilter == "group" && !item.isGroupFunded {
                return false
            }
            if fundingFilter == "single" && item.isGroupFunded {
                return false
            }
            if !matchesBudget(item: item, minBudgetCents: minBudget, maxBudgetCents: maxBudget) {
                return false
            }
            return true
        }

        if minBudget != nil || maxBudget != nil {
            output.sort { left, right in
                let leftPrice = left.priceCents ?? left.targetCents ?? Int.max
                let rightPrice = right.priceCents ?? right.targetCents ?? Int.max
                if leftPrice == rightPrice {
                    return left.title.localizedCaseInsensitiveCompare(right.title) == .orderedAscending
                }
                return leftPrice < rightPrice
            }
        } else if let archiveAlert = archiveAlert {
            let indexMap = Dictionary(uniqueKeysWithValues: archiveAlert.suggestedItemIds.enumerated().map { ($0.element, $0.offset) })
            output.sort { left, right in
                let l = indexMap[left.id] ?? Int.max
                let r = indexMap[right.id] ?? Int.max
                if l == r { return left.title < right.title }
                return l < r
            }
        }

        return output
    }

    private var reservedStats: (reserved: Int, total: Int) {
        guard let model = model else { return (0, 0) }
        return (
            model.items.filter { $0.availability == "reserved" }.count,
            model.items.count
        )
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                if guestArchivedItemAlertsEnabled, let archiveAlert = archiveAlert {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Reserved item was archived")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color.orange)
                            Text("\"\(archiveAlert.archivedItemTitle)\" \(archiveAlert.archivedItemPriceCents.map { "(\(formatMoney(cents: $0, currency: model?.wishlist.currency ?? "USD")))" } ?? "")")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                            Text("Please choose another available item below.")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("OK") {
                            Task {
                                await dismissArchiveAlert(archiveAlert)
                            }
                        }
                        .buttonStyle(WishPillButtonStyle(variant: .neutral))
                    }
                    .wishCardStyle()
                }

                if isLoading {
                    PlaceholderCard(text: "Loading shared wishlist...")
                    PlaceholderCard(text: "Loading shared wishlist...")
                } else if let pageError {
                    VStack(spacing: 8) {
                        Text("Wishlist unavailable")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(WishTheme.headerBlue)
                        Text(pageError)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)

                        Button("Retry") {
                            Task {
                                await loadModel(showSpinner: true)
                            }
                        }
                        .buttonStyle(WishPillButtonStyle(variant: .warm))
                    }
                    .wishCardStyle()
                } else if let model = model {
                    header(model)
                    if isFilterPanelVisible {
                        filters
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    itemList(model)
                }
            }
            .wishPageLayout()
        }
        .background(WishTheme.background.ignoresSafeArea())
        .navigationTitle("Shared wishlist")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    showingNotificationSettings = true
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(WishTheme.accentBlue)
                }
                .accessibilityLabel("Notification settings")

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isFilterPanelVisible.toggle()
                    }
                } label: {
                    Image(systemName: isFilterPanelVisible ? "xmark.circle.fill" : "magnifyingglass")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(WishTheme.accentBlue)
                }
                .accessibilityLabel(isFilterPanelVisible ? "Hide search and filters" : "Show search and filters")
            }
        }
        .task(id: shareToken) {
            await loadModel(showSpinner: true)

            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                await loadModel(showSpinner: false)
            }
        }
        .task(id: "\(model?.version ?? "")-\(auth.email ?? "")") {
            await refreshActorStateForModel()
        }
        .sheet(item: $activeItem) { item in
            PublicItemSheet(
                item: item,
                currency: model?.wishlist.currency ?? "USD",
                isReservedByMe: myReservedItemIds.contains(item.id),
                isSignedIn: auth.isAuthenticated,
                actionError: actionError,
                actionSuccess: actionSuccess,
                contributionInput: $contributionInput,
                onClose: {
                    activeItem = nil
                    contributionInput = ""
                    actionError = nil
                    actionSuccess = nil
                },
                onReserve: {
                    Task {
                        await reserveAction(item: item, action: "reserve")
                    }
                },
                onUnreserve: {
                    Task {
                        await reserveAction(item: item, action: "unreserve")
                    }
                },
                onContribute: {
                    Task {
                        await contributeAction(item: item)
                    }
                },
                allowsReservationActions: true,
                readOnlyNotice: nil,
                onShareItem: {
                    let response: PublicItemShareLinkResponse = try await APIClient.shared.request(
                        path: "/api/public/\(shareToken)/items/\(item.id)/share-link",
                        method: "GET",
                        headers: auth.actorHeaders ?? [:]
                    )
                    return response.shareUrl
                }
            )
        }
        .sheet(isPresented: $showingAuthSheet) {
            NavigationStack {
                AccountView()
            }
            .environmentObject(auth)
        }
        .sheet(isPresented: $showingNotificationSettings) {
            NavigationStack {
                NotificationSettingsSheet()
            }
        }
        .onChange(of: guestArchivedItemAlertsEnabled) {
            if guestArchivedItemAlertsEnabled {
                Task {
                    await refreshActorStateForModel()
                }
            } else {
                archiveAlert = nil
            }
        }
    }

    private func header(_ model: PublicWishlistResponse) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(model.wishlist.title)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(WishTheme.headerBlue)

            VStack(alignment: .leading, spacing: 8) {
                headerDetailRow(title: "Occasion", value: formatDateLabel(model.wishlist.occasionDate))
                headerDetailRow(title: "Reserved", value: "\(reservedStats.reserved) of \(reservedStats.total)")
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.45))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.white.opacity(0.75), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))

            if let note = model.wishlist.occasionNote, !note.isEmpty {
                Text(note)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !auth.isAuthenticated {
                Text("Sign in or create account to reserve or contribute.")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(WishTheme.heroGradient)
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.white.opacity(0.65), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private var filters: some View {
        VStack(spacing: 8) {
            TextField("Search items", text: $search)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color(red: 0.84, green: 0.85, blue: 0.87), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 12))

            HStack(spacing: 8) {
                TextField("Min budget", text: $minBudgetInput)
                    .keyboardType(.decimalPad)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color(red: 0.84, green: 0.85, blue: 0.87), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                TextField("Max budget", text: $maxBudgetInput)
                    .keyboardType(.decimalPad)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color(red: 0.84, green: 0.85, blue: 0.87), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    availabilityFilterMenu(minWidth: 140)
                    fundingFilterMenu(minWidth: 140)
                    resetFiltersButton
                }

                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        availabilityFilterMenu(minWidth: 0)
                        fundingFilterMenu(minWidth: 0)
                    }

                    HStack {
                        Spacer()
                        resetFiltersButton
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .wishCardStyle()
    }

    private func availabilityFilterMenu(minWidth: CGFloat) -> some View {
        Menu {
            Button("All") { availabilityFilter = "all" }
            Button("Available") { availabilityFilter = "available" }
            Button("Reserved") { availabilityFilter = "reserved" }
        } label: {
            HStack(spacing: 6) {
                Text(availabilityFilterTitle)
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)
                    .allowsTightening(true)
                    .fixedSize(horizontal: true, vertical: false)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 12, weight: .semibold))
            }
            .font(.system(size: 17, weight: .medium))
            .foregroundStyle(WishTheme.accentBlue)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minWidth: minWidth, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.white)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(red: 0.84, green: 0.85, blue: 0.87), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private func fundingFilterMenu(minWidth: CGFloat) -> some View {
        Menu {
            Button("All items") { fundingFilter = "all" }
            Button("Group funded") { fundingFilter = "group" }
            Button("Single gift") { fundingFilter = "single" }
        } label: {
            HStack(spacing: 6) {
                Text(fundingFilterTitle)
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)
                    .allowsTightening(true)
                    .fixedSize(horizontal: true, vertical: false)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 12, weight: .semibold))
            }
            .font(.system(size: 17, weight: .medium))
            .foregroundStyle(WishTheme.accentBlue)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minWidth: minWidth, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.white)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(red: 0.84, green: 0.85, blue: 0.87), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private var resetFiltersButton: some View {
        Button("Reset") {
            search = ""
            availabilityFilter = "all"
            fundingFilter = "all"
            minBudgetInput = ""
            maxBudgetInput = ""
        }
        .buttonStyle(WishPillButtonStyle(variant: .neutral))
    }

    private func parseBudgetInput(_ raw: String) -> Int? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return parseMoneyToCents(trimmed)
    }

    private func matchesBudget(item: PublicItem, minBudgetCents: Int?, maxBudgetCents: Int?) -> Bool {
        guard minBudgetCents != nil || maxBudgetCents != nil else {
            return true
        }

        // Group-funded items stay discoverable even above max budget since guests can contribute smaller amounts.
        if item.isGroupFunded {
            if let minBudgetCents {
                let funded = max(item.fundedCents, 0)
                let target = item.targetCents ?? item.priceCents ?? funded
                let shortfall = max(target - funded, 0)
                return shortfall >= minBudgetCents
            }
            return true
        }

        guard let itemPriceCents = item.priceCents ?? item.targetCents else {
            return true
        }

        if let minBudgetCents, itemPriceCents < minBudgetCents {
            return false
        }

        if let maxBudgetCents, itemPriceCents > maxBudgetCents {
            return false
        }

        return true
    }

    private func contributedByCurrentActor(_ item: PublicItem) -> Bool {
        guard let email = auth.email?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !email.isEmpty else {
            return false
        }

        return item.normalizedContributorBreakdown.contains { entry in
            entry.guestEmail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == email
        }
    }

    private func statusBadge(
        for item: PublicItem,
        reservedByMe: Bool,
        contributedByMe: Bool
    ) -> (title: String, background: Color, foreground: Color) {
        if reservedByMe {
            return ("Reserved by you", Color.blue.opacity(0.2), WishTheme.accentBlue)
        }
        if contributedByMe {
            return ("Contributed by you", Color.blue.opacity(0.2), WishTheme.accentBlue)
        }
        if item.availability == "available" {
            return ("Available", Color.green.opacity(0.2), Color.green)
        }
        return ("Reserved", Color.orange.opacity(0.2), Color.orange)
    }

    private func itemList(_ model: PublicWishlistResponse) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if filteredItems.isEmpty {
                Text("No matching items right now.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .wishCardStyle()
            }

            ForEach(filteredItems) { item in
                let reservedByMe = myReservedItemIds.contains(item.id)
                let contributedByMe = contributedByCurrentActor(item)
                let progressPercent = Int(max(0, min(100, item.progressRatio * 100)))
                let status = statusBadge(
                    for: item,
                    reservedByMe: reservedByMe,
                    contributedByMe: contributedByMe
                )

                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 10) {
                        if let imageUrl = item.imageUrl, let url = URL(string: imageUrl) {
                            AsyncImage(url: url) { phase in
                                switch phase {
                                case .success(let image):
                                    image
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 74, height: 74)
                                        .clipped()
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                default:
                                    fallbackThumbnail
                                }
                            }
                        } else {
                            fallbackThumbnail
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .top, spacing: 8) {
                                Text(item.title)
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(.primary)
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                Text(status.title)
                                    .font(.system(size: 11, weight: .semibold))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 5)
                                    .background(status.background)
                                    .foregroundStyle(status.foreground)
                                    .clipShape(Capsule())
                            }

                            if let description = item.description, !description.isEmpty {
                                Text(description)
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            Text(formatMoney(cents: item.priceCents, currency: model.wishlist.currency))
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(WishTheme.headerBlue)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if item.isGroupFunded {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Funding progress")
                                Spacer()
                                Text("\(formatMoney(cents: item.fundedCents, currency: model.wishlist.currency)) / \(formatMoney(cents: item.targetCents, currency: model.wishlist.currency))")
                            }
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)

                            GeometryReader { proxy in
                                let width = proxy.size.width * CGFloat(progressPercent) / 100.0
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Color.gray.opacity(0.16))
                                    Capsule().fill(WishTheme.mainGradient).frame(width: max(4, width))
                                }
                            }
                            .frame(height: 8)
                        }
                    }

                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 8) {
                            Spacer(minLength: 0)

                            Button(item.availability == "available" ? "Reserve" : (reservedByMe ? "Manage reservation" : "View details")) {
                                activeItem = item
                                actionError = nil
                                actionSuccess = nil
                            }
                            .buttonStyle(WishPillButtonStyle(variant: .neutral))

                            if item.isGroupFunded {
                                Button("Contribute") {
                                    activeItem = item
                                    actionError = nil
                                    actionSuccess = nil
                                }
                                .buttonStyle(WishPillButtonStyle(variant: .main))
                            }

                            Spacer(minLength: 0)
                        }

                        VStack(spacing: 8) {
                            Button(item.availability == "available" ? "Reserve" : (reservedByMe ? "Manage reservation" : "View details")) {
                                activeItem = item
                                actionError = nil
                                actionSuccess = nil
                            }
                            .buttonStyle(WishPillButtonStyle(variant: .neutral))

                            if item.isGroupFunded {
                                Button("Contribute") {
                                    activeItem = item
                                    actionError = nil
                                    actionSuccess = nil
                                }
                                .buttonStyle(WishPillButtonStyle(variant: .main))
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    activeItem = item
                    actionError = nil
                    actionSuccess = nil
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .wishCardStyle()
            }
        }
    }

    private func headerDetailRow(title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            Spacer(minLength: 6)
            Text(value)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(WishTheme.headerBlue)
                .multilineTextAlignment(.trailing)
        }
    }

    private var fallbackThumbnail: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(Color.white)
            .frame(width: 74, height: 74)
            .overlay(
                Text("No image")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color(red: 0.84, green: 0.85, blue: 0.87), lineWidth: 1)
            )
    }

    private func loadModel(showSpinner: Bool) async {
        if showSpinner {
            isLoading = true
        }

        do {
            let response: PublicWishlistResponse = try await APIClient.shared.request(
                path: "/api/public/\(shareToken)/wishlist",
                method: "GET",
                headers: auth.actorHeaders ?? [:]
            )
            model = response
            SharedWishlistTokenCache.save(token: shareToken, forWishlistId: response.wishlist.id)
            pageError = nil
        } catch {
            if model == nil {
                pageError = error.localizedDescription
            }
        }

        if showSpinner {
            isLoading = false
        }
    }

    private func refreshActorStateForModel() async {
        guard let model = model else { return }

        if let email = auth.email {
            let key = "\(model.wishlist.id)-\(email)"
            if trackedOpenKey != key {
                trackedOpenKey = key
                do {
                    try await APIClient.shared.requestIgnoringBody(
                        path: "/api/public/\(shareToken)/opened",
                        method: "POST",
                        headers: ["x-actor-email": email]
                    )
                } catch {
                    // Ignore tracking failures.
                }
            }

            do {
                let reservations: MyReservationsResponse = try await APIClient.shared.request(
                    path: "/api/public/\(shareToken)/my-reservations",
                    method: "GET",
                    headers: ["x-actor-email": email]
                )
                myReservedItemIds = Set(reservations.itemIds)
            } catch {
                myReservedItemIds = []
            }

            if guestArchivedItemAlertsEnabled {
                do {
                    let alertResponse: ArchiveAlertResponse = try await APIClient.shared.request(
                        path: "/api/public/\(shareToken)/archive-alert",
                        method: "GET",
                        headers: ["x-actor-email": email]
                    )
                    archiveAlert = alertResponse.alert
                } catch {
                    archiveAlert = nil
                }
            } else {
                archiveAlert = nil
            }
        } else {
            myReservedItemIds = []
            archiveAlert = nil
        }
    }

    private func reserveAction(item: PublicItem, action: String) async {
        guard let email = auth.email else {
            actionError = nil
            showingAuthSheet = true
            return
        }

        do {
            let response: ReservationResponse = try await APIClient.shared.request(
                path: "/api/public/\(shareToken)/reservations",
                method: "POST",
                headers: [
                    "content-type": "application/json",
                    "x-actor-email": email,
                    "x-idempotency-key": randomIdempotencyKey()
                ],
                body: ReservationRequest(itemId: item.id, action: action)
            )

            updatePublicItem(response.item)

            if action == "reserve" {
                myReservedItemIds.insert(item.id)
                actionSuccess = "Item reserved."
                activeItem = nil
            } else {
                myReservedItemIds.remove(item.id)
                actionSuccess = "Reservation released."
            }

            actionError = nil
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func contributeAction(item: PublicItem) async {
        guard let email = auth.email else {
            actionError = nil
            showingAuthSheet = true
            return
        }

        guard let cents = parseMoneyToCents(contributionInput), cents >= 100 else {
            actionError = "Contribution must be at least 1.00."
            return
        }

        do {
            let response: ContributionResponse = try await APIClient.shared.request(
                path: "/api/public/\(shareToken)/contributions",
                method: "POST",
                headers: [
                    "content-type": "application/json",
                    "x-actor-email": email,
                    "x-idempotency-key": randomIdempotencyKey()
                ],
                body: ContributionRequest(itemId: item.id, amountCents: cents)
            )

            updatePublicItem(response.item)
            actionError = nil
            actionSuccess = "Contribution saved."
            contributionInput = ""
            activeItem = nil
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func dismissArchiveAlert(_ alert: ArchiveAlert) async {
        guard let email = auth.email else {
            archiveAlert = nil
            return
        }

        do {
            try await APIClient.shared.requestIgnoringBody(
                path: "/api/public/\(shareToken)/archive-alert",
                method: "POST",
                headers: [
                    "content-type": "application/json",
                    "x-actor-email": email
                ],
                body: ArchiveAlertDismissRequest(notificationId: alert.id)
            )
        } catch {
            // Ignore dismiss errors and still hide alert locally.
        }

        archiveAlert = nil
    }

    private func updatePublicItem(_ item: PublicItem) {
        guard var model = model else { return }
        model.items = model.items.map { current in
            current.id == item.id ? item : current
        }
        self.model = model
    }
}

private struct PublicItemSheet: View {
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    let item: PublicItem
    let currency: String
    let isReservedByMe: Bool
    let isSignedIn: Bool
    let actionError: String?
    let actionSuccess: String?
    @Binding var contributionInput: String

    let onClose: () -> Void
    let onReserve: () -> Void
    let onUnreserve: () -> Void
    let onContribute: () -> Void
    let allowsReservationActions: Bool
    let readOnlyNotice: String?
    let onShareItem: (() async throws -> String)?
    @State private var selectedPhotoIndex = 0
    @State private var sharePayload: SharePayload?
    @State private var shareError: String?

    private var itemReservedByOther: Bool {
        item.availability == "reserved" && !isReservedByMe
    }

    private var photoURLs: [String] {
        item.normalizedImageURLs
    }

    private var resolvedPhotoURLs: [URL] {
        photoURLs.compactMap { raw in
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            return URL(string: trimmed)
        }
    }

    private var contributorBreakdown: [PublicContributorEntry] {
        item.normalizedContributorBreakdown
    }

    private var reservationStatusTitle: String {
        if item.availability == "available" {
            return "Available"
        }
        return isReservedByMe ? "Reserved by you" : "Reserved by another guest"
    }

    private var reservationStatusHint: String {
        if item.availability == "available" {
            return "Claim this gift to avoid duplicate purchases."
        }
        if isReservedByMe {
            return "You already reserved this gift. You can release it anytime."
        }
        return "This gift has already been claimed by another guest."
    }

    private var resolvedActionError: String? {
        shareError ?? actionError
    }

    private var detailsColumn: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(item.title)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(WishTheme.headerBlue)

            if let description = item.description, !description.isEmpty {
                Text(description)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }

            Text(formatMoney(cents: item.priceCents, currency: currency))
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(WishTheme.headerBlue)

            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(WishTheme.headerBlue)
                    Text("Reservation")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.primary)
                    Spacer()
                    Text(reservationStatusTitle)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(WishTheme.headerBlue)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.white.opacity(0.78))
                        .clipShape(Capsule())
                }

                Text(reservationStatusHint)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color(red: 0.36, green: 0.37, blue: 0.42))

                if allowsReservationActions {
                    if item.availability == "available" {
                        HStack {
                            Spacer()
                            Button("Reserve gift") { onReserve() }
                                .buttonStyle(WishPillButtonStyle(variant: .main))
                            Spacer()
                        }
                        .frame(maxWidth: .infinity)
                    } else if isReservedByMe {
                        HStack {
                            Spacer()
                            Button("Release my reservation") { onUnreserve() }
                                .buttonStyle(WishPillButtonStyle(variant: .neutral))
                            Spacer()
                        }
                        .frame(maxWidth: .infinity)
                    } else if itemReservedByOther {
                        Text("Already reserved by another guest.")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text(readOnlyNotice ?? "This shared item link is view-only. Open the full wishlist to reserve or contribute.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 1.0, green: 0.97, blue: 0.83), Color(red: 0.88, green: 0.95, blue: 1.0)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.white.opacity(0.9), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.07), radius: 10, x: 0, y: 6)

            if item.isGroupFunded {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Contribution")
                        .font(.system(size: 15, weight: .semibold))

                    if !contributorBreakdown.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Who contributed")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(WishTheme.headerBlue)

                            ForEach(contributorBreakdown) { entry in
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    Text(entry.guestEmail)
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    Spacer(minLength: 8)
                                    Text(formatMoney(cents: entry.amountCents, currency: currency))
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(WishTheme.headerBlue)
                                    if entry.contributionCount > 1 {
                                        Text("x\(entry.contributionCount)")
                                            .font(.system(size: 10, weight: .medium))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        .padding(10)
                        .background(Color.white.opacity(0.62))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }

                    if allowsReservationActions {
                        Text("Enter amount in dollars (minimum 1.00).")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)

                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 8) {
                                contributionField
                                Button("Contribute") {
                                    onContribute()
                                }
                                .buttonStyle(WishPillButtonStyle(variant: .main))
                            }

                            VStack(spacing: 8) {
                                contributionField
                                Button("Contribute") {
                                    onContribute()
                                }
                                .buttonStyle(WishPillButtonStyle(variant: .main))
                            }
                        }
                    } else {
                        Text("Contributions are unavailable from this shared item link.")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
                .wishCardStyle()
            }

            if let actionError = resolvedActionError {
                Text(actionError)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.red)
                    .wishCardStyle()
            }

            if let actionSuccess {
                HStack(alignment: .center, spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.green)
                    Text(actionSuccess)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color(red: 0.09, green: 0.44, blue: 0.19))
                        .lineLimit(2)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.green.opacity(0.18))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.green.opacity(0.45), lineWidth: 1)
                )
            }

            if !isSignedIn && allowsReservationActions {
                Text("Sign in or create account to reserve or contribute.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .wishCardStyle()
            }
        }
    }

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                let interfaceIsLandscape = UIApplication.shared.connectedScenes
                    .compactMap { $0 as? UIWindowScene }
                    .first { $0.activationState == .foregroundActive }?
                    .interfaceOrientation.isLandscape == true
                let isPhoneLandscape = UIDevice.current.userInterfaceIdiom == .phone && (interfaceIsLandscape || UIDevice.current.orientation.isLandscape)
                let isHorizontalLayout = proxy.size.width > proxy.size.height || verticalSizeClass == .compact || isPhoneLandscape
                let layoutMaxWidth: CGFloat = isHorizontalLayout ? 980 : WishTheme.contentMaxWidth
                let availableWidth = max(0, min(proxy.size.width - WishTheme.pageHorizontalPadding * 2, layoutMaxWidth))
                let mediaSide = max(240, min(availableWidth * 0.44, 520, proxy.size.height * 0.82))

                if isHorizontalLayout, !resolvedPhotoURLs.isEmpty {
                    HStack(alignment: .top, spacing: 16) {
                        photoGallery
                            .frame(width: mediaSide)

                        ScrollView {
                            detailsColumn
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.bottom, 16)
                        }
                        .frame(maxHeight: .infinity, alignment: .top)
                    }
                    .frame(maxWidth: layoutMaxWidth, alignment: .leading)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(.horizontal, WishTheme.pageHorizontalPadding)
                    .padding(.vertical, WishTheme.pageVerticalPadding)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            if !resolvedPhotoURLs.isEmpty {
                                photoGallery
                            }
                            detailsColumn
                        }
                        .frame(maxWidth: layoutMaxWidth, alignment: .leading)
                        .frame(maxWidth: .infinity, alignment: .top)
                        .padding(.horizontal, WishTheme.pageHorizontalPadding)
                        .padding(.vertical, WishTheme.pageVerticalPadding)
                        .padding(.bottom, 16)
                    }
                }
            }
            .background(WishTheme.background.ignoresSafeArea())
            .navigationTitle("Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button("Close") { onClose() }
                }
            }
            .sheet(item: $sharePayload) { payload in
                ActivityShareSheet(activityItems: [payload.text])
            }
            .onAppear {
                selectedPhotoIndex = 0
            }
            .onChange(of: item.id) { _, _ in
                selectedPhotoIndex = 0
                shareError = nil
            }
            .onChange(of: resolvedPhotoURLs.count) { _, newCount in
                if newCount == 0 {
                    selectedPhotoIndex = 0
                } else if selectedPhotoIndex >= newCount {
                    selectedPhotoIndex = max(0, newCount - 1)
                }
            }
        }
    }

    private var contributionField: some View {
        TextField("10.00", text: $contributionInput)
            .keyboardType(.decimalPad)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.white)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(red: 0.84, green: 0.85, blue: 0.87), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var photoGallery: some View {
        VStack(alignment: .leading, spacing: 6) {
            TabView(selection: $selectedPhotoIndex) {
                ForEach(Array(resolvedPhotoURLs.enumerated()), id: \.offset) { index, url in
                    ZStack {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFit()
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                            default:
                                ProgressView()
                            }
                        }
                    }
                    .tag(index)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(1, contentMode: .fit)
            .tabViewStyle(.page(indexDisplayMode: .automatic))

            if resolvedPhotoURLs.count > 1 {
                Text("Photo \(selectedPhotoIndex + 1) of \(resolvedPhotoURLs.count)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func shareCurrentItem() {
        guard let onShareItem else { return }

        Task {
            do {
                let shareText = try await onShareItem()
                await MainActor.run {
                    shareError = nil
                    sharePayload = SharePayload(text: shareText)
                }
            } catch {
                await MainActor.run {
                    shareError = error.localizedDescription
                }
            }
        }
    }
}

private struct ActivityView: View {
    @EnvironmentObject private var auth: AuthStore

    private struct WishlistRoute: Identifiable, Hashable {
        let id: String
        let title: String
    }

    private struct SharedWishlistRoute: Identifiable, Hashable {
        let token: String
        var id: String { token }
    }

    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var rows: [ActivityEntry] = []
    @State private var search = ""
    @State private var selectedWishlist: WishlistRoute?
    @State private var selectedSharedWishlist: SharedWishlistRoute?
    @State private var deletingWishlistIds = Set<String>()

    private var filteredRows: [ActivityEntry] {
        let needle = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let searchedRows = rows.filter { row in
            guard !needle.isEmpty else { return true }
            return row.wishlistTitle.lowercased().contains(needle)
                || (row.itemTitle ?? "").lowercased().contains(needle)
                || row.action.lowercased().contains(needle)
        }

        let wishlistIdsWithActionRows = Set(
            searchedRows
                .filter { $0.action != "opened_wishlist" }
                .map { $0.wishlistId }
        )

        return searchedRows.filter { row in
            guard row.action == "opened_wishlist" else { return true }
            if row.wishlistUnavailable == true {
                // Keep unavailable visit rows so swipe-to-delete remains discoverable.
                return true
            }
            return !wishlistIdsWithActionRows.contains(row.wishlistId)
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                if !auth.isAuthenticated {
                    Text("Sign in to view your activity.")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.secondary)
                        .wishCardStyle()
                } else {
                    controls
                    content
                }
            }
            .wishPageLayout()
        }
        .background(WishTheme.background.ignoresSafeArea())
        .navigationTitle("My activity")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: auth.email ?? "") {
            await loadActivity()
        }
        .navigationDestination(item: $selectedWishlist) { wishlist in
            WishlistEditorView(wishlistId: wishlist.id, wishlistTitle: wishlist.title)
                .environmentObject(auth)
        }
        .navigationDestination(item: $selectedSharedWishlist) { route in
            PublicWishlistView(shareToken: route.token)
                .environmentObject(auth)
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Search by wishlist, item, or action", text: $search)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color(red: 0.84, green: 0.85, blue: 0.87), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .wishCardStyle()
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            PlaceholderCard(text: "Loading activity...")
            PlaceholderCard(text: "Loading activity...")
        } else if let errorMessage {
            VStack(alignment: .leading, spacing: 8) {
                Text(errorMessage)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.red)

                Button("Retry") {
                    Task {
                        await loadActivity()
                    }
                }
                .buttonStyle(WishPillButtonStyle(variant: .warm))
            }
            .wishCardStyle()
        } else if filteredRows.isEmpty {
            Text("No activity yet.")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .wishCardStyle()
        } else {
            ForEach(filteredRows) { row in
                let isUnavailableWishlist = row.wishlistUnavailable == true
                let canDeleteWishlist = isUnavailableWishlist && row.action == "opened_wishlist"

                Button {
                    if isUnavailableWishlist {
                        return
                    }

                    if let shareToken = extractShareToken(from: row.openItemPath), !shareToken.isEmpty {
                        selectedSharedWishlist = SharedWishlistRoute(token: shareToken)
                        return
                    }

                    if let cachedToken = SharedWishlistTokenCache.token(forWishlistId: row.wishlistId), !cachedToken.isEmpty {
                        selectedSharedWishlist = SharedWishlistRoute(token: cachedToken)
                        return
                    }

                    selectedWishlist = WishlistRoute(
                        id: row.wishlistId,
                        title: row.wishlistTitle
                    )
                } label: {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(row.wishlistTitle)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.primary)

                            if let itemTitle = row.itemTitle, !itemTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Text(itemTitle)
                                    .font(.system(size: 13))
                                    .foregroundStyle(.secondary)
                            }

                            let activityText = activityLabel(for: row)
                            if !activityText.isEmpty {
                                Text(activityText)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Text(formatEventDate(row.happenedAt))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(WishTheme.headerBlue)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.white.opacity(0.72))
                            .clipShape(Capsule())
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(deletingWishlistIds.contains(row.wishlistId))
                .wishCardStyle()
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    if canDeleteWishlist {
                        Button(role: .destructive) {
                            Task {
                                await deleteUnavailableWishlist(wishlistId: row.wishlistId)
                            }
                        } label: {
                            Label("Delete list", systemImage: "trash")
                        }
                    }
                }
            }
        }
    }

    private func loadActivity() async {
        guard let email = auth.email else {
            rows = []
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            let response: ActivityResponse = try await APIClient.shared.request(
                path: "/api/me/activity",
                method: "GET",
                headers: ["x-actor-email": email]
            )

            rows = response.activities
        } catch {
            errorMessage = error.localizedDescription
            rows = []
        }

        isLoading = false
    }

    private func deleteUnavailableWishlist(wishlistId: String) async {
        guard let email = auth.email else {
            return
        }
        if deletingWishlistIds.contains(wishlistId) {
            return
        }

        deletingWishlistIds.insert(wishlistId)
        defer {
            deletingWishlistIds.remove(wishlistId)
        }

        do {
            let _: ActivityDeleteWishlistResponse = try await APIClient.shared.request(
                path: "/api/me/activity",
                method: "DELETE",
                headers: [
                    "x-actor-email": email,
                    "content-type": "application/json"
                ],
                body: ActivityDeleteWishlistRequest(wishlistId: wishlistId)
            )

            await loadActivity()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func activityLabel(for row: ActivityEntry) -> String {
        var parts: [String] = []

        switch row.action {
        case "opened_wishlist":
            break
        case "contributed":
            parts.append("Contributed")
        case "reserved":
            parts.append("Reserved")
        default:
            parts.append("Released reservation")
        }

        if let amountCents = row.amountCents {
            parts.append(formatMoney(cents: amountCents))
        }

        if let status = row.status {
            parts.append(status)
        }

        return parts.joined(separator: " • ")
    }
}

private struct AccountView: View {
    @EnvironmentObject private var auth: AuthStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    private enum AuthFocusField {
        case email
        case password
    }

    @State private var mode: AuthMode = .signIn
    @State private var email = ""
    @State private var password = ""
    @FocusState private var authFocusField: AuthFocusField?

    @State private var toast: ToastState?

    @State private var showingResetSheet = false
    @State private var resetEmail = ""
    @State private var resetMessage: String?

    var body: some View {
        let isPhoneLandscape = UIDevice.current.userInterfaceIdiom == .phone && verticalSizeClass == .compact
        let formMaxWidth: CGFloat = isPhoneLandscape ? 420 : WishTheme.contentMaxWidth

        ScrollView {
            VStack(spacing: 14) {
                authForm
            }
            .wishPageLayout(maxWidth: formMaxWidth)
        }
        .navigationTitle(mode == .signIn ? "Sign in" : "Create account")
        .navigationBarTitleDisplayMode(.inline)
        .background(WishTheme.background.ignoresSafeArea())
        .environment(\.colorScheme, .light)
        .preferredColorScheme(.light)
        .sheet(isPresented: $showingResetSheet) {
            NavigationStack {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Reset password")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(WishTheme.headerBlue)

                    TextField(
                        "",
                        text: $resetEmail,
                        prompt: Text("Email")
                            .foregroundStyle(Color(red: 0.67, green: 0.69, blue: 0.74))
                    )
                        .foregroundStyle(Color(red: 0.15, green: 0.17, blue: 0.21))
                        .tint(WishTheme.accentBlue)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(Color.white)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color(red: 0.84, green: 0.85, blue: 0.87), lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                    if let resetMessage {
                        Text(resetMessage)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                    }

                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 8) {
                            Button("Cancel") {
                                showingResetSheet = false
                                resetMessage = nil
                            }
                            .buttonStyle(WishPillButtonStyle(variant: .neutral))

                            Button("Send reset email") {
                                Task {
                                    await requestReset()
                                }
                            }
                            .buttonStyle(WishPillButtonStyle(variant: .main))
                        }

                        VStack(spacing: 8) {
                            Button("Cancel") {
                                showingResetSheet = false
                                resetMessage = nil
                            }
                            .buttonStyle(WishPillButtonStyle(variant: .neutral))

                            Button("Send reset email") {
                                Task {
                                    await requestReset()
                                }
                            }
                            .buttonStyle(WishPillButtonStyle(variant: .main))
                        }
                    }

                    Spacer()
                }
                .wishPageLayout()
                .background(WishTheme.background.ignoresSafeArea())
            }
        }
        .overlay(alignment: .top) {
            if let toast {
                ToastBanner(message: toast.message, isError: toast.isError)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
            }
        }
        .onChange(of: toast?.id) {
            guard toast != nil else { return }
            Task {
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                if !Task.isCancelled {
                    withAnimation {
                        toast = nil
                    }
                }
            }
        }
        .onAppear {
            if auth.isAuthenticated {
                dismiss()
            }
        }
        .onChange(of: auth.isAuthenticated) {
            if auth.isAuthenticated {
                dismiss()
            }
        }
    }

    private var authForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(mode == .signIn ? "Sign in" : "Create account")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(WishTheme.headerBlue)

            Picker("Auth mode", selection: $mode) {
                ForEach(AuthMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .tint(WishTheme.accentBlue)

            TextField(
                "",
                text: $email,
                prompt: Text("Email")
                    .foregroundStyle(Color(red: 0.67, green: 0.69, blue: 0.74))
            )
                .foregroundStyle(Color(red: 0.15, green: 0.17, blue: 0.21))
                .tint(WishTheme.accentBlue)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.next)
                .focused($authFocusField, equals: .email)
                .onSubmit {
                    authFocusField = .password
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color(red: 0.84, green: 0.85, blue: 0.87), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 12))

            SecureField(
                "",
                text: $password,
                prompt: Text("Password")
                    .foregroundStyle(Color(red: 0.67, green: 0.69, blue: 0.74))
            )
                .foregroundStyle(Color(red: 0.15, green: 0.17, blue: 0.21))
                .tint(WishTheme.accentBlue)
                .submitLabel(mode == .signIn ? .go : .done)
                .focused($authFocusField, equals: .password)
                .onSubmit {
                    guard mode == .signIn, !auth.isBusy else { return }
                    Task {
                        await submitAuth()
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color(red: 0.84, green: 0.85, blue: 0.87), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 12))

            if mode == .signIn {
                HStack(spacing: 8) {
                    Button(auth.isBusy ? "Signing in..." : mode.rawValue) {
                        Task {
                            await submitAuth()
                        }
                    }
                    .buttonStyle(WishPillButtonStyle(variant: .cool))
                    .disabled(auth.isBusy)

                    Spacer(minLength: 0)

                    Button("Forgot password?") {
                        resetEmail = email
                        resetMessage = nil
                        showingResetSheet = true
                    }
                    .buttonStyle(WishPillButtonStyle(variant: .neutral))
                }
            } else {
                Button(auth.isBusy ? "Creating account..." : mode.rawValue) {
                    Task {
                        await submitAuth()
                    }
                }
                .buttonStyle(WishPillButtonStyle(variant: .cool))
                .disabled(auth.isBusy)
            }
        }
        .wishCardStyle()
    }

    private func submitAuth() async {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedEmail.isEmpty || password.isEmpty {
            toast = ToastState(message: "Email and password are required.", isError: true)
            return
        }

        do {
            if mode == .signIn {
                try await auth.signIn(email: trimmedEmail, password: password)
                dismiss()
            } else {
                let message = try await auth.signUp(email: trimmedEmail, password: password)
                toast = ToastState(message: message, isError: false)
            }
        } catch {
            toast = ToastState(message: error.localizedDescription, isError: true)
        }
    }

    private func requestReset() async {
        let trimmedEmail = resetEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedEmail.isEmpty {
            resetMessage = "Enter your email first."
            return
        }

        do {
            let message = try await auth.requestPasswordReset(email: trimmedEmail)
            resetMessage = message
        } catch {
            resetMessage = error.localizedDescription
        }
    }
}

private struct ToastBanner: View {
    let message: String
    let isError: Bool

    private var foregroundColor: Color {
        if isError {
            return Color(red: 0.72, green: 0.11, blue: 0.16)
        }
        return Color(red: 0.07, green: 0.43, blue: 0.15)
    }

    private var backgroundColor: Color {
        if isError {
            return Color(red: 1.0, green: 0.9, blue: 0.9)
        }
        return Color(red: 0.89, green: 0.98, blue: 0.9)
    }

    private var borderColor: Color {
        if isError {
            return Color(red: 0.92, green: 0.52, blue: 0.55)
        }
        return Color(red: 0.44, green: 0.78, blue: 0.5)
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(foregroundColor)
            Text(message)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(foregroundColor)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
        }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity)
            .background(backgroundColor)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(borderColor, lineWidth: 1.2)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: Color.black.opacity(0.12), radius: 8, x: 0, y: 4)
    }
}

private struct PlaceholderCard: View {
    let text: String

    var body: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(Color.white)
            .frame(height: 96)
            .overlay(
                Text(text)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color(red: 0.88, green: 0.89, blue: 0.91), lineWidth: 1)
            )
    }
}

private struct ActivityShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    ContentView()
        .environmentObject(AuthStore())
}
