//
//  WirelessConnectView.swift
//  AndroidFileSync
//
//  Wireless ADB pairing and connection (Android 11+)
//  Supports QR code pairing and manual pairing
//

import SwiftUI
import Network
internal import Combine
import CoreImage.CIFilterBuiltins

// MARK: - mDNS Pairing Browser

enum AutoDiscoveryStatus: Equatable {
    case idle
    case searching
    case deviceFound
    case pairing
    case paired
    case failed(String)
}

struct DiscoveredDevice: Identifiable, Equatable {
    var id: String { ip }
    let ip: String
    var pairingPort: UInt16?
    var connectPort: UInt16?
}

/// Browses the local network for ADB pairing services via mDNS.
/// Uses NWBrowser and NWConnection for real-time resolution (bypasses mDNSResponder cache).
class ADBPairingBrowser: ObservableObject {
    @Published var status: AutoDiscoveryStatus = .idle
    @Published var discoveredDevices: [String: DiscoveredDevice] = [:]
    
    private var pairingBrowser: NWBrowser?
    private var connectBrowser: NWBrowser?
    
    // Map of endpoints to resolve details for accurate removal
    // We store Hashable Representation mapping instead of NWEndpoint directly,
    // as NWEndpoint is an enum and hashes correctly by its host/port values or service.
    private var endpointToIPAndType: [NWEndpoint: (ip: String, isPairing: Bool)] = [:]
    private var activeConnections: [NWEndpoint: NWConnection] = [:]
    
    private let queue = DispatchQueue(label: "com.androidfilesync.adb.mdns")
    
    func startBrowsing() {
        DispatchQueue.main.async {
            self.discoveredDevices.removeAll()
            self.endpointToIPAndType.removeAll()
            self.status = .searching
        }
        
        print("📶 NWBrowser: Browsing for _adb-tls-pairing._tcp and _adb-tls-connect._tcp...")
        
        // 1. Setup Pairing Browser
        let pairParams = NWParameters.tcp
        if let ipOpts = pairParams.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options {
            ipOpts.version = .v4 // Force IPv4 everywhere
        }
        pairParams.includePeerToPeer = true // Helps discover devices on direct WiFi links
        pairingBrowser = NWBrowser(for: .bonjour(type: "_adb-tls-pairing._tcp", domain: "local."), using: pairParams)
        
        pairingBrowser?.browseResultsChangedHandler = { [weak self] results, changes in
            for change in changes {
                switch change {
                case .added(let result), .changed(_, let result, _):
                    self?.resolveEndpoint(result.endpoint, isPairing: true)
                case .removed(let result):
                    self?.handleRemoval(for: result.endpoint)
                default:
                    break
                }
            }
        }
        
        // 2. Setup Connect Browser
        let connectParams = NWParameters.tcp
        if let ipOpts = connectParams.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options {
            ipOpts.version = .v4
        }
        connectParams.includePeerToPeer = true
        connectBrowser = NWBrowser(for: .bonjour(type: "_adb-tls-connect._tcp", domain: "local."), using: connectParams)
        
        connectBrowser?.browseResultsChangedHandler = { [weak self] results, changes in
            for change in changes {
                switch change {
                case .added(let result), .changed(_, let result, _):
                    self?.resolveEndpoint(result.endpoint, isPairing: false)
                case .removed(let result):
                    self?.handleRemoval(for: result.endpoint)
                default:
                    break
                }
            }
        }
        
        pairingBrowser?.start(queue: queue)
        connectBrowser?.start(queue: queue)
    }
    
    func stopBrowsing() {
        pairingBrowser?.cancel()
        pairingBrowser = nil
        connectBrowser?.cancel()
        connectBrowser = nil
        
        for (_, connection) in activeConnections {
            connection.cancel()
        }
        activeConnections.removeAll()
        
        DispatchQueue.main.async {
            if self.status == .searching {
                self.status = .idle
            }
            self.discoveredDevices.removeAll()
            self.endpointToIPAndType.removeAll()
        }
    }
    
    private func resolveEndpoint(_ endpoint: NWEndpoint, isPairing: Bool) {
        activeConnections[endpoint]?.cancel()
        
        let connectionParams = NWParameters.tcp
        if let ipOpts = connectionParams.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options {
            ipOpts.version = .v4
        }
        let connection = NWConnection(to: endpoint, using: connectionParams)
        activeConnections[endpoint] = connection
        
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                if let path = connection.currentPath,
                   case let .hostPort(host, port) = path.remoteEndpoint {
                    
                    let ipString = "\(host)"
                    let cleanIp = ipString.components(separatedBy: "%").first ?? ipString
                    let portNumber = port.rawValue
                    
                    print("📶 NWBrowser: \(isPairing ? "Pairing" : "Connect") -> \(cleanIp):\(portNumber)")
                    
                    DispatchQueue.main.async {
                        self?.endpointToIPAndType[endpoint] = (cleanIp, isPairing)
                        
                        var device = self?.discoveredDevices[cleanIp] ?? DiscoveredDevice(ip: cleanIp)
                        if isPairing {
                            device.pairingPort = portNumber
                        } else {
                            device.connectPort = portNumber
                        }
                        
                        self?.discoveredDevices[cleanIp] = device
                        self?.evaluateStatus()
                    }
                    
                    // Critical: Close connection so Android doesn't get flooded
                    connection.cancel()
                    DispatchQueue.main.async {
                        self?.activeConnections.removeValue(forKey: endpoint)
                    }
                }
            case .failed(let error):
                print("📶 NWBrowser: Endpoint resolution failed: \(error)")
                connection.cancel()
                DispatchQueue.main.async {
                    self?.activeConnections.removeValue(forKey: endpoint)
                }
            case .cancelled:
                DispatchQueue.main.async {
                    self?.activeConnections.removeValue(forKey: endpoint)
                }
            default:
                break
            }
        }
        
        connection.start(queue: queue)
    }
    
    private func handleRemoval(for endpoint: NWEndpoint) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            if let info = self.endpointToIPAndType[endpoint] {
                if var device = self.discoveredDevices[info.ip] {
                    if info.isPairing {
                        device.pairingPort = nil
                    } else {
                        device.connectPort = nil
                    }
                    
                    if device.pairingPort == nil && device.connectPort == nil {
                        self.discoveredDevices.removeValue(forKey: info.ip)
                    } else {
                        self.discoveredDevices[info.ip] = device
                    }
                }
                self.endpointToIPAndType.removeValue(forKey: endpoint)
            }
            self.evaluateStatus()
        }
    }
    
    private func evaluateStatus() {
        if discoveredDevices.isEmpty {
            if self.status == .deviceFound {
                self.status = .searching
            }
        } else {
            if self.status == .searching {
                self.status = .deviceFound
            }
        }
    }
}

// MARK: - QR Code Generator

struct QRCodeView: View {
    let data: String
    
    var body: some View {
        if let image = generateQRCode() {
            Image(nsImage: image)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
        } else {
            Image(systemName: "qrcode")
                .font(.system(size: 100))
                .foregroundColor(.secondary)
        }
    }
    
    private func generateQRCode() -> NSImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        
        guard let data = data.data(using: .utf8) else { return nil }
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("L", forKey: "inputCorrectionLevel")
        
        guard let ciImage = filter.outputImage else { return nil }
        
        // Scale up for sharp rendering
        let scale = 10.0
        let transformed = ciImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        
        guard let cgImage = context.createCGImage(transformed, from: transformed.extent) else { return nil }
        
        return NSImage(cgImage: cgImage, size: NSSize(width: transformed.extent.width, height: transformed.extent.height))
    }
}

// MARK: - Main View

struct WirelessConnectView: View {
    @ObservedObject var deviceManager: DeviceManager
    var onConnected: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    
    // Tab selection
    @State private var selectedTab: PairingTab = .autoDiscovery
    
    // QR Code pairing state
    @StateObject private var pairingBrowser = ADBPairingBrowser()
    @State private var autoPairingCode = ""
    @State private var visiblePairingPort = ""
    @State private var selectedDeviceIP = ""
    
    // Manual pairing fields
    @State private var ipAddress = ""
    @State private var pairingPort = ""
    @State private var pairingCode = ""
    @State private var connectPort = ""
    
    // Shared state
    @State private var isPairing = false
    @State private var statusMessage = ""
    @State private var isError = false
    @State private var isSuccess = false
    @State private var showConnectOnly = false
    
    enum PairingTab: String, CaseIterable {
        case autoDiscovery = "Auto-Discovery"
        case manual = "Advanced"
    }
    

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header
            Divider()
            
            // Tab picker
            Picker("", selection: $selectedTab) {
                ForEach(PairingTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 8)
            .onChange(of: selectedTab) { _ in
                // Stop browsing when switching tabs
                pairingBrowser.stopBrowsing()
                pairingBrowser.status = .idle
                statusMessage = ""
                isError = false
                isSuccess = false
                visiblePairingPort = ""
                autoPairingCode = ""
            }
            
            // Tab content
            switch selectedTab {
            case .autoDiscovery:
                autoDiscoveryTab
            case .manual:
                manualTab
            }
        }
        .frame(width: 500, height: 620)
        .onDisappear {
            pairingBrowser.stopBrowsing()
        }
    }
    
    // MARK: - Header
    
    private var header: some View {
        HStack {
            Image(systemName: "wifi")
                .font(.title2)
                .foregroundColor(.blue)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Connect via WiFi")
                    .font(.headline)
                Text("Android 11+ Wireless Debugging")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button(action: { dismiss() }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    // MARK: - Auto-Discovery Tab
    
    private var autoDiscoveryTab: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Instructions
                VStack(alignment: .leading, spacing: 12) {
                    Text("Auto-Discovery makes pairing easy. Just ensure your phone and Mac are on the same WiFi network.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    VStack(alignment: .leading, spacing: 10) {
                        qrStepRow(number: 1, text: "Open Settings → Developer Options")
                        qrStepRow(number: 2, text: "Enable Wireless Debugging")
                        qrStepRow(number: 3, text: "Tap 'Pair device with pairing code'")
                    }
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(NSColor.controlBackgroundColor))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                        )
                )
                
                // Content area
                VStack(spacing: 16) {
                    if pairingBrowser.status == .idle || pairingBrowser.status == .searching {
                        // Searching state
                        VStack(spacing: 16) {
                            if pairingBrowser.status == .searching {
                                ProgressView()
                                    .scaleEffect(1.2)
                                    .padding(.top, 10)
                                
                                Text("Searching for devices on network...")
                                    .font(.headline)
                                
                                Text("Ensure your Android device is on the 'Pair device with pairing code' screen.")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                                
                                Text("Debug: \(pairingBrowser.discoveredDevices.count) device(s) tracked")
                                    .font(.caption2)
                                    .foregroundColor(.gray)
                                    .padding(.top, 4)
                            } else {
                                Button(action: startAutoDiscovery) {
                                    HStack(spacing: 8) {
                                        Image(systemName: "magnifyingglass")
                                        Text("Start Auto-Discovery")
                                    }
                                    .font(.body.weight(.medium))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 24)
                                    .padding(.vertical, 12)
                                    .background(
                                        LinearGradient(
                                            colors: [.blue, .purple],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .cornerRadius(10)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: 180)
                        
                    } else {
                        // Device found / Pairing / Paired / Failed states
                        VStack(spacing: 16) {
                            
                            // Status indicator
                            autoDiscoveryStatusView
                            
                            if pairingBrowser.status != .idle && pairingBrowser.status != .searching && pairingBrowser.status != .pairing && pairingBrowser.status != .paired {
                                // Input form
                                VStack(alignment: .leading, spacing: 16) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        if pairingBrowser.discoveredDevices.count > 1 {
                                            Text("Multiple Devices Discovered")
                                                .font(.headline)
                                            
                                            Picker("Select Device", selection: $selectedDeviceIP) {
                                                ForEach(Array(pairingBrowser.discoveredDevices.keys.sorted()), id: \.self) { ip in
                                                    Text(ip).tag(ip)
                                                }
                                            }
                                            .pickerStyle(.menu)
                                            .labelsHidden()
                                            
                                        } else {
                                            Text("Device Discovered")
                                                .font(.headline)
                                            Text("IP: \(selectedDeviceIP)")
                                                .font(.subheadline)
                                                .foregroundColor(.secondary)
                                        }
                                    } // CLOSE VStack "spacing: 4"
                                    
                                    // Make sure we have a device object
                                    let isCurrentlyConnected = deviceManager.isConnected && deviceManager.connectionType == .wireless && deviceManager.lastWirelessIP == selectedDeviceIP && !selectedDeviceIP.isEmpty

                                    
                                    if isCurrentlyConnected {
                                        VStack(spacing: 12) {
                                            HStack(spacing: 8) {
                                                Image(systemName: "checkmark.circle.fill")
                                                    .foregroundColor(.green)
                                                Text("Currently Connected")
                                                    .font(.subheadline.weight(.semibold))
                                                    .foregroundColor(.green)
                                            }
                                            .padding(.bottom, 8)
                                            
                                            Button(action: {
                                                Task {
                                                    await deviceManager.disconnectWireless()
                                                }
                                            }) {
                                                HStack(spacing: 6) {
                                                    Image(systemName: "xmark.circle")
                                                    Text("Disconnect")
                                                }
                                                .font(.body.weight(.medium))
                                                .foregroundColor(.white)
                                                .frame(maxWidth: .infinity)
                                                .padding(.vertical, 10)
                                                .background(Color.red.opacity(0.8))
                                                .cornerRadius(8)
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    } else {
                                        HStack(spacing: 16) {
                                            VStack(alignment: .leading, spacing: 8) {
                                                Text("Pairing Port (from phone)")
                                                    .font(.subheadline.weight(.medium))
                                                
                                                TextField("e.g. 41583", text: $visiblePairingPort)
                                                    .textFieldStyle(.roundedBorder)
                                                    .font(.title3.monospacedDigit())
                                            }
                                            
                                            VStack(alignment: .leading, spacing: 8) {
                                                Text("6-Digit Code")
                                                    .font(.subheadline.weight(.medium))
                                                
                                                TextField("000000", text: $autoPairingCode)
                                                    .textFieldStyle(.roundedBorder)
                                                    .font(.title3.monospacedDigit())
                                            }
                                        }
                                    .onChange(of: pairingBrowser.discoveredDevices) { devices in
                                        // Pick a default if empty or selected vanished
                                        if selectedDeviceIP.isEmpty, let firstIP = devices.keys.first {
                                            selectedDeviceIP = firstIP
                                        } else if !selectedDeviceIP.isEmpty, devices[selectedDeviceIP] == nil, let firstIP = devices.keys.first {
                                            selectedDeviceIP = firstIP
                                        }
                                        
                                        // Auto-fill pairing port if newly discovered
                                        if let dev = devices[selectedDeviceIP], let port = dev.pairingPort, visiblePairingPort.isEmpty {
                                            visiblePairingPort = String(port)
                                        }
                                    }
                                    .onChange(of: selectedDeviceIP) { newIP in
                                        visiblePairingPort = ""
                                        if let dev = pairingBrowser.discoveredDevices[newIP], let port = dev.pairingPort {
                                            visiblePairingPort = String(port)
                                        }
                                    }
                                    } // Close 'else' block
                                    
                                    if !isCurrentlyConnected {
                                        Button(action: pairWithAutoDiscovery) {
                                            HStack(spacing: 6) {
                                                Image(systemName: "link")
                                                Text("Pair & Connect")
                                            }
                                            .font(.body.weight(.medium))
                                            .foregroundColor(.white)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 10)
                                            .background((autoPairingCode.count == 6 && !visiblePairingPort.isEmpty) ? Color.blue : Color.gray)
                                            .cornerRadius(8)
                                        }
                                        .buttonStyle(.plain)
                                        .disabled(autoPairingCode.count != 6 || visiblePairingPort.isEmpty)
                                    }
                                }
                                .padding(20)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color(NSColor.controlBackgroundColor))
                                )
                                .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
                            }
                        }
                    }
                }
                
                Spacer(minLength: 20)
                
                // Bottom buttons
                HStack {
                    Button("Cancel") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                    
                    Spacer()
                    
                    if pairingBrowser.status != .idle && pairingBrowser.status != .searching {
                        Button(action: startAutoDiscovery) {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.clockwise")
                                Text("Search Again")
                            }
                        }
                    }
                }
            }
            .padding(24)
        }
        .onAppear {
            if pairingBrowser.status == .idle {
                startAutoDiscovery()
            }
        }
    }
    
    @ViewBuilder
    private var autoDiscoveryStatusView: some View {
        switch pairingBrowser.status {
        case .idle, .searching:
            EmptyView()
        case .deviceFound:
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text("Device found! Ready to pair.")
                    .font(.subheadline)
                    .foregroundColor(.green)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.green.opacity(0.1)))
        case .pairing:
            HStack(spacing: 8) {
                ProgressView()
                    .scaleEffect(0.7)
                Text("Pairing with device...")
                    .font(.subheadline)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.blue.opacity(0.1)))
        case .paired:
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text("Paired & Connected!")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.green)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.green.opacity(0.1)))
        case .failed(let message):
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                Text(message)
                    .font(.subheadline)
                    .foregroundColor(.orange)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.1)))
        }
    }
    
    private func qrStepRow(number: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(number)")
                .font(.caption2.weight(.bold))
                .foregroundColor(.white)
                .frame(width: 18, height: 18)
                .background(Circle().fill(Color.blue))
            
            Text(text)
                .font(.subheadline)
                .foregroundColor(.primary)
        }
    }
    
    // MARK: - Auto-Discovery Logic
    
    private func startAutoDiscovery() {
        autoPairingCode = ""
        visiblePairingPort = ""
        selectedDeviceIP = ""
        pairingBrowser.stopBrowsing()
        
        // Start discovering any _adb-tls-pairing._tcp service
        pairingBrowser.startBrowsing()
    }
    
    private func pairWithAutoDiscovery() {
        guard !selectedDeviceIP.isEmpty, !visiblePairingPort.isEmpty, !autoPairingCode.isEmpty else { return }
        
        guard let device = pairingBrowser.discoveredDevices[selectedDeviceIP] else { return }
        
        pairingBrowser.status = .pairing
        
        Task {
            // Pair using the user-verified port and the 6 digit code
            let (pairSuccess, pairMessage) = await ADBManager.pairDevice(
                ip: device.ip,
                port: visiblePairingPort,
                code: autoPairingCode
            )
            
            guard pairSuccess else {
                await MainActor.run {
                    pairingBrowser.status = .failed(pairMessage)
                }
                return
            }
            
            // Give Android a moment to update internal state
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            
            // Try connecting with the discovered Connect Port, falling back to discovered Pairing Port if none
            var targetConnectPort = device.connectPort != nil ? String(device.connectPort!) : "5555"
            var fallbackPorts = [targetConnectPort]
            if targetConnectPort != "5555" { fallbackPorts.append("5555") }
            if let pPort = device.pairingPort {
                fallbackPorts.append(String(pPort))
            }
            
            for tryPort in fallbackPorts {
                let (s, _) = await deviceManager.connectWirelessly(ip: device.ip, port: tryPort)
                if s {
                    await MainActor.run {
                        pairingBrowser.status = .paired
                        onConnected?()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            dismiss()
                        }
                    }
                    return
                }
            }
            
            // Connected successfully but couldn't auto-connect the daemon, which is common
            await MainActor.run {
                pairingBrowser.status = .paired
                onConnected?()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    dismiss()
                }
            }
        }
    }
    
    // MARK: - Manual Tab
    
    private var manualTab: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Instructions
                VStack(alignment: .leading, spacing: 12) {
                    Text("Setup Instructions")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.secondary)
                    
                    stepRow(number: 1, text: "Open Settings → Developer Options on your phone")
                    stepRow(number: 2, text: "Enable Wireless Debugging")
                    stepRow(number: 3, text: "Tap Pair device with pairing code")
                    stepRow(number: 4, text: "Enter the IP, port, and pairing code shown below")
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(NSColor.controlBackgroundColor))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                        )
                )
                
                // Input fields
                manualInputFields
                
                // Status message
                if !statusMessage.isEmpty {
                    statusBanner
                }
                
                // Action buttons
                manualActionButtons
            }
            .padding(24)
        }
    }
    
    // MARK: - Manual Input Fields
    
    private var manualInputFields: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Device IP Address")
                    .font(.subheadline.weight(.medium))
                TextField("e.g. 192.168.1.100", text: $ipAddress)
                    .textFieldStyle(.roundedBorder)
            }
            
            if !showConnectOnly {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Pairing Port")
                            .font(.subheadline.weight(.medium))
                        TextField("e.g. 37215", text: $pairingPort)
                            .textFieldStyle(.roundedBorder)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Pairing Code")
                            .font(.subheadline.weight(.medium))
                        TextField("e.g. 482604", text: $pairingCode)
                            .textFieldStyle(.roundedBorder)
                    }
                }
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Connection Port")
                    .font(.subheadline.weight(.medium))
                HStack {
                    TextField("e.g. 41235", text: $connectPort)
                        .textFieldStyle(.roundedBorder)
                    Text("(shown under Wireless Debugging)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Toggle(isOn: $showConnectOnly) {
                Text("Already paired — just connect")
                    .font(.subheadline)
            }
            .toggleStyle(.checkbox)
        }
    }
    
    // MARK: - Status Banner
    
    private var statusBanner: some View {
        HStack(spacing: 8) {
            if isPairing {
                ProgressView()
                    .scaleEffect(0.7)
            } else {
                Image(systemName: isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .foregroundColor(isError ? .orange : .green)
            }
            
            Text(statusMessage)
                .font(.subheadline)
                .foregroundColor(isError ? .orange : (isSuccess ? .green : .primary))
            
            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isError ? Color.orange.opacity(0.1) : (isSuccess ? Color.green.opacity(0.1) : Color.blue.opacity(0.1)))
        )
    }
    
    // MARK: - Manual Action Buttons
    
    private var manualActionButtons: some View {
        HStack {
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
            
            Spacer()
            
            if deviceManager.connectionType == .wireless {
                Button(action: {
                    Task { await deviceManager.disconnectWireless() }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "wifi.slash")
                        Text("Disconnect")
                    }
                }
                .tint(.red)
            }
            
            Button(action: performManualConnection) {
                HStack(spacing: 6) {
                    if isPairing {
                        ProgressView()
                            .scaleEffect(0.6)
                    } else {
                        Image(systemName: "wifi")
                    }
                    Text(showConnectOnly ? "Connect" : "Pair & Connect")
                }
                .frame(minWidth: 120)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isPairing || !isManualInputValid)
            .keyboardShortcut(.defaultAction)
        }
    }
    
    // MARK: - Helper Methods
    
    private func stepRow(number: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(.caption.weight(.bold))
                .foregroundColor(.white)
                .frame(width: 20, height: 20)
                .background(Circle().fill(Color.blue))
            
            Text(text)
                .font(.subheadline)
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
    
    private var isManualInputValid: Bool {
        if ipAddress.trimmingCharacters(in: .whitespaces).isEmpty { return false }
        if connectPort.trimmingCharacters(in: .whitespaces).isEmpty { return false }
        if !showConnectOnly {
            if pairingPort.trimmingCharacters(in: .whitespaces).isEmpty { return false }
            if pairingCode.trimmingCharacters(in: .whitespaces).isEmpty { return false }
        }
        return true
    }
    
    private func performManualConnection() {
        let ip = ipAddress.trimmingCharacters(in: .whitespaces)
        let cPort = connectPort.trimmingCharacters(in: .whitespaces)
        
        isPairing = true
        isError = false
        isSuccess = false
        statusMessage = showConnectOnly ? "Connecting..." : "Pairing..."
        
        Task {
            let (success, message): (Bool, String)
            
            if showConnectOnly {
                (success, message) = await deviceManager.connectWirelessly(ip: ip, port: cPort)
            } else {
                let pPort = pairingPort.trimmingCharacters(in: .whitespaces)
                let code = pairingCode.trimmingCharacters(in: .whitespaces)
                (success, message) = await deviceManager.pairAndConnect(
                    ip: ip,
                    pairingPort: pPort,
                    pairingCode: code,
                    connectPort: cPort
                )
            }
            
            await MainActor.run {
                isPairing = false
                statusMessage = message
                isError = !success
                isSuccess = success
                
                if success {
                    onConnected?()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        dismiss()
                    }
                }
            }
        }
    }
}
