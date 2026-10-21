#if DEBUG
    import Models
    import SwiftUI

    /// The Phase 24b checkpoint screen: placeholder paid actions through the gateway (the fake
    /// backend, or the real one once configured), her allowances, and what she reads for each limit.
    /// Debug builds only: launch with `-limits-lab`.
    public struct LimitsLabScreen: View {
        @State private var model: LimitsLabModel

        public init(account: any AccountService, paid: any PaidActionService, controls: LimitsLabControls?) {
            _model = State(initialValue: LimitsLabModel(account: account, paid: paid, controls: controls))
        }

        public var body: some View {
            NavigationStack {
                List {
                    if !model.signedIn {
                        Section {
                            button("Sign in with Apple", id: "signIn") { await model.signIn() }
                        }
                    }
                    allowancesSection
                    actionsSection
                    if model.controls != nil { switchesSection }
                }
                // Pinned to the bottom, so the outcome stays on screen wherever the list is scrolled.
                .safeAreaInset(edge: .bottom) {
                    if let message = model.message { resultBar(message) }
                }
                .navigationTitle(Text(verbatim: "Limits"))
                .task { await model.start() }
                .refreshable { await model.refreshUsage() }
            }
            .accessibilityIdentifier("limitsLab")
        }

        private func resultBar(_ message: String) -> some View {
            Label {
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: message).accessibilityIdentifier("limitsLab.message")
                    if let detail = model.detail {
                        Text(verbatim: detail)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("limitsLab.detail")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } icon: {
                Image(systemName: model.messageIsProblem ? "hand.raised" : "checkmark.circle")
            }
            .padding()
            .background(.regularMaterial, in: .rect(cornerRadius: 16))
            .padding(.horizontal)
        }

        private var allowancesSection: some View {
            Section {
                if let usage = model.usage {
                    ForEach(usage.allowances, id: \.category) { allowance in
                        AllowanceMeter(allowance, paused: usage.paused.contains(feature(of: allowance.category)))
                            .accessibilityIdentifier("limitsLab.meter.\(allowance.category.rawValue)")
                    }
                } else {
                    Text(verbatim: model.signedIn ? "Loading…" : "Sign in to see them.")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text(verbatim: "What's left")
            }
        }

        private var actionsSection: some View {
            Section {
                button("Ask the stylist (swap)", id: "askStylist") {
                    await model.run(.style(mode: .swap, contextRevision: "rev_lab"))
                }
                button("Full outfit idea", id: "fullOutfit") {
                    await model.run(.style(mode: .full, contextRevision: "rev_lab"))
                }
                button("Make a try-on picture", id: "tryOn") { await model.run(.tryOn(contextRevision: "rev_lab")) }
                button("Send the last one again (same key)", id: "sendAgain") { await model.sendAgain() }
                    .disabled(!model.canSendAgain)
                if model.controls != nil {
                    button("Full outfit idea, answer lost on the way", id: "lostAnswer") {
                        await model.runWithLostAnswer(.style(mode: .full, contextRevision: "rev_lab"))
                    }
                }
                if model.isWorking {
                    HStack {
                        ProgressView()
                        Text(verbatim: "Waiting for the server…")
                    }
                }
            } header: {
                Text(verbatim: "Paid actions (placeholders until 27a and 33a)")
            }
            .disabled(!model.signedIn || model.isWorking)
        }

        private var switchesSection: some View {
            Section {
                Toggle(isOn: binding(.style)) { Text(verbatim: "Stylist paused (kill switch)") }
                    .accessibilityIdentifier("limitsLab.pause.style")
                Toggle(isOn: binding(.tryOn)) { Text(verbatim: "Try-on paused (kill switch)") }
                    .accessibilityIdentifier("limitsLab.pause.tryOn")
                button("Start over (forget usage)", id: "startOver") { await model.startOver() }
            } header: {
                Text(verbatim: "Fake server switches")
            } footer: {
                Text(verbatim: "On the real backend these are Jose's: npx convex run controls:setSwitch.")
            }
        }

        private func button(_ title: String, id: String, action: @escaping () async -> Void) -> some View {
            Button {
                Task { await action() }
            } label: {
                Text(verbatim: title)
            }
            .accessibilityIdentifier("limitsLab.\(id)")
        }

        private func binding(_ feature: PaidFeature) -> Binding<Bool> {
            Binding(
                get: { model.paused.contains(feature) },
                set: { on in Task { await model.setPaused(feature, on) } })
        }

        private func feature(of category: UsageCategory) -> PaidFeature {
            category == .tryOn ? .tryOn : .style
        }
    }
#endif
