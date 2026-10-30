import DesignSystem
import Models
import SwiftUI

/// Report a problem's words (Release, guideline 1.2).
nonisolated enum AIReportText {
    static var reportAProblem: String {
        String(
            localized: "Report a problem", bundle: .module, comment: "Link under an AI result: opens the report sheet")
    }

    static var reportHint: String {
        String(
            localized: "Tells us privately that this result is wrong or offensive.", bundle: .module,
            comment: "VoiceOver hint on Report a problem")
    }

    static var title: String {
        String(localized: "Report a problem", bundle: .module, comment: "Report sheet title")
    }

    static var intro: String {
        String(
            localized: "Tell us what’s wrong with this result. It comes to us privately, and we read every report.",
            bundle: .module, comment: "Report sheet: first line")
    }

    static var aboutHeader: String {
        String(localized: "What’s it about?", bundle: .module, comment: "Report sheet: above the subject choice")
    }

    static func subject(_ subject: AIReportSubject) -> String {
        switch subject {
        case .look: String(localized: "The outfit", bundle: .module, comment: "Report sheet: subject")
        case .why: String(localized: "The reason under it", bundle: .module, comment: "Report sheet: subject")
        case .askAnswer: String(localized: "The stylist’s answer", bundle: .module, comment: "Report sheet: subject")
        case .tryOnPicture: String(localized: "The picture", bundle: .module, comment: "Report sheet: subject")
        }
    }

    static var reasonHeader: String {
        String(localized: "What’s wrong?", bundle: .module, comment: "Report sheet: above the reasons")
    }

    static func reason(_ reason: AIReportReason) -> String {
        switch reason {
        case .wrongOrOffensive:
            String(localized: "It’s wrong or offensive", bundle: .module, comment: "Report sheet: reason")
        case .notMyClothes:
            String(localized: "These aren’t my clothes", bundle: .module, comment: "Report sheet: reason")
        case .looksWrongOnMe:
            String(localized: "It looks wrong on me", bundle: .module, comment: "Report sheet: reason")
        case .other:
            String(localized: "Something else", bundle: .module, comment: "Report sheet: reason")
        }
    }

    static var needsReason: String {
        String(localized: "Choose what’s wrong first.", bundle: .module, comment: "Report sheet: Send without a reason")
    }

    static var noteLabel: String {
        String(localized: "Anything to add?", bundle: .module, comment: "Report sheet: note field label")
    }

    static var notePrompt: String {
        String(localized: "A few words, if you like", bundle: .module, comment: "Report sheet: note field placeholder")
    }

    static var pictureRow: String {
        String(localized: "Include the picture", bundle: .module, comment: "Report sheet: switch to send the picture")
    }

    static var pictureOff: String {
        String(
            localized: "Off: the picture stays on this iPhone.", bundle: .module,
            comment: "Report sheet: under Include the picture, off")
    }

    static var pictureOn: String {
        String(
            localized:
                "The picture, without your face, goes to our private support inbox only. Never to the image service.",
            bundle: .module, comment: "Report sheet: under Include the picture, on")
    }

    static func hideRow(_ subject: AIReportSubject) -> String {
        subject == .tryOnPicture
            ? String(
                localized: "Hide this picture", bundle: .module, comment: "Report sheet: switch to hide the picture")
            : String(localized: "Hide these looks", bundle: .module, comment: "Report sheet: switch to hide the result")
    }

    static func hideDetail(_ subject: AIReportSubject) -> String {
        subject == .tryOnPicture
            ? String(
                localized: "It’s removed from your pictures after sending. You can undo that straight away.",
                bundle: .module, comment: "Report sheet: under Hide this picture")
            : String(
                localized: "They leave your history after sending. A look you saved stays saved.", bundle: .module,
                comment: "Report sheet: under Hide these looks")
    }

    static func whatsSent(includesPicture: Bool) -> String {
        includesPicture
            ? String(
                localized:
                    "Sent: your reason, your note, the picture, and which result it was and when. Never your closet or your name.",
                bundle: .module, comment: "Report sheet: what goes, with the picture")
            : String(
                localized:
                    "Sent: your reason, your note, and which result it was and when. No photos, and never your closet or your name.",
                bundle: .module, comment: "Report sheet: what goes, without a picture")
    }

    static var send: String {
        String(localized: "Send report", bundle: .module, comment: "Report sheet: send button")
    }

    static var sentTitle: String {
        String(localized: "Thank you. Your report is on its way to us.", bundle: .module, comment: "Report sheet: sent")
    }

    static func reference(_ ref: String) -> String {
        String(
            localized: "Reference \(ref)", bundle: .module,
            comment: "Report sheet: the ticket reference, like NK-7F3A9C21")
    }

    static var done: String {
        String(localized: "Done", bundle: .module, comment: "Report sheet: closes after sending")
    }

    static var hiddenTitle: String {
        String(
            localized: "Those looks are hidden", bundle: .module, comment: "Your looks after hiding a reported result")
    }

    static var hiddenMessage: String {
        String(
            localized: "Thanks for telling us. Try a different outfit for new ideas without those pieces together.",
            bundle: .module, comment: "Your looks after hiding a reported result")
    }

    static func problem(_ problem: FeedbackSendProblem) -> String {
        switch problem {
        case .screenshotRefused:
            String(
                localized: "The picture couldn’t be included. Turn off Include the picture, then send again.",
                bundle: .module, comment: "Report sheet: the picture couldn't be read or was refused")
        case .rateLimited(let seconds):
            String(
                localized: "You’ve sent a lot of reports. Try again in \(CloudLimitText.waitText(seconds)).",
                bundle: .module, comment: "Report sheet: too many reports; the argument is a wait like '5 minutes'")
        default:
            FeedbackText.sendProblem(problem, hasScreenshot: false)
        }
    }
}

/// What opens the report sheet: the result, what she may say it's about, and how to hide it.
struct AIReportRoute: Identifiable {
    let id = UUID()
    let target: AIReportTarget
    var subjects: [AIReportSubject]?
    /// Hides the result once the report is sent, if she chose to. `nil` when it can't be hidden.
    var hide: (@MainActor () -> Void)?
}

extension View {
    /// The report sheet, for a route. Hiding the result waits until the sheet has gone, so the
    /// screen under it can move (Saved Looks goes back after removing a picture).
    func aiReportSheet(_ route: Binding<AIReportRoute?>) -> some View {
        modifier(AIReportSheetModifier(route: route))
    }
}

private struct AIReportSheetModifier: ViewModifier {
    @Binding var route: AIReportRoute?
    @State private var pendingHide: (@MainActor () -> Void)?

    func body(content: Content) -> some View {
        content
            .nookSheet(
                item: $route, title: { _ in AIReportText.title }, detents: [.large],
                onDismiss: {
                    let hide = pendingHide
                    pendingHide = nil
                    hide?()
                },
                content: { current in
                    AIReportSheet(
                        route: current, sent: { hides in pendingHide = hides ? current.hide : nil },
                        close: { route = nil })
                }
            )
    }
}

/// The sheet: its scroll view, the sign-in check, and Done after sending.
struct AIReportSheet: View {
    let route: AIReportRoute
    /// The report went; true when she chose to hide the result, which happens once the sheet has
    /// gone, however it's closed.
    let sent: (Bool) -> Void
    let close: () -> Void

    @State private var model: AIReportModel

    init(route: AIReportRoute, sent: @escaping (Bool) -> Void, close: @escaping () -> Void) {
        self.route = route
        self.sent = sent
        self.close = close
        _model = State(
            initialValue: AIReportModel(target: route.target, subjects: route.subjects, canHide: route.hide != nil))
    }

    var body: some View {
        ScrollView {
            AIReportContent(model: model, done: close)
        }
        .onChange(of: model.phase) { _, phase in
            if case .sent = phase { sent(model.hides && model.canHide) }
        }
        .scrollDismissesKeyboard(.interactively)
        .interactiveDismissDisabled(model.isSending)
        .signInGate()
    }

}

/// The sheet's content, apart from its scroll view, so a still image can draw it.
struct AIReportContent: View {
    @Bindable var model: AIReportModel
    var done: () -> Void = {}

    @Environment(\.services) private var services
    @Environment(\.signIn) private var signIn
    @AccessibilityFocusState private var focus: Field?

    enum Field: Hashable { case note }

    var body: some View {
        VStack(alignment: .leading, spacing: NookSpacing.medium) {
            switch model.phase {
            case .sent(let receipt):
                sent(receipt)
            case .writing, .sending:
                writing
            }
        }
        .padding(NookSpacing.medium)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("report.sheet")
    }

    @ViewBuilder private var writing: some View {
        Text(AIReportText.intro)
            .nookTextStyle(.body)
            .foregroundStyle(.nook.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
        if model.subjects.count > 1 {
            choices(header: AIReportText.aboutHeader, identifier: "report.subject") {
                ForEach(model.subjects, id: \.self) { subject in
                    ChoiceRow(
                        title: AIReportText.subject(subject), isSelected: model.subject == subject,
                        identifier: "report.subject.\(subject.rawValue)"
                    ) { model.subject = subject }
                }
            }
        }
        choices(header: AIReportText.reasonHeader, identifier: "report.reasons") {
            ForEach(model.reasons, id: \.self) { reason in
                ChoiceRow(
                    title: AIReportText.reason(reason), isSelected: model.reason == reason,
                    identifier: "report.reason.\(reason.rawValue)"
                ) { model.reason = reason }
            }
        }
        if model.needsReason, model.reason == nil {
            FieldProblemNote(message: AIReportText.needsReason)
                .accessibilityIdentifier("report.needsReason")
        }
        EditorTextField(
            label: AIReportText.noteLabel, isOptional: true, prompt: AIReportText.notePrompt, text: $model.note,
            isMultiline: true, identifier: "report.note", focus: $focus, focusValue: .note)
        if model.offersPicture || model.canHide {
            SettingsGroup {
                if model.offersPicture {
                    SettingsSwitchRow(
                        title: AIReportText.pictureRow,
                        detail: model.includesPicture ? AIReportText.pictureOn : AIReportText.pictureOff,
                        systemImage: "photo", isOn: model.includesPicture, identifier: "report.includePicture",
                        set: { model.includesPicture = $0 })
                }
                if model.canHide {
                    SettingsSwitchRow(
                        title: AIReportText.hideRow(model.target.subject),
                        detail: AIReportText.hideDetail(model.target.subject), systemImage: "eye.slash",
                        isOn: model.hides, identifier: "report.hide", set: { model.hides = $0 })
                }
            }
        }
        Text(AIReportText.whatsSent(includesPicture: model.includesPicture))
            .nookTextStyle(.note)
            .foregroundStyle(.nook.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("report.whatsSent")
        if let problem = model.problem {
            NookBanner(AIReportText.problem(problem), systemImage: "exclamationmark.circle")
                .accessibilityIdentifier("report.problem")
        }
        NookButton(
            AIReportText.send, systemImage: "paperplane", kind: .primary, isLoading: model.isSending, fillsWidth: true
        ) {
            Task { await model.send(with: services, signIn: signIn) }
        }
        .accessibilityIdentifier("report.send")
    }

    @ViewBuilder private func sent(_ receipt: FeedbackReceipt) -> some View {
        Label(AIReportText.sentTitle, systemImage: "checkmark.circle")
            .nookTextStyle(.body)
            .foregroundStyle(.nook.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("report.sent")
        Text(AIReportText.reference(receipt.reference))
            .nookTextStyle(.note)
            .foregroundStyle(.nook.textSecondary)
            .textSelection(.enabled)
        NookButton(AIReportText.done, kind: .primary, fillsWidth: true, action: done)
            .accessibilityIdentifier("report.done")
    }

    private func choices(header: String, identifier: String, @ViewBuilder rows: () -> some View) -> some View {
        SettingsGroup(header: header, identifier: identifier) {
            rows()
        }
    }
}

/// One choice in a list where only one can be picked: a row with a checkmark. VoiceOver reads it
/// as a button that is selected or not.
private struct ChoiceRow: View {
    let title: String
    let isSelected: Bool
    let identifier: String
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            HStack(spacing: NookSpacing.small) {
                Text(title)
                    .nookTextStyle(.body)
                    .foregroundStyle(.nook.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.nook.accent : Color.nook.textSecondary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, NookSpacing.medium)
            .frame(minHeight: NookSpacing.minimumTapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityIdentifier(identifier)
    }
}
