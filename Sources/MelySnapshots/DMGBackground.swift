import SwiftUI
import MelyCore
import MelyUI

/// The installer window (task 7.8), 660×420: Mely waves, an arrow leads from the app's
/// icon (Finder draws it at 170,215) to «Программы» (490,215).
struct DMGBackground: View {
    static let size = CGSize(width: 660, height: 420)

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 1.0, green: 0.97, blue: 0.93), Color(red: 0.99, green: 0.91, blue: 0.86)],
                           startPoint: .top, endPoint: .bottom)
            // Soft blobs, as the island's glow.
            Circle().fill(Color(red: 0.55, green: 0.9, blue: 0.7).opacity(0.25)).frame(width: 260).blur(radius: 50)
                .offset(x: -230, y: -150)
            Circle().fill(Color(red: 1, green: 0.62, blue: 0.68).opacity(0.25)).frame(width: 280).blur(radius: 60)
                .offset(x: 240, y: 170)
            VStack(spacing: 4) {
                HStack(spacing: 10) {
                    MelyCharacterFrame(pose: .happy, gaze: CGPoint(x: 0.4, y: 0.2), time: 0.6)
                        .frame(width: 46, height: 46)
                    Text("Mely").font(.system(size: 30, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color(red: 0.24, green: 0.16, blue: 0.15))
                }
                Text("Перетащи Mely в «Программы»")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(Color(red: 0.24, green: 0.16, blue: 0.15).opacity(0.6))
            }
            .position(x: Self.size.width / 2, y: 70)
            ZStack {
                Arrow(head: false)
                    .stroke(Color(red: 0.24, green: 0.16, blue: 0.15).opacity(0.35),
                            style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [2, 9]))
                Arrow(head: true)
                    .stroke(Color(red: 0.24, green: 0.16, blue: 0.15).opacity(0.35),
                            style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            }
            .frame(width: 150, height: 40)
            .position(x: Self.size.width / 2, y: 215)
            Text("Потом открой Mely из «Программ» — он появится в челке")
                .font(.system(size: 11.5, design: .rounded))
                .foregroundStyle(Color(red: 0.24, green: 0.16, blue: 0.15).opacity(0.45))
                .position(x: Self.size.width / 2, y: 385)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .environment(\.colorScheme, .light)
    }
}

/// A gentle curved arrow, left to right.
private struct Arrow: Shape {
    /// The head alone (solid), or the dotted curve alone.
    let head: Bool

    func path(in r: CGRect) -> Path {
        var p = Path()
        guard head else {
            p.move(to: CGPoint(x: r.minX, y: r.midY + 6))
            p.addQuadCurve(to: CGPoint(x: r.maxX - 4, y: r.midY + 5), control: CGPoint(x: r.midX, y: r.minY - 14))
            return p
        }
        p.move(to: CGPoint(x: r.maxX - 14, y: r.midY - 8))
        p.addLine(to: CGPoint(x: r.maxX, y: r.midY + 6))
        p.addLine(to: CGPoint(x: r.maxX - 17, y: r.midY + 13))
        return p
    }
}
