import SwiftUI

struct GomokuBoardView: View {
    let boardSize: Int
    let moves: [Move]
    let isInteractive: Bool
    let onPlay: (BoardPoint) -> Void
    @State private var hoveredPoint: BoardPoint?

    // iOS double-tap state
    #if os(iOS)
    @State private var pendingPoint: BoardPoint?
    #endif

    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            let rect = CGRect(x: (geometry.size.width - side) / 2, y: (geometry.size.height - side) / 2,
                              width: side, height: side)
            Canvas { context, _ in drawBoard(in: rect, context: &context) }
                .contentShape(Rectangle())
                #if os(iOS)
                .gesture(SpatialTapGesture().onEnded { value in
                    guard isInteractive else { return }
                    guard let tapped = point(at: value.location, in: rect) else {
                        pendingPoint = nil
                        return
                    }
                    // Skip if already occupied
                    if moves.contains(where: { $0.point == tapped }) {
                        pendingPoint = nil
                        return
                    }
                    if pendingPoint == tapped {
                        // Second tap on same point → confirm
                        pendingPoint = nil
                        onPlay(tapped)
                    } else {
                        // First tap → show ghost
                        pendingPoint = tapped
                    }
                })
                #else
                .gesture(SpatialTapGesture().onEnded { value in
                    if isInteractive, let point = point(at: value.location, in: rect) { onPlay(point) }
                })
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location): hoveredPoint = isInteractive ? point(at: location, in: rect) : nil
                    case .ended: hoveredPoint = nil
                    }
                }
                #endif
        }
        .aspectRatio(1, contentMode: .fit)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 28).fill(Color(red: 0.82, green: 0.64, blue: 0.37))
            .shadow(color: .black.opacity(0.18), radius: 28, y: 14))
        .accessibilityLabel(L10n.format("board.accessibility_label", boardSize))
        #if os(iOS)
        // Dismiss pending point when interactivity changes
        .onChange(of: isInteractive) { _, newValue in
            if !newValue { pendingPoint = nil }
        }
        #endif
    }

    private func drawBoard(in rect: CGRect, context: inout GraphicsContext) {
        let padding = max(26, rect.width * 0.055), span = rect.width - padding * 2
        let cell = span / CGFloat(boardSize - 1), origin = CGPoint(x: rect.minX + padding, y: rect.minY + padding)
        var grid = Path()
        for i in 0..<boardSize {
            let offset = CGFloat(i) * cell
            grid.move(to: CGPoint(x: origin.x, y: origin.y + offset)); grid.addLine(to: CGPoint(x: origin.x + span, y: origin.y + offset))
            grid.move(to: CGPoint(x: origin.x + offset, y: origin.y)); grid.addLine(to: CGPoint(x: origin.x + offset, y: origin.y + span))
        }
        context.stroke(grid, with: .color(.black.opacity(0.58)), lineWidth: max(0.65, cell * 0.026))
        for point in stars {
            let center = screenPoint(point, origin: origin, cell: cell), d = max(4, cell * 0.16)
            context.fill(Path(ellipseIn: CGRect(x: center.x-d/2, y: center.y-d/2, width: d, height: d)), with: .color(.black.opacity(0.72)))
        }
        // Ghost stone: hover on macOS, pending (first-tap) on iOS
        #if os(iOS)
        let ghostPoint = pendingPoint
        #else
        let ghostPoint = hoveredPoint
        #endif
        if let ghostPoint, !moves.contains(where: { $0.point == ghostPoint }) {
            let center = screenPoint(ghostPoint, origin: origin, cell: cell), d = cell * 0.76
            let color: Color = moves.count.isMultiple(of: 2) ? .black : .white
            #if os(iOS)
            // More visible ghost on iOS (pending confirmation)
            context.fill(Path(ellipseIn: CGRect(x: center.x-d/2, y: center.y-d/2, width: d, height: d)), with: .color(color.opacity(0.45)))
            #else
            context.fill(Path(ellipseIn: CGRect(x: center.x-d/2, y: center.y-d/2, width: d, height: d)), with: .color(color.opacity(0.25)))
            #endif
        }
        for (index, move) in moves.enumerated() { drawStone(move, last: index == moves.count-1, origin: origin, cell: cell, context: &context) }
    }

    private func drawStone(_ move: Move, last: Bool, origin: CGPoint, cell: CGFloat, context: inout GraphicsContext) {
        let center = screenPoint(move.point, origin: origin, cell: cell), d = cell * 0.82
        let rect = CGRect(x: center.x-d/2, y: center.y-d/2, width: d, height: d)
        context.drawLayer { layer in
            layer.addFilter(.shadow(color: .black.opacity(0.28), radius: cell*0.09, x: cell*0.04, y: cell*0.07))
            let colors: [Color] = move.stone == .black ? [Color(white: 0.27), Color(white: 0.025)] : [.white, Color(white: 0.72)]
            layer.fill(Path(ellipseIn: rect), with: .radialGradient(Gradient(colors: colors),
                center: CGPoint(x: rect.minX+d*0.34, y: rect.minY+d*0.28), startRadius: 0, endRadius: d*0.72))
        }
        if last {
            let marker = max(4, cell*0.16)
            context.fill(Path(ellipseIn: CGRect(x: center.x-marker/2, y: center.y-marker/2, width: marker, height: marker)), with: .color(.red.opacity(0.9)))
        }
    }

    private var stars: [BoardPoint] {
        let values = boardSize == 15 ? [3,7,11] : boardSize == 19 ? [3,9,15] : [boardSize/2]
        return values.flatMap { y in values.map { BoardPoint(x: $0, y: y) } }
    }
    private func screenPoint(_ point: BoardPoint, origin: CGPoint, cell: CGFloat) -> CGPoint {
        CGPoint(x: origin.x + CGFloat(point.x)*cell, y: origin.y + CGFloat(point.y)*cell)
    }
    private func point(at location: CGPoint, in rect: CGRect) -> BoardPoint? {
        let padding = max(26, rect.width*0.055), cell = (rect.width-padding*2)/CGFloat(boardSize-1)
        let x = Int(round((location.x-rect.minX-padding)/cell)), y = Int(round((location.y-rect.minY-padding)/cell))
        guard (0..<boardSize).contains(x), (0..<boardSize).contains(y) else { return nil }
        let point = BoardPoint(x: x, y: y), center = screenPoint(point, origin: CGPoint(x: rect.minX+padding, y: rect.minY+padding), cell: cell)
        return hypot(location.x-center.x, location.y-center.y) <= cell*0.48 ? point : nil
    }
}
