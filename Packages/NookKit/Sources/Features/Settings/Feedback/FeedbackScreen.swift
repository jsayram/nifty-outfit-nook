import DesignSystem
import Models
import PhotosUI
import SwiftUI
import UIKit

/// Send feedback (RD-10, `feedback.html`): the middle desk drawer, also on Profile and at the end
/// of Help. See `FeedbackModel` for what's sent and how.
struct FeedbackScreen: View {
    /// The note kept at the root, so a half-written one waits for her (`nil` in previews).
    @Environment(\.feedbackDraft) private var shared
    @Environment(\.services) private var services
    @Environment(\.signInAgain) private var signInAgain
    @State private var local = FeedbackModel()
    @Environment(\.dismiss) private var dismiss
    @AccessibilityFocusState private var focus: FeedbackField?
    /// The system photo picker for the screenshot (24d). It needs no permission: the app gets only
    /// the one picture she picks.
    @State private var showsPicker = false
    @State private var pickedItem: PhotosPickerItem?
    @State private var showsSupportPage = false

    private var model: FeedbackModel { shared ?? local }

    var body: some View {
        FeedbackPage(
            model: model,
            focus: $focus,
            send: send,
            chooseScreenshot: { showsPicker = true },
            openSupportPage: { showsSupportPage = true },
            done: {
                model.startOver()
                dismiss()
            },
            writeAnother: { model.startOver() },
            signIn: services.offersSignIn && !services.cloudUnavailable
                ? { Task { if await signInAgain(.support) { await model.checkRoute() } } } : nil
        )
        .navigationTitle(SettingsText.feedbackTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // The title is on the wall, as on Profile.
            ToolbarItem(placement: .principal) {
                Text(verbatim: "").accessibilityHidden(true)
            }
        }
        .sheet(isPresented: sharing) {
            if case .sharing(let text) = model.phase {
                ShareSheet(text: text, subject: FeedbackComposer.subject) { completed in
                    model.shareFinished(completed: completed)
                }
                .presentationDetents([.medium, .large])
                .ignoresSafeArea()
            }
        }
        .photosPicker(isPresented: $showsPicker, selection: $pickedItem, matching: .screenshots)
        .onChange(of: pickedItem) { _, item in
            guard let item else { return }
            pickedItem = nil
            Task {
                // The picture is read here and cleaned in the model; nothing keeps the original.
                if let data = try? await item.loadTransferable(type: Data.self) {
                    await model.attachScreenshot(data)
                } else {
                    await model.attachScreenshot(Data())
                }
            }
        }
        .fullScreenCover(isPresented: $showsSupportPage) {
            SafariView(url: services.supportLinks.supportPage)
                .ignoresSafeArea()
        }
        .task { await model.checkRoute() }
        .onDisappear {
            // Leaving stops a send in progress; the note stays and can be sent again.
            model.cancelSending()
            // A sent note has nothing left to keep; the next visit starts a new one.
            if case .sent = model.phase { model.startOver() }
        }
        // Send feedback's quick tour (Phase 16b), while she's writing, before the keyboard is up.
        .screenTour(FeedbackTour.definition, isReady: model.phase == .writing)
    }

    /// Send: the support queue when she's signed in, the share sheet otherwise. A note that can't
    /// go yet sends her to what needs fixing.
    private func send() {
        switch model.route {
        case .shareSheet:
            if !model.send() { focus = .message }
        case .supportQueue:
            if (try? model.note()) == nil {
                // Shows the problem; nothing is sent.
                model.markTriedToSend()
                focus = model.replyProblem == nil ? .message : .replyAddress
            } else {
                model.beginSubmit()
            }
        }
    }

    private var sharing: Binding<Bool> {
        Binding(
            get: {
                if case .sharing = model.phase { return true }
                return false
            },
            set: { isShown in
                if !isShown { model.shareFinished(completed: false) }
            })
    }
}

/// Where VoiceOver goes when Send finds a problem.
enum FeedbackField: Hashable {
    case message
    case replyAddress
}

/// Send feedback, top to bottom: what it's about, her note, the app details switch, exactly what
/// would be sent, and Send. After sending: thank you, with what went. Separate from
/// `FeedbackScreen` so snapshot tests can draw it.
struct FeedbackPage: View {
    @Bindable var model: FeedbackModel
    let focus: AccessibilityFocusState<FeedbackField?>.Binding
    var send: () -> Void = {}
    /// Opens the photo picker for the screenshot (support queue only).
    var chooseScreenshot: () -> Void = {}
    /// Opens the website's support page. `nil` hides the row (snapshot tests, previews).
    var openSupportPage: (() -> Void)?
    var done: () -> Void = {}
    var writeAnother: () -> Void = {}
    /// Release: signed out on a build with sign-in, Sign in to send it to us directly. `nil`
    /// hides it (no sign-in in this build, snapshot tests).
    var signIn: (() -> Void)?

    var body: some View {
        SettingsPage(
            header: SettingsHeader(
                title: SettingsText.feedbackTitle, lede: SettingsText.feedbackLede, art: .drawersFeedback)
        ) {
            if case .sent(let note) = model.phase {
                sent(note)
            } else {
                writing
            }
        }
    }

    // MARK: Writing

    @ViewBuilder private var writing: some View {
        SettingsGroup(header: FeedbackText.kindHeader, identifier: "feedback.kind") {
            NookFlowLayout {
                ForEach(FeedbackKind.allCases, id: \.self) { kind in
                    NookChip(kind.title, isSelected: model.kind == kind) {
                        model.kind = kind
                    }
                    .accessibilityIdentifier("feedback.kind.\(kind.rawValue)")
                }
            }
            .padding(.horizontal, NookSpacing.small)
            .padding(.bottom, NookSpacing.xSmall)
        }

        VStack(alignment: .leading, spacing: NookSpacing.small) {
            EditorTextField(
                label: FeedbackText.messageLabel(model.kind), prompt: FeedbackText.messagePrompt,
                text: $model.message, isMultiline: true, problem: model.messageProblem.map(FeedbackText.problem),
                identifier: "feedback.message", focus: focus, focusValue: .message
            )
            .tourAnchor(FeedbackTour.Anchor.message, label: FeedbackText.messageLabel(model.kind))
            Text(FeedbackText.messageHint)
                .nookTextStyle(.note)
                .foregroundStyle(.nook.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(NookSpacing.medium)
        .floorCard()

        if model.route == .supportQueue {
            replyAddress
            screenshotGroup
        }

        SettingsGroup {
            SettingsSwitchRow(
                title: FeedbackText.detailsRow,
                detail: model.includesDetails ? FeedbackText.detailsRowOn : FeedbackText.detailsRowOff,
                systemImage: "info.circle", isOn: model.includesDetails, identifier: "feedback.details",
                set: { model.includesDetails = $0 })
        }

        if model.route == .supportQueue {
            SettingsGroup {
                SettingsSwitchRow(
                    title: FeedbackText.closetRow,
                    detail: model.includesClosetCounts ? FeedbackText.closetRowOn : FeedbackText.closetRowOff,
                    systemImage: "tray.full", isOn: model.includesClosetCounts, identifier: "feedback.closetCounts",
                    set: { model.includesClosetCounts = $0 })
            }
            // 31: only when the phone has crash or speed reports to share.
            if model.offersDeviceHealth {
                SettingsGroup {
                    SettingsSwitchRow(
                        title: FeedbackText.healthRow,
                        detail: model.includesDeviceHealth ? FeedbackText.healthRowOn : FeedbackText.healthRowOff,
                        systemImage: "waveform.path.ecg", isOn: model.includesDeviceHealth,
                        identifier: "feedback.deviceHealth", set: { model.includesDeviceHealth = $0 })
                }
            }
        }

        SettingsGroup(header: FeedbackText.previewHeader, identifier: "feedback.preview") {
            preview(model.preview)
            if let screenshot = model.screenshot, model.route == .supportQueue {
                ScreenshotThumbnail(screenshot: screenshot)
                    .padding(.horizontal, NookSpacing.small)
            }
            SettingsNote(model.route == .supportQueue ? FeedbackText.queueNote : FeedbackText.neverSent)
        }

        // Release: signed out, the share sheet still works; signing in sends it to us directly.
        if model.route == .shareSheet, let signIn {
            VStack(alignment: .leading, spacing: NookSpacing.xSmall) {
                NookButton(
                    FeedbackText.signInToSend, systemImage: "person.crop.circle", kind: .soft, fillsWidth: true,
                    action: signIn
                )
                .accessibilityIdentifier("feedback.signIn")
                Text(FeedbackText.signInToSendDetail)
                    .nookTextStyle(.note)
                    .foregroundStyle(.nook.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, NookSpacing.small)
            }
        }

        VStack(alignment: .leading, spacing: NookSpacing.small) {
            NookButton(
                model.phase == .sending ? FeedbackText.sending : FeedbackText.send,
                systemImage: model.phase == .sending ? "hourglass" : "paperplane", fillsWidth: true, action: send
            )
            .disabled(model.phase == .sending)
            .accessibilityIdentifier("feedback.send")
            .tourAnchor(FeedbackTour.Anchor.send, label: FeedbackText.send)
            if let problem = model.sendProblem {
                FieldProblemNote(message: FeedbackText.sendProblem(problem, hasScreenshot: model.screenshot != nil))
                    .accessibilityIdentifier("feedback.sendProblem")
            }
            Label {
                Text(model.route == .supportQueue ? FeedbackText.queueHowItGoes : FeedbackText.howItGoes)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "lock")
                    .accessibilityHidden(true)
            }
            .nookTextStyle(.note)
            .foregroundStyle(.nook.textSecondary)
            .padding(.horizontal, NookSpacing.small)
            .padding(.vertical, NookSpacing.xSmall)
            .floorCard()
        }

        if let openSupportPage {
            Button(action: openSupportPage) {
                NookRow(
                    FeedbackText.supportPageRow, subtitle: FeedbackText.supportPageDetail,
                    systemImage: "lifepreserver", accessory: .chevron)
            }
            .buttonStyle(.nookRow)
            .padding(.vertical, NookSpacing.xSmall)
            .floorCard()
            .accessibilityHint(Text(PrivacyText.opensWebsite))
            .accessibilityIdentifier("feedback.supportPage")
        }
    }

    // MARK: The support queue's extras (24d)

    @ViewBuilder private var replyAddress: some View {
        VStack(alignment: .leading, spacing: NookSpacing.small) {
            EditorTextField(
                label: FeedbackText.replyLabel, isOptional: true, prompt: FeedbackText.replyPrompt,
                text: $model.replyAddress, isEmailAddress: true,
                problem: model.replyProblem.map(FeedbackText.problem), identifier: "feedback.reply", focus: focus,
                focusValue: .replyAddress)
            Text(FeedbackText.replyHint)
                .nookTextStyle(.note)
                .foregroundStyle(.nook.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(NookSpacing.medium)
        .floorCard()
    }

    @ViewBuilder private var screenshotGroup: some View {
        SettingsGroup(header: FeedbackText.screenshotHeader, identifier: "feedback.screenshot") {
            if let screenshot = model.screenshot {
                HStack(alignment: .center, spacing: NookSpacing.small) {
                    ScreenshotThumbnail(screenshot: screenshot, height: 88)
                    VStack(alignment: .leading, spacing: NookSpacing.xSmall) {
                        Button(FeedbackText.chooseAnother, action: chooseScreenshot)
                            .accessibilityIdentifier("feedback.screenshot.change")
                        Button(FeedbackText.removeScreenshot, role: .destructive) { model.removeScreenshot() }
                            .accessibilityIdentifier("feedback.screenshot.remove")
                    }
                    .nookTextStyle(.body)
                }
                .padding(.horizontal, NookSpacing.small)
                .padding(.vertical, NookSpacing.xSmall)
            } else if model.isPreparingScreenshot {
                HStack(spacing: NookSpacing.small) {
                    ProgressView()
                    Text(FeedbackText.screenshotPreparing)
                        .nookTextStyle(.body)
                        .foregroundStyle(.nook.textSecondary)
                }
                .padding(NookSpacing.small)
                .accessibilityElement(children: .combine)
            } else {
                Button(action: chooseScreenshot) {
                    NookRow(FeedbackText.addScreenshot, systemImage: "photo", accessory: .chevron)
                }
                .buttonStyle(.nookRow)
                .accessibilityIdentifier("feedback.screenshot.add")
                #if DEBUG
                    FeedbackSampleScreenshot.button { data in
                        Task { await model.attachScreenshot(data) }
                    }
                #endif
            }
            if let problem = model.screenshotProblem {
                FieldProblemNote(message: FeedbackText.screenshotProblem(problem))
                    .padding(.horizontal, NookSpacing.small)
                    .accessibilityIdentifier("feedback.screenshot.problem")
            }
            SettingsNote(FeedbackText.screenshotHint)
        }
    }

    /// The exact text, on a stronger tint, or a line saying it'll show here.
    private func preview(_ text: String?) -> some View {
        Text(text ?? FeedbackText.previewEmpty)
            .nookTextStyle(text == nil ? .note : .body)
            .foregroundStyle(text == nil ? Color.nook.textSecondary : Color.nook.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(NookSpacing.medium)
            .background(Color.nook.tintStrong, in: NookRadius.shape(NookRadius.button))
            .padding(.horizontal, NookSpacing.xSmall)
            .accessibilityIdentifier("feedback.previewText")
    }

    // MARK: Sent

    @ViewBuilder private func sent(_ note: FeedbackNote) -> some View {
        VStack(spacing: NookSpacing.medium) {
            Image(systemName: "checkmark")
                .font(.title2.weight(.bold))
                .foregroundStyle(.nook.onAccent)
                .frame(width: 56, height: 56)
                .background(Color.nook.accent, in: Circle())
                .accessibilityHidden(true)
            Text(FeedbackText.thanksTitle)
                .nookTextStyle(.title)
                .foregroundStyle(.nook.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Text(model.receipt == nil ? FeedbackText.thanksMessage : FeedbackText.thanksQueueMessage)
                .nookTextStyle(.body)
                .foregroundStyle(.nook.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let receipt = model.receipt {
                Text(FeedbackText.referenceLine(receipt.reference))
                    .nookTextStyle(.note)
                    .foregroundStyle(.nook.textPrimary)
                    .accessibilityIdentifier("feedback.reference")
                if note.replyAddress == nil {
                    Text(FeedbackText.noReplyAddressNote)
                        .nookTextStyle(.note)
                        .foregroundStyle(.nook.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(NookSpacing.large)
        .floorCard()
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("feedback.sent")

        SettingsGroup {
            preview(FeedbackComposer.text(note))
        }

        NookAdaptiveStack {
            NookButton(FeedbackText.done, fillsWidth: true, action: done)
                .accessibilityIdentifier("feedback.done")
            NookButton(FeedbackText.writeAnother, kind: .soft, fillsWidth: true, action: writeAnother)
                .accessibilityIdentifier("feedback.writeAnother")
        }
    }
}

/// The screenshot she attached, as it will be sent (already cleaned and shrunk).
struct ScreenshotThumbnail: View {
    let screenshot: FeedbackScreenshot
    var height: CGFloat = 160

    var body: some View {
        if let image = UIImage(data: screenshot.data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxHeight: height)
                .clipShape(NookRadius.shape(NookRadius.small))
                .accessibilityLabel(Text(FeedbackText.screenshotLabel))
                .accessibilityIdentifier("feedback.screenshot.thumbnail")
        }
    }
}
