#if DEBUG
    import Models
    import SwiftUI

    /// The Phase 24a checkpoint screen: sign in with the fake Apple sign-in (or Clerk, once it's
    /// configured), make the authenticated who-am-I call, and switch the fake backend between its
    /// failure modes to see each one handled.
    ///
    /// Debug builds only: launch with `-gateway-lab`. The real sign-in screens come later, with a
    /// design.
    public struct GatewayLabScreen: View {
        @State private var model: GatewayLabModel
        @Environment(\.connection) private var connection

        public init(account: any AccountService, controls: GatewayLabControls?, log: GatewayLabLog) {
            _model = State(initialValue: GatewayLabModel(account: account, controls: controls, log: log))
        }

        public var body: some View {
            NavigationStack {
                List {
                    // Phase 26: where the cloud is needed, an offline banner says so and what still works.
                    if connection.isOffline {
                        Section {
                            CloudOfflineBanner(retry: { Task { await model.whoAmI() } })
                                .listRowInsets(EdgeInsets())
                                .listRowBackground(Color.clear)
                        }
                    }
                    accountSection
                    if let message = model.message { resultSection(message) }
                    if let controls = model.controls { modesSection(controls) }
                    logSection
                }
                .navigationTitle(Text(verbatim: "Gateway"))
                .task { await model.refreshStatus() }
            }
            .accessibilityIdentifier("gatewayLab")
        }

        private var accountSection: some View {
            Section {
                LabeledContent {
                    Text(verbatim: model.providerName)
                } label: {
                    Text(verbatim: "Sign-in")
                }
                LabeledContent {
                    Text(verbatim: statusText).accessibilityIdentifier("gatewayLab.status")
                } label: {
                    Text(verbatim: "Status")
                }
                Button {
                    Task { await model.signIn() }
                } label: {
                    Label {
                        Text(verbatim: "Sign in with Apple")
                    } icon: {
                        Image(systemName: "apple.logo")
                    }
                }
                .accessibilityIdentifier("gatewayLab.signIn")
                Button {
                    Task { await model.whoAmI() }
                } label: {
                    Label {
                        Text(verbatim: "Who am I?")
                    } icon: {
                        Image(systemName: "person.crop.circle.badge.questionmark")
                    }
                }
                .disabled(model.isWaitingToRetry)
                .accessibilityIdentifier("gatewayLab.whoAmI")
                Button(role: .destructive) {
                    Task { await model.signOut() }
                } label: {
                    Text(verbatim: "Sign out")
                }
                .accessibilityIdentifier("gatewayLab.signOut")
                if model.isWorking {
                    HStack {
                        ProgressView()
                        Text(verbatim: "Waiting for the backend…")
                    }
                }
            } footer: {
                Text(verbatim: "Your closet never depends on this: it works signed out and offline.")
            }
        }

        private func resultSection(_ message: String) -> some View {
            Section {
                Label {
                    Text(verbatim: message).accessibilityIdentifier("gatewayLab.message")
                } icon: {
                    Image(systemName: model.messageIsProblem ? "exclamationmark.triangle" : "checkmark.circle")
                }
                if !model.lastCallLines.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(model.lastCallLines.enumerated()), id: \.offset) { _, line in
                            Text(verbatim: line).font(.caption.monospaced())
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("gatewayLab.lastCall")
                }
            } header: {
                Text(verbatim: "Result")
            }
        }

        private func modesSection(_ controls: GatewayLabControls) -> some View {
            Section {
                ForEach(controls.modes) { mode in
                    Button {
                        model.setMode(mode.id)
                    } label: {
                        HStack {
                            Text(verbatim: mode.title)
                            Spacer()
                            if model.modeID == mode.id {
                                Image(systemName: "checkmark").accessibilityHidden(true)
                            }
                        }
                    }
                    .accessibilityAddTraits(model.modeID == mode.id ? .isSelected : [])
                    .accessibilityIdentifier("gatewayLab.mode.\(mode.id)")
                }
            } header: {
                Text(verbatim: "Fake backend behaviour")
            }
        }

        private var logSection: some View {
            Section {
                ForEach(Array(model.log.lines.enumerated().reversed()), id: \.offset) { _, line in
                    Text(verbatim: line).font(.caption.monospaced())
                }
            } header: {
                Text(verbatim: "Requests, newest first")
            }
        }

        private var statusText: String {
            switch model.status {
            case .unknown: "…"
            case .signedOut: "Signed out"
            case .signedIn(let user?): "Signed in as \(user.id)"
            case .signedIn(nil): "Signed in"
            }
        }
    }
#endif
