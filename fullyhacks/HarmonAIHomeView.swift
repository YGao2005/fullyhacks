import SwiftUI

struct MainNeonButton: View {
    var title: String
    var action: () -> Void
    
    @State private var isPressed = false
    @State private var glowIntensity: CGFloat = 0.6
    
    var body: some View {
        Button(action: {
            isPressed = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                isPressed = false
            }
            action()
        }) {
            Text(title)
                .font(.headline)
                .fontWeight(.bold)
                .foregroundColor(.black)
                .padding(.vertical, 15)
                .padding(.horizontal, 90)
                .background(
                    ZStack {
                        RoundedRectangle(cornerRadius: 20)
                            .fill(Color.white.opacity(1))
                        
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(Color.white, lineWidth: 2)
                            .shadow(color: Color.white.opacity(glowIntensity), radius: 10, x: 0, y: 0)
                    }
                )
        }
        .scaleEffect(isPressed ? 0.95 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isPressed)
        .onAppear {
            // Create pulsing glow effect
            withAnimation(Animation.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                glowIntensity = 0.9
            }
        }
    }
}

struct SecondaryNeonButton: View {
    var title: String
    var action: () -> Void
    
    @State private var isPressed = false
    @State private var glowIntensity: CGFloat = 0.6
    
    var body: some View {
        Button(action: {
            isPressed = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                isPressed = false
            }
            action()
        }) {
            Text(title)
                .font(.headline)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .padding(.vertical, 15)
                .padding(.horizontal, 90)
                .background(
                    ZStack {
                        RoundedRectangle(cornerRadius: 20)
                            .fill(Color.black.opacity(0.6))
                        
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(Color.white, lineWidth: 2)
                            .shadow(color: Color.white.opacity(glowIntensity), radius: 10, x: 0, y: 0)
                    }
                )
        }
        .scaleEffect(isPressed ? 0.95 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isPressed)
        .onAppear {
            // Create pulsing glow effect
            withAnimation(Animation.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                glowIntensity = 0.9
            }
        }
    }
}

struct HarmonAITitleView: View {
    @State private var glowIntensity: CGFloat = 0.7
    
    var body: some View {
        Text("HarmonAI")
            .font(.system(size: 44, weight: .bold, design: .rounded))
            .foregroundColor(.white)
            .shadow(color: Color.white.opacity(glowIntensity), radius: 15, x: 0, y: 0)
            .padding(.top, 100)
            .onAppear {
                // Create subtle pulsing effect for the title
                withAnimation(Animation.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
                    glowIntensity = 0.9
                }
            }
    }
}

struct HarmonAISubtitleView: View {
    @State private var glowIntensity: CGFloat = 0.7
    
    var body: some View {
        Text("Mediator of the Digital World")
            .font(.system(size: 20, weight: .bold, design: .rounded))
            .foregroundColor(Color.white.opacity(0.6))
            .shadow(color: Color.white.opacity(glowIntensity), radius: 15, x: 0, y: 0)
            .padding(.top, 0)
            .onAppear {
                // Create subtle pulsing effect for the title
                withAnimation(Animation.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
                    glowIntensity = 0.9
                }
            }
    }
}

struct HarmonAIHomeView: View {
    var body: some View {
        ZStack {
            // Galaxy background
            GeometryReader { geometry in
                GalaxyEffectView(screenSize: geometry.frame(in: .global))
            }
            
            VStack {
                // Title at the top
                HarmonAITitleView()
                
                HarmonAISubtitleView()
                
                
                Spacer()
                
                // Buttons at the bottom
                VStack(spacing: 20) {
                    MainNeonButton(title: "New Discussion") {
                        print("Create button tapped")
                    }
                    
                    SecondaryNeonButton(title: "Old Discussions") {
                        print("Explore button tapped")
                    }
                }
                .padding(.bottom, 80)
            }
        }
        .edgesIgnoringSafeArea(.all)
    }
}

// Preview
struct HarmonAIHomeView_Previews: PreviewProvider {
    static var previews: some View {
        HarmonAIHomeView()
    }
}

