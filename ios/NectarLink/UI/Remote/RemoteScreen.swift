import CoreMotion
import SwiftUI
import UIKit

/// Gyroscope Air Mouse controller backed by `CMMotionManager`.
final class AirMouseController: ObservableObject {
    @Published private(set) var isActive = false
    private let motionManager = CMMotionManager()
    var onDelta: ((Float, Float) -> Void)?

    func start() {
        guard motionManager.isDeviceMotionAvailable, !isActive else { return }
        isActive = true
        motionManager.deviceMotionUpdateInterval = 1.0 / 60.0
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let rate = motion?.rotationRate else { return }
            let dx = Float(-rate.z * 18.0)
            let dy = Float(-rate.x * 18.0)
            if abs(dx) > 0.25 || abs(dy) > 0.25 {
                self.onDelta?(dx, dy)
            }
        }
    }

    func stop() {
        guard isActive else { return }
        motionManager.stopDeviceMotionUpdates()
        isActive = false
    }
}

struct RemoteScreen: View {
    @ObservedObject var store: CoreStore
    @ObservedObject var theme: ThemeManager
    @Environment(\.colorScheme) private var systemScheme

    enum RemoteTab: String, CaseIterable, Identifiable {
        case trackpad = "Trackpad"
        case presentation = "Presenter"
        case keyboard = "Keyboard"
        var id: String { rawValue }
    }

    @State private var tab: RemoteTab = .trackpad
    @StateObject private var airMouse = AirMouseController()
    @State private var lastDragLocation: CGPoint?
    @State private var lastScrollY: CGFloat?
    @State private var typedText = ""
    @State private var activeMods: Set<String> = []

    private var palette: Palette {
        theme.palette(for: systemScheme)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                palette.surface.ignoresSafeArea()
                if theme.family == .hive {
                    HiveCombView(
                        palette: palette,
                        isDark: theme.isDark(systemScheme: systemScheme),
                        isConnected: store.activePc?.link.isConnected ?? false
                    )
                }

                VStack(spacing: 14) {
                    Picker("Remote Mode", selection: $tab) {
                        ForEach(RemoteTab.allCases) { item in
                            Text(item.rawValue).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 18)

                    switch tab {
                    case .trackpad:
                        trackpadView
                    case .presentation:
                        presentationView
                    case .keyboard:
                        keyboardView
                    }
                }
                .padding(.top, 8)
                .padding(.bottom, 96)
            }
            .navigationTitle(store.activePc.map { "Remote • \($0.info.name)" } ?? "Remote Input")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                airMouse.onDelta = { dx, dy in
                    store.remoteMove(dx: dx, dy: dy)
                }
            }
            .onDisappear {
                airMouse.stop()
            }
        }
    }

    // MARK: - Trackpad & Air Mouse

    private var trackpadView: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                // Main Trackpad Surface
                GeometryReader { _ in
                    ZStack {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(palette.surfaceContainer)
                            .overlay(
                                RoundedRectangle(cornerRadius: 24, style: .continuous)
                                    .strokeBorder(palette.outlineVariant.opacity(0.45), lineWidth: 1)
                            )

                        VStack(spacing: 8) {
                            Image(systemName: airMouse.isActive ? "gyroscope" : "hand.point.up.left")
                                .font(.system(size: 32))
                                .foregroundStyle(palette.primary.opacity(0.55))
                            Text(airMouse.isActive ? "Air Mouse Active — Move iPhone in air" : "Slide to move cursor • Tap to click")
                                .font(.caption)
                                .foregroundStyle(palette.onSurfaceVariant.opacity(0.75))
                        }
                    }
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                if let prev = lastDragLocation {
                                    let dx = Float(value.location.x - prev.x) * 1.65
                                    let dy = Float(value.location.y - prev.y) * 1.65
                                    if abs(dx) > 0.1 || abs(dy) > 0.1 {
                                        store.remoteMove(dx: dx, dy: dy)
                                    }
                                }
                                lastDragLocation = value.location
                            }
                            .onEnded { value in
                                let dist = hypot(
                                    value.location.x - value.startLocation.x,
                                    value.location.y - value.startLocation.y
                                )
                                if dist < 6 {
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    store.remoteButton(button: "left", action: "click")
                                }
                                lastDragLocation = nil
                            }
                    )
                }

                // Vertical Scroll Strip
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(palette.surfaceContainerHigh)
                    VStack {
                        Image(systemName: "chevron.up")
                        Spacer()
                        Image(systemName: "arrow.up.and.down")
                        Spacer()
                        Image(systemName: "chevron.down")
                    }
                    .font(.caption2)
                    .foregroundStyle(palette.onSurfaceVariant)
                    .padding(.vertical, 16)
                }
                .frame(width: 44)
                .gesture(
                    DragGesture(minimumDistance: 1)
                        .onChanged { value in
                            if let prevY = lastScrollY {
                                let dy = Float(value.location.y - prevY) * 0.18
                                if abs(dy) > 0.05 {
                                    store.remoteScroll(dx: 0, dy: dy, fast: true)
                                }
                            }
                            lastScrollY = value.location.y
                        }
                        .onEnded { _ in
                            lastScrollY = nil
                        }
                )
            }
            .padding(.horizontal, 18)

            // Mouse Buttons & Air Mouse Toggle
            HStack(spacing: 10) {
                mouseButton(label: "Left Click", buttonName: "left")
                mouseButton(label: "Middle", buttonName: "middle")
                mouseButton(label: "Right Click", buttonName: "right")

                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    if airMouse.isActive {
                        airMouse.stop()
                    } else {
                        airMouse.start()
                    }
                } label: {
                    Image(systemName: "gyroscope")
                        .font(.title3.weight(.semibold))
                        .frame(width: 48, height: 48)
                        .background(
                            airMouse.isActive ? palette.primary : palette.surfaceContainerHigh,
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                        )
                        .foregroundStyle(airMouse.isActive ? palette.onPrimary : palette.onSurface)
                }
            }
            .padding(.horizontal, 18)
        }
    }

    private func mouseButton(label: String, buttonName: String) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            store.remoteButton(button: buttonName, action: "click")
        } label: {
            Text(label)
                .font(.caption.weight(.semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(palette.surfaceContainerHigh, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .foregroundStyle(palette.onSurface)
        }
    }

    // MARK: - Presentation Remote & Laser Pointer

    private var presentationView: some View {
        VStack(spacing: 14) {
            HStack(spacing: 14) {
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    store.remoteSlide(action: "previous")
                } label: {
                    VStack(spacing: 8) {
                        Image(systemName: "arrow.left.circle.fill")
                            .font(.system(size: 36))
                        Text("Previous Slide")
                            .font(.subheadline.weight(.bold))
                    }
                    .frame(maxWidth: .infinity, minHeight: 110)
                    .background(palette.surfaceContainerHigh, in: RoundedRectangle(cornerRadius: 20))
                    .foregroundStyle(palette.onSurface)
                }

                Button {
                    UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
                    store.remoteSlide(action: "next")
                } label: {
                    VStack(spacing: 8) {
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.system(size: 36))
                        Text("Next Slide")
                            .font(.subheadline.weight(.bold))
                    }
                    .frame(maxWidth: .infinity, minHeight: 110)
                    .background(palette.primary, in: RoundedRectangle(cornerRadius: 20))
                    .foregroundStyle(palette.onPrimary)
                }
            }

            HStack(spacing: 10) {
                slideControlBtn("Start Show", icon: "play.fill", action: "start")
                slideControlBtn("Black Screen", icon: "rectangle.fill", action: "black")
                slideControlBtn("End Show", icon: "stop.fill", action: "stop")
            }

            // Laser Pointer Pad
            GeometryReader { geo in
                ZStack {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(palette.surfaceContainer)
                        .overlay(
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .strokeBorder(Color.red.opacity(0.45), lineWidth: 1.5)
                        )
                    VStack(spacing: 6) {
                        Image(systemName: "scope")
                            .font(.title)
                            .foregroundStyle(.red)
                        Text("Hold & drag to shine Laser Pointer on PC")
                            .font(.caption)
                            .foregroundStyle(palette.onSurfaceVariant)
                    }
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let x = Float(max(0, min(1, value.location.x / max(1, geo.size.width))))
                            let y = Float(max(0, min(1, value.location.y / max(1, geo.size.height))))
                            store.remoteLaser(on: true, x: x, y: y)
                        }
                        .onEnded { _ in
                            store.remoteLaser(on: false, x: 0.5, y: 0.5)
                        }
                )
            }
        }
        .padding(.horizontal, 18)
    }

    private func slideControlBtn(_ title: String, icon: String, action: String) -> some View {
        Button {
            store.remoteSlide(action: action)
        } label: {
            Label(title, systemImage: icon)
                .font(.caption.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(palette.surfaceContainerHigh, in: RoundedRectangle(cornerRadius: 12))
                .foregroundStyle(palette.onSurface)
        }
    }

    // MARK: - Remote Keyboard

    private var keyboardView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Type on PC")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(palette.onSurface)

                HStack(spacing: 8) {
                    TextField("Type text to send to PC…", text: $typedText)
                        .padding(12)
                        .background(palette.surfaceContainerHigh, in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(palette.onSurface)
                        .onSubmit {
                            sendTypedText()
                        }

                    Button {
                        sendTypedText()
                    } label: {
                        Image(systemName: "paperplane.fill")
                            .padding(12)
                            .background(palette.primary, in: RoundedRectangle(cornerRadius: 12))
                            .foregroundStyle(palette.onPrimary)
                    }
                }

                Text("Modifiers")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(palette.onSurfaceVariant)

                HStack(spacing: 8) {
                    ForEach(["ctrl", "alt", "shift", "win"], id: \.self) { mod in
                        let isSelected = activeMods.contains(mod)
                        Button {
                            if isSelected {
                                activeMods.remove(mod)
                            } else {
                                activeMods.insert(mod)
                            }
                        } label: {
                            Text(mod.uppercased())
                                .font(.caption.weight(.bold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(
                                    isSelected ? palette.primary : palette.surfaceContainerHigh,
                                    in: RoundedRectangle(cornerRadius: 10)
                                )
                                .foregroundStyle(isSelected ? palette.onPrimary : palette.onSurface)
                        }
                    }
                }

                Text("Function & Navigation Keys")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(palette.onSurfaceVariant)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    specialKeyButton("Esc", key: "Escape")
                    specialKeyButton("Tab", key: "Tab")
                    specialKeyButton("Backspace", key: "BackSpace")
                    specialKeyButton("Enter", key: "Return")
                    specialKeyButton("↑", key: "Up")
                    specialKeyButton("↓", key: "Down")
                    specialKeyButton("←", key: "Left")
                    specialKeyButton("→", key: "Right")
                    specialKeyButton("Space", key: "space")
                    specialKeyButton("Home", key: "Home")
                    specialKeyButton("End", key: "End")
                    specialKeyButton("Del", key: "Delete")
                }
            }
            .padding(18)
            .nectarCard(palette: palette, family: theme.family, cornerRadius: 22)
            .padding(.horizontal, 18)
        }
    }

    private func sendTypedText() {
        guard !typedText.isEmpty else { return }
        store.remoteText(typedText)
        typedText = ""
    }

    private func specialKeyButton(_ label: String, key: String) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            store.remoteKey(key: key, mods: Array(activeMods))
            activeMods.removeAll()
        } label: {
            Text(label)
                .font(.caption.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(palette.surfaceContainerHigh, in: RoundedRectangle(cornerRadius: 10))
                .foregroundStyle(palette.onSurface)
        }
    }
}
