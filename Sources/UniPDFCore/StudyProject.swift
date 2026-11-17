import Foundation

public struct StudyProject: Codable, Sendable {
    /// 2 added slide annotations; 3 text highlights; 4 comments. Older projects still open.
    public static let currentVersion = 4
    public var version = currentVersion
    public var title: String
    public var pdfData: Data?
    public var pages: [Int: PageNotes]

    public init(title: String = String(localized: "New Lecture"), pdfData: Data? = nil, pages: [Int: PageNotes] = [:]) {
        self.title = title
        self.pdfData = pdfData
        self.pages = pages
    }

    public static func decode(_ data: Data) throws -> StudyProject {
        var project = try JSONDecoder().decode(Self.self, from: data)
        guard (1...currentVersion).contains(project.version) else { throw ProjectError.unsupportedVersion }
        guard project.pages.keys.allSatisfy({ $0 >= 0 }),
              project.pages.values.allSatisfy({ $0.drawing.allSatisfy(\.isValid) && $0.annotations.allSatisfy(\.isValid) }) else {
            throw ProjectError.invalidData
        }
        project.version = currentVersion
        return project
    }

    public func encoded() throws -> Data { try JSONEncoder().encode(self) }
}

public enum ProjectError: LocalizedError {
    case unsupportedVersion, invalidData, invalidPDF, lockedPDF, exportFailed, invalidImage

    public var errorDescription: String? {
        switch self {
        case .unsupportedVersion: String(localized: "This project needs a newer version of UniPDF.")
        case .invalidData: String(localized: "The project file contains invalid data. Open a different file or a backup.")
        case .invalidPDF: String(localized: "This file does not contain a readable PDF. Choose a different PDF.")
        case .lockedPDF: String(localized: "This PDF is protected. Unlock it in Preview first and import an unprotected copy.")
        case .exportFailed: String(localized: "The study PDF could not be created. Try again.")
        case .invalidImage: String(localized: "This image cannot be read. Choose a PNG, JPEG, HEIC or TIFF image.")
        }
    }
}

public struct PageNotes: Codable, Sendable, Equatable {
    public var text = ""
    public var formula = ""
    public var drawing: [InkElement] = []
    /// Placed on the slide itself, unlike `drawing`, which is a sketch in the notes column.
    public var annotations: [SlideAnnotation] = []
    public init() {}
    public var isEmpty: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        formula.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && drawing.isEmpty && annotations.isEmpty
    }

    private enum CodingKeys: String, CodingKey { case text, formula, drawing, annotations }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        text = try container.decode(String.self, forKey: .text)
        formula = try container.decode(String.self, forKey: .formula)
        drawing = try container.decode([InkElement].self, forKey: .drawing)
        // Projects of version 1 have none.
        annotations = try container.decodeIfPresent([SlideAnnotation].self, forKey: .annotations) ?? []
    }
}

public enum InkTool: String, Codable, CaseIterable, Sendable {
    case pen, line, arrow, rectangle, ellipse
    public var label: String {
        switch self {
        case .pen: String(localized: "Pen")
        case .line: String(localized: "Line")
        case .arrow: String(localized: "Arrow")
        case .rectangle: String(localized: "Rectangle")
        case .ellipse: String(localized: "Ellipse")
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
        case .graphite: String(localized: "Graphite")
        case .blue: String(localized: "Blue")
        case .red: String(localized: "Red")
        case .green: String(localized: "Green")
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
