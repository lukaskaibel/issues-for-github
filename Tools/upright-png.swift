import AppKit

// upright-png <file>...: rewrites screenshots so their pixels stand upright. Test screenshots of a turned iPad
// keep the screen's portrait pixels and say how to turn them; apps that ignore that would show them sideways.
for path in CommandLine.arguments.dropFirst() {
    guard let image = NSImage(contentsOfFile: path),
          let upright = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
          let png = NSBitmapImageRep(cgImage: upright).representation(using: .png, properties: [:]) else {
        FileHandle.standardError.write(Data("Could not read \(path)\n".utf8))
        exit(1)
    }
    try png.write(to: URL(fileURLWithPath: path))
}
