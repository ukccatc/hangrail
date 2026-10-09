import SwiftUI

/// One photo with its clothespin. All the charm lives here: it drops onto
/// the line, swings, sways with the breeze and falls when you pull it off.
struct PeggedView: View {
    let item: Pegged
    @ObservedObject var line: Line

    @State private var swing: Double = 0
    @State private var arrived = false
    @State private var hovering = false

    private var copied: Bool { line.copiedID == item.id }
    private var dragging: Bool { line.draggingID == item.id }
    private var reordering: Bool { line.reorderID == item.id }
    private var pressed: Bool { line.pressedID == item.id }

    var body: some View {
        VStack(spacing: -12) {
            Clothespin()
                .zIndex(1)
            card
        }
        .rotationEffect(.degrees(swing + item.tilt), anchor: .top)
        .offset(y: arrived ? 0 : -46)
        // The fall itself is drawn over the whole screen by CaptureFlight, so
        // the card here just steps aside at once.
        .opacity(item.falling || item.flying ? 0 : (arrived ? 1 : 0))
        .transaction { t in if item.falling { t.animation = nil } }
        .animation(.easeOut(duration: 0.16), value: item.flying)
        .onAppear(perform: arrive)
        .onChange(of: item.flying) { was, now in if was && !now { land() } }
        .onChange(of: line.gust) { _, _ in breeze() }
        .onChange(of: copied) { _, isCopied in if isCopied { nudge(3) } }
    }

    /// The photo fits inside the card area keeping its proportions, so the
    /// white border hugs it whether the screenshot is wide or tall.
    static func photoSize(for size: CGSize) -> CGSize {
        let maxW = Layout.cardWidth - 14, maxH: CGFloat = 104
        guard size.width > 0, size.height > 0 else { return CGSize(width: maxW, height: maxH) }
        let scale = min(maxW / size.width, maxH / size.height)
        return CGSize(width: size.width * scale, height: size.height * scale)
    }

    /// The card around the photo: the photo plus the glass inset.
    static func cardSize(for size: CGSize) -> CGSize {
        let p = photoSize(for: size)
        return CGSize(width: p.width + Frame.inset * 2, height: p.height + Frame.inset * 2)
    }

    static func cardSize(for item: Pegged) -> CGSize {
        if item.note != nil {
            return CGSize(width: NoteSlip.width, height: NoteSlip.height)
        }
        return cardSize(for: item.thumb.size)
    }

    /// Distance from the top of the hanging view (the clip) to the card.
    static let cardOffsetBelowTop: CGFloat = 26 - 12

    private var photoSize: CGSize { Self.photoSize(for: item.thumb.size) }

    private var card: some View {
        framed
            .shadow(color: .black.opacity(reordering ? 0.40 : (hovering ? 0.28 : 0.28)),
                    radius: reordering ? 18 : (hovering ? 12 : 8),
                    y: reordering ? 12 : (hovering ? 7 : 6))
            // Holding presses the photo in slowly, so a long press feels like
            // it is building up to something.
            .scaleEffect(pressed ? 0.95 : (hovering ? 1.035 : 1), anchor: .top)
            .animation(pressed ? .easeInOut(duration: 0.45) : .spring(response: 0.3, dampingFraction: 0.6), value: pressed)
            .opacity(dragging ? 0.45 : 1)
            .overlay(alignment: .topLeading) {
                // Drawn here, clicked through GrabView, which sits on top.
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.primary)
                    .frame(width: 20, height: 20)
                    .glassFrame(circle: true)
                    .padding(3)
                    .opacity(hovering && !dragging ? 1 : 0)
                    .scaleEffect(hovering ? 1 : 0.6)
                    .allowsHitTesting(false)
            }
            .overlay(alignment: .topTrailing) {
                if item.pinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(HangTheme.amber)
                        .padding(6)
                        .allowsHitTesting(false)
                }
            }
            .overlay(GrabArea(item: item, line: line))
            .overlay(alignment: .bottom) {
                if copied {
                    Label(L("Copied"), systemImage: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .glassFrame(capsule: true)
                        .offset(y: 16)
                        .transition(.opacity.combined(with: .offset(y: -4)))
                }
            }
            .animation(.easeOut(duration: 0.18), value: hovering)
            .animation(.easeOut(duration: 0.2), value: copied)
            .onHover { hovering = $0 }
            .background(
                GeometryReader { g in
                    Color.clear.preference(key: HitRectsKey.self,
                                           value: item.falling ? [:] : [item.id: g.frame(in: .global)])
                }
            )
    }

    /// Notes skip the photo glass. The material blur washes the paper out
    /// and the slip stops reading as a note.
    @ViewBuilder
    private var framed: some View {
        if item.note != nil {
            face
        } else {
            face
                .padding(Frame.inset)
                .glassFrame(cornerRadius: Frame.radius)
        }
    }

    @ViewBuilder
    private var face: some View {
        if let note = item.note {
            NoteSlip(text: note)
        } else {
            Image(nsImage: item.thumb)
                .resizable()
                .interpolation(.high)
                .frame(width: photoSize.width, height: photoSize.height)
                .clipShape(RoundedRectangle(cornerRadius: Frame.radius - Frame.inset, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Frame.radius - Frame.inset, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5)
                )
        }
    }

    private func arrive() {
        // A capture that flew in is already in place; the flight did the arriving.
        if item.flying {
            arrived = true
            return
        }
        swing = 16
        withAnimation(.spring(response: 0.42, dampingFraction: 0.72)) { arrived = true }
        withAnimation(.interpolatingSpring(stiffness: 46, damping: 2.6)) { swing = 0 }
    }

    /// Landing after the flight: no jump, just a small sway from rest.
    private func land() {
        nudge(2.2)
    }

    private func breeze() {
        let delay = Double.random(in: 0...0.35)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            nudge(Double.random(in: 1.6...3.4))
        }
    }

    private func nudge(_ degrees: Double) {
        withAnimation(.easeOut(duration: 0.3)) { swing = degrees }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation(.interpolatingSpring(stiffness: 38, damping: 2.4)) { swing = 0 }
        }
    }
}

/// A paper slip on the rail. Text is real type, so a short note stays large
/// and a long one shrinks instead of being a scaled-down picture of text.
struct NoteSlip: View {
    let text: String
    var compact = false

    static let width: CGFloat = 132
    static let height: CGFloat = 108

    private var pointSize: CGFloat {
        let count = text.count
        let oneLine = !text.contains("\n")
        let size: CGFloat
        if oneLine && count <= 22 { size = 22 }
        else if count <= 70 { size = 16 }
        else { size = 12 }
        return compact ? max(11, size - 4) : size
    }

    private var isShort: Bool { text.count <= 22 && !text.contains("\n") }

    var body: some View {
        Text(text)
            .font(.system(size: pointSize, weight: isShort ? .semibold : .medium, design: .rounded))
            .foregroundStyle(HangTheme.night)
            .multilineTextAlignment(isShort ? .center : .leading)
            .lineLimit(compact ? 4 : (isShort ? 3 : 6))
            .minimumScaleFactor(0.72)
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity,
                alignment: isShort ? .center : .topLeading)
            .padding(.leading, compact ? 14 : 22)
            .padding(.trailing, compact ? 8 : 10)
            .padding(.vertical, compact ? 6 : 10)
            .frame(width: compact ? nil : Self.width, height: compact ? nil : Self.height)
            .background { NotePaper() }
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .shadow(color: HangTheme.amberDeep.opacity(0.25), radius: 0, y: 1)
    }
}

/// Ruled paper. The amber margin sits clear of the text.
private struct NotePaper: View {
    var body: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(
                colors: [HangTheme.paper, HangTheme.paperShade],
                startPoint: .top,
                endPoint: .bottom)
            VStack(spacing: 0) {
                ForEach(0..<8, id: \.self) { index in
                    Spacer(minLength: 0)
                    Rectangle()
                        .fill(HangTheme.amberDeep.opacity(index == 0 ? 0 : 0.28))
                        .frame(height: 0.6)
                }
            }
            .padding(.horizontal, 6)
            Rectangle()
                .fill(HangTheme.amber.opacity(0.7))
                .frame(width: 1)
                .padding(.leading, 14)
            LinearGradient(
                colors: [Color.white.opacity(0.28), Color.clear],
                startPoint: .top,
                endPoint: .center)
        }
    }
}

enum Frame {
    static let radius: CGFloat = 16
    static let inset: CGFloat = 4
}

extension View {
    /// A crisp glass: the system's blurred material with a thin specular
    /// edge, lit from above. No refraction, so the background stays sharp
    /// around the frame instead of bending like gel.
    func glassFrame(cornerRadius: CGFloat = 0, circle: Bool = false, capsule: Bool = false) -> some View {
        let shape: AnyShape = circle ? AnyShape(Circle())
            : capsule ? AnyShape(Capsule())
            : AnyShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        return background(.ultraThinMaterial, in: shape)
            .overlay(
                shape.stroke(
                    LinearGradient(
                        colors: [HangTheme.cyanGlow.opacity(0.45), Color.white.opacity(0.12), HangTheme.amber.opacity(0.25)],
                        startPoint: .top,
                        endPoint: .bottom),
                    lineWidth: 0.9)
            )
            .overlay(shape.stroke(HangTheme.night.opacity(0.35), lineWidth: 1).padding(-0.5))
    }
}

/// Gunmetal clip with an amber bite — Blade Runner 2049 hardware on the ribbon.
struct Clothespin: View {
    private let metal = LinearGradient(
        stops: [
            .init(color: HangTheme.mist, location: 0),
            .init(color: Color(white: 0.88), location: 0.4),
            .init(color: HangTheme.slate, location: 1),
        ],
        startPoint: .top, endPoint: .bottom)

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                .fill(HangTheme.night)
                .frame(width: 18, height: 22)
                .offset(y: 2)
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(metal)
                .frame(width: 16, height: 26)
                .overlay(
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [HangTheme.cyanGlow.opacity(0.5), HangTheme.amber.opacity(0.35)],
                                startPoint: .top, endPoint: .bottom),
                            lineWidth: 0.7)
                )
                .overlay(alignment: .top) {
                    Capsule()
                        .fill(HangTheme.amberDeep.opacity(0.95))
                        .frame(width: 11, height: 5)
                        .padding(.top, 7)
                }
                .overlay(alignment: .bottom) {
                    Capsule()
                        .fill(HangTheme.cyan.opacity(0.35))
                        .frame(width: 8, height: 2)
                        .padding(.bottom, 5)
                }
        }
        .shadow(color: HangTheme.night.opacity(0.55), radius: 3, y: 2)
        .allowsHitTesting(false)
    }
}
