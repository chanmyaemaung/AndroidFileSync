//  DeviceManager.swift
//  (DEFINITIVE DETECTION FIX)
//

import Foundation
internal import Combine

@MainActor
class DeviceManager: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var isConnected = false
    @Published var isDetecting = true // Start in "detecting" state
    @Published var connectionType: ConnectionType = .none
    @Published var deviceName = "No Device"
    @Published var statusMessage = "Scanning for devices..."
    @Published var lastWirelessIP = ""
    
    private var adbAvailable = false
    
    enum ConnectionType: String {
        case none = "None"
        case usb = "USB"
        case wireless = "WiFi"
    }
    
    // MARK: - Core Logic
    
    func detectDevice() async {
        print("📱 DeviceManager: Starting device detection...")
        
        // Ensure UI shows "detecting" state
        if !isDetecting {
            await MainActor.run { 
                self.isDetecting = true 
                self.statusMessage = "Scanning for devices..."
            }
        }
        
        // Check for ADB devices (with timeout to prevent hanging)
        adbAvailable = await ADBManager.isDeviceConnected()
        print("📱 DeviceManager: ADB available = \(adbAvailable)")
        
        // Check if it's a wireless connection
        let isWireless = adbAvailable ? await ADBManager.isWirelessConnection() : false
        
        // Update the state on the main thread
        await MainActor.run {
            if adbAvailable {
                if isWireless {
                    self.connectionType = .wireless
                    self.deviceName = "Android Device"
                    self.statusMessage = "Connected via WiFi"
                } else {
                    self.connectionType = .usb
                    self.deviceName = "Android Device"
                    self.statusMessage = "Connected via USB"
                }
                self.isConnected = true
                print("📱 DeviceManager: Device connected (\(self.connectionType.rawValue))!")
            } else {
                self.connectionType = .none
                self.deviceName = "No Device"
                self.statusMessage = "No device detected. Please connect your device."
                self.isConnected = false
                print("📱 DeviceManager: No device found")
            }
            
            // Detection is complete, hide the initial loading screen
            self.isDetecting = false
        }
    }
    
    // MARK: - Wireless Connection (Android 11+)
    
    /// Pair and connect to an Android 11+ device wirelessly
    func pairAndConnect(ip: String, pairingPort: String, pairingCode: String, connectPort: String) async -> (Bool, String) {
        await MainActor.run {
            self.isDetecting = true
            self.statusMessage = "Pairing with device..."
        }
        
        // Step 1: Pair
        let (pairSuccess, pairMessage) = await ADBManager.pairDevice(ip: ip, port: pairingPort, code: pairingCode)
        
        guard pairSuccess else {
            await MainActor.run {
                self.isDetecting = false
                self.statusMessage = pairMessage
            }
            return (false, pairMessage)
        }
        
        await MainActor.run {
            self.statusMessage = "Paired! Connecting..."
        }
        
        // Step 2: Connect
        let (connectSuccess, connectMessage) = await ADBManager.connectWireless(ip: ip, port: connectPort)
        
        if connectSuccess {
            await MainActor.run {
                self.lastWirelessIP = ip
            }
            // Re-detect to update all state properly
            await detectDevice()
            return (true, "Connected wirelessly to \(ip)")
        } else {
            await MainActor.run {
                self.isDetecting = false
                self.statusMessage = connectMessage
            }
            return (false, connectMessage)
        }
    }
    
    /// Connect to a previously paired device
    func connectWirelessly(ip: String, port: String = "5555") async -> (Bool, String) {
        await MainActor.run {
            self.isDetecting = true
            self.statusMessage = "Connecting to \(ip)..."
        }
        
        let (success, message) = await ADBManager.connectWireless(ip: ip, port: port)
        
        if success {
            await MainActor.run {
                self.lastWirelessIP = ip
            }
            await detectDevice()
            return (true, message)
        } else {
            await MainActor.run {
                self.isDetecting = false
                self.statusMessage = message
            }
            return (false, message)
        }
    }
    
    /// Disconnect wireless device
    func disconnectWireless() async {
        let _ = await ADBManager.disconnectAllWireless()
        await MainActor.run {
            self.lastWirelessIP = ""
        }
        await detectDevice()
    }
    
    /// Re-detect device after QR pairing auto-connected it
    func detectDeviceAfterWirelessConnect() {
        Task {
            await detectDevice()
        }
    }
    
    func listFiles(path: String = "/sdcard") async throws -> [UnifiedFile] {
        guard adbAvailable else {
            throw NSError(
                domain: "DeviceManager",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "No device connected"]
            )
        }
        
        let adbFiles = try await ADBManager.listFiles(path: path)
        return adbFiles.map { UnifiedFile(from: $0) }
    }
    
    func getRealStoragePath() async -> String {
        return "/storage/emulated/0" // Default fallback
    }
}

