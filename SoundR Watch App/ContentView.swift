import SwiftUI
import Foundation
import AVFoundation

struct SoundRadarApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

class SoundDetectionManager: ObservableObject {
    private var engine: AVAudioEngine?
    private var inputNode: AVAudioInputNode?
    
    init() {
        setupAudioSession()
    }
    
    private func setupAudioSession() {
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.playAndRecord, mode: .default, options: [])
            try audioSession.setActive(true)
        } catch {
            print("Error setting up audio session: \(error.localizedDescription)")
        }
    }
    
    func start(completion: @escaping (Double) -> Void) {
        engine = AVAudioEngine()
        inputNode = engine?.inputNode
        
        guard let inputNode = inputNode else {
            return
        }
        
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputNode.inputFormat(forBus: 0)) { buffer, time in
            let bufferLength = UInt32(buffer.frameLength)
            let channels = UnsafeBufferPointer(start: buffer.floatChannelData, count: Int(buffer.format.channelCount))
            var sum: Float = 0.0
            for i in 0..<Int(bufferLength) {
                sum += channels[0][i] * channels[0][i]
            }
            let rms = sqrt(sum / Float(bufferLength))
            //Adj dB
            let dB = 100 * log10(Double(rms))
            
            DispatchQueue.main.async {
                completion(dB)
            }
        }
        
        do {
            try engine?.start()
            inputNode.volume = 100.0 // Adjust the input volume.
        } catch {
            print("Error starting AVAudioEngine: \(error.localizedDescription)")
        }
    }
    
    func stop() {
        inputNode?.removeTap(onBus: 0)
        engine?.stop()
    }
}

struct ContentView: View {
    @StateObject private var soundDetection = SoundDetectionManager()
    @State private var arrowRotation: Angle = .zero
    @State private var likelyDistance: Double = 0.0
    @State private var isLockingOn: Bool = false
    
    private let EMAFactor: Double = 0.2 // Exponential moving average factor for arrow rotation.
    
    var body: some View {
        VStack {
            ZStack {
                Circle()
                    .foregroundColor(isLockingOn ? Color.green.opacity(1) : Color.blue.opacity(1))
                    .frame(width: 180, height: 160)
                    .padding()
                
                ArrowView()
                    .rotationEffect(arrowRotation)
            }
            
            Text(String(format: "%.2f meters", likelyDistance))
                .foregroundColor(isLockingOn ? .green : .black)
                .font(.body)
                .padding()
        }
        .onAppear {
            startSoundDetection()
        }
        .onDisappear {
            stopSoundDetection()
        }
    }
    
    private func startSoundDetection() {
        var baselineSoundLevel: Double = 40 // Initial baseline sound level
        var isBaselineSet = false

        soundDetection.start { soundLevel in
            // Adaptive thresholding
            if !isBaselineSet {
                baselineSoundLevel = soundLevel
                isBaselineSet = true
            } else {
                let threshold = baselineSoundLevel + 5.0 // Adjust the threshold as needed
                self.isLockingOn = soundLevel > threshold
            }
            
            // Smooth arrow rotation.
            self.arrowRotation = self.arrowRotation * (1.0 - self.EMAFactor) + Angle(degrees: soundLevel * 2) * self.EMAFactor
            
            // Estimate distance from sound level
            self.likelyDistance = calculateLikelyDistanceFromSoundLevel(soundLevel)
        }
    }

    
    private func stopSoundDetection() {
        soundDetection.stop()
    }
    //Distance
    private func calculateLikelyDistanceFromSoundLevel(_ soundLevel: Double) -> Double {
        let attenuationFactor = 100.0 // Adjust this factor based on your environment and sound source
        let distance = pow(10, (ReferenceSoundLevel - soundLevel) / (2 * attenuationFactor))
        return distance
    }

    private let ReferenceSoundLevel: Double = 1  // Reference sound level at the reference distance
}
//Arrow
struct ArrowView: View {
    var body: some View {
        Triangle()
            .frame(width: 20, height: 70)
            .foregroundColor(.red)
            .rotationEffect(Angle(degrees: 45))
    }
}
//Shape
struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.minY))
        return path
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}

