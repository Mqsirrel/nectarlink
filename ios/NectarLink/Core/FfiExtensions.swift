// SPDX-License-Identifier: MPL-2.0

import Foundation

extension Link {
    public var isConnected: Bool {
        if case .online = self {
            return true
        }
        return false
    }

    public var badgeText: String {
        switch self {
        case .online(let relayed, let usb, let rttMs):
            if usb { return "USB (\(rttMs)ms)" }
            if relayed { return "Relay (\(rttMs)ms)" }
            return "LAN (\(rttMs)ms)"
        case .connecting:
            return "Connecting…"
        case .offline(let lastSeen):
            if let lastSeen = lastSeen {
                let date = Date(timeIntervalSince1970: TimeInterval(lastSeen))
                let formatter = RelativeDateTimeFormatter()
                return "Offline · \(formatter.localizedString(for: date, relativeTo: Date()))"
            }
            return "Offline"
        }
    }
}

extension PhotoThumb {
    public var jpeg: Data {
        data
    }
}

extension FileToSend {
    public var name: String {
        switch self {
        case .fd(let name, _, _):
            return name
        case .path(let name, _, _):
            return name
        }
    }
}

extension LocalSendPeer: Identifiable {
    public var host: String { ip }
    public var protocolHttps: Bool { self.protocol.lowercased() == "https" }
}
