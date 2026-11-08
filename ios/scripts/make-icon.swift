// App Store 用のアプリアイコン（1024×1024、角丸・透過なし）を描く。図柄は Web 版の icons/icon-512.png と同じダンベル
// 使い方：swift ios/scripts/make-icon.swift ios/LiftLog/Assets.xcassets/AppIcon.appiconset/icon-1024.png
import AppKit

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon-1024.png"
let size = 1024
let k = CGFloat(size) / 512
guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                          space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { exit(1) }
func color(_ hex: UInt32) -> CGColor {
  CGColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255, blue: CGFloat(hex & 0xff) / 255, alpha: 1)
}
// 512px の図での座標（y は上から）
func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat, _ c: UInt32) {
  let rr = CGRect(x: x * k, y: CGFloat(size) - (y + h) * k, width: w * k, height: h * k)
  ctx.addPath(CGPath(roundedRect: rr, cornerWidth: r * k, cornerHeight: r * k, transform: nil))
  ctx.setFillColor(color(c))
  ctx.fillPath()
}
ctx.setFillColor(color(0x0d0d0d))
ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
rect(113, 180, 42, 152, 10, 0xffd400)   // 左の黄色いプレート
rect(357, 180, 42, 152, 10, 0xffd400)   // 右の黄色いプレート
rect(153, 143, 42, 226, 12, 0xf2f2f2)   // 左の白いプレート
rect(317, 143, 42, 226, 12, 0xf2f2f2)   // 右の白いプレート
rect(92, 238, 328, 36, 6, 0xf2f2f2)     // バー

let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("書き出しました: \(out)")
