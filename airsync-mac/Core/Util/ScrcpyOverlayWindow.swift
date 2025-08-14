//
//  ScrcpyOverlayWindow.swift
//  AirSync
//
//  Created by Sameera Sandakelum on 2025-08-14.
//

import AppKit
import SwiftUI

class ScrcpyOverlayWindow: NSWindow {
    private(set) var scrcpyWindowBounds: CGRect
    private let deviceName: String
    private let package: String?
    private var overlayController: NSHostingController<ScrcpyOverlayView>?
    
    init(scrcpyBounds: CGRect, deviceName: String, package: String?) {
        self.scrcpyWindowBounds = scrcpyBounds
        self.deviceName = deviceName
        self.package = package
        
        // Position overlay in the top-right corner of the scrcpy window title bar
        let overlayWidth: CGFloat = 120
        let overlayHeight: CGFloat = 32
        let overlayX = scrcpyBounds.maxX - overlayWidth - 80 // Leave space for window controls
        let overlayY = scrcpyBounds.maxY - overlayHeight - 8  // Position in title bar
        
        let overlayFrame = NSRect(
            x: overlayX,
            y: overlayY,
            width: overlayWidth,
            height: overlayHeight
        )
        
        super.init(
            contentRect: overlayFrame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        
        setupWindow()
        setupContent()
        setupObservers()
    }
    
    private func setupWindow() {
        // Make window transparent and floating
        backgroundColor = NSColor.clear
        isOpaque = false
        level = .floating
        hasShadow = false
        ignoresMouseEvents = false
        
        // Allow window to appear over full-screen apps
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        
        // Prevent window from becoming key or main
        hidesOnDeactivate = false
        canHide = false
    }
    
    private func setupContent() {
        let overlayView = ScrcpyOverlayView(
            deviceName: deviceName,
            package: package,
            onOpenOnDevice: { [weak self] in
                self?.handleOpenOnDevice()
            }
        )
        
        overlayController = NSHostingController(rootView: overlayView)
        contentView = overlayController?.view
        
        // Make the hosting view transparent
        overlayController?.view.wantsLayer = true
        overlayController?.view.layer?.backgroundColor = NSColor.clear.cgColor
    }
    
    private func setupObservers() {
        // Monitor for changes in scrcpy window position/size
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(updatePosition),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        
        // Start periodic position updates to track scrcpy window
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] timer in
            guard self?.isVisible == true else {
                timer.invalidate()
                return
            }
            self?.updateScrcpyWindowBounds()
        }
    }
    
    @objc private func updatePosition() {
        updateScrcpyWindowBounds()
    }
    
    private func updateScrcpyWindowBounds() {
        // Query current scrcpy window bounds
        let options = CGWindowListOption(arrayLiteral: [.optionOnScreenOnly, .excludeDesktopElements])
        let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID)
        
        guard let windows = windowList as? [[String: Any]] else { return }
        
        // Find scrcpy window with matching device name
        for windowInfo in windows {
            if let windowTitle = windowInfo["kCGWindowName"] as? String,
               windowTitle.contains(deviceName) {
                
                let newBounds = extractWindowBounds(from: windowInfo)
                if !newBounds.equalTo(scrcpyWindowBounds) {
                    scrcpyWindowBounds = newBounds
                    repositionOverlay()
                }
                return
            }
        }
        
        // If scrcpy window not found, hide overlay
        if isVisible {
            orderOut(nil)
        }
    }
    
    private func extractWindowBounds(from windowInfo: [String: Any]) -> CGRect {
        guard let boundsDict = windowInfo["kCGWindowBounds"] as? [String: Any],
              let x = boundsDict["X"] as? CGFloat,
              let y = boundsDict["Y"] as? CGFloat,
              let width = boundsDict["Width"] as? CGFloat,
              let height = boundsDict["Height"] as? CGFloat else {
            return CGRect.zero
        }
        
        return CGRect(x: x, y: y, width: width, height: height)
    }
    
    private func repositionOverlay() {
        let overlayWidth: CGFloat = 120
        let overlayHeight: CGFloat = 32
        let overlayX = scrcpyWindowBounds.maxX - overlayWidth - 80
        let overlayY = scrcpyWindowBounds.maxY - overlayHeight - 8
        
        let newFrame = NSRect(
            x: overlayX,
            y: overlayY,
            width: overlayWidth,
            height: overlayHeight
        )
        
        setFrame(newFrame, display: true, animate: false)
    }
    
    private func handleOpenOnDevice() {
        guard let packageName = package else {
            // If no specific package, try to get current foreground app
            ADBConnector.getCurrentForegroundApp { [weak self] detectedPackage in
                if let detectedPackage = detectedPackage, !detectedPackage.isEmpty {
                    ADBConnector.launchAppOnDevice(package: detectedPackage)
                } else {
                    // Show error or fallback action
                    DispatchQueue.main.async {
                        self?.showNoAppError()
                    }
                }
            }
            return
        }
        
        ADBConnector.launchAppOnDevice(package: packageName)
    }
    
    private func showNoAppError() {
        let alert = NSAlert()
        alert.messageText = "No App Detected"
        alert.informativeText = "Could not detect the current app on your device. Make sure an app is open in the mirror."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
    
    func show() {
        makeKeyAndOrderFront(nil)
    }
    
    override func close() {
        NotificationCenter.default.removeObserver(self)
        super.close()
    }
    
    // Override to prevent the window from becoming key
    override var canBecomeKey: Bool {
        return false
    }
    
    override var canBecomeMain: Bool {
        return false
    }
}

// MARK: - SwiftUI Overlay View

struct ScrcpyOverlayView: View {
    let deviceName: String
    let package: String?
    let onOpenOnDevice: () -> Void
    
    @State private var isHovered = false
    @State private var isPressed = false
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "iphone.and.arrow.forward")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.primary)
            
            Text("Open on device")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.primary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(.regularMaterial)
                .opacity(isHovered ? 0.9 : 0.7)
        )
        .scaleEffect(isPressed ? 0.95 : 1.0)
        .animation(.easeInOut(duration: 0.1), value: isPressed)
        .animation(.easeInOut(duration: 0.2), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.1)) {
                isPressed = true
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.easeInOut(duration: 0.1)) {
                    isPressed = false
                }
                onOpenOnDevice()
            }
        }
        .help("Open this app on your device")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    ScrcpyOverlayView(
        deviceName: "Test Device",
        package: "com.example.app",
        onOpenOnDevice: {}
    )
    .frame(width: 120, height: 32)
}
