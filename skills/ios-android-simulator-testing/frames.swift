// Video → frames + one contact sheet, so a model that reads images can "watch" a recording.
// Uses AVFoundation (ships with Xcode), no ffmpeg needed.
//   swift frames.swift <video.mp4> <out-dir> [count=12]
// Writes <out-dir>/frame-01.png … and <out-dir>/sheet.png (frames in a 4-column grid, time order).
import AVFoundation
import AppKit

let args = CommandLine.arguments
guard args.count >= 3 else { print("usage: swift frames.swift <video> <out-dir> [count]"); exit(1) }
let out = URL(fileURLWithPath: args[2])
let count = args.count > 3 ? max(1, Int(args[3]) ?? 12) : 12
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

let asset = AVURLAsset(url: URL(fileURLWithPath: args[1]))
let duration = CMTimeGetSeconds(asset.duration)
guard duration > 0 else { print("frames: empty or unreadable video"); exit(1) }
let gen = AVAssetImageGenerator(asset: asset)
gen.appliesPreferredTrackTransform = true
gen.requestedTimeToleranceBefore = .zero
gen.requestedTimeToleranceAfter = .zero

func png(_ img: CGImage, _ url: URL) {
    let rep = NSBitmapImageRep(cgImage: img)
    try? rep.representation(using: .png, properties: [:])?.write(to: url)
}

var frames: [CGImage] = []
for i in 0..<count {
    let t = duration * (Double(i) + 0.5) / Double(count)  // evenly spread, skip the very first/last frame
    guard let img = try? gen.copyCGImage(at: CMTime(seconds: t, preferredTimescale: 600), actualTime: nil) else { continue }
    frames.append(img)
    png(img, out.appendingPathComponent(String(format: "frame-%02d.png", i + 1)))
}
guard let first = frames.first else { print("frames: no frames decoded"); exit(1) }

// Contact sheet: 4 columns, each frame scaled to 300 px wide.
let cols = min(4, frames.count), rows = (frames.count + cols - 1) / cols
let w = 300, h = Int(Double(first.height) * 300 / Double(first.width)), gap = 8
let W = cols * w + (cols + 1) * gap, H = rows * h + (rows + 1) * gap
let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.setFillColor(CGColor(gray: 0.5, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
for (i, img) in frames.enumerated() {
    let x = gap + (i % cols) * (w + gap), y = H - (gap + (i / cols) * (h + gap)) - h  // row 0 on top
    ctx.draw(img, in: CGRect(x: x, y: y, width: w, height: h))
}
png(ctx.makeImage()!, out.appendingPathComponent("sheet.png"))
print(out.appendingPathComponent("sheet.png").path + "  (\(frames.count) frames over \(String(format: "%.1f", duration)) s, left→right, top→bottom)")
