import CoreGraphics

/// Original vector body figure (front and back) made of anatomical regions.
/// Pure CoreGraphics so it can be rendered by the app and by a standalone script.
/// Design space is 200 x 440 with the body centred on x = 100; right-side shapes are mirrored.
enum BodyFigure {
    enum Side { case front, back }

    struct Region {
        /// `MuscleGroup` raw value this region belongs to, or nil for parts that are never colored.
        let group: String?
        let path: CGPath
    }

    static let canvas = CGSize(width: 200, height: 440)

    private static func mirrored(_ p: CGPath) -> CGPath {
        var t = CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: canvas.width, ty: 0)
        return p.copy(using: &t) ?? p
    }

    /// The right-hand shape plus its mirror image.
    private static func pair(_ p: CGPath) -> CGPath {
        let m = CGMutablePath()
        m.addPath(p)
        m.addPath(mirrored(p))
        return m
    }

    private static func region(_ group: String?, _ build: (CGMutablePath) -> Void) -> Region {
        let p = CGMutablePath()
        build(p)
        p.closeSubpath()
        return Region(group: group, path: pair(p))
    }

    /// A shape that straddles the centre line is drawn once, not mirrored.
    private static func centre(_ group: String?, _ build: (CGMutablePath) -> Void) -> Region {
        let p = CGMutablePath()
        build(p)
        p.closeSubpath()
        return Region(group: group, path: p)
    }

    static func regions(_ side: Side) -> [Region] {
        switch side {
        case .front: return front
        case .back:  return back
        }
    }

    // MARK: Shared neutral parts

    private static let head = centre(nil) { p in
        p.addEllipse(in: CGRect(x: 80, y: 8, width: 40, height: 50))
    }

    private static let neck = centre(nil) { p in
        p.move(to: CGPoint(x: 88, y: 56))
        p.addLine(to: CGPoint(x: 112, y: 56))
        p.addCurve(to: CGPoint(x: 118, y: 80), control1: CGPoint(x: 112, y: 66), control2: CGPoint(x: 116, y: 72))
        p.addLine(to: CGPoint(x: 82, y: 80))
        p.addCurve(to: CGPoint(x: 88, y: 56), control1: CGPoint(x: 84, y: 72), control2: CGPoint(x: 88, y: 66))
    }

    private static let forearm = region(nil) { p in
        p.move(to: CGPoint(x: 151, y: 182))
        p.addCurve(to: CGPoint(x: 164, y: 192), control1: CGPoint(x: 158, y: 179), control2: CGPoint(x: 164, y: 184))
        p.addCurve(to: CGPoint(x: 160, y: 236), control1: CGPoint(x: 165, y: 208), control2: CGPoint(x: 163, y: 224))
        p.addCurve(to: CGPoint(x: 150, y: 242), control1: CGPoint(x: 158, y: 242), control2: CGPoint(x: 153, y: 244))
        p.addCurve(to: CGPoint(x: 151, y: 182), control1: CGPoint(x: 144, y: 222), control2: CGPoint(x: 145, y: 200))
    }

    private static let hand = region(nil) { p in
        p.addEllipse(in: CGRect(x: 146, y: 246, width: 17, height: 26))
    }

    private static let foot = region(nil) { p in
        p.move(to: CGPoint(x: 106, y: 414))
        p.addCurve(to: CGPoint(x: 128, y: 416), control1: CGPoint(x: 114, y: 410), control2: CGPoint(x: 124, y: 410))
        p.addCurve(to: CGPoint(x: 132, y: 432), control1: CGPoint(x: 132, y: 422), control2: CGPoint(x: 134, y: 428))
        p.addLine(to: CGPoint(x: 104, y: 432))
        p.addCurve(to: CGPoint(x: 106, y: 414), control1: CGPoint(x: 103, y: 424), control2: CGPoint(x: 104, y: 418))
    }

    private static let knee = region(nil) { p in
        p.addEllipse(in: CGRect(x: 105, y: 330, width: 28, height: 22))
    }

    private static let hips = centre(nil) { p in
        p.move(to: CGPoint(x: 66, y: 212))
        p.addCurve(to: CGPoint(x: 100, y: 222), control1: CGPoint(x: 80, y: 220), control2: CGPoint(x: 90, y: 224))
        p.addCurve(to: CGPoint(x: 134, y: 212), control1: CGPoint(x: 110, y: 224), control2: CGPoint(x: 120, y: 220))
        p.addCurve(to: CGPoint(x: 100, y: 236), control1: CGPoint(x: 132, y: 228), control2: CGPoint(x: 116, y: 236))
        p.addCurve(to: CGPoint(x: 66, y: 212), control1: CGPoint(x: 84, y: 236), control2: CGPoint(x: 68, y: 228))
    }

    // MARK: Solid body underneath the muscles

    private static let baseTorso = region(nil) { p in
        p.move(to: CGPoint(x: 100, y: 78))
        p.addLine(to: CGPoint(x: 126, y: 82))
        p.addCurve(to: CGPoint(x: 150, y: 96), control1: CGPoint(x: 138, y: 84), control2: CGPoint(x: 146, y: 90))
        p.addCurve(to: CGPoint(x: 140, y: 132), control1: CGPoint(x: 152, y: 108), control2: CGPoint(x: 144, y: 122))
        p.addCurve(to: CGPoint(x: 136, y: 214), control1: CGPoint(x: 138, y: 164), control2: CGPoint(x: 136, y: 190))
        p.addCurve(to: CGPoint(x: 138, y: 244), control1: CGPoint(x: 140, y: 226), control2: CGPoint(x: 142, y: 236))
        p.addLine(to: CGPoint(x: 100, y: 250))
    }

    private static let baseArm = region(nil) { p in
        p.move(to: CGPoint(x: 140, y: 112))
        p.addCurve(to: CGPoint(x: 167, y: 124), control1: CGPoint(x: 150, y: 108), control2: CGPoint(x: 164, y: 114))
        p.addCurve(to: CGPoint(x: 163, y: 188), control1: CGPoint(x: 172, y: 146), control2: CGPoint(x: 166, y: 170))
        p.addCurve(to: CGPoint(x: 161, y: 248), control1: CGPoint(x: 168, y: 210), control2: CGPoint(x: 164, y: 232))
        p.addLine(to: CGPoint(x: 148, y: 250))
        p.addCurve(to: CGPoint(x: 146, y: 186), control1: CGPoint(x: 144, y: 228), control2: CGPoint(x: 143, y: 204))
        p.addCurve(to: CGPoint(x: 140, y: 112), control1: CGPoint(x: 136, y: 166), control2: CGPoint(x: 134, y: 134))
    }

    private static let baseLeg = region(nil) { p in
        p.move(to: CGPoint(x: 102, y: 224))
        p.addLine(to: CGPoint(x: 138, y: 224))
        p.addCurve(to: CGPoint(x: 132, y: 326), control1: CGPoint(x: 146, y: 262), control2: CGPoint(x: 140, y: 300))
        p.addCurve(to: CGPoint(x: 134, y: 354), control1: CGPoint(x: 134, y: 336), control2: CGPoint(x: 136, y: 346))
        p.addCurve(to: CGPoint(x: 124, y: 414), control1: CGPoint(x: 138, y: 378), control2: CGPoint(x: 130, y: 400))
        p.addLine(to: CGPoint(x: 106, y: 414))
        p.addCurve(to: CGPoint(x: 106, y: 352), control1: CGPoint(x: 103, y: 392), control2: CGPoint(x: 102, y: 372))
        p.addCurve(to: CGPoint(x: 104, y: 326), control1: CGPoint(x: 106, y: 342), control2: CGPoint(x: 104, y: 334))
        p.addCurve(to: CGPoint(x: 102, y: 224), control1: CGPoint(x: 99, y: 296), control2: CGPoint(x: 99, y: 260))
    }

    // MARK: Shared muscle shapes (same outline front and back, different group)

    private static func deltoid() -> Region {
        region("Shoulders") { p in
            p.move(to: CGPoint(x: 118, y: 84))
            p.addCurve(to: CGPoint(x: 152, y: 88), control1: CGPoint(x: 130, y: 80), control2: CGPoint(x: 144, y: 82))
            p.addCurve(to: CGPoint(x: 166, y: 112), control1: CGPoint(x: 162, y: 94), control2: CGPoint(x: 168, y: 102))
            p.addCurve(to: CGPoint(x: 158, y: 138), control1: CGPoint(x: 166, y: 122), control2: CGPoint(x: 163, y: 132))
            p.addCurve(to: CGPoint(x: 140, y: 118), control1: CGPoint(x: 150, y: 134), control2: CGPoint(x: 142, y: 128))
            p.addCurve(to: CGPoint(x: 118, y: 84), control1: CGPoint(x: 134, y: 106), control2: CGPoint(x: 124, y: 94))
        }
    }

    private static func upperArm(_ group: String) -> Region {
        region(group) { p in
            p.move(to: CGPoint(x: 142, y: 124))
            p.addCurve(to: CGPoint(x: 164, y: 134), control1: CGPoint(x: 150, y: 122), control2: CGPoint(x: 160, y: 126))
            p.addCurve(to: CGPoint(x: 160, y: 176), control1: CGPoint(x: 167, y: 148), control2: CGPoint(x: 164, y: 164))
            p.addCurve(to: CGPoint(x: 146, y: 178), control1: CGPoint(x: 156, y: 180), control2: CGPoint(x: 150, y: 181))
            p.addCurve(to: CGPoint(x: 142, y: 124), control1: CGPoint(x: 138, y: 160), control2: CGPoint(x: 138, y: 138))
        }
    }

    private static func thigh() -> Region {
        region("Legs") { p in
            p.move(to: CGPoint(x: 103, y: 232))
            p.addCurve(to: CGPoint(x: 138, y: 232), control1: CGPoint(x: 116, y: 226), control2: CGPoint(x: 132, y: 224))
            p.addCurve(to: CGPoint(x: 130, y: 322), control1: CGPoint(x: 144, y: 262), control2: CGPoint(x: 138, y: 298))
            p.addCurve(to: CGPoint(x: 107, y: 322), control1: CGPoint(x: 124, y: 330), control2: CGPoint(x: 112, y: 330))
            p.addCurve(to: CGPoint(x: 103, y: 232), control1: CGPoint(x: 101, y: 296), control2: CGPoint(x: 100, y: 262))
        }
    }

    // MARK: Front

    private static let front: [Region] = [
        baseTorso, baseArm, baseLeg,
        head, neck, hips, forearm, hand, knee, foot,
        deltoid(),
        upperArm("Biceps"),
        // Pectoral
        region("Chest") { p in
            p.move(to: CGPoint(x: 103, y: 94))
            p.addCurve(to: CGPoint(x: 132, y: 98), control1: CGPoint(x: 114, y: 90), control2: CGPoint(x: 125, y: 92))
            p.addCurve(to: CGPoint(x: 136, y: 116), control1: CGPoint(x: 136, y: 104), control2: CGPoint(x: 138, y: 110))
            p.addCurve(to: CGPoint(x: 118, y: 136), control1: CGPoint(x: 134, y: 128), control2: CGPoint(x: 128, y: 136))
            p.addCurve(to: CGPoint(x: 103, y: 134), control1: CGPoint(x: 112, y: 138), control2: CGPoint(x: 106, y: 138))
        },
        // Abs: three blocks per side
        region("Core") { p in
            p.addRoundedRect(in: CGRect(x: 103, y: 142, width: 18, height: 22), cornerWidth: 6, cornerHeight: 6)
        },
        region("Core") { p in
            p.addRoundedRect(in: CGRect(x: 103, y: 168, width: 18, height: 22), cornerWidth: 6, cornerHeight: 6)
        },
        region("Core") { p in
            p.addRoundedRect(in: CGRect(x: 103, y: 194, width: 17, height: 20), cornerWidth: 6, cornerHeight: 6)
        },
        // Obliques
        region("Core") { p in
            p.move(to: CGPoint(x: 125, y: 142))
            p.addCurve(to: CGPoint(x: 133, y: 168), control1: CGPoint(x: 131, y: 148), control2: CGPoint(x: 134, y: 158))
            p.addCurve(to: CGPoint(x: 126, y: 212), control1: CGPoint(x: 133, y: 186), control2: CGPoint(x: 130, y: 202))
            p.addCurve(to: CGPoint(x: 125, y: 142), control1: CGPoint(x: 123, y: 190), control2: CGPoint(x: 122, y: 160))
        },
        thigh(),
        // Shin
        region("Legs") { p in
            p.move(to: CGPoint(x: 108, y: 354))
            p.addCurve(to: CGPoint(x: 130, y: 354), control1: CGPoint(x: 116, y: 350), control2: CGPoint(x: 126, y: 348))
            p.addCurve(to: CGPoint(x: 122, y: 410), control1: CGPoint(x: 134, y: 376), control2: CGPoint(x: 128, y: 398))
            p.addCurve(to: CGPoint(x: 108, y: 408), control1: CGPoint(x: 118, y: 414), control2: CGPoint(x: 110, y: 414))
            p.addCurve(to: CGPoint(x: 108, y: 354), control1: CGPoint(x: 104, y: 390), control2: CGPoint(x: 104, y: 370))
        },
    ]

    // MARK: Back

    private static let back: [Region] = [
        baseTorso, baseArm, baseLeg,
        head, neck, hips, forearm, hand, knee, foot,
        deltoid(),
        upperArm("Triceps"),
        // Trapezius
        centre("Back") { p in
            p.move(to: CGPoint(x: 100, y: 78))
            p.addCurve(to: CGPoint(x: 134, y: 88), control1: CGPoint(x: 112, y: 80), control2: CGPoint(x: 124, y: 84))
            p.addCurve(to: CGPoint(x: 136, y: 100), control1: CGPoint(x: 138, y: 92), control2: CGPoint(x: 138, y: 96))
            p.addCurve(to: CGPoint(x: 100, y: 130), control1: CGPoint(x: 128, y: 114), control2: CGPoint(x: 114, y: 126))
            p.addCurve(to: CGPoint(x: 66, y: 100), control1: CGPoint(x: 86, y: 126), control2: CGPoint(x: 72, y: 114))
            p.addCurve(to: CGPoint(x: 66, y: 88), control1: CGPoint(x: 62, y: 96), control2: CGPoint(x: 62, y: 92))
            p.addCurve(to: CGPoint(x: 100, y: 78), control1: CGPoint(x: 76, y: 84), control2: CGPoint(x: 88, y: 80))
        },
        // Latissimus
        region("Back") { p in
            p.move(to: CGPoint(x: 140, y: 108))
            p.addCurve(to: CGPoint(x: 138, y: 152), control1: CGPoint(x: 144, y: 122), control2: CGPoint(x: 142, y: 138))
            p.addCurve(to: CGPoint(x: 120, y: 196), control1: CGPoint(x: 134, y: 170), control2: CGPoint(x: 128, y: 186))
            p.addCurve(to: CGPoint(x: 104, y: 192), control1: CGPoint(x: 114, y: 198), control2: CGPoint(x: 108, y: 197))
            p.addCurve(to: CGPoint(x: 104, y: 136), control1: CGPoint(x: 100, y: 172), control2: CGPoint(x: 100, y: 152))
            p.addCurve(to: CGPoint(x: 140, y: 108), control1: CGPoint(x: 116, y: 134), control2: CGPoint(x: 132, y: 124))
        },
        // Glute
        region("Legs") { p in
            p.move(to: CGPoint(x: 103, y: 208))
            p.addCurve(to: CGPoint(x: 136, y: 214), control1: CGPoint(x: 116, y: 202), control2: CGPoint(x: 130, y: 204))
            p.addCurve(to: CGPoint(x: 132, y: 246), control1: CGPoint(x: 142, y: 224), control2: CGPoint(x: 140, y: 238))
            p.addCurve(to: CGPoint(x: 105, y: 244), control1: CGPoint(x: 122, y: 252), control2: CGPoint(x: 110, y: 252))
            p.addCurve(to: CGPoint(x: 103, y: 208), control1: CGPoint(x: 100, y: 232), control2: CGPoint(x: 100, y: 218))
        },
        // Hamstring
        region("Legs") { p in
            p.move(to: CGPoint(x: 104, y: 252))
            p.addCurve(to: CGPoint(x: 136, y: 252), control1: CGPoint(x: 116, y: 256), control2: CGPoint(x: 130, y: 256))
            p.addCurve(to: CGPoint(x: 130, y: 322), control1: CGPoint(x: 140, y: 276), control2: CGPoint(x: 136, y: 304))
            p.addCurve(to: CGPoint(x: 107, y: 322), control1: CGPoint(x: 124, y: 330), control2: CGPoint(x: 112, y: 330))
            p.addCurve(to: CGPoint(x: 104, y: 252), control1: CGPoint(x: 102, y: 296), control2: CGPoint(x: 101, y: 274))
        },
        // Calf
        region("Legs") { p in
            p.move(to: CGPoint(x: 108, y: 352))
            p.addCurve(to: CGPoint(x: 132, y: 354), control1: CGPoint(x: 116, y: 346), control2: CGPoint(x: 128, y: 346))
            p.addCurve(to: CGPoint(x: 124, y: 408), control1: CGPoint(x: 138, y: 374), control2: CGPoint(x: 130, y: 396))
            p.addCurve(to: CGPoint(x: 108, y: 406), control1: CGPoint(x: 120, y: 414), control2: CGPoint(x: 110, y: 412))
            p.addCurve(to: CGPoint(x: 108, y: 352), control1: CGPoint(x: 103, y: 388), control2: CGPoint(x: 102, y: 368))
        },
    ]
}
