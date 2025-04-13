import SwiftUI

class GalaxyViewModel: ObservableObject {
    @Published var stars: [Star] = []
    @Published var nebulaPhase: Double = 0.0
    @Published var screenSize: CGRect {
        didSet {
            // Update galaxy center and radius when screen size changes
            galaxyCenter = CGPoint(x: screenSize.width / 2, y: screenSize.height / 2)
            galaxyRadius = min(screenSize.width, screenSize.height) * 0.4
        }
    }
    private let starCount = 300  // Increased star count for better density
    private var galaxyCenter: CGPoint
    private var galaxyRadius: CGFloat
    
    // Transformation properties
    @Published var isTransforming = false
    @Published var transformationProgress: Double = 0.0
    private let transformationDuration: Double = 2.0
    private var transformationStartTime: Date?
    private var rotationSpeed: Double = 0.0008 // Starting rotation speed
    private let maxRotationSpeed: Double = 0.05
    
    // Audio visualization properties
    @Published var isVisualizingAudio = false
    @Published var audioLevels: [Float] = []
    private var audioMultiplier: CGFloat = 150.0 // Control the height of the visualization
    
    init(screenSize: CGRect) {
        self.screenSize = screenSize
        self.galaxyCenter = CGPoint(x: screenSize.width / 2, y: screenSize.height / 2)
        self.galaxyRadius = min(screenSize.width, screenSize.height) * 0.4
        self.audioLevels = Array(repeating: 0, count: 100)
        
        createStars()
    }
    
    func startTransformation() {
        print("Starting transformation")
        isTransforming = true
        transformationProgress = 0.0
        transformationStartTime = Date()
        // Speed up rotation initially
        rotationSpeed = 0.005
    }
    
    // Update audio levels from the AudioManager
    func updateAudioLevels(_ levels: [Float]) {
        self.audioLevels = levels
    }
    
    // Start audio visualization after transformation is complete
    func startAudioVisualization() {
        isVisualizingAudio = true
    }
    
    // Stop audio visualization
    func stopAudioVisualization() {
        isVisualizingAudio = false
    }
    
    func updateStars() {
        // Handle transformation if active
        if isTransforming {
            updateTransformation()
        }
        
        // Handle the different states: galaxy, transformation, or audio visualization
        for i in 0..<stars.count {
            let starPosition = stars[i].position
            
            // Calculate vector from center
            let dx = starPosition.x - galaxyCenter.x
            let dy = starPosition.y - galaxyCenter.y
            
            if isVisualizingAudio && transformationProgress >= 1.0 {
                // Audio visualization mode
                updateStarForAudioVisualization(i)
            } else if isTransforming && transformationProgress > 0.3 {
                // During transformation, gradually move stars to horizontal line formation
                updateStarDuringTransformation(i, dx: dx, dy: dy)
            } else {
                // Normal galaxy rotation (pre-transformation)
                updateStarInGalaxyMode(i, dx: dx, dy: dy)
            }
            
            // Adjust brightness based on mode
            if isVisualizingAudio {
                // Make stars pulse with the audio
                let audioIndex = min(Int(Double(i) / Double(stars.count) * Double(audioLevels.count)), audioLevels.count - 1)
                stars[i].brightness = max(0.3, Double(audioLevels[audioIndex]))
            } else if isTransforming {
                // Transformation effect
                stars[i].brightness = 0.3 + abs(sin(Double(i) + transformationProgress * 20)) * 0.7
            } else {
                // Regular twinkle effect
                stars[i].brightness = 0.3 + abs(sin(Double(i) + Double(Date().timeIntervalSince1970) * stars[i].speed)) * 0.7
            }
        }
        
        // Update nebula animation - slower
        nebulaPhase += 0.001
        if nebulaPhase > 1.0 {
            nebulaPhase = 0.0
        }
    }
    
    // Update star positions for audio visualization
    private func updateStarForAudioVisualization(_ index: Int) {
        // Calculate which audio index corresponds to this star
        let audioIndex = min(Int(Double(index) / Double(stars.count) * Double(audioLevels.count)), audioLevels.count - 1)
        
        // Get the audio level for this star
        let audioLevel = CGFloat(audioLevels[audioIndex])
        
        // Calculate the target x position (evenly distributed across screen)
        let spreadWidth = screenSize.width * 0.8
        let xPosition = galaxyCenter.x - spreadWidth/2 + CGFloat(Double(index) / Double(stars.count)) * spreadWidth
        
        // Calculate the y position based on audio level
        let baseY = galaxyCenter.y
        let offset = audioLevel * audioMultiplier
        
        // Add some randomness for a more organic look
        let randomFactor = CGFloat.random(in: 0.8...1.2)
        
        // Update the star position
        stars[index].position = CGPoint(
            x: xPosition,
            y: baseY - (offset * randomFactor)
        )
    }
    
    // Update star during the transformation phase
    private func updateStarDuringTransformation(_ index: Int, dx: CGFloat, dy: CGFloat) {
        let currentPosition = stars[index].position
        let targetY = galaxyCenter.y
        let currentDistance = sqrt(dx * dx + dy * dy)
        
        // Keep the star's distance from center but flatten the y coordinate
        let flatteningFactor = min(1.0, (transformationProgress - 0.3) * 2.5)
        
        // Calculate new position with progressively flattening y coordinates
        var newY = currentPosition.y + (targetY - currentPosition.y) * CGFloat(flatteningFactor)
        
        // Add a wave effect to the line as it forms
        if transformationProgress > 0.7 {
            let waveFactor = (transformationProgress - 0.7) * 3.3 // Scale to 0-1 in the final 30% of animation
            newY = targetY + sin(CGFloat(dx) * 0.05) * CGFloat(10 * (1.0 - waveFactor))
        }
        
        // As we progress, distribute stars more evenly along x-axis for waveform-like appearance
        let newX: CGFloat
        if transformationProgress > 0.8 {
            // Start distributing more evenly
            let distributionFactor = (transformationProgress - 0.8) * 5 // Scale to 0-1 in final 20%
            
            // Create a target position based on original distance and angle
            let originalAngle = atan2(dy, dx)
            let targetX = galaxyCenter.x + cos(originalAngle) * currentDistance
            
            // Map stars to be more evenly distributed horizontally
            let spreadWidth = screenSize.width * 0.8
            let spreadPosition = galaxyCenter.x - spreadWidth/2 + CGFloat(Double(index) / Double(stars.count)) * spreadWidth
            
            // Blend between spiral and even distribution
            newX = targetX * (1-CGFloat(distributionFactor)) + spreadPosition * CGFloat(distributionFactor)
        } else {
            // During early transformation, maintain relative x positions but increase rotation
            var angle = atan2(dy, dx)
            let effectiveRotationSpeed = rotationSpeed * (1.0 + transformationProgress * 5) // Accelerate rotation
            angle += effectiveRotationSpeed
            newX = galaxyCenter.x + cos(angle) * currentDistance
        }
        
        stars[index].position = CGPoint(x: newX, y: newY)
    }
    
    // Update star in normal galaxy mode
    private func updateStarInGalaxyMode(_ index: Int, dx: CGFloat, dy: CGFloat) {
        // Calculate current angle and distance
        let distance = sqrt(dx * dx + dy * dy)
        var angle = atan2(dy, dx)
        
        // Rotate based on distance from center (inner stars rotate faster)
        let effectiveRotationSpeed = rotationSpeed / (distance / galaxyRadius + 0.1)
        angle += effectiveRotationSpeed
        
        // New position
        let newX = galaxyCenter.x + cos(angle) * distance
        let newY = galaxyCenter.y + sin(angle) * distance
        
        stars[index].position = CGPoint(x: newX, y: newY)
    }
    
    private func updateTransformation() {
        guard let startTime = transformationStartTime else {
            print("No start time set")
            return
        }
        
        let elapsed = Date().timeIntervalSince(startTime)
        transformationProgress = min(1.0, elapsed / transformationDuration)
        
        // First half: speed up rotation
        if transformationProgress < 0.5 {
            // Gradually increase rotation speed
            rotationSpeed = 0.005 + (maxRotationSpeed - 0.005) * (transformationProgress * 2)
        } else {
            // Second half: slow down rotation as we flatten
            rotationSpeed = maxRotationSpeed * (1 - ((transformationProgress - 0.5) * 2))
        }
        
        // Handle completion
        if transformationProgress >= 1.0 {
            //print("Transformation complete")
            // The transformation is complete, automatically start audio visualization
            startAudioVisualization()
        }
    }
    
    func createStars() {
        stars = []
        
        for _ in 0..<starCount {
            // Create stars following a spiral pattern
            let angle = Double.random(in: 0...(2 * Double.pi))
            let distance = Double.random(in: 0...Double(galaxyRadius))
            let spiralFactor = Double.random(in: 0...6.0)
            
            let adjustedAngle = angle + (distance / Double(galaxyRadius)) * spiralFactor
            
            let x = galaxyCenter.x + CGFloat(cos(adjustedAngle) * distance)
            let y = galaxyCenter.y + CGFloat(sin(adjustedAngle) * distance)
            
            if x >= 0 && x <= screenSize.width && y >= 0 && y <= screenSize.height {
                var star = Star(in: screenSize)
                star.position = CGPoint(x: x, y: y)
                stars.append(star)
            }
        }
    }
}
