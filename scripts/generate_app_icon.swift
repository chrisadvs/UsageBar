import Foundation
import AppKit

struct IconSpec {
    let filename: String
    let pointSize: Int
    let scale: Int
    var pixelSize: Int { pointSize * scale }
}

let iconSpecs: [IconSpec] = [
    IconSpec(filename: "icon_16x16.png", pointSize: 16, scale: 1),
    IconSpec(filename: "icon_16x16@2x.png", pointSize: 16, scale: 2),
    IconSpec(filename: "icon_32x32.png", pointSize: 32, scale: 1),
    IconSpec(filename: "icon_32x32@2x.png", pointSize: 32, scale: 2),
    IconSpec(filename: "icon_128x128.png", pointSize: 128, scale: 1),
    IconSpec(filename: "icon_128x128@2x.png", pointSize: 128, scale: 2),
    IconSpec(filename: "icon_256x256.png", pointSize: 256, scale: 1),
    IconSpec(filename: "icon_256x256@2x.png", pointSize: 256, scale: 2),
    IconSpec(filename: "icon_512x512.png", pointSize: 512, scale: 1),
    IconSpec(filename: "icon_512x512@2x.png", pointSize: 512, scale: 2)
]

let embeddedSVG = """
<svg viewBox="0 0 128 128" xmlns="http://www.w3.org/2000/svg">
  <defs>
    <linearGradient id="plate" x1="20%" y1="0%" x2="80%" y2="100%">
      <stop offset="0%" stop-color="#2A2F38"/>
      <stop offset="100%" stop-color="#14171C"/>
    </linearGradient>
  </defs>
  <rect x="0" y="0" width="128" height="128" rx="29" ry="29" fill="url(#plate)"/>
  <g transform="translate(25,25) scale(0.78)">
    <g transform="rotate(-90 50 50)">
      <circle cx="50" cy="50" r="36" fill="none" stroke="#C96442" stroke-width="14" stroke-linecap="round" stroke-dasharray="65 161.2" stroke-dashoffset="0"/>
      <circle cx="50" cy="50" r="36" fill="none" stroke="#4F7CFF" stroke-width="14" stroke-linecap="round" stroke-dasharray="65 161.2" stroke-dashoffset="-75.4"/>
      <circle cx="50" cy="50" r="36" fill="none" stroke="#2FB8A6" stroke-width="14" stroke-linecap="round" stroke-dasharray="65 161.2" stroke-dashoffset="-150.8"/>
    </g>
  </g>
</svg>
"""

func renderPNG(svgData: Data, pixelSize: Int) -> Data? {
    guard let img = NSImage(data: svgData) else {
        print("Error: Failed to parse SVG data")
        return nil
    }
    img.size = NSSize(width: pixelSize, height: pixelSize)

    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelSize,
        pixelsHigh: pixelSize,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        print("Error: Failed to create NSBitmapImageRep for size \(pixelSize)")
        return nil
    }
    rep.size = NSSize(width: pixelSize, height: pixelSize)

    NSGraphicsContext.saveGraphicsState()
    let ctx = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current = ctx
    ctx?.imageInterpolation = .high
    img.draw(
        in: NSRect(x: 0, y: 0, width: pixelSize, height: pixelSize),
        from: .zero,
        operation: .sourceOver,
        fraction: 1.0
    )
    NSGraphicsContext.restoreGraphicsState()

    return rep.representation(using: .png, properties: [:])
}

func main() {
    let fileManager = FileManager.default
    let currentDir = URL(fileURLWithPath: fileManager.currentDirectoryPath)

    // Locate SVG source file or fallback to embedded SVG
    let candidateSVGPaths = [
        currentDir.appendingPathComponent("Resources/AppIcon.svg"),
        currentDir.appendingPathComponent("scripts/AppIcon.svg")
    ]
    var svgData: Data = embeddedSVG.data(using: .utf8)!
    for candidate in candidateSVGPaths {
        if let data = try? Data(contentsOf: candidate) {
            print("Using SVG source from: \(candidate.path)")
            svgData = data
            break
        }
    }

    // Destination directories
    let iconsetDir = currentDir.appendingPathComponent("Resources/AppIcon.iconset")
    let appiconsetDir = currentDir.appendingPathComponent("Sources/TokenUsageWidget/Assets.xcassets/AppIcon.appiconset")

    try? fileManager.createDirectory(at: iconsetDir, withIntermediateDirectories: true)
    try? fileManager.createDirectory(at: appiconsetDir, withIntermediateDirectories: true)

    print("Generating icon bitmaps...")
    for spec in iconSpecs {
        guard let pngData = renderPNG(svgData: svgData, pixelSize: spec.pixelSize) else {
            fatalError("Failed to render PNG for \(spec.filename)")
        }

        // Write to Resources/AppIcon.iconset
        let iconsetTarget = iconsetDir.appendingPathComponent(spec.filename)
        try! pngData.write(to: iconsetTarget)

        // Write to Assets.xcassets/AppIcon.appiconset
        let appiconsetTarget = appiconsetDir.appendingPathComponent(spec.filename)
        try! pngData.write(to: appiconsetTarget)

        print("  ✓ \(spec.filename) (\(spec.pixelSize)x\(spec.pixelSize) px)")
    }

    // Write Contents.json for AppIcon.appiconset
    let contentsJSON = """
    {
      "images" : [
        {
          "filename" : "icon_16x16.png",
          "idiom" : "mac",
          "scale" : "1x",
          "size" : "16x16"
        },
        {
          "filename" : "icon_16x16@2x.png",
          "idiom" : "mac",
          "scale" : "2x",
          "size" : "16x16"
        },
        {
          "filename" : "icon_32x32.png",
          "idiom" : "mac",
          "scale" : "1x",
          "size" : "32x32"
        },
        {
          "filename" : "icon_32x32@2x.png",
          "idiom" : "mac",
          "scale" : "2x",
          "size" : "32x32"
        },
        {
          "filename" : "icon_128x128.png",
          "idiom" : "mac",
          "scale" : "1x",
          "size" : "128x128"
        },
        {
          "filename" : "icon_128x128@2x.png",
          "idiom" : "mac",
          "scale" : "2x",
          "size" : "128x128"
        },
        {
          "filename" : "icon_256x256.png",
          "idiom" : "mac",
          "scale" : "1x",
          "size" : "256x256"
        },
        {
          "filename" : "icon_256x256@2x.png",
          "idiom" : "mac",
          "scale" : "2x",
          "size" : "256x256"
        },
        {
          "filename" : "icon_512x512.png",
          "idiom" : "mac",
          "scale" : "1x",
          "size" : "512x512"
        },
        {
          "filename" : "icon_512x512@2x.png",
          "idiom" : "mac",
          "scale" : "2x",
          "size" : "512x512"
        }
      ],
      "info" : {
        "author" : "xcode",
        "version" : 1
      }
    }
    """
    let contentsURL = appiconsetDir.appendingPathComponent("Contents.json")
    try! contentsJSON.data(using: .utf8)!.write(to: contentsURL)
    print("  ✓ Wrote Contents.json to \(contentsURL.path)")

    // Run iconutil to create .icns
    let icnsURL = currentDir.appendingPathComponent("Resources/AppIcon.icns")
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
    process.arguments = ["-c", "icns", iconsetDir.path, "-o", icnsURL.path]
    do {
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus == 0 {
            print("  ✓ Successfully created \(icnsURL.path)")
        } else {
            print("Error: iconutil exited with status \(process.terminationStatus)")
            exit(process.terminationStatus != 0 ? process.terminationStatus : 1)
        }
    } catch {
        print("Error executing iconutil: \(error)")
        exit(1)
    }
}

main()
