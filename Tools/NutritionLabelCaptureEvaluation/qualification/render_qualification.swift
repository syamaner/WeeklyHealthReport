// Renders the two fictional route C qualification labels (plan section 8.2) as PNG files.
// Fictional products and values; nothing here is a real label. Usage:
//   xcrun swift render_qualification.swift <output folder>
import AppKit

struct Label {
    let name: String
    let lines: [(String, String, String)]  // label, column 1, column 2
    let title: String
    let header: (String, String, String)
    let footer: [String]
}

let labels = [
    Label(
        name: "qualification-zh-hant.png",
        lines: [
            ("熱量", "120大卡", "240大卡"), ("蛋白質", "3.5公克", "7.0公克"), ("脂肪", "4.0公克", "8.0公克"),
            ("　飽和脂肪", "1.5公克", "3.0公克"), ("　反式脂肪", "0公克", "0公克"), ("碳水化合物", "17.5公克", "35.0公克"),
            ("　糖", "6.0公克", "12.0公克"), ("鈉", "85毫克", "170毫克"),
        ],
        title: "營養標示",
        header: ("", "每份", "每100公克"),
        footer: ["每一份量50公克", "本包裝含4份"]
    ),
    Label(
        name: "qualification-en-uk.png",
        lines: [
            ("Energy", "1050kJ", "315kJ"), ("", "250kcal", "75kcal"), ("Fat", "9.0g", "2.7g"),
            ("of which saturates", "3.2g", "1.0g"), ("Carbohydrate", "36g", "10.8g"), ("of which sugars", "12g", "3.6g"),
            ("Fibre", "4.1g", "1.2g"), ("Protein", "6.0g", "1.8g"), ("Salt", "0.45g", "0.14g"),
        ],
        title: "NUTRITION",
        header: ("Typical values", "per 100g", "per 30g serving"),
        footer: ["This pack contains 10 servings"]
    ),
]

let out = URL(fileURLWithPath: CommandLine.arguments[1])
let width = 900.0
for label in labels {
    let rowHeight = 56.0
    let height = 120.0 + Double(label.lines.count + 1) * rowHeight + Double(label.footer.count) * rowHeight + 40
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(width), pixelsHigh: Int(height), bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
    else { fatalError("no bitmap") }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSColor.white.setFill()
    NSRect(x: 0, y: 0, width: width, height: height).fill()
    let font = NSFont(name: "PingFang TC", size: 30) ?? NSFont.systemFont(ofSize: 30)
    let bold = NSFont(name: "PingFangTC-Semibold", size: 38) ?? NSFont.boldSystemFont(ofSize: 38)
    let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]
    var y = height - 80
    (label.title as NSString).draw(at: NSPoint(x: 40, y: y), withAttributes: [.font: bold, .foregroundColor: NSColor.black])
    y -= rowHeight
    let columns = [40.0, 430.0, 660.0]
    for (index, text) in [label.header.0, label.header.1, label.header.2].enumerated() {
        (text as NSString).draw(at: NSPoint(x: columns[index], y: y), withAttributes: attributes)
    }
    NSColor.black.setFill()
    NSRect(x: 30, y: y - 8, width: width - 60, height: 3).fill()
    for line in label.lines {
        y -= rowHeight
        for (index, text) in [line.0, line.1, line.2].enumerated() {
            (text as NSString).draw(at: NSPoint(x: columns[index], y: y), withAttributes: attributes)
        }
    }
    for text in label.footer {
        y -= rowHeight
        (text as NSString).draw(at: NSPoint(x: 40, y: y), withAttributes: attributes)
    }
    NSGraphicsContext.restoreGraphicsState()
    guard let data = rep.representation(using: .png, properties: [:]) else { fatalError("no png") }
    try data.write(to: out.appendingPathComponent(label.name))
}
