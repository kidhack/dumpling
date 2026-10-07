import SwiftUI

struct ContentView: View {
    var body: some View {
        ZStack {
            Color(hex: "FAFAF0").ignoresSafeArea()

            VStack(spacing: 0) {
                // Y2K title bar
                HStack {
                    Text("🥟 DUMPLING")
                        .font(.custom("Courier New", size: 11).bold())
                        .foregroundColor(Color(hex: "1A1A1A"))
                    Spacer()
                    ForEach(["□", "—", "×"], id: \.self) { sym in
                        Text(sym)
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .frame(width: 18, height: 18)
                            .background(Color(hex: "FAFAF0"))
                            .overlay(Rectangle().stroke(Color(hex: "1A1A1A"), lineWidth: 2))
                            .shadow(color: Color(hex: "1A1A1A"), radius: 0, x: 2, y: 2)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color(hex: "B3D9FF"))
                .overlay(Rectangle().frame(height: 3).foregroundColor(Color(hex: "1A1A1A")), alignment: .bottom)

                Spacer()

                VStack(spacing: 24) {
                    Text("🥟")
                        .font(.system(size: 64))

                    Text("DUMPLING")
                        .font(.custom("Courier New", size: 22).bold())
                        .foregroundColor(Color(hex: "1A1A1A"))

                    Text("Share content from any app\nto route it to the right place.")
                        .font(.custom("Courier New", size: 12))
                        .foregroundColor(Color(hex: "1A1A1A").opacity(0.7))
                        .multilineTextAlignment(.center)

                    Text("Use the share sheet to get started.")
                        .font(.custom("Courier New", size: 10))
                        .foregroundColor(Color(hex: "1A1A1A").opacity(0.5))
                        .padding(12)
                        .background(Color(hex: "FFF3B3"))
                        .overlay(Rectangle().stroke(Color(hex: "1A1A1A"), lineWidth: 2))
                        .shadow(color: Color(hex: "1A1A1A"), radius: 0, x: 3, y: 3)
                }

                Spacer()
            }
        }
    }
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >> 8) & 0xFF) / 255
        let b = Double(int & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}

#Preview {
    ContentView()
}
