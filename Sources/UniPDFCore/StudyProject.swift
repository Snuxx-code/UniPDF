import Foundation

public struct StudyProject: Codable, Sendable {
    public var version = 1
    public var title: String
    public var pdfData: Data?
    public var pages: [Int: PageNotes]

    public init(title: String = "Neue Vorlesung", pdfData: Data? = nil, pages: [Int: PageNotes] = [:]) {
        self.title = title
        self.pdfData = pdfData
        self.pages = pages
    }

    public static func decode(_ data: Data) throws -> StudyProject {
        let project = try JSONDecoder().decode(Self.self, from: data)
        guard project.version == 1 else { throw ProjectError.unsupportedVersion }
        guard project.pages.keys.allSatisfy({ $0 >= 0 }),
              project.pages.values.allSatisfy({ $0.drawing.allSatisfy(\.isValid) }) else {
            throw ProjectError.invalidData
        }
        return project
    }

    public func encoded() throws -> Data { try JSONEncoder().encode(self) }
}

public enum ProjectError: LocalizedError {
    case unsupportedVersion, invalidData, invalidPDF, lockedPDF, exportFailed

    public var errorDescription: String? {
        switch self {
        case .unsupportedVersion: "Dieses Projekt benötigt eine neuere Version von UniPDF."
        case .invalidData: "Die Projektdatei enthält ungültige Daten. Öffne eine andere Datei oder eine Sicherung."
        case .invalidPDF: "Diese Datei enthält kein lesbares PDF. Wähle ein anderes PDF."
        case .lockedPDF: "Dieses PDF ist geschützt. Entsperre es zuerst in Vorschau und importiere eine ungeschützte Kopie."
        case .exportFailed: "Das Lern-PDF konnte nicht erstellt werden. Versuche es erneut."
        }
    }
}

public struct PageNotes: Codable, Sendable, Equatable {
    public var text = ""
    public var formula = ""
    public var drawing: [InkElement] = []
    public init() {}
    public var isEmpty: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        formula.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && drawing.isEmpty
    }
}

public enum InkTool: String, Codable, CaseIterable, Sendable {
    case pen, line, arrow, rectangle, ellipse
    public var label: String {
        switch self {
        case .pen: "Stift"
        case .line: "Linie"
        case .arrow: "Pfeil"
        case .rectangle: "Rechteck"
        case .ellipse: "Ellipse"
        }
    }
    public var symbol: String {
        switch self {
        case .pen: "pencil.tip"
        case .line: "line.diagonal"
        case .arrow: "arrow.up.right"
        case .rectangle: "rectangle"
        case .ellipse: "circle"
        }
    }
}

public enum InkColor: String, Codable, CaseIterable, Sendable {
    case graphite, blue, red, green
    public var label: String {
        switch self {
        case .graphite: "Graphit"
        case .blue: "Blau"
        case .red: "Rot"
        case .green: "Grün"
        }
    }
}

public struct InkPoint: Codable, Sendable, Equatable {
    public var x: Double
    public var y: Double
    public init(x: Double, y: Double) { self.x = x; self.y = y }
}

public struct InkElement: Codable, Sendable, Equatable, Identifiable {
    public var id = UUID()
    public var tool: InkTool
    public var color: InkColor
    public var width: Double
    public var points: [InkPoint]
    public init(tool: InkTool, color: InkColor, width: Double = 2.5, points: [InkPoint]) {
        self.tool = tool; self.color = color; self.width = width; self.points = points
    }
    public var isValid: Bool {
        width.isFinite && width > 0 && width <= 30 && !points.isEmpty &&
        points.allSatisfy { $0.x.isFinite && $0.y.isFinite && (0...800).contains($0.x) && (0...500).contains($0.y) }
    }
}
