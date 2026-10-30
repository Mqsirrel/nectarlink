// SPDX-License-Identifier: MPL-2.0

import CallKit
import Foundation
import UIKit

/// Observes live phone/VoIP call state via `CXCallObserver` and initiates
/// outgoing phone calls via the system `tel://` handler.
public final class IosCalls: NSObject, CXCallObserverDelegate, @unchecked Sendable {
    public static let shared = IosCalls()

    public var onCallChanged: (@Sendable (Call) -> Void)?

    private let observer = CXCallObserver()
    private let lock = NSLock()
    private var activeStartTimes: [UUID: Int64] = [:]

    private override init() {
        super.init()
        observer.setDelegate(self, queue: .main)
    }

    public func callObserver(_ callObserver: CXCallObserver, callChanged call: CXCall) {
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000.0)
        let phase: CallPhase
        var sinceMs: Int64? = nil
        var missed = false

        lock.lock()
        if call.hasEnded {
            phase = .ended
            let wasConnected = activeStartTimes.removeValue(forKey: call.uuid) != nil
            missed = !call.isOutgoing && !call.hasConnected && !wasConnected
        } else if call.hasConnected {
            phase = .active
            let start = activeStartTimes[call.uuid] ?? nowMs
            activeStartTimes[call.uuid] = start
            sinceMs = start
        } else {
            phase = .ringing
        }
        lock.unlock()

        let callModel = Call(
            id: call.uuid.uuidString,
            state: phase,
            incoming: !call.isOutgoing,
            number: nil,
            name: nil,
            photo: nil,
            missed: missed,
            since: sinceMs,
            controls: nil
        )
        onCallChanged?(callModel)
    }

    public func dial(number: String) -> Bool {
        let cleaned = number.filter { $0.isNumber || "+*#,".contains($0) }
        guard !cleaned.isEmpty, let url = URL(string: "tel://\(cleaned)") else {
            return false
        }
        DispatchQueue.main.async {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        }
        return true
    }
}
