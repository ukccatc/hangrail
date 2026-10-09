import SwiftUI

enum Layout {
    static let panelHeight: CGFloat = 210
    static let ropeTop: CGFloat = 10
    /// Kept for capacity: roughly how many cards fit across the screen.
    static let spacing: CGFloat = 174
    static let cardWidth: CGFloat = 150
    static let pinAbove: CGFloat = 9.5
    /// Gap between default-centered cards, in place units (0…1).
    static let placeStep: CGFloat = 0.14
    /// Keep auto-placed cards away from the rail ends.
    static let placeInset: CGFloat = 0.12

    /// Soft ribbon sag — deeper than a wire, still subtle across a wide display.
    static func sag(width: CGFloat) -> CGFloat { min(42, width * 0.026) }

    static func ropeY(x: CGFloat, width: CGFloat) -> CGFloat {
        guard width > 0 else { return ropeTop }
        let f = x / width
        return ropeTop + 4 * sag(width: width) * f * (1 - f)
    }

    /// Left and right padding so a card never hangs off-screen.
    static func margin(for width: CGFloat) -> CGFloat {
        max(cardWidth / 2 + 40, width * 0.06)
    }

    static func usableWidth(_ width: CGFloat) -> CGFloat {
        max(1, width - 2 * margin(for: width))
    }

    /// Convert a 0…1 place on the rail into a panel x coordinate.
    static func x(place: CGFloat, width: CGFloat) -> CGFloat {
        let m = margin(for: width)
        return m + min(1, max(0, place)) * usableWidth(width)
    }

    static func place(x: CGFloat, width: CGFloat) -> CGFloat {
        let m = margin(for: width)
        return min(1, max(0, (x - m) / usableWidth(width)))
    }

    /// Legacy centered row, used only to seed places when restoring old saves.
    static func x(index: Int, count: Int, width: CGFloat) -> CGFloat {
        let total = CGFloat(max(count - 1, 0)) * spacing
        return width / 2 - total / 2 + CGFloat(index) * spacing
    }
}

struct LineView: View {
    @ObservedObject var line: Line

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            ZStack(alignment: .topLeading) {
                Rope(width: width, highlighted: line.receivingDrop)

                if line.items.isEmpty {
                    Hint()
                        .position(x: width / 2, y: Layout.ropeY(x: width / 2, width: width) + 34)
                        .transition(.opacity)
                }

                if let id = line.reorderID, let item = line.items.first(where: { $0.id == id }) {
                    let x = Layout.x(place: item.place, width: width)
                    let y = Layout.ropeY(x: x, width: width)
                    // Landing mark on the rail: where the clip will grip again.
                    Capsule()
                        .fill(HangTheme.amber)
                        .frame(width: 32, height: 4)
                        .shadow(color: HangTheme.amber.opacity(0.7), radius: 4, y: 0)
                        .position(x: x, y: y)
                        .allowsHitTesting(false)
                }

                ForEach(line.items) { item in
                    let sliding = line.reorderID == item.id
                    let x = Layout.x(place: item.place, width: width)
                    let ropeY = Layout.ropeY(x: x, width: width)
                    PeggedView(item: item, line: line)
                        .frame(width: Layout.cardWidth, height: Layout.panelHeight - ropeY, alignment: .top)
                        // Lift off the rail while sliding so the clip reads as unclipped.
                        .scaleEffect(sliding ? 1.08 : 1, anchor: .top)
                        .offset(y: sliding ? -12 : 0)
                        .position(x: x, y: ropeY - Layout.pinAbove + (Layout.panelHeight - ropeY) / 2)
                        .zIndex(sliding ? 2 : Double(item.place))
                        .animation(sliding ? nil : .spring(response: 0.28, dampingFraction: 0.86), value: item.place)
                }

                // In front of the cards, but it only claims hits while an image
                // file is being dragged in, so clicks still reach the photos.
                DropRail(line: line)
                    .frame(width: width, height: Layout.panelHeight)
            }
            .animation(.spring(response: 0.55, dampingFraction: 0.78), value: line.items.map(\.id))
            .animation(.easeInOut(duration: 0.3), value: line.items.isEmpty)
            // Tucked away, the whole line waits above the top edge and slides
            // out from under the menu bar, the way an auto-hiding Dock does.
            .offset(y: line.revealed ? 0 : -(Layout.panelHeight + 12))
            .animation(line.revealed ? .spring(response: 0.42, dampingFraction: 0.82)
                                     : .easeIn(duration: 0.22), value: line.revealed)
        }
        .onPreferenceChange(HitRectsKey.self) { rects in
            line.hitRects = rects
        }
    }
}

private struct Hint: View {
    var body: some View {
        Text(L("Take a screenshot or drag one here"))
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.regularMaterial, in: Capsule())
    }
}

/// Blade Runner 2049 ribbon: night-slate tape, amber stitch, cyan drop glow.
struct Rope: View {
    let width: CGFloat
    var highlighted = false

    private var path: Path {
        Path { p in
            let top = Layout.ropeTop
            p.move(to: CGPoint(x: -24, y: top))
            p.addQuadCurve(
                to: CGPoint(x: width + 24, y: top),
                control: CGPoint(x: width / 2, y: top + 2 * Layout.sag(width: width)))
        }
    }

    var body: some View {
        ZStack {
            if highlighted {
                path.stroke(HangTheme.cyan.opacity(0.55), lineWidth: 16)
                    .blur(radius: 7)
                path.stroke(HangTheme.amber.opacity(0.35), lineWidth: 10)
                    .blur(radius: 4)
            }
            path.stroke(Color.black.opacity(0.4), lineWidth: 12)
                .offset(y: 4.5)
                .blur(radius: 4.5)
            // Night body — desert dusk over Los Angeles blackout.
            path.stroke(
                LinearGradient(
                    colors: [HangTheme.mist, HangTheme.slate, HangTheme.night],
                    startPoint: .top,
                    endPoint: .bottom),
                style: StrokeStyle(lineWidth: 8, lineCap: .round))
            // Cool specular, like wet neon on steel.
            path.stroke(HangTheme.cyanGlow.opacity(0.22), lineWidth: 1.4)
                .offset(y: -2.4)
            // Amber dashed stitch — the 2049 signature.
            path.stroke(HangTheme.amber.opacity(0.7),
                        style: StrokeStyle(lineWidth: 0.9, lineCap: .round, dash: [3, 4]))
                .offset(y: 0.2)
            path.stroke(HangTheme.amberDeep.opacity(0.35),
                        style: StrokeStyle(lineWidth: 0.7, lineCap: .round, dash: [3, 4]))
                .offset(y: 1.6)
            if highlighted {
                path.stroke(HangTheme.cyan.opacity(0.95), lineWidth: 1.8)
            }
        }
        .mask(
            LinearGradient(stops: [
                .init(color: .clear, location: 0),
                .init(color: .black, location: 0.015),
                .init(color: .black, location: 0.985),
                .init(color: .clear, location: 1),
            ], startPoint: .leading, endPoint: .trailing)
        )
        .allowsHitTesting(false)
        .animation(.easeOut(duration: 0.15), value: highlighted)
    }
}

struct HitRectsKey: PreferenceKey {
    static var defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}
