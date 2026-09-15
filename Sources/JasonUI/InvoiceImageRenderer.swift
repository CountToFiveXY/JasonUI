import AppKit

@MainActor
enum InvoiceImageRenderer {
    private static let imageWidth: CGFloat = 1_200
    private static let margin: CGFloat = 64
    private static let tableHeaderHeight: CGFloat = 52
    private static let rowHeight: CGFloat = 58
    private static let totalHeight: CGFloat = 76
    private static let bottomWhitespace: CGFloat = 150
    private static let brandHeaderHeight: CGFloat = 300

    static func makeImage(records: [ExpenseRecord], currencyCode: String) -> NSImage {
        let sortedRecords = records.sorted { $0.createdAt < $1.createdAt }
        // Keep the table visually attached to the two header cards.
        let tableTop: CGFloat = 230
        let imageHeight = tableTop
            + tableHeaderHeight
            + CGFloat(sortedRecords.count) * rowHeight
            + totalHeight
            + bottomWhitespace
        let size = NSSize(width: imageWidth, height: max(imageHeight, 386))
        let image = NSImage(size: size)

        image.lockFocus()
        defer { image.unlockFocus() }

        NSColor.white.setFill()
        NSRect(origin: .zero, size: size).fill()

        drawBrandHeader(in: size)

        let tableWidth = imageWidth - margin * 2
        let headerY = size.height - tableTop - tableHeaderHeight
        NSColor(calibratedWhite: 0.94, alpha: 1).setFill()
        NSRect(x: margin, y: headerY, width: tableWidth, height: tableHeaderHeight).fill()
        drawText("Purpose (用途)", in: columnRect(y: headerY + 16, column: .purpose), header: true)
        drawText("Created (日期)", in: columnRect(y: headerY + 16, column: .created), header: true)
        drawText(
            "Amount (金额)",
            in: columnRect(y: headerY + 16, column: .amount),
            header: true,
            alignment: .right
        )

        var rowY = headerY - rowHeight
        for record in sortedRecords {
            drawText(
                record.purpose,
                in: columnRect(y: rowY + 18, column: .purpose),
                font: invoiceFont(size: 19, weight: .medium),
                color: .labelColor
            )
            drawText(
                dateText(for: record.createdAt),
                in: columnRect(y: rowY + 18, column: .created),
                font: invoiceFont(size: 18, weight: .regular),
                color: .secondaryLabelColor
            )
            drawText(
                formattedAmount(record.amountInCents, currencyCode: currencyCode),
                in: columnRect(y: rowY + 18, column: .amount),
                font: invoiceFont(size: 19, weight: .semibold),
                color: .labelColor,
                alignment: .right
            )
            drawSeparator(at: rowY)
            rowY -= rowHeight
        }

        let totalY = rowY - totalHeight
        NSColor.systemIndigo.withAlphaComponent(0.11).setFill()
        NSBezierPath(
            roundedRect: NSRect(x: margin, y: totalY, width: tableWidth, height: totalHeight),
            xRadius: 10,
            yRadius: 10
        ).fill()
        drawText(
            "Total (合计)",
            in: NSRect(x: margin + 20, y: totalY + 24, width: 260, height: 30),
            font: invoiceFont(size: 20, weight: .bold),
            color: .systemIndigo
        )
        drawText(
            formattedAmount(
                sortedRecords.reduce(0) { $0 + $1.amountInCents },
                currencyCode: currencyCode
            ),
            in: NSRect(x: imageWidth - margin - 270, y: totalY + 20, width: 250, height: 36),
            font: invoiceFont(size: 26, weight: .bold),
            color: .systemIndigo,
            alignment: .right
        )

        return image
    }

    nonisolated static func dateText(for date: Date) -> String {
        date.formatted(.iso8601.year().month().day())
    }

    private enum Column { case purpose, created, amount }

    private static func drawBrandHeader(in size: NSSize) {
        let headerRect = NSRect(
            x: 0,
            y: size.height - brandHeaderHeight,
            width: imageWidth,
            height: brandHeaderHeight
        )
        let gradient = NSGradient(
            starting: NSColor(calibratedRed: 0.025, green: 0.018, blue: 0.045, alpha: 1),
            ending: NSColor(calibratedRed: 0.16, green: 0.055, blue: 0.29, alpha: 1)
        )!
        let brandPanel = NSRect(
            x: margin,
            y: headerRect.minY + 94,
            width: 430,
            height: 158
        )
        gradient.draw(in: brandPanel, angle: 0)

        let payerPanel = NSRect(
            x: 714,
            y: brandPanel.minY,
            width: imageWidth - 714 - margin,
            height: brandPanel.height
        )
        NSColor(calibratedRed: 0.92, green: 0.90, blue: 0.95, alpha: 1).setFill()
        NSBezierPath(roundedRect: payerPanel, xRadius: 8, yRadius: 8).fill()

        drawText(
            "To: Archer (付款人)",
            in: NSRect(
                x: payerPanel.minX + 28,
                y: payerPanel.minY + 50,
                width: payerPanel.width - 56,
                height: 48
            ),
            font: invoiceFont(size: 28, weight: .semibold),
            color: NSColor(calibratedRed: 0.20, green: 0.08, blue: 0.34, alpha: 1)
        )

        if let brandImage = loadBrandImage() {
            let available = NSSize(width: brandPanel.width - 44, height: brandPanel.height - 28)
            let scale = min(
                available.width / brandImage.size.width,
                available.height / brandImage.size.height
            )
            let drawnSize = NSSize(
                width: brandImage.size.width * scale,
                height: brandImage.size.height * scale
            )
            let destination = NSRect(
                x: brandPanel.minX + (brandPanel.width - drawnSize.width) / 2,
                y: brandPanel.minY + (brandPanel.height - drawnSize.height) / 2,
                width: drawnSize.width,
                height: drawnSize.height
            )
            brandImage.draw(
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
                in: NSRect(
                    x: brandPanel.minX + 20,
                    y: brandPanel.minY + 52,
                    width: brandPanel.width - 40,
                    height: 58
                ),
                font: invoiceFont(size: 38, weight: .bold),
                color: .white,
                alignment: .center
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

    private static func columnRect(y: CGFloat, column: Column) -> NSRect {
        switch column {
        case .purpose:
            NSRect(x: margin + 20, y: y, width: 490, height: 28)
        case .created:
            NSRect(x: 590, y: y, width: 230, height: 28)
        case .amount:
            NSRect(x: imageWidth - margin - 250, y: y, width: 230, height: 28)
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
        font: NSFont = .systemFont(ofSize: 16),
        color: NSColor = .secondaryLabelColor,
        header: Bool = false,
        alignment: NSTextAlignment = .left
    ) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [
            .font: header ? invoiceFont(size: 16, weight: .semibold) : font,
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]
        (text as NSString).draw(in: rect, withAttributes: attributes)
    }

    private static func formattedAmount(_ cents: Int64, currencyCode: String) -> String {
        (Decimal(cents) / 100).formatted(.currency(code: currencyCode))
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
