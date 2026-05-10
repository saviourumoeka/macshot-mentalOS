import AppKit
import Vision

/// Runs Vision text recognition on a captured screenshot image and persists the
/// result as two sidecar files:
///   - `{uuid}_ocr.json`      — full OCR data: text + per-observation bounding boxes + confidence
///   - `{uuid}_context.json`  — `ocrText` field updated for quick substring search
///
/// All work is async on a background thread. OCR failure is silent — it never
/// blocks the UI or corrupts the capture.
enum CaptureOCR {

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    /// Trigger OCR for a newly saved capture. Safe to call from any thread.
    /// - Parameters:
    ///   - id: The UUID string of the history entry.
    ///   - image: The composited screenshot (annotations baked in, redactions applied).
    ///   - historyDirectory: The directory where sidecar files are written.
    static func run(id: String, image: NSImage, historyDirectory: URL) {
        DispatchQueue.global(qos: .utility).async {
            guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                Log.error("OCR skipped: NSImage has no CGImage representation", category: .ocr, ["id": id])
                return
            }
            let result = extractText(id: id, from: cgImage)
            persist(result: result, historyDirectory: historyDirectory)
        }
    }

    // MARK: - Private

    private static func extractText(id: String, from cgImage: CGImage) -> OCRResult {
        var observationModels: [OCRResult.Observation] = []

        let request = VisionOCR.makeTextRecognitionRequest { req, _ in
            guard let observations = req.results as? [VNRecognizedTextObservation] else { return }
            observationModels = observations.compactMap { obs in
                guard let top = obs.topCandidates(1).first else { return nil }
                let bbox = obs.boundingBox
                return OCRResult.Observation(
                    text: top.string,
                    confidence: Double(top.confidence),
                    boundingBox: OCRResult.BoundingBox(
                        x: bbox.origin.x,
                        y: bbox.origin.y,
                        width: bbox.width,
                        height: bbox.height
                    )
                )
            }
        }

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
        } catch {
            Log.error("Vision OCR request failed", category: .ocr, error: error, ["id": id])
        }

        let fullText = observationModels.map(\.text).joined(separator: "\n")
        Log.debug("OCR extracted text", category: .ocr, ["id": id, "chars": fullText.count, "observations": observationModels.count])
        return OCRResult(id: id, extractedAt: Date(), text: fullText, observations: observationModels)
    }

    private static func persist(result: OCRResult, historyDirectory: URL) {
        let ocrURL = historyDirectory.appendingPathComponent("\(result.id)_ocr.json")
        do {
            let data = try encoder.encode(result)
            try data.write(to: ocrURL, options: .atomic)
        } catch {
            Log.error("Failed to write OCR sidecar", category: .ocr, error: error, ["id": result.id, "path": ocrURL.path])
        }

        // Patch ocrText in the context sidecar so search can find it
        // without loading the larger _ocr.json. Reindex after write completes.
        let id = result.id
        ContextCapture.update(
            id: id, in: historyDirectory,
            completionOnMain: {
                SearchIndex.shared.reindex(id: id, in: historyDirectory)
            },
            transform: { metadata in
                metadata.ocrText = result.text
            }
        )

        CaptureEnrichmentPipeline.run(id: result.id, ocrText: result.text, historyDirectory: historyDirectory)
    }
}
