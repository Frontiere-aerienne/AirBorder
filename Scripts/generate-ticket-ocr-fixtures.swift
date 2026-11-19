// PROCEDURAL: Generates non-personal images for the simulator ticket OCR driver.
import AppKit
import Foundation

let output = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/airborder-ticket-ocr", isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

func write(_ name: String, lines: [String]) throws {
    let size = NSSize(width: 1200, height: 700)
    let image = NSImage(size: size)
    image.lockFocus()
    NSColor.white.setFill()
    NSRect(origin: .zero, size: size).fill()
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedSystemFont(ofSize: 66, weight: .bold),
        .foregroundColor: NSColor.black
    ]
    for (index, line) in lines.enumerated() {
        (line as NSString).draw(at: NSPoint(x: 75, y: 510 - index * 110), withAttributes: attributes)
    }
    image.unlockFocus()
    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:]) else {
        fatalError("Could not render ticket fixture")
    }
    try png.write(to: output.appendingPathComponent(name))
}

try write("unreadable.png", lines: ["BOARDING PASS", "PLEASE TRY AGAIN"])
try write("readable.png", lines: ["BOARDING PASS", "NH 123", "HND - LAX", "2027-05-20"])
try write("sign-nonmatch.png", lines: ["BAGGAGE CLAIM"])
try write("sign-gates.png", lines: ["搭乗口", "Gates 105-109"])
print(output.path)
