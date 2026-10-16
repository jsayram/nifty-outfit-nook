import DesignSystem
import Models
import SwiftUI

/// One source in Suitcases' list (`.srow`): a round tick, the suitcase's small drawing, its name
/// and a line ("8 pieces · Used 2 weeks ago"), and a chevron that opens it. The tick part
/// chooses it as Style Me's source; the chevron opens the suitcase. The chosen row sits on a soft
/// tint with a shadow below, and reads "Style Me source · 5 pieces".
///
/// Two VoiceOver buttons: the choice ("Weekend", "8 pieces · Used 2 weeks ago", selected when
/// it's the source) and "Open Weekend".
struct SourceRow: View {
    enum Picture {
        case suitcase(SuitcaseIcon)
        case mainCloset
    }

    let title: String
    let detail: String
    let picture: Picture
    let isChosen: Bool
    /// The words of the choice's hint.
    var chooseHint = String(
        localized: "Makes it the source for Style Me.", bundle: .module, comment: "Hint on a source in Suitcases")
    let identifier: String
    let choose: () -> Void
    /// Opens it. `nil` for no chevron.
    var open: (() -> Void)?

    @ScaledMetric(relativeTo: .body) private var minHeight: CGFloat = 60
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var words: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .nookTextStyle(.headline)
                .foregroundStyle(.nook.textPrimary)
            Text(detail)
                .nookTextStyle(.note)
                .foregroundStyle(isChosen ? Color.nook.accent : Color.nook.textSecondary)
                .fontWeight(isChosen ? .semibold : .regular)
        }
        .multilineTextAlignment(.leading)
        .fixedSize(horizontal: false, vertical: true)
    }

    var body: some View {
        HStack(spacing: 0) {
            Button(action: choose) {
                // At the accessibility sizes the words go under the tick and the drawing, so a
                // name like "Weekend" keeps the full width and never breaks mid-word.
                Group {
                    if dynamicTypeSize.isAccessibilitySize {
                        VStack(alignment: .leading, spacing: NookSpacing.xSmall) {
                            HStack(spacing: NookSpacing.small) {
                                tick
                                art
                            }
                            words
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        HStack(spacing: NookSpacing.small) {
                            tick
                            art
                            words
                            Spacer(minLength: 0)
                        }
                    }
                }
                .padding(.leading, 10)
                .padding(.vertical, 6)
                .frame(minHeight: max(minHeight, NookSpacing.minimumTapTarget))
                .contentShape(Rectangle())
            }
            .buttonStyle(ClosetPressStyle())
            .accessibilityLabel(Text(title))
            .accessibilityValue(Text(detail))
            .accessibilityHint(Text(chooseHint))
            .accessibilityAddTraits(isChosen ? [.isSelected] : [])
            .accessibilityIdentifier("\(identifier).choose")
            if let open {
                Button(action: open) {
                    Image(systemName: "chevron.right")
                        .font(Font.nook.label)
                        .foregroundStyle(.nook.chevron)
                        .frame(width: NookSpacing.minimumTapTarget, height: NookSpacing.minimumTapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(ClosetPressStyle())
                .accessibilityLabel(
                    Text("Open \(title)", bundle: .module, comment: "Button on a suitcase's row: opens it")
                )
                .accessibilityIdentifier("\(identifier).open")
                .padding(.trailing, NookSpacing.xxSmall)
            }
        }
        .background {
            if isChosen {
                NookRadius.shape(NookRadius.group)
                    .fill(Color.nook.tintStrong)
                    .softShadow(.drop, in: NookRadius.shape(NookRadius.group))
            }
        }
    }

    private var tick: some View {
        ZStack {
            Circle()
                .fill(isChosen ? Color.nook.accent : Color.nook.tintStrong)
            if isChosen {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.nook.onAccent)
            } else {
                Circle()
                    .strokeBorder(Color.nook.chevron, lineWidth: 2)
            }
        }
        .frame(width: 24, height: 24)
        .accessibilityHidden(true)
    }

    @ViewBuilder private var art: some View {
        switch picture {
        case .suitcase(let icon):
            SuitcaseArtView(icon: icon, height: 50)
                .frame(width: 34, height: 50)
        case .mainCloset:
            Image(systemName: "hanger")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.nook.accent)
                .frame(width: 34, height: 40)
                .background(Color.nook.accentSoft, in: NookRadius.shape(NookRadius.small))
                .accessibilityHidden(true)
        }
    }
}

/// A suitcase's row, from the model.
struct SuitcaseSourceRow: View {
    let suitcase: Suitcase
    let model: SuitcasesModel
    let choose: (WardrobeSource) -> Void
    let open: (Suitcase) -> Void

    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale

    var body: some View {
        let source = WardrobeSource.suitcase(suitcase.id)
        let isChosen = model.isChosen(source)
        let lastUsed = SuitcasesText.lastUsed(
            suitcase.lastUsedAt, now: model.loadedAt, calendar: calendar, locale: locale)
        SourceRow(
            title: suitcase.name,
            detail: suitcase.isArchived
                ? "\(SuitcasesText.pieces(model.pieceCount(of: suitcase))) · \(SuitcasesText.archived)"
                : SuitcasesText.rowDetail(
                    pieceCount: model.pieceCount(of: suitcase), lastUsed: lastUsed, isChosen: isChosen),
            picture: .suitcase(suitcase.icon),
            isChosen: isChosen,
            // An archived suitcase can't be a source until it's brought back (PRD §7.7), so
            // tapping it opens it, where Bring it back is.
            chooseHint: suitcase.isArchived
                ? String(localized: "Opens the suitcase.", bundle: .module, comment: "Hint on a suitcase name")
                : String(
                    localized: "Makes it the source for Style Me.", bundle: .module,
                    comment: "Hint on a source in Suitcases"),
            identifier: "suitcases.row.\(suitcase.id.rawValue)",
            choose: { suitcase.isArchived ? open(suitcase) : choose(source) },
            open: { open(suitcase) }
        )
    }
}

/// The main closet's row: every piece in her closet.
struct MainClosetSourceRow: View {
    let model: SuitcasesModel
    let choose: (WardrobeSource) -> Void

    var body: some View {
        let isChosen = model.isChosen(.mainCloset)
        let count = SuitcasesText.closetPieces(model.closetCount)
        SourceRow(
            title: SuitcasesText.mainCloset,
            detail: isChosen ? "\(SuitcasesText.styleMeSource) · \(count)" : count,
            picture: .mainCloset,
            isChosen: isChosen,
            identifier: "suitcases.row.mainCloset",
            choose: { choose(.mainCloset) }
        )
    }
}
