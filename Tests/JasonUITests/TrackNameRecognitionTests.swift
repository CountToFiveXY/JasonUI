import Foundation
import Testing
@testable import JasonUI

struct TrackNameRecognitionTests {
    private func track(_ name: String, map: String = "Shanghai", chinese: String? = nil) -> MapTrackSummary {
        MapTrackSummary(id: name.lowercased().replacingOccurrences(of: " ", with: "-"), name: name,
                        chineseName: chinese, mapID: map.lowercased(), mapName: map, mapChineseName: nil)
    }

    private func line(_ text: String, x: Double, y: Double, width: Double = 150) -> RecognizedLine {
        RecognizedLine(text: text, confidence: 0.98,
                       bounds: RecognizedTextBounds(x: x, y: y, width: width, height: 20))
    }

    @Test func joinsScreenshotCaptionAndIgnoresMapHeading() throws {
        // Actual Cloud Vision result for the supplied Shanghai screenshot.
        let data = Data(#"""
        {"text":"SHANGHAI\nDOUBLE\nROUNDABOUT","lines":[
          {"text":"SHANGHAI","confidence":0.991,"bounds":{"x":86,"y":264,"width":192,"height":33}},
          {"text":"DOUBLE","confidence":0.992,"bounds":{"x":119,"y":322,"width":128,"height":29}},
          {"text":"ROUNDABOUT","confidence":0.994,"bounds":{"x":65,"y":363,"width":240,"height":27}}
        ]}
        """#.utf8)
        let recognized = try JSONDecoder().decode(RecognizedText.self, from: data)
        #expect(TrackNameRecognition.names(from: recognized.lines, catalogue: [track("Double Roundabout")]) == ["DOUBLE ROUNDABOUT"])
    }

    @Test func joinsThreeOrMoreLines() {
        let lines = [line("A", x: 65, y: 0, width: 20), line("PARK", x: 45, y: 25, width: 60),
                     line("IN A", x: 45, y: 50, width: 60), line("RUN", x: 40, y: 75, width: 70)]
        #expect(TrackNameRecognition.names(from: lines, catalogue: [track("A Park in a Run")]) == ["A PARK IN A RUN"])
    }

    @Test func interleavedOCRRowsKeepCardOrderAndRepeatedTracks() {
        let lines = [line("DOUBLE", x: 260, y: 0, width: 80),
                     line("NOTRE DAME", x: 0, y: 25),
                     line("ROUNDABOUT", x: 220, y: 25, width: 160),
                     line("NOTRE DAME", x: 440, y: 25)]
        #expect(TrackNameRecognition.names(from: lines, catalogue: [track("Double Roundabout"), track("Notre Dame")])
                == ["NOTRE DAME", "DOUBLE ROUNDABOUT", "NOTRE DAME"])
    }

    @Test func neverJoinsDifferentCardsOrDistantRows() {
        let lines = [line("DOUBLE", x: 0, y: 0, width: 80), line("ROUNDABOUT", x: 300, y: 25),
                     line("ROUNDABOUT", x: 0, y: 200)]
        #expect(TrackNameRecognition.names(from: lines, catalogue: [track("Double Roundabout")])
                == ["DOUBLE", "ROUNDABOUT", "ROUNDABOUT"])
    }

    @Test func adjacentLinesWorkWithOlderBackendAndKeepUnmatchedText() {
        let lines = ["DOUBLE", "ROUNDABOUT", "NOT A TRACK"].map { RecognizedLine(text: $0, confidence: 1) }
        #expect(TrackNameRecognition.names(from: lines, catalogue: [track("Double Roundabout")])
                == ["DOUBLE ROUNDABOUT", "NOT A TRACK"])
    }

    @Test func prefersFullNameWhenFirstLineAlsoNamesATrack() {
        let lines = [line("DOUBLE", x: 40, y: 0, width: 80), line("ROUNDABOUT", x: 0, y: 25, width: 160)]
        #expect(TrackNameRecognition.names(from: lines, catalogue: [track("Double"), track("Double Roundabout")])
                == ["DOUBLE ROUNDABOUT"])
    }

    @Test func keepsSingleParagraphNamesAndSupportsChineseNames() {
        let lines = [RecognizedLine(text: "DOUBLE\nROUNDABOUT", confidence: 1),
                     RecognizedLine(text: "双", confidence: 1), RecognizedLine(text: "环岛", confidence: 1)]
        #expect(TrackNameRecognition.names(from: lines, catalogue: [track("Double Roundabout", chinese: "双环岛")])
                == ["DOUBLE\nROUNDABOUT", "双 环岛"])
    }
}
