import SwiftUI

/// Figma "Language (English)" (858:12519).
struct LanguageView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var pending: String?

    var body: some View {
        SubScreen(spacing: 16, top: 52) {
            StackedHeader(title: "Language") { dismiss() }
            GroupedList {
                row("English", selected: true)
                RowDivider()
                row("日本語", selected: false)
                RowDivider()
                row("Français", selected: false)
            }
        }
        .alert("\(pending ?? "") is coming soon", isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("AirBorder is in English for now.")
        }
    }

    private func row(_ name: String, selected: Bool) -> some View {
        Button { if !selected { pending = name } } label: {
            HStack {
                Text(name).outfitText(16, selected ? .semibold : .medium)
                Spacer()
                if selected { Image("icCheckList").resizable().frame(width: 18, height: 18) }
            }
            .padding(.horizontal, 16)
            .frame(height: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Help & information: what the app does and where the trip details come from.
struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        SubScreen(spacing: 20, top: 48) {
            BackButton { dismiss() }
            Text("Help & information").outfitText(28, .bold).accessibilityAddTraits(.isHeader)
            InfoCard {
                Text("Your layover, planned to the minute").outfitText(18, .bold)
                Text("See how long you have, how to reach your gate, and what fits in between.")
                    .outfitText(15, .regular, AB.secondary)
            }
            InfoCard {
                Text("Where the details come from").outfitText(18, .bold)
                Text("The trip in this version is a saved sample journey through Tokyo Haneda. Flight times, gates, venues, queues and previous trips are not live.")
                    .outfitText(15, .regular, AB.secondary)
                Text("Walking times start from your walks on previous trips through Haneda. When you connect Apple Health, its walking speed refines them.")
                    .outfitText(15, .regular, AB.secondary)
            }
            .accessibilityIdentifier("dataSources")
        }
    }
}

/// Figma "Edit profile" (858:8671) with "Change photo" (858:8689).
struct EditProfileView: View {
    @EnvironmentObject private var store: JourneyStore
    @Environment(\.dismiss) private var dismiss
    @State private var first = ""
    @State private var last = ""
    @State private var choosesPhoto = false
    @State private var picker: PhotoSource?

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        BackButton { dismiss() }
                        Text("Your profile").outfitText(18, .semibold)
                    }
                    Button { choosesPhoto = true } label: { ProfileAvatar() }
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .accessibilityLabel("Change photo")
                    field("First name", text: $first, content: .givenName)
                    field("Last name", text: $last, content: .familyName).padding(.top, 8)
                }
                .padding(.horizontal, 18)
                .padding(.top, 2)
            }
            CTAButton(title: "Save changes", height: 52, fullWidth: false) {
                store.firstName = first.trimmingCharacters(in: .whitespacesAndNewlines)
                store.lastName = last.trimmingCharacters(in: .whitespacesAndNewlines)
                dismiss()
            }
            .frame(width: 200)
            .padding(.bottom, 8)
        }
        .background(AB.screen.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            first = store.firstName
            last = store.lastName
        }
        .confirmationDialog("Change photo", isPresented: $choosesPhoto, titleVisibility: .hidden) {
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button("Take photo") { picker = .camera }
            }
            Button("Choose from library") { picker = .library }
            if store.profilePhoto != nil {
                Button("Remove photo", role: .destructive) { store.profilePhoto = nil }
            }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(item: $picker) { source in
            ImagePicker(source: source) { store.profilePhoto = $0 }.ignoresSafeArea()
        }
    }

    private func field(_ label: String, text: Binding<String>, content: UITextContentType) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).outfitText(14, .semibold, AB.muted)
            TextField(label, text: text)
                .font(Outfit.font(16, .regular))
                .foregroundStyle(AB.navy)
                .textContentType(content)
                .padding(.horizontal, 17)
                .frame(height: 54)
                .background(AB.card, in: RoundedRectangle(cornerRadius: 12))
                .accessibilityIdentifier(label == "First name" ? "firstNameField" : "lastNameField")
        }
    }
}

enum PhotoSource: String, Identifiable {
    case camera, library
    var id: String { rawValue }
}

/// System camera or photo library picker for the profile photo.
struct ImagePicker: UIViewControllerRepresentable {
    let source: PhotoSource
    let picked: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let controller = UIImagePickerController()
        controller.sourceType = source == .camera ? .camera : .photoLibrary
        controller.allowsEditing = true
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ImagePicker
        init(_ parent: ImagePicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = (info[.editedImage] ?? info[.originalImage]) as? UIImage { parent.picked(image) }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}

/// Figma "Import your flight" (858:11655): where is your ticket?
struct AddFlightView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openDestination) private var open

    private struct Source: Identifiable {
        var id: String { title }
        let title: String
        let detail: String
        let icon: String?
        let symbol: String?
        let destination: Destination
    }

    private let sources = [
        Source(title: "Camera", detail: "Scan your ticket", icon: nil, symbol: "camera", destination: .cameraPermission),
        Source(title: "PDF", detail: "PDF ticket or itinerary", icon: nil, symbol: "doc.text", destination: .choosePDF),
        Source(title: "Apple Wallet", detail: "Boarding pass", icon: nil, symbol: "wallet.pass", destination: .importWallet),
        Source(title: "Google Wallet", detail: "Boarding pass", icon: nil, symbol: "creditcard", destination: .importWallet),
        Source(title: "Gmail", detail: "Booking email", icon: "logoGmail", symbol: nil, destination: .connectGmail),
        Source(title: "Google Calendar", detail: "Flight event", icon: "logoGoogleCalendar", symbol: nil, destination: .connectCalendar),
    ]

    var body: some View {
        SubScreen(spacing: 20, top: 48) {
            BackButton { dismiss() }
            Text("Add a flight").outfitText(28, .bold).accessibilityAddTraits(.isHeader)
            Text("Where is your ticket?").outfitText(15, .regular, AB.secondary)
            GroupedList(radius: 16, bordered: true) {
                ForEach(sources) { source in
                    row(source.title, source.detail) {
                        if let icon = source.icon {
                            Image(icon).resizable().scaledToFit().frame(width: source.title == "Gmail" ? 20 : 32, height: source.title == "Gmail" ? 16 : 32)
                        } else if let symbol = source.symbol {
                            Image(systemName: symbol).font(.system(size: 18)).foregroundStyle(AB.navy)
                        }
                    } perform: { open(source.destination) }
                    .accessibilityIdentifier("import-\(source.title)")
                    RowDivider()
                }
                row("Add manually", "Enter flight number") {
                    Image("icPlusDark").resizable().frame(width: 18, height: 18)
                } perform: { open(.manualEntry) }
                .accessibilityIdentifier("addManually")
            }
        }
    }

    private func row<Icon: View>(_ title: String, _ detail: String, @ViewBuilder icon: () -> Icon, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            HStack(spacing: 14) {
                icon()
                    .frame(width: 32, height: 32)
                    .background(.white, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color(hex: 0xDEE5EB), lineWidth: 1))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).outfitText(16, .semibold)
                    Text(detail).outfitText(13, .regular, AB.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image("icRowArrow").resizable().frame(width: 16, height: 16)
            }
            .padding(.horizontal, 16)
            .frame(height: 62)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
