import CoreLocation
import Foundation
import Network
import Observation
import SwiftUI

extension Notification.Name {
    static let networkFixturePushReceived = Notification.Name("networkFixturePushReceived")
}

@MainActor
@Observable
final class NetworkProbeModel {
    private(set) var pathStatus = "Waiting"
    private(set) var pathDetails = ""
    private(set) var requestStatus = "Not run"
    private(set) var requestDetails = ""
    private(set) var eventStatus = "None"
    private(set) var locationStatus = "Waiting"

    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "com.simpilot.network-condition-fixture.path")
    private let locationProbe = LocationProbe()
    private var started = false

    init() {
        locationProbe.onUpdate = { [weak self] status in
            Task { @MainActor in self?.locationStatus = status }
        }
    }

    func start() {
        guard !started else { return }
        started = true
        monitor.pathUpdateHandler = { [weak self] path in
            let status: String
            switch path.status {
            case .satisfied: status = "satisfied"
            case .unsatisfied: status = "unsatisfied"
            case .requiresConnection: status = "requiresConnection"
            @unknown default: status = "unknown"
            }
            let interfaces = path.availableInterfaces.map(\.type.debugName).sorted().joined(separator: ",")
            Task { @MainActor in
                self?.pathStatus = status
                self?.pathDetails = "interfaces=\(interfaces) expensive=\(path.isExpensive) constrained=\(path.isConstrained)"
            }
        }
        monitor.start(queue: monitorQueue)
        locationProbe.start()
    }

    func handle(url: URL) {
        eventStatus = "Deep link: \(url.host ?? url.absoluteString)"
    }

    func handlePush(_ notification: Notification) {
        let value = notification.userInfo?["fixture-event"] as? String ?? "received"
        eventStatus = "Push: \(value)"
    }

    func runRequest() {
        requestStatus = "Running"
        requestDetails = ""
        let startedAt = ContinuousClock.now
        let defaultURL = "https://example.com/?probe=\(UUID().uuidString)"
        let configuredURL = ProcessInfo.processInfo.environment["NETWORK_PROBE_URL"] ?? defaultURL
        guard let url = URL(string: configuredURL) else {
            requestStatus = "Failed"
            requestDetails = "invalid-url"
            return
        }
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.timeoutInterval = 8

        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 10
        let session = URLSession(configuration: configuration)
        session.dataTask(with: request) { [weak self] data, response, error in
            let elapsed = startedAt.duration(to: .now)
            let elapsedSeconds = Double(elapsed.components.seconds) +
                Double(elapsed.components.attoseconds) / 1_000_000_000_000_000_000
            let status: String
            let details: String
            if let error = error as NSError? {
                status = "Failed"
                details = "domain=\(error.domain) code=\(error.code) elapsed=\(String(format: "%.2f", elapsedSeconds))s"
            } else {
                let httpStatus = (response as? HTTPURLResponse)?.statusCode ?? -1
                status = "Succeeded"
                details = "http=\(httpStatus) bytes=\(data?.count ?? 0) elapsed=\(String(format: "%.2f", elapsedSeconds))s"
            }
            Task { @MainActor in
                self?.requestStatus = status
                self?.requestDetails = details
                session.invalidateAndCancel()
            }
        }.resume()
    }
}

private final class LocationProbe: NSObject, CLLocationManagerDelegate {
    var onUpdate: ((String) -> Void)?
    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    func start() {
        manager.startUpdatingLocation()
        publishAuthorization(manager.authorizationStatus)
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        publishAuthorization(manager.authorizationStatus)
        if manager.authorizationStatus == .authorizedAlways ||
            manager.authorizationStatus == .authorizedWhenInUse {
            manager.startUpdatingLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let coordinate = locations.last?.coordinate else { return }
        onUpdate?(String(format: "%.4f,%.4f", coordinate.latitude, coordinate.longitude))
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        onUpdate?("error=\((error as NSError).code)")
    }

    private func publishAuthorization(_ status: CLAuthorizationStatus) {
        switch status {
        case .notDetermined: onUpdate?("permission=not-determined")
        case .restricted: onUpdate?("permission=restricted")
        case .denied: onUpdate?("permission=denied")
        case .authorizedAlways: onUpdate?("permission=always")
        case .authorizedWhenInUse: onUpdate?("permission=when-in-use")
        @unknown default: onUpdate?("permission=unknown")
        }
    }
}

private extension NWInterface.InterfaceType {
    var debugName: String {
        switch self {
        case .wifi: "wifi"
        case .cellular: "cellular"
        case .wiredEthernet: "wiredEthernet"
        case .loopback: "loopback"
        case .other: "other"
        @unknown default: "unknown"
        }
    }
}

struct ContentView: View {
    @State private var model = NetworkProbeModel()
    @State private var typedText = ""
    @State private var secretText = ""

    var body: some View {
        NavigationStack {
            List {
                NetworkPathSection(
                    status: model.pathStatus,
                    details: model.pathDetails
                )
                SystemEventSection(
                    eventStatus: model.eventStatus,
                    locationStatus: model.locationStatus
                )
                NetworkRequestSection(model: model)
                TextEntrySection(text: $typedText, secret: $secretText)
            }
            .navigationTitle("Network Probe")
        }
        .task { model.start() }
        .onOpenURL { model.handle(url: $0) }
        .onReceive(NotificationCenter.default.publisher(for: .networkFixturePushReceived)) {
            model.handlePush($0)
        }
    }
}

private struct NetworkPathSection: View {
    let status: String
    let details: String

    var body: some View {
        Section("NWPathMonitor") {
            LabeledContent("Status", value: status)
                .accessibilityIdentifier("network-probe.path-status")
            Text(details)
                .font(.footnote.monospaced())
                .accessibilityIdentifier("network-probe.path-details")
        }
    }
}

private struct SystemEventSection: View {
    let eventStatus: String
    let locationStatus: String

    var body: some View {
        Section("System Events") {
            LabeledContent("Event", value: eventStatus)
                .accessibilityIdentifier("network-probe.event-status")
            LabeledContent("Location", value: locationStatus)
                .accessibilityIdentifier("network-probe.location-status")
        }
    }
}

private struct NetworkRequestSection: View {
    let model: NetworkProbeModel

    var body: some View {
        Section("Network Request") {
            LabeledContent("Result", value: model.requestStatus)
                .accessibilityIdentifier("network-probe.request-status")
            Text(model.requestDetails)
                .font(.footnote.monospaced())
                .accessibilityIdentifier("network-probe.request-details")
            Button("Run Request") { model.runRequest() }
                .accessibilityIdentifier("network-probe.run-request")
        }
    }
}

private struct TextEntrySection: View {
    @Binding var text: String
    @Binding var secret: String

    var body: some View {
        Section("Text Input") {
            TextField("Enter text", text: $text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityIdentifier("text-input.field")
            // Echo the field's current value so a saved test can assert on the
            // exact entered text ("Typed, <value>") through describe-ui.
            LabeledContent("Typed", value: text)
                .accessibilityIdentifier("text-input.echo")
            // A secure field reports masked text as its AXValue, so `set-text`
            // cannot confirm its own write here. Present so that behaviour is
            // measurable instead of assumed.
            SecureField("Enter secret", text: $secret)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityIdentifier("secure-input.field")
            LabeledContent("Secret length", value: "\(secret.count)")
                .accessibilityIdentifier("secure-input.echo")
        }
    }
}
