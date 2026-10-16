import DesignSystem
import Models
import SwiftUI

/// The sheet for one measurement (`fit.html`'s measurement editor): how to measure it, the box
/// with its unit, what's wrong when Save finds a problem, Save, and Clear when it has a value.
///
/// Numbers use the decimal keypad and the region's decimal separator. VoiceOver hears each box
/// with its unit ("Waist in inches"), and when Save finds a problem it's announced and VoiceOver
/// moves to it. An empty box saves as "not added", never as zero (PRD §10.2).
struct MeasurementSheet: View {
    /// Saves what she typed. Returns false when it wasn't saved, so the sheet stays open.
    let save: (MeasurementForm.Value) async -> Bool
    let clear: () async -> Bool

    @Environment(\.locale) private var locale
    @Environment(\.closetIsStillImage) private var isStillImage
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var form: MeasurementForm
    @State private var problem: EntryProblem?
    @State private var didFail = false
    @State private var isSaving = false
    @AccessibilityFocusState private var problemFocused: Bool

    init(
        form: MeasurementForm, problem: EntryProblem? = nil, save: @escaping (MeasurementForm.Value) async -> Bool,
        clear: @escaping () async -> Bool
    ) {
        self.save = save
        self.clear = clear
        _form = State(initialValue: form)
        _problem = State(initialValue: problem)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: NookSpacing.medium) {
            boxes
            if let problem {
                problemNote(FitText.problem(problem, field: form.field, units: form.units))
            } else if didFail {
                problemNote(ProfileText.failed)
            }
            NookAdaptiveStack {
                NookButton(ProfileText.save, systemImage: "checkmark", isLoading: isSaving, fillsWidth: true) {
                    submit()
                }
                .accessibilityIdentifier("measurement.save")
                if form.hadValue {
                    NookButton(FitText.clear, kind: .soft, fillsWidth: true) {
                        run { await clear() }
                    }
                    .accessibilityIdentifier("measurement.clear")
                }
            }
        }
        .hiddenWhenInactive()
        .onChange(of: form) {
            problem = nil
            didFail = false
        }
    }

    @ViewBuilder private var boxes: some View {
        if form.usesFeetAndInches {
            let layout =
                dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: NookSpacing.small))
                : AnyLayout(HStackLayout(alignment: .top, spacing: NookSpacing.medium))
            layout {
                NumberBox(
                    label: FitText.feet, spoken: FitText.feet, unit: FitText.feetSymbol, text: $form.feet,
                    identifier: "measurement.feet")
                NumberBox(
                    label: FitText.inches, spoken: FitText.inches, unit: FitText.unitSymbol(.height, .imperial),
                    text: $form.inches, identifier: "measurement.inches")
            }
        } else {
            NumberBox(
                label: FitText.name(form.field), spoken: FitText.spokenBox(form.field, form.units),
                unit: FitText.unitSymbol(form.field, form.units), text: $form.text, identifier: "measurement.value")
        }
    }

    @ViewBuilder
    private func problemNote(_ message: String) -> some View {
        let note = FieldProblemNote(message: message)
            .accessibilityIdentifier("measurement.problem")
        if isStillImage {
            note
        } else {
            note.accessibilityFocused($problemFocused)
        }
    }

    private func submit() {
        do {
            let value = try form.value(locale: locale)
            run { await save(value) }
        } catch {
            problem = error
            AccessibilityNotification.Announcement(FitText.problem(error, field: form.field, units: form.units))
                .post()
            problemFocused = true
        }
    }

    private func run(_ change: @escaping () async -> Bool) {
        Task {
            isSaving = true
            didFail = !(await change())
            isSaving = false
        }
    }
}

/// A number box with its label above and its unit after it. Decimal keypad, one line.
struct NumberBox: View {
    let label: String
    /// What VoiceOver calls the box, with its unit.
    let spoken: String
    let unit: String
    @Binding var text: String
    let identifier: String

    @Environment(\.closetIsStillImage) private var isStillImage
    @FocusState private var isFocused: Bool
    @ScaledMetric(relativeTo: .body) private var minHeight: CGFloat = 48

    var body: some View {
        VStack(alignment: .leading, spacing: NookSpacing.xSmall) {
            EditorFieldLabel(label: label)
                .accessibilityHidden(true)
            HStack(spacing: NookSpacing.small) {
                field
                Text(unit)
                    .nookTextStyle(.label)
                    .foregroundStyle(.nook.textSecondary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, NookSpacing.small)
            .frame(maxWidth: .infinity, minHeight: max(minHeight, NookSpacing.minimumTapTarget), alignment: .leading)
            .background {
                NookRadius.shape(NookRadius.button)
                    .fill(Color.nook.tintStrong)
                    .softShadow(.drop, in: NookRadius.shape(NookRadius.button))
            }
            .contentShape(NookRadius.shape(NookRadius.button))
            .onTapGesture { isFocused = true }
        }
    }

    @ViewBuilder private var field: some View {
        if isStillImage {
            Text(text)
                .nookTextStyle(.body)
                .foregroundStyle(.nook.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            TextField(text: $text, prompt: Text(verbatim: "")) {
                Text(spoken)
            }
            .keyboardType(.decimalPad)
            .textContentType(nil)
            .autocorrectionDisabled()
            .nookTextStyle(.body)
            .foregroundStyle(.nook.textPrimary)
            .focused($isFocused)
            .accessibilityLabel(Text(spoken))
            .accessibilityValue(Text(text))
            .accessibilityIdentifier(identifier)
        }
    }
}
