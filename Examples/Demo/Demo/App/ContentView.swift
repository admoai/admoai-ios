import AdMoai
import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = ContentViewModel()
    @State private var showingRequest = false
    @State private var showingPreview = false
    @State private var showingRequestDetails = false

    var body: some View {
        NavigationStack {
            VStack {
                Form {
                    Section {
                        Text(
                            "This interface demonstrates how to build a decision request. The actual implementation will be handled by the SDK."
                        )
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    }

                    // Placement
                    Section {
                        NavigationLink {
                            PlacementPicker(placement: $viewModel.placement)
                        } label: {
                            LabeledContent {
                                Text(
                                    placementMockData.first {
                                        $0.id == viewModel.placement.key
                                    }?
                                    .name ?? viewModel.placement.key
                                )
                                .foregroundStyle(.secondary)
                            } label: {
                                Label("Key", systemImage: "key")
                            }
                        }

                        LabeledContent {
                            Text("Native")
                                .foregroundStyle(.secondary)
                        } label: {
                            Label("Format", systemImage: "square.stack")
                        }
                    } header: {
                        Text("Placement")
                    } footer: {
                        Text(
                            "This demo uses a single placement object, but you can include multiple ones. For each, you can specify the number of creatives to return and filter by advertiser and template.\nCurrently, AdMoai supports only the native format."
                        )
                    }

                    // Targeting
                    Section {
                        NavigationLink {
                            GeoTargetingPicker(targeting: $viewModel.targeting)
                        } label: {
                            LabeledContent {
                                if viewModel.targeting.geo?.isEmpty ?? true {
                                    Text("None")
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text("\(viewModel.targeting.geo?.count ?? 0) cities")
                                        .foregroundStyle(.secondary)
                                }
                            } label: {
                                Label("Geo Targeting", systemImage: "globe")
                            }
                        }

                        NavigationLink {
                            LocationTargetingPicker(targeting: $viewModel.targeting)
                        } label: {
                            LabeledContent {
                                if viewModel.targeting.location?.isEmpty ?? true {
                                    Text("None")
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text("\(viewModel.targeting.location?.count ?? 0) locations")
                                        .foregroundStyle(.secondary)
                                }
                            } label: {
                                Label("Location Targeting", systemImage: "mappin.and.ellipse")
                            }
                        }

                        NavigationLink {
                            CustomTargetingPicker(targeting: $viewModel.targeting)
                        } label: {
                            LabeledContent {
                                if viewModel.targeting.custom?.isEmpty ?? true {
                                    Text("None")
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text("\(viewModel.targeting.custom?.count ?? 0) pairs")
                                        .foregroundStyle(.secondary)
                                }
                            } label: {
                                Label("Custom Targeting", systemImage: "slider.horizontal.3")
                            }
                        }
                    } header: {
                        Text("Targeting")
                    } footer: {
                        Text(
                            "Targeting allows you to specify criteria to filter the creatives returned by AdMoai."
                        )
                    }

                    // User
                    Section {
                        // User ID
                        LabeledContent {
                            TextField(
                                "User ID",
                                text: Binding(
                                    get: { viewModel.user.id ?? "" },
                                    set: { newValue in
                                        viewModel.user = User(
                                            id: newValue.isEmpty ? nil : newValue,
                                            ip: viewModel.user.ip,
                                            timezone: viewModel.user.timezone,
                                            consent: viewModel.user.consent
                                        )
                                    }
                                )
                            )
                            .multilineTextAlignment(.trailing)
                        } label: {
                            Label("ID", systemImage: "person.circle")
                        }

                        // IP Address
                        LabeledContent {
                            TextField(
                                "IP Address",
                                text: Binding(
                                    get: { viewModel.user.ip ?? "" },
                                    set: { newValue in
                                        viewModel.user = User(
                                            id: viewModel.user.id,
                                            ip: newValue.isEmpty ? nil : newValue,
                                            timezone: viewModel.user.timezone,
                                            consent: viewModel.user.consent
                                        )
                                    }
                                )
                            )
                            .multilineTextAlignment(.trailing)
                        } label: {
                            Label("IP", systemImage: "network")
                        }

                        // Timezone
                        NavigationLink {
                            TimezonePicker(
                                selection: Binding(
                                    get: { viewModel.user.timezone },
                                    set: { newValue in
                                        viewModel.user = User(
                                            id: viewModel.user.id,
                                            ip: viewModel.user.ip,
                                            timezone: newValue,
                                            consent: viewModel.user.consent
                                        )
                                    }
                                )
                            )
                        } label: {
                            LabeledContent {
                                Text(viewModel.user.timezone ?? "None")
                                    .foregroundStyle(.secondary)
                            } label: {
                                Label("Timezone", systemImage: "clock")
                            }
                        }

                        // Consent (existing code)
                        DisclosureGroup {
                            LabeledContent {
                                Toggle(
                                    "",
                                    isOn: Binding(
                                        get: { viewModel.user.consent?.gdpr ?? false },
                                        set: { newValue in
                                            viewModel.user = User(
                                                id: viewModel.user.id,
                                                ip: viewModel.user.ip,
                                                timezone: viewModel.user.timezone,
                                                consent: User.Consent(gdpr: newValue)
                                            )
                                        }
                                    )
                                )
                                .labelsHidden()
                            } label: {
                                Label("GDPR", systemImage: "shield.checkerboard")
                            }
                        } label: {
                            Label("Consent", systemImage: "shield.fill")
                        }
                    } header: {
                        Text("User")
                    } footer: {
                        Text(
                            "The user ID and IP address enable frequency capping and geo-targeting respectively. The timezone enables day/hour parting for time-based ad delivery. GDPR consent must be enabled to serve ads with frequency capping."
                        )
                    }

                    Section {
                        LabeledContent("Name") {
                            Text((viewModel.buildRequest().app?.name) ?? "-")
                                .foregroundStyle(.secondary)
                        }
                        LabeledContent("Version") {
                            Text((viewModel.buildRequest().app?.version) ?? "-")
                                .foregroundStyle(.secondary)
                        }
                        LabeledContent("Build") {
                            Text((viewModel.buildRequest().app?.buildNumber) ?? "-")
                                .foregroundStyle(.secondary)
                        }
                        LabeledContent("Identifier") {
                            Text((viewModel.buildRequest().app?.identifier) ?? "-")
                                .foregroundStyle(.secondary)
                        }
                        LabeledContent("Language") {
                            Text((viewModel.buildRequest().app?.language) ?? "-")
                                .foregroundStyle(.secondary)
                        }
                    } header: {
                        Text("App")
                    } footer: {
                        Text("App information is automatically set by the SDK.")
                    }

                    Section {
                        LabeledContent("Device ID") {
                            Text((viewModel.buildRequest().device?.id) ?? "-")
                                .foregroundStyle(.secondary)
                                .font(.system(.caption, design: .monospaced))
                        }
                        LabeledContent("Model") {
                            Text((viewModel.buildRequest().device?.model) ?? "-")
                                .foregroundStyle(.secondary)
                        }
                        LabeledContent("Manufacturer") {
                            Text((viewModel.buildRequest().device?.manufacturer) ?? "-")
                                .foregroundStyle(.secondary)
                        }
                        LabeledContent("OS") {
                            Text((viewModel.buildRequest().device?.os) ?? "-")
                                .foregroundStyle(.secondary)
                        }
                        LabeledContent("OS Version") {
                            Text((viewModel.buildRequest().device?.osVersion) ?? "-")
                                .foregroundStyle(.secondary)
                        }
                        LabeledContent("Timezone") {
                            Text((viewModel.buildRequest().device?.timezone) ?? "-")
                                .foregroundStyle(.secondary)
                        }
                        LabeledContent("Language") {
                            Text((viewModel.buildRequest().device?.language) ?? "-")
                                .foregroundStyle(.secondary)
                        }
                    } header: {
                        Text("Device")
                    } footer: {
                        Text("Device information is automatically set by the SDK.")
                    }

                    Section {
                        Toggle("Collect App Data", isOn: $viewModel.collectAppData)
                        Toggle("Collect Device Data", isOn: $viewModel.collectDeviceData)
                    } header: {
                        Text("Data Collection")
                    } footer: {
                        Text(
                            "App and device information are collected by default when initializing the SDK. You can disable collection either globally using SDK configuration or per-request."
                        )
                    }
                }

                VStack(spacing: 12) {
                    // View HTTP Request button
                    Button {
                        showingRequestDetails = true
                    } label: {
                        HStack {
                            Image(systemName: "doc.text.magnifyingglass")
                            Text("View HTTP Request")
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.bordered)
                    .sheet(
                        isPresented: $showingRequestDetails,
                        onDismiss: {
                            showingRequestDetails = false
                        }
                    ) {
                        if let request = try? viewModel.getHTTPRequest() {
                            HTTPRequestView(request: request)
                        }
                    }

                    // Request and Preview button
                    Button {
                        Task {
                            try await viewModel.loadAds()
                            showingPreview = true
                        }
                    } label: {
                        HStack {
                            if viewModel.isLoading {
                                ProgressView()
                            } else {
                                Image(systemName: "arrow.right.circle")
                            }
                            Text(viewModel.isLoading ? "Loading..." : "Request and Preview")
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.isLoading)
                }
                .padding(.horizontal, 24)
                .padding(.top, 12)
            }
            .navigationTitle("Decision Request")
            .navigationDestination(isPresented: $showingPreview) {
                PreviewResultView(viewModel: viewModel)
                    .environmentObject(viewModel)
            }
        }
    }
}

#Preview {
    ContentView()
}
