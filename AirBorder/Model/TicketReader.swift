import Foundation
import PDFKit
import UIKit
import Vision

/// Flight details read from a ticket photo or PDF. Only what was found in the document is kept.
struct ParsedTicket: Hashable {
    let number: String
    let date: String?
    let from: String?
    let to: String?
    /// "ANA-itinerary.pdf" or "Your ticket photo".
    let source: String

    var route: String? {
        guard let from, let to else { return nil }
        return "\(from) → \(to)"
    }
}

enum TicketReader {
    private static let airlineCodes = ["NH", "JL", "TG", "BA", "UA", "AA", "DL", "AF", "LH", "SQ", "CX", "QF", "EK", "KE", "OZ", "AC", "NZ", "MH", "BR", "CI"]
    private static let months = ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"]

    /// Finds a flight number, date and route in free text (OCR or PDF text).
    static func parse(_ text: String, source: String, defaultYear: Int = Calendar.current.component(.year, from: Date())) -> ParsedTicket? {
        let upper = text.uppercased()
        guard let number = flightNumber(in: upper) else { return nil }
        let route = routeCodes(in: upper)
        return ParsedTicket(number: number, date: date(in: upper, defaultYear: defaultYear), from: route?.0, to: route?.1, source: source)
    }

    static func flightNumber(in text: String) -> String? {
        let pattern = #"\b([A-Z][A-Z0-9]|[0-9][A-Z])\s?([0-9]{1,4})\b"#
        let matches = captures(pattern, in: text)
        let known = matches.first { airlineCodes.contains($0[0]) }
        guard let match = known ?? matches.first(where: { $0[1].count >= 2 && !$0[0].allSatisfy(\.isNumber) }) else { return nil }
        let digits = String(Int(match[1]) ?? 0)
        return "\(match[0]) \(digits)"
    }

    static func date(in text: String, defaultYear: Int) -> String? {
        if let iso = captures(#"\b(20[0-9]{2})-([01][0-9])-([0-3][0-9])\b"#, in: text).first {
            let value = "\(iso[0])-\(iso[1])-\(iso[2])"
            return TripDate.isValid(value) ? value : nil
        }
        let monthPattern = months.joined(separator: "|")
        if let m = captures(#"\b([0-3]?[0-9])\s?("# + monthPattern + #")[A-Z]*\.?\s?(20[0-9]{2}|[0-9]{2})?\b"#, in: text).first {
            return iso(day: m[0], month: m[1], year: m[2], defaultYear: defaultYear)
        }
        if let m = captures(#"\b("# + monthPattern + #")[A-Z]*\.?\s([0-3]?[0-9]),?\s(20[0-9]{2})\b"#, in: text).first {
            return iso(day: m[1], month: m[0], year: m[2], defaultYear: defaultYear)
        }
        return nil
    }

    static func routeCodes(in text: String) -> (String, String)? {
        guard let m = captures(#"\b([A-Z]{3})\s*(?:→|->|–|—|-|TO)\s*([A-Z]{3})\b"#, in: text).first else { return nil }
        return (m[0], m[1])
    }

    private static func iso(day: String, month: String, year: String, defaultYear: Int) -> String? {
        guard let monthIndex = months.firstIndex(of: String(month.prefix(3))), let dayValue = Int(day), (1 ... 31).contains(dayValue) else { return nil }
        var yearValue = Int(year) ?? defaultYear
        if yearValue < 100 { yearValue += 2000 }
        let iso = String(format: "%04d-%02d-%02d", yearValue, monthIndex + 1, dayValue)
        return TripDate.isValid(iso) ? iso : nil
    }

    private static func captures(_ pattern: String, in text: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).map { match in
            (1 ..< match.numberOfRanges).map { index in
                Range(match.range(at: index), in: text).map { String(text[$0]) } ?? ""
            }
        }
    }

    // MARK: Sources

    static func read(pdf url: URL) -> ParsedTicket? {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        guard let text = PDFDocument(url: url)?.string else { return nil }
        return parse(text, source: url.lastPathComponent)
    }

    /// Recognises text in a ticket photo on this iPhone with Vision.
    static func read(photo: UIImage) async -> ParsedTicket? {
        guard let cgImage = photo.cgImage else { return nil }
        return await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, _ in
                let lines = (request.results as? [VNRecognizedTextObservation])?.compactMap { $0.topCandidates(1).first?.string } ?? []
                continuation.resume(returning: parse(lines.joined(separator: "\n"), source: "Your ticket photo"))
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try VNImageRequestHandler(cgImage: cgImage, orientation: .up).perform([request])
                } catch {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}
