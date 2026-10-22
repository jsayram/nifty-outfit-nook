import DesignSystem
import Models
import SwiftUI

/// What Profile's rows do. The screen fills these in; snapshot tests leave them empty.
struct ProfileActions {
    var retry: () -> Void = {}
    var editName: () -> Void = {}
    var open: (ProfileDestination) -> Void = { _ in }
    var openSheet: (ProfileSheet) -> Void = { _ in }
    var setTracksLaundry: @MainActor @Sendable (Bool) -> Void = { _ in }
}

/// Profile, top to bottom (`settings.html`, Phase 14a): the wall with her name sign, then three
/// groups of rows on the floor.
///
/// 1. Name on your sign, Styling access (30a), Fit and measurements, Your try-on photo.
/// 2. Style Me: Preferences, Avoid repeating outfits for, and the Track laundry switch (14b).
/// 3. Help and privacy: Accessibility, Help, App tours (16b), Send feedback, Privacy and
///    terms, Delete my data (14b).
///
/// Separate from `ProfileScreen` so snapshot tests can draw it from a model.
struct ProfilePage: View {
    let model: ProfileModel
    /// Backups shows when her closet is in the store (Phase 21b).
    var showsBackups = false
    var actions = ProfileActions()

    @Environment(\.closetIsStillImage) private var isStillImage
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if isStillImage {
            page
                .background(Color.nook.floor)
        } else {
            TourScrollReader {
                ScrollView(.vertical) {
                    page
                }
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
                .readablePane()
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
                action: actions.editName
            )
            .tourAnchor(ProfileTour.Anchor.name, label: ProfileText.nameRow, action: actions.editName)
            // 30a: under the name, as in `settings.html`.
            row(
                StylingAccessText.title, subtitle: StylingAccessText.rowDetail,
                value: StylingAccessText.rowValue(model.subscription, isComplimentary: model.isComplimentary),
                systemImage: "sparkles",
                identifier: "profile.stylingAccess"
            ) {
                actions.open(.stylingAccess)
            }
            row(
                ProfileText.fitRow, subtitle: ProfileText.fitRowDetail, systemImage: "ruler",
                identifier: "profile.fit"
            ) {
                actions.open(.fit)
            }
            .tourAnchor(ProfileTour.Anchor.fit, label: ProfileText.fitRow) { actions.open(.fit) }
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
            SettingsSwitchRow(
                title: ProfileText.laundryRow,
                detail: ProfileText.laundryDetail(
                    isOn: model.profile.preferences.tracksLaundry, kept: model.keptDirtyCount),
                systemImage: "washer", isOn: model.profile.preferences.tracksLaundry,
                identifier: "profile.laundry", set: actions.setTracksLaundry)
        }
    }

    private var help: some View {
        group(ProfileText.helpSection) {
            ForEach(ProfileDestination.helpAndPrivacy(showsBackups: showsBackups), id: \.self) { destination in
                row(
                    destination.title, systemImage: destination.systemImage,
                    identifier: "profile.\(destination.identifier)"
                ) {
                    actions.open(destination)
                }
                // App tours sits under Help, as in `settings.html` (Phase 16b).
                if destination == .help {
                    row(
                        AppToursText.row, subtitle: AppToursText.rowDetail, systemImage: "sparkles",
                        identifier: "profile.appTours"
                    ) {
                        actions.openSheet(.appTours)
                    }
                    .tourAnchor(ProfileTour.Anchor.appTours, label: AppToursText.row) {
                        actions.openSheet(.appTours)
                    }
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
