import SwiftUI

/// Figma "Profile" (858:10517).
struct ProfileView: View {
    @EnvironmentObject private var store: JourneyStore
    @Environment(\.openDestination) private var open
    @State private var confirmsReset = false
    @State private var sheet: ProfileSheet?

    private enum ProfileSheet: String, Identifiable { case about, privacy; var id: String { rawValue } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 26) {
                    identity
                    VStack(alignment: .leading, spacing: 10) {
                        SectionLabel(text: "Settings")
                        GroupedList(radius: 16, bordered: true) {
                            ProfileRow(icon: "icGlobe", title: "Language", value: "English") { open(.language) }
                            RowDivider()
                            HStack(spacing: 12) {
                                Image("icWheelchair").resizable().frame(width: 22, height: 22)
                                Toggle(isOn: $store.stepFreeRoutes) {
                                    Text("Step-free routes").outfitText(15, .medium)
                                }
                                .tint(AB.primary)
                                .accessibilityIdentifier("stepFreeToggle")
                            }
                            .padding(.horizontal, 16)
                            .frame(height: 52)
                            RowDivider()
                            ProfileRow(icon: "icProfileRow", title: "Connected accounts") { open(.connectedAccounts) }
                                .accessibilityIdentifier("connectedAccountsRow")
                            RowDivider()
                            ProfileRow(icon: "icGateRow", title: "Saved flights") { open(.savedFlights) }
                            RowDivider()
                            ProfileRow(icon: "icClock", title: "Previous trips") { open(.previousTrips) }
                                .accessibilityIdentifier("previousTripsRow")
                            RowDivider()
                            ProfileRow(icon: "icRefresh", title: "Reset preferences", titleColor: AB.resetRed, showsArrow: false) {
                                confirmsReset = true
                            }
                        }
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        SectionLabel(text: "About")
                        GroupedList(radius: 16, bordered: true) {
                            ProfileRow(icon: "icInfo", title: "About AirBorder") { sheet = .about }
                            RowDivider()
                            ProfileRow(icon: "icShield", title: "Privacy") { sheet = .privacy }
                            RowDivider()
                            ProfileRow(icon: "icGuide", title: "Replay tutorial") { open(.tutorial) }
                        }
                    }
                }
                Button { open(.help) } label: {
                    Text("Help & information").outfitText(12, .regular, AB.muted).underline()
                        .frame(minHeight: 40)
                }
                .buttonStyle(.plain)
                .padding(.top, 24)
            }
            .padding(.horizontal, 18)
            .padding(.top, 10)
            .padding(.bottom, tabBarClearance)
        }
        .scrollIndicators(.hidden)
        .background(AB.screen.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: $sheet) { item in
            switch item {
            case .about: Sheets.aboutAirBorder()
            case .privacy: Sheets.privacy()
            }
        }
        .confirmationDialog("Reset preferences?", isPresented: $confirmsReset, titleVisibility: .visible) {
            Button("Reset", role: .destructive) { store.resetPreferences() }
        } message: {
            Text("Your stops, journey steps and route settings go back to how they started.")
        }
    }

    private var identity: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Your profile")
                    .outfitText(30, .bold).tracking(-1).accessibilityAddTraits(.isHeader)
                Button { open(.editProfile) } label: {
                    Text("Edit profile").outfitText(14, .semibold, AB.primary)
                }
                .buttonStyle(.plain)
            }
            Spacer()
            ProfileAvatar()
        }
    }
}

struct ProfileRow: View {
    let icon: String
    let title: String
    var value: String?
    var titleColor: Color = AB.navy
    var showsArrow = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(icon).resizable().frame(width: 22, height: 22)
                Text(title).outfitText(15, .medium, titleColor)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let value { Text(value).outfitText(14, .regular, AB.muted) }
                if showsArrow { Image("icRowArrow").resizable().frame(width: 16, height: 16) }
            }
            .padding(.horizontal, 16)
            .frame(height: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Avatar: the traveller's photo, or the Figma profile icon on the chip circle.
struct ProfileAvatar: View {
    @EnvironmentObject private var store: JourneyStore

    var body: some View {
        Group {
            if let photo = store.profilePhoto {
                Image(uiImage: photo).resizable().scaledToFill().frame(width: 68, height: 68).clipShape(Circle())
            } else {
                Image("avatarProfile").resizable().frame(width: 62.5, height: 62.5).offset(y: 0.5)
                    .frame(width: 50, height: 50)
                    .frame(width: 68, height: 68)
                    .background(AB.chip, in: Circle())
            }
        }
        .accessibilityLabel(store.profilePhoto == nil ? "No profile photo" : "Profile photo")
    }
}
