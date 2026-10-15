import DesignSystem
import Models
import SwiftUI

/// What Profile's rows do. The screen fills these in; snapshot tests leave them empty.
struct ProfileActions {
    var retry: () -> Void = {}
    var editName: () -> Void = {}
    var open: (ProfileDestination) -> Void = { _ in }
    var openSheet: (ProfileSheet) -> Void = { _ in }
}

/// Profile, top to bottom (`settings.html`, Phase 14a): the wall with her name sign, then three
/// groups of rows on the floor.
///
/// 1. Name on your sign, Fit and measurements, Your try-on photo.
/// 2. Style Me: Preferences, Avoid repeating outfits for, Track laundry.
/// 3. Help and privacy: Accessibility, App tours, Help, Send feedback, Privacy and terms, Delete
///    my data.
///
/// Track laundry and the third group are stand-ins until Phase 14b (and 16a for App tours).
/// Separate from `ProfileScreen` so snapshot tests can draw it from a model.
struct ProfilePage: View {
    let model: ProfileModel
    var actions = ProfileActions()

    @Environment(\.closetIsStillImage) private var isStillImage
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Rows stay a comfortable reading width on a wide screen.
    static let maximumWidth: CGFloat = 640

    var body: some View {
        if isStillImage {
            page
                .background(Color.nook.floor)
        } else {
            ScrollView(.vertical) {
                page
            }
            .background(FloorBackground())
        }
    }

    private var page: some View {
        VStack(spacing: 0) {
            ProfileHeader(signName: model.phase == .loaded ? model.profile.signName : nil, editName: actions.editName)
            content
                // At the accessibility sizes the rows take a little more of the width, so long
                // words like "measurements" fit on a line instead of breaking.
                .padding(
                    .horizontal, dynamicTypeSize.isAccessibilitySize ? NookSpacing.small : NookSpacing.screenMargin
                )
                .padding(.top, NookSpacing.large)
                .padding(.bottom, NookSpacing.xxxLarge)
                .frame(maxWidth: Self.maximumWidth)
                .frame(maxWidth: .infinity)
                .background(Color.nook.floor)
        }
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .loading:
            NookLoadingState(FitText.loading)
                .floorCard()
        case .failed:
            NookErrorState(FitText.failedTitle, message: FitText.failedMessage, retry: actions.retry)
                .floorCard()
        case .loaded:
            VStack(alignment: .leading, spacing: NookSpacing.groupGap) {
                you
                styleMe
                help
            }
        }
    }

    private var you: some View {
        group {
            row(
                ProfileText.nameRow, subtitle: ProfileText.nameRowDetail,
                value: SignName.shown(model.profile.signName), systemImage: "signature", identifier: "profile.name",
                action: actions.editName)
            row(
                ProfileText.fitRow, subtitle: ProfileText.fitRowDetail, systemImage: "ruler",
                identifier: "profile.fit"
            ) {
                actions.open(.fit)
            }
            row(
                ProfileText.photoRow, subtitle: ProfileText.photoRowDetail,
                value: model.hasTryOnPhoto ? ProfileText.photoAdded : ProfileText.photoNotAdded,
                systemImage: "camera", identifier: "profile.tryOnPhoto"
            ) {
                actions.openSheet(.tryOnPhoto)
            }
        }
    }

    private var styleMe: some View {
        group(ProfileText.styleMeSection) {
            row(
                ProfileText.preferencesRow, subtitle: ProfileText.preferencesRowDetail,
                value: model.profile.preferences.pieceMode.title, systemImage: "slider.horizontal.3",
                identifier: "profile.preferences"
            ) {
                actions.openSheet(.preferences)
            }
            row(
                ProfileText.repeatRow, value: model.profile.preferences.repeatWindow.title,
                systemImage: "arrow.trianglehead.2.clockwise", identifier: "profile.repeat"
            ) {
                actions.openSheet(.repeatWindow)
            }
            row(
                ProfileText.laundryRow,
                value: model.profile.preferences.tracksLaundry ? ProfileText.on : ProfileText.off,
                systemImage: "washer", identifier: "profile.laundry"
            ) {
                actions.open(.trackLaundry)
            }
        }
    }

    private var help: some View {
        group(ProfileText.helpSection) {
            ForEach(ProfileDestination.later, id: \.self) { destination in
                row(
                    destination.title, subtitle: destination == .tours ? ProfileText.toursRowDetail : nil,
                    systemImage: destination.systemImage, identifier: "profile.\(destination.identifier)"
                ) {
                    actions.open(destination)
                }
            }
        }
    }

    private func group<Rows: View>(_ header: String? = nil, @ViewBuilder rows: () -> Rows) -> some View {
        VStack(alignment: .leading, spacing: NookSpacing.xxSmall) {
            if let header {
                NookSectionHeader(header)
                    .padding(.horizontal, NookSpacing.small)
                    .padding(.bottom, NookSpacing.xxSmall)
            }
            rows()
        }
        .padding(.vertical, NookSpacing.xSmall)
        .padding(.horizontal, dynamicTypeSize.isAccessibilitySize ? 0 : NookSpacing.xSmall)
        .floorCard()
    }

    private func row(
        _ title: String, subtitle: String? = nil, value: String? = nil, systemImage: String, identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            NookRow(title, subtitle: subtitle, value: value, systemImage: systemImage, accessory: .chevron)
        }
        .buttonStyle(.nookRow)
        .accessibilityIdentifier(identifier)
    }
}
