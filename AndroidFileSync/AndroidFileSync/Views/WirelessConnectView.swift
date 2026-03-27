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

/// Browses the local network for ADB pairing services via mDNS.
/// Uses NetService for resolution (does NOT open TCP connections, unlike NWConnection).
class ADBPairingBrowser: NSObject, ObservableObject, NetServiceBrowserDelegate, NetServiceDelegate {
    @Published var isSearching = false
    
    /// Called on main thread when a matching service is resolved
    var onServiceResolved: ((String, UInt16) -> Void)?
    
    private var browser: NetServiceBrowser?
    private var targetServiceName: String?
    private var discoveredService: NetService?
    
    func startBrowsing(for serviceName: String) {
        targetServiceName = serviceName
        
        DispatchQueue.main.async {
            self.isSearching = true
        }
        
        print("📶 mDNS: Browsing for _adb-tls-pairing._tcp matching '\(serviceName)'...")
        
        browser = NetServiceBrowser()
        browser?.delegate = self
        browser?.searchForServices(ofType: "_adb-tls-pairing._tcp.", inDomain: "local.")
    }
    
    func stopBrowsing() {
        browser?.stop()
        browser = nil
        discoveredService?.stop()
        discoveredService = nil
        DispatchQueue.main.async {
            self.isSearching = false
        }
    }
    
    // MARK: - NetServiceBrowserDelegate
    
    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        print("📶 mDNS: Discovered service: \(service.name)")
        
        guard let target = targetServiceName, service.name.hasPrefix(target) else { return }
        
        print("📶 mDNS: ✅ Matched target service: \(service.name)")
        
        // Resolve the service to get IP and port WITHOUT opening a TCP connection
        discoveredService = service
        service.delegate = self
        service.resolve(withTimeout: 15.0)
    }
    
    func netServiceBrowser(_ browser: NetServiceBrowser, didNotSearch errorDict: [String: NSNumber]) {
        print("📶 mDNS: Browse error: \(errorDict)")
    }
    
    // MARK: - NetServiceDelegate
    
    func netServiceDidResolveAddress(_ sender: NetService) {
        let port = UInt16(sender.port)
        
        // Extract IPv4 address from the resolved addresses
        guard let addresses = sender.addresses else {
            print("📶 mDNS: No addresses found")
            return
        }
        
        for data in addresses {
            var storage = sockaddr_storage()
            data.withUnsafeBytes { ptr in
                _ = withUnsafeMutableBytes(of: &storage) { dest in
                    dest.copyBytes(from: ptr)
                }
            }
            
            if storage.ss_family == UInt8(AF_INET) {
                // IPv4
                var addr = withUnsafePointer(to: &storage) {
                    $0.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee }
                }
                var ipStr = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                inet_ntop(AF_INET, &addr.sin_addr, &ipStr, socklen_t(INET_ADDRSTRLEN))
                let ip = String(cString: ipStr)
                
                print("📶 mDNS: Resolved to \(ip):\(port)")
                
                DispatchQueue.main.async {
                    self.isSearching = false
                    self.onServiceResolved?(ip, port)
                }
                
                // Stop browsing after finding the service
                browser?.stop()
                return
            }
        }
    }
    
    func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {
        print("📶 mDNS: Resolve error: \(errorDict)")
        DispatchQueue.main.async {
            self.isSearching = false
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
    @State private var selectedTab: PairingTab = .qrCode
    
    // QR Code pairing state
    @State private var qrString = ""
    @State private var qrServiceName = ""
    @State private var qrPassword = ""
    @StateObject private var pairingBrowser = ADBPairingBrowser()
    @State private var qrStatus: QRPairingStatus = .idle
    
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
        case qrCode = "QR Code"
        case manual = "Manual"
    }
    
    enum QRPairingStatus {
        case idle
        case waitingForScan
        case deviceFound
        case pairing
        case paired
        case failed(String)
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
                qrStatus = .idle
                statusMessage = ""
                isError = false
                isSuccess = false
            }
            
            // Tab content
            switch selectedTab {
            case .qrCode:
                qrCodeTab
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
    
    // MARK: - QR Code Tab
    
    private var qrCodeTab: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Instructions
                VStack(alignment: .leading, spacing: 8) {
                    Text("On your Android device:")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.secondary)
                    
                    qrStepRow(number: 1, text: "Open Settings → Developer Options")
                    qrStepRow(number: 2, text: "Enable Wireless Debugging")
                    qrStepRow(number: 3, text: "Tap Pair device with QR code")
                    qrStepRow(number: 4, text: "Scan the QR code below")
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(NSColor.controlBackgroundColor))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                        )
                )
                
                // QR Code display
                VStack(spacing: 12) {
                    if qrString.isEmpty {
                        // Generate button
                        Button(action: startQRPairing) {
                            HStack(spacing: 8) {
                                Image(systemName: "qrcode")
                                Text("Generate QR Code")
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
                    } else {
                        // QR Code image
                        QRCodeView(data: qrString)
                            .frame(width: 200, height: 200)
                            .padding(16)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.white)
                            )
                            .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
                        
                        // Status indicator
                        qrStatusView
                    }
                }
                
                // Bottom buttons
                HStack {
                    Button("Cancel") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                    
                    Spacer()
                    
                    if !qrString.isEmpty {
                        Button(action: startQRPairing) {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.clockwise")
                                Text("New QR Code")
                            }
                        }
                    }
                }
            }
            .padding(24)
        }
    }
    
    @ViewBuilder
    private var qrStatusView: some View {
        switch qrStatus {
        case .idle:
            EmptyView()
        case .waitingForScan:
            HStack(spacing: 8) {
                ProgressView()
                    .scaleEffect(0.7)
                Text("Waiting for device to scan...")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.blue.opacity(0.1)))
        case .deviceFound:
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text("Device found! Connecting...")
                    .font(.subheadline)
                    .foregroundColor(.green)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.green.opacity(0.1)))
        case .pairing:
            HStack(spacing: 8) {
                ProgressView()
                    .scaleEffect(0.7)
                Text("Pairing...")
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
    
    // MARK: - QR Pairing Logic
    
    private func startQRPairing() {
        // Generate new QR data
        let (qr, service, password) = ADBManager.generateQRPairingData()
        qrString = qr
        qrServiceName = service
        qrPassword = password
        qrStatus = .waitingForScan
        
        // Start browsing for the pairing service
        pairingBrowser.stopBrowsing()
        pairingBrowser.onServiceResolved = { [self] ip, port in
            handleDeviceDiscovered(ip: ip, port: port)
        }
        pairingBrowser.startBrowsing(for: service)
    }
    
    private func handleDeviceDiscovered(ip: String, port: UInt16) {
        qrStatus = .pairing
        pairingBrowser.stopBrowsing()
        
        Task {
            // Pair using the generated password
            let (pairSuccess, pairMessage) = await ADBManager.pairDevice(
                ip: ip,
                port: String(port),
                code: qrPassword
            )
            
            guard pairSuccess else {
                await MainActor.run {
                    qrStatus = .failed(pairMessage)
                }
                return
            }
            
            // Give Android a moment to advertise the connect service
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            
            // After pairing, the device may auto-connect via mDNS.
            // Check adb devices first — if the device is already connected, we're done.
            let connected = await ADBManager.isDeviceConnected()
            if connected, let serial = ADBManager.activeDeviceSerial, serial.contains(ip) {
                await MainActor.run {
                    qrStatus = .paired
                    deviceManager.detectDeviceAfterWirelessConnect()
                    onConnected?()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        dismiss()
                    }
                }
                return
            }
            
            // Try connecting with adb connect on common ports
            for tryPort in [String(port), "5555", "37265", "42000", "41011"] {
                let (s, _) = await deviceManager.connectWirelessly(ip: ip, port: tryPort)
                if s {
                    await MainActor.run {
                        qrStatus = .paired
                        onConnected?()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            dismiss()
                        }
                    }
                    return
                }
            }
            
            // Pairing succeeded but no connect port found
            await MainActor.run {
                qrStatus = .failed("Paired ✅ but could not auto-connect. Use Manual tab to connect with the port shown under Wireless Debugging.")
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
