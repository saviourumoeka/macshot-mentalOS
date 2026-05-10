import Foundation

struct OCRResult: Codable {

    struct BoundingBox: Codable {
        // Normalized coordinates in Vision space (origin bottom-left, 0..1)
        let x: Double
        let y: Double
        let width: Double
        let height: Double
    }

    struct Observation: Codable {
        let text: String
        let confidence: Double
        let boundingBox: BoundingBox
    }

    let id: String
    let extractedAt: Date
    let text: String
    let observations: [Observation]
}
