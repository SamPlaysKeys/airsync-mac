//
//  ScrcpyWindowMonitor.swift
//  AirSync
//
//  Created by Sameera Sandakelum on 2025-08-14.
//

import AppKit
import Foundation
import SwiftUI

class ScrcpyWindowMonitor: NSObject, ObservableObject {
    static let shared = ScrcpyWindowMonitor()
    
    private var overlayWindows: [String: ScrcpyOverlayWindow] = [:] // Use window title as key
    private var monitoringTimer: Timer?
    private var expectedDeviceName: String?
    private var currentPackage: String?
    
    override init() {
        super.init()
        setupWindowObservers()
    }
    
    deinit {
        stopMonitoring()
        NSNotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - Public Methods
    
    func startMonitoring(deviceName: String, package: String? = nil) {
        expectedDeviceName = deviceName
        currentPackage = package
        
        // Start periodic window monitoring
        monitoringTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.scanForScrcpyWindows()
        }
    }
    
    func stopMonitoring() {
        monitoringTimer?.invalidate()
        monitoringTimer = nil
        
        // Clean up all overlay windows
        for overlay in overlayWindows.values {
            overlay.close()
        }
        overlayWindows.removeAll()
        
        expectedDeviceName = nil
        currentPackage = nil
    }
    
    // MARK: - Private Methods
    
    private func setupWindowObservers() {
        NSNotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidClose(_:)),
            name: NSWindow.willCloseNotification,
            object: nil
        )
    }
    
    @objc private func windowDidClose(_ notification: Notification) {
        // Clean up any closed overlay windows
        overlayWindows = overlayWindows.filter { _, overlay in
            overlay.isVisible
        }
    }
    
    private func scanForScrcpyWindows() {
        guard let expectedName = expectedDeviceName else { return }
        
        let windows = NSApplication.shared.windows
        let runningApps = NSWorkspace.shared.runningApplications
        
        // Look for scrcpy process
        let scrcpyApps = runningApps.filter { app in
            app.localizedName?.lowercased().contains("scrcpy") == true ||
            app.bundleIdentifier?.contains("scrcpy") == true
        }
        
        for scrcpyApp in scrcpyApps {
            // Get windows for this app
            let appWindows = getWindowsForApp(scrcpyApp)
            
            for windowInfo in appWindows {
                if let windowTitle = windowInfo["kCGWindowName"] as? String,
                   windowTitle.contains(expectedName) {
                    
                    // Check if we already have an overlay for a window at this position
                    let bounds = extractWindowBounds(from: windowInfo)
                    if !hasOverlayAtBounds(bounds) {
                        createOverlayForWindow(bounds: bounds, title: windowTitle)
                    }
                }
            }
        }
    }
    
    private func getWindowsForApp(_ app: NSRunningApplication) -> [[String: Any]] {
        let options = CGWindowListOption(arrayLiteral: [.optionOnScreenOnly, .excludeDesktopElements])
        let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID)
        
        guard let windows = windowList as? [[String: Any]] else { return [] }
        
        return windows.filter { windowInfo in
            if let windowPID = windowInfo["kCGWindowOwnerPID"] as? Int32 {
                return windowPID == app.processIdentifier
            }
            return false
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
    
    private func hasOverlayAtBounds(_ bounds: CGRect) -> Bool {
        return overlayWindows.values.contains { overlay in
            overlay.scrcpyWindowBounds.equalTo(bounds)
        }
    }
    
    private func createOverlayForWindow(bounds: CGRect, title: String) {
        let overlay = ScrcpyOverlayWindow(
            scrcpyBounds: bounds,
            deviceName: expectedDeviceName ?? "",
            package: currentPackage
        )
        
        overlay.show()
        
        // Store reference using window title as key
        overlayWindows[title] = overlay
    }
}
