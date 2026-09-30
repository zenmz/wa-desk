// Gambar icon wa-desk ke PNG 1024x1024 dengan CoreGraphics. Dipanggil build.sh:
//   swiftc -O icon/make-icon.swift -o make-icon -framework AppKit && ./make-icon out.png
import AppKit

let size: CGFloat = 1024
let out = CommandLine.arguments.dropFirst().first ?? "icon-1024.png"
let cs = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8,
                    bytesPerRow: 0, space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: cs, components: [CGFloat((hex >> 16) & 0xFF) / 255,
                                         CGFloat((hex >> 8) & 0xFF) / 255,
                                         CGFloat(hex & 0xFF) / 255, alpha])!
}
func rounded(_ r: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

// Grid icon macOS: tile 824x824 di tengah kanvas 1024.
let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
let tilePath = rounded(tile, 185)

// Bayangan tile.
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 44, color: rgb(0x000000, 0.35))
ctx.addPath(tilePath); ctx.setFillColor(rgb(0x065F46)); ctx.fillPath()
ctx.restoreGState()

// Gradien emerald diagonal + cahaya lembut kiri-atas.
ctx.saveGState()
ctx.addPath(tilePath); ctx.clip()
let grad = CGGradient(colorsSpace: cs, colors: [rgb(0x34D399), rgb(0x059669), rgb(0x065F46)] as CFArray,
                      locations: [0, 0.55, 1])!
ctx.drawLinearGradient(grad, start: CGPoint(x: tile.minX, y: tile.maxY),
                       end: CGPoint(x: tile.maxX, y: tile.minY), options: [])
let light = CGGradient(colorsSpace: cs, colors: [rgb(0xFFFFFF, 0.30), rgb(0xFFFFFF, 0)] as CFArray,
                       locations: [0, 1])!
let lightCenter = CGPoint(x: tile.minX + 230, y: tile.maxY - 130)
ctx.drawRadialGradient(light, startCenter: lightCenter, startRadius: 0,
                       endCenter: lightCenter, endRadius: 640, options: [])
ctx.restoreGState()

// Gelembung chat putih dengan ekor kiri-bawah. Digambar dalam satu transparency layer
// supaya bayangannya satu, bukan dobel di area tumpang tindih.
let bubble = CGRect(x: 232, y: 360, width: 560, height: 400)
let tail = CGMutablePath()
tail.move(to: CGPoint(x: bubble.minX + 70, y: bubble.minY + 60))
tail.addLine(to: CGPoint(x: bubble.minX + 10, y: bubble.minY - 92))
tail.addLine(to: CGPoint(x: bubble.minX + 214, y: bubble.minY + 2))
tail.closeSubpath()

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -20), blur: 40, color: rgb(0x022C22, 0.45))
ctx.beginTransparencyLayer(auxiliaryInfo: nil)
ctx.setFillColor(rgb(0xFFFFFF))
ctx.addPath(rounded(bubble, 120)); ctx.fillPath()
ctx.addPath(tail); ctx.fillPath()
ctx.endTransparencyLayer()
ctx.restoreGState()

// Dua baris pesan di dalam gelembung.
func line(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ color: CGColor) {
    ctx.addPath(rounded(CGRect(x: x, y: y, width: w, height: 64), 32))
    ctx.setFillColor(color); ctx.fillPath()
}
line(bubble.minX + 96, bubble.midY + 30, 368, rgb(0x059669))
line(bubble.minX + 96, bubble.midY - 82, 232, rgb(0x34D399))

let png = NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])!
try! png.write(to: URL(fileURLWithPath: out))
