import AVFoundation
import SwiftUI
import UIKit

struct CameraPreviewLayerView: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {
        uiView.previewLayer.session = session
    }

    final class PreviewUIView: UIView {
        override class var layerClass: AnyClass {
            AVCaptureVideoPreviewLayer.self
        }

        var previewLayer: AVCaptureVideoPreviewLayer {
            layer as! AVCaptureVideoPreviewLayer
        }
    }
}

struct WebcamScreen: View {
    @ObservedObject var store: CoreStore
    @ObservedObject var theme: ThemeManager
    @ObservedObject private var webcam = WebcamStreamer.shared
    @Environment(\.colorScheme) private var systemScheme

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
                        isConnected: webcam.isStreaming
                    )
                }

                VStack(spacing: 16) {
                    // Live Camera Preview Card
                    ZStack(alignment: .topLeading) {
                        if webcam.isStreaming {
                            CameraPreviewLayerView(session: webcam.captureSession)
                                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                        } else {
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .fill(palette.surfaceContainer)
                                .overlay(
                                    VStack(spacing: 12) {
                                        Image(systemName: "video.fill")
                                            .font(.system(size: 46))
                                            .foregroundStyle(palette.primary)
                                        Text("Use iPhone as PC Webcam")
                                            .font(.headline)
                                            .foregroundStyle(palette.onSurface)
                                        Text("Hardware-encoded H.264 / HEVC low-latency camera stream")
                                            .font(.caption)
                                            .foregroundStyle(palette.onSurfaceVariant)
                                    }
                                )
                        }

                        if webcam.isStreaming {
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(Color.red)
                                    .frame(width: 8, height: 8)
                                Text("LIVE • \(webcam.width)×\(webcam.height) @ \(webcam.fps)fps")
                                    .font(.caption2.monospacedDigit().weight(.bold))
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(.ultraThinMaterial, in: Capsule())
                            .foregroundStyle(.white)
                            .padding(14)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 310)

                    // Resolution Picker & Controls
                    VStack(spacing: 14) {
                        HStack {
                            Text("Resolution")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(palette.onSurfaceVariant)
                            Spacer()
                            HStack(spacing: 8) {
                                resolutionPill(title: "720p", height: 720)
                                resolutionPill(title: "1080p", height: 1080)
                                resolutionPill(title: "4K", height: 2160)
                            }
                        }

                        if webcam.isStreaming {
                            HStack(spacing: 12) {
                                Image(systemName: "minus.magnifyingglass")
                                    .foregroundStyle(palette.onSurfaceVariant)
                                Slider(
                                    value: Binding(
                                        get: { Double(webcam.zoomRatio) },
                                        set: { webcam.setZoom(Float($0)) }
                                    ),
                                    in: 1.0...Double(max(2.0, webcam.maxZoomRatio))
                                )
                                .tint(palette.primary)
                                Text(String(format: "%.1fx", webcam.zoomRatio))
                                    .font(.caption.monospacedDigit().weight(.bold))
                                    .foregroundStyle(palette.primary)
                            }
                        }

                        HStack(spacing: 12) {
                            Button {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                webcam.switchCamera()
                            } label: {
                                Label(
                                    webcam.cameraFacing == "front" ? "Front Lens" : "Back Lens",
                                    systemImage: "arrow.triangle.2.circlepath.camera.fill"
                                )
                                .font(.caption.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(palette.surfaceContainerHigh, in: RoundedRectangle(cornerRadius: 14))
                                .foregroundStyle(palette.onSurface)
                            }

                            if webcam.hasTorch && webcam.cameraFacing == "back" {
                                Button {
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    webcam.setTorch(!webcam.torchEnabled)
                                } label: {
                                    Label(
                                        webcam.torchEnabled ? "Torch On" : "Torch Off",
                                        systemImage: webcam.torchEnabled ? "flashlight.on.fill" : "flashlight.off.fill"
                                    )
                                    .font(.caption.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(
                                        webcam.torchEnabled ? palette.primary : palette.surfaceContainerHigh,
                                        in: RoundedRectangle(cornerRadius: 14)
                                    )
                                    .foregroundStyle(webcam.torchEnabled ? palette.onPrimary : palette.onSurface)
                                }
                            }
                        }

                        if let pc = store.activePc {
                            Button {
                                Task {
                                    if webcam.isStreaming {
                                        webcam.stop(pcId: pc.id)
                                        if let node = store.node {
                                            try? await node.webcamStop(pcId: pc.id)
                                        }
                                    } else {
                                        let granted = await WebcamStreamer.requestPermission()
                                        guard granted else {
                                            store.showToast("Camera permission required")
                                            return
                                        }
                                        _ = webcam.start(
                                            pcId: pc.id,
                                            camera: webcam.cameraFacing,
                                            maxHeight: webcam.maxHeight,
                                            fps: webcam.fps,
                                            preferHevc: true
                                        )
                                    }
                                }
                            } label: {
                                Label(
                                    webcam.isStreaming ? "Stop Webcam Stream" : "Start Webcam for \(pc.info.name)",
                                    systemImage: webcam.isStreaming ? "stop.fill" : "video.badge.plus"
                                )
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(
                                    webcam.isStreaming ? Tokens.errorDark : palette.primary,
                                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                                )
                                .foregroundStyle(webcam.isStreaming ? Color.black : palette.onPrimary)
                            }
                        } else {
                            Text("Pair and connect a PC to stream your iPhone camera.")
                                .font(.caption)
                                .foregroundStyle(palette.onSurfaceVariant)
                        }
                    }
                    .padding(18)
                    .nectarCard(palette: palette, family: theme.family, cornerRadius: 22)

                    Spacer()
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)
                .padding(.bottom, 96)
            }
            .navigationTitle("PC Webcam")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func resolutionPill(title: String, height: UInt32) -> some View {
        let active = webcam.maxHeight == height
        return Button {
            webcam.setResolution(maxHeight: height, fps: webcam.fps)
        } label: {
            Text(title)
                .font(.caption.weight(.bold))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(active ? palette.primary : palette.surfaceContainerHigh, in: Capsule())
                .foregroundStyle(active ? palette.onPrimary : palette.onSurface)
        }
    }
}
