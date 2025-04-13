import SwiftUI

struct Star: Identifiable {
    let id = UUID()
    var position: CGPoint
    var size: CGFloat
    var brightness: Double
    var speed: Double
    var color: Color
    
    init(in rect: CGRect) {
        position = CGPoint(
            x: CGFloat.random(in: 0..<rect.width),
            y: CGFloat.random(in: 0..<rect.height)
        )
        size = CGFloat.random(in: 1...3)
        brightness = Double.random(in: 0.2...1.0)
        speed = Double.random(in: 0.1...0.5)
        
        // Create different star colors for a more realistic galaxy
        let colorChoice = Int.random(in: 0...10)
        if colorChoice < 6 {
            // White/blue stars (most common)
            color = Color(
                red: Double.random(in: 0.8...1.0),
                green: Double.random(in: 0.8...1.0),
                blue: 1.0
            )
        } else if colorChoice < 8 {
            // Yellow/orange stars
            color = Color(
                red: Double.random(in: 0.8...1.0),
                green: Double.random(in: 0.6...0.8),
                blue: Double.random(in: 0.3...0.5)
            )
        } else {
            // Red stars
            color = Color(
                red: Double.random(in: 0.8...1.0),
                green: Double.random(in: 0.3...0.6),
                blue: Double.random(in: 0.3...0.5)
            )
        }
    }
}

struct StarView: View {
    let star: Star
    @State private var twinkle = false
    
    var body: some View {
        Circle()
            .fill(star.color)
            .frame(width: star.size, height: star.size)
            .opacity(twinkle ? star.brightness : star.brightness * 0.7)
            .blur(radius: star.size * 0.2)
            .position(star.position)
            .onAppear {
                withAnimation(Animation.easeInOut(duration: 1 + Double.random(in: 0...2)).repeatForever()) {
                    twinkle.toggle()
                }
            }
    }
}

struct NebulaView: View {
    let colors: [Color] = [
        Color(red: 0.1, green: 0.0, blue: 0.2),
        Color(red: 0.2, green: 0.0, blue: 0.3),
        Color(red: 0.0, green: 0.1, blue: 0.3),
        Color(red: 0.3, green: 0.0, blue: 0.3)
    ]
    
    @Binding var phase: Double
    let center: CGPoint
    let radius: CGFloat
    
    var body: some View {
        ZStack {
            // Create multiple overlapping radial gradients for a more organic look
            ForEach(0..<6) { index in
                RadialGradient(
                    gradient: Gradient(colors: [
                        colors[index % colors.count].opacity(0.2),
                        colors[index % colors.count].opacity(0.0)
                    ]),
                    center: UnitPoint(
                        x: 0.5 + 0.3 * cos(Double(index) * .pi / 3 + phase * 2 * .pi),
                        y: 0.5 + 0.3 * sin(Double(index) * .pi / 3 + phase * 2 * .pi)
                    ),
                    startRadius: radius * 0.1,
                    endRadius: radius * 0.9
                )
                .scaleEffect(1.0 + 0.1 * sin(Double(index) + phase * 4))
                .blendMode(.screen)
            }
        }
        .frame(width: radius * 2.5, height: radius * 2.5)
        .position(center)
    }
}

struct GalaxyEffectView: View {
    @ObservedObject var viewModel: GalaxyViewModel
    private let timer = Timer.publish(every: 1/60, on: .main, in: .common).autoconnect()
    
    init(viewModel: GalaxyViewModel) {
        self.viewModel = viewModel
    }
    
    var body: some View {
        ZStack {
            // Deep space background
            Color.black.edgesIgnoringSafeArea(.all)
            
            // Nebula effect - fade out during transformation
            NebulaView(
                phase: $viewModel.nebulaPhase,
                center: CGPoint(x: viewModel.screenSize.width / 2, y: viewModel.screenSize.height / 2),
                radius: min(viewModel.screenSize.width, viewModel.screenSize.height) * 0.4
            )
            .opacity(viewModel.isTransforming ? 1.0 - viewModel.transformationProgress : 1.0)
            
            // Stars
            ForEach(viewModel.stars) { star in
                StarView(star: star)
            }
        }
        .onReceive(timer) { _ in
            viewModel.updateStars()
        }
    }
}

// Usage example
//struct ContentView: View {
//    var body: some View {
//        GeometryReader { geometry in
//            GalaxyEffectView(screenSize: geometry.frame(in: .global))
//        }
//    }
//}

// Preview
//struct ContentView_Previews: PreviewProvider {
//    static var previews: some View {
//        ContentView()
//    }
//}
