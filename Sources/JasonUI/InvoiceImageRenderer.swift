import AppKit

@MainActor
enum InvoiceImageRenderer {
    private static let imageWidth: CGFloat = 1_200
    private static let margin: CGFloat = 64
    private static let tableTop: CGFloat = 242
    private static let tableHeaderHeight: CGFloat = 52
    private static let rowHeight: CGFloat = 58
    private static let accentGreen = NSColor(srgbRed: 0.09, green: 0.45, blue: 0.30, alpha: 1)
    private static let brandPurple = NSColor(srgbRed: 0.20, green: 0.08, blue: 0.34, alpha: 1)

    static func makeImage(records: [ExpenseRecord], issuedAt: Date = Date()) -> NSImage {
        let sortedRecords = records.sorted { $0.createdAt < $1.createdAt }
        let total = sortedRecords.reduce(0) { $0 + $1.amountInCents }
        let imageHeight = tableTop
            + tableHeaderHeight
            + CGFloat(sortedRecords.count) * rowHeight
            + margin
        let size = NSSize(width: imageWidth, height: imageHeight)
        let image = NSImage(size: size)

        image.lockFocus()
        defer { image.unlockFocus() }

        NSColor.white.setFill()
        NSRect(origin: .zero, size: size).fill()

        drawSummary(pageHeight: imageHeight, issuedAt: issuedAt, total: total)

        let tableWidth = imageWidth - margin * 2
        let headerY = size.height - tableTop - tableHeaderHeight
        NSColor(calibratedWhite: 0.94, alpha: 1).setFill()
        NSRect(x: margin, y: headerY, width: tableWidth, height: tableHeaderHeight).fill()
        NSColor.black.setFill()
        NSRect(x: margin, y: headerY + tableHeaderHeight - 2, width: tableWidth, height: 2).fill()

        let headingFont = invoiceFont(size: 25, weight: .bold)
        for (title, column, alignment) in [
            ("Purpose (用途)", Column.purpose, NSTextAlignment.left),
            ("Created (日期)", .created, .left),
            ("Amount (金额)", .amount, .right),
        ] {
            drawText(
                title,
                in: columnRect(y: headerY + 8, column: column, height: 36),
                font: headingFont,
                color: accentGreen,
                alignment: alignment
            )
        }

        var rowY = headerY - rowHeight
        for record in sortedRecords {
            drawText(
                record.purpose,
                in: columnRect(y: rowY + 18, column: .purpose),
                font: invoiceFont(size: 19, weight: .medium),
                color: .black
            )
            drawText(
                dateText(for: record.createdAt),
                in: columnRect(y: rowY + 18, column: .created),
                font: invoiceFont(size: 18, weight: .regular),
                color: NSColor(calibratedWhite: 0.46, alpha: 1)
            )
            drawText(
                formattedAmount(record.amountInCents),
                in: columnRect(y: rowY + 18, column: .amount),
                font: invoiceFont(size: 19, weight: .semibold),
                color: .black,
                alignment: .right
            )
            drawSeparator(at: rowY)
            rowY -= rowHeight
        }

        return image
    }

    nonisolated static func dateText(for date: Date) -> String {
        date.formatted(.iso8601.year().month().day())
    }

    private enum Column { case purpose, created, amount }

    private static func drawSummary(pageHeight: CGFloat, issuedAt: Date, total: Int64) {
        let left = margin + 20
        let right = imageWidth - margin - 20
        let rightColumnWidth: CGFloat = 540
        let rightColumnX = right - rightColumnWidth
        let labelFont = invoiceFont(size: 26, weight: .bold)
        let valueFont = invoiceFont(size: 26, weight: .regular)

        drawBrand(pageHeight: pageHeight, textLeft: left)
        drawText(
            "For:",
            in: NSRect(x: left, y: pageHeight - 177, width: 380, height: 36),
            font: labelFont,
            color: accentGreen
        )
        drawText(
            "Archer",
            in: NSRect(x: left, y: pageHeight - 212, width: 380, height: 36),
            font: valueFont
        )
        drawText(
            "Date Issued (开票日期):",
            in: NSRect(x: rightColumnX, y: pageHeight - 79, width: rightColumnWidth, height: 36),
            font: labelFont,
            color: accentGreen,
            alignment: .right
        )
        let issuedDate = issuedAt.formatted(Date.ISO8601FormatStyle(timeZone: .current).year().month().day())
        drawText(
            issuedDate,
            in: NSRect(x: rightColumnX, y: pageHeight - 114, width: rightColumnWidth, height: 36),
            font: valueFont,
            alignment: .right
        )
        drawText(
            "Total (合计):",
            in: NSRect(x: rightColumnX, y: pageHeight - 162, width: rightColumnWidth, height: 36),
            font: labelFont,
            color: accentGreen,
            alignment: .right
        )
        drawText(
            formattedAmount(total),
            in: NSRect(x: rightColumnX, y: pageHeight - 218, width: rightColumnWidth, height: 56),
            font: invoiceFont(size: 44, weight: .bold),
            alignment: .right
        )
    }

    private static func drawBrand(pageHeight: CGFloat, textLeft: CGFloat) {
        if let brandImage = loadBrandImage() {
            let available = NSSize(width: 395, height: 116)
            let scale = min(
                available.width / brandImage.size.width,
                available.height / brandImage.size.height
            )
            let drawnSize = NSSize(
                width: brandImage.size.width * scale,
                height: brandImage.size.height * scale
            )
            let destination = NSRect(
                x: margin + 5,
                y: pageHeight - 25 - drawnSize.height,
                width: drawnSize.width,
                height: drawnSize.height
            )
            // Tint the transparent logo in isolation so the white page stays white.
            let tintedBrand = NSImage(size: drawnSize)
            tintedBrand.lockFocus()
            let bounds = NSRect(origin: .zero, size: drawnSize)
            brandImage.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1)
            if let context = NSGraphicsContext.current?.cgContext {
                context.setBlendMode(.sourceAtop)
                context.setFillColor(brandPurple.cgColor)
                context.fill(bounds)
            }
            tintedBrand.unlockFocus()
            tintedBrand.draw(
                in: destination,
                from: .zero,
                operation: .sourceOver,
                fraction: 1,
                respectFlipped: true,
                hints: [.interpolation: NSImageInterpolation.high]
            )
        } else {
            drawText(
                "Galaxy® · A",
                in: NSRect(x: textLeft, y: pageHeight - 112, width: 380, height: 58),
                font: invoiceFont(size: 38, weight: .bold),
                color: brandPurple
            )
        }
    }

    static let brandImageName = "GalaxyArcherBrand"

    private static func loadBrandImage() -> NSImage? {
        guard let url = brandImageURL() else { return nil }
        return NSImage(contentsOf: url)
    }

    /// Where the brand image lives, or nil when it is not packaged.
    ///
    /// `Bundle.module` is deliberately avoided: it traps when SwiftPM's
    /// resource bundle is missing, and `a ?? Bundle.module...` evaluates both
    /// sides, so it brought the app down even when the main bundle already
    /// had the image. A missing decoration must never fail a bill.
    static func brandImageURL() -> URL? {
        if let url = Bundle.main.url(forResource: brandImageName, withExtension: "png") {
            return url
        }
        return resourceBundle()?.url(forResource: brandImageName, withExtension: "png")
    }

    /// SwiftPM's resource bundle, located by hand so that a missing one
    /// returns nil rather than trapping the way `Bundle.module` does.
    private static func resourceBundle() -> Bundle? {
        let roots = [
            Bundle.main.resourceURL,
            Bundle.main.bundleURL,
            Bundle.main.executableURL?.deletingLastPathComponent(),
        ].compactMap { $0 }

        for root in roots {
            let url = root.appendingPathComponent("JasonUI_JasonUI.bundle")
            if let bundle = Bundle(url: url) {
                return bundle
            }
        }
        return nil
    }

    private static func columnRect(y: CGFloat, column: Column, height: CGFloat = 28) -> NSRect {
        switch column {
        case .purpose:
            NSRect(x: margin + 20, y: y, width: 490, height: height)
        case .created:
            NSRect(x: 590, y: y, width: 230, height: height)
        case .amount:
            NSRect(x: imageWidth - margin - 250, y: y, width: 230, height: height)
        }
    }

    private static func drawSeparator(at y: CGFloat) {
        NSColor(calibratedWhite: 0.87, alpha: 1).setStroke()
        let separator = NSBezierPath()
        separator.move(to: NSPoint(x: margin, y: y))
        separator.line(to: NSPoint(x: imageWidth - margin, y: y))
        separator.lineWidth = 1
        separator.stroke()
    }

    private static func drawText(
        _ text: String,
        in rect: NSRect,
        font: NSFont,
        color: NSColor = .black,
        alignment: NSTextAlignment = .left
    ) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]
        (text as NSString).draw(in: rect, withAttributes: attributes)
    }

    private static func formattedAmount(_ cents: Int64) -> String {
        LedgerStore.formattedAmount(cents)
    }

    private static func invoiceFont(size: CGFloat, weight: NSFont.Weight) -> NSFont {
        let fontName: String
        switch weight {
        case .bold: fontName = "AvenirNext-Bold"
        case .semibold: fontName = "AvenirNext-DemiBold"
        case .medium: fontName = "AvenirNext-Medium"
        default: fontName = "AvenirNext-Regular"
        }
        return NSFont(name: fontName, size: size) ?? .systemFont(ofSize: size, weight: weight)
    }
}
