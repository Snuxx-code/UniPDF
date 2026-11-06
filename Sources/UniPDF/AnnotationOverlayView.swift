import AppKit
import PDFKit
import UniformTypeIdentifiers
import UniPDFCore

enum AnnotationTool: Equatable {
    case select, pen, text, highlight, eraser
    case shape(SlideShape)
}

enum AnnotationKind { case stroke, text, image, highlight, eraser }

struct AnnotationStyle: Equatable {
    var color = AnnotationColor(InkColor.blue)
    var highlightColor = PDFTextHighlight.yellow
    var lineWidth = 2.0
    /// In slide points, like the stroke width.
    var eraserRadius = 10.0
    /// Whether the eraser removes a whole stroke or highlight as soon as it touches it.
    var erasesWholeStrokes = false
    var text = SlideTextStyle()
}

/// The PDF with the annotation layer on top. Siblings, because PDFView manages its own subviews.
final class SlideCanvasView: NSView {
    let pdfView = SlidePDFView()
    let highlights = HighlightLayerView()
    let overlay: AnnotationOverlayView

    init(session: PDFSession) {
        overlay = AnnotationOverlayView(session: session, pdfView: pdfView)
        super.init(frame: .zero)
        pdfView.overlay = overlay
        overlay.highlightLayer = highlights
        highlights.overlay = overlay
        for view in [pdfView, highlights, overlay] {
            view.frame = bounds
            view.autoresizingMask = [.width, .height]
            addSubview(view)
        }
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("Not used from a coder") }
}

/// Text highlights between the PDF and the other annotations. The layer multiplies with the slide,
/// as a highlighter on paper does, so that dark text keeps its contrast instead of being tinted.
final class HighlightLayerView: NSView {
    weak var overlay: AnnotationOverlayView?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        clipsToBounds = true
        compositingFilter = CIFilter(name: "CIMultiplyBlendMode")
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("Not used from a coder") }

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) { overlay?.drawHighlights(dirtyRect) }
}

final class SlidePDFView: PDFView {
    weak var overlay: AnnotationOverlayView?

    override func setCursorFor(_ area: PDFAreaOfInterest) {
        if overlay?.ownsCursor != true { super.setCursorFor(area) }
    }

    override func layout() {
        super.layout()
        overlay?.pageGeometryDidChange()
    }

    // After a click on the slide this view is focused. A screenshot should still land on the slide.
    @objc func paste(_ sender: Any?) { overlay?.paste(sender) }
}

/// Draws the annotations of the current slide and handles the tools. Anything the tools do not
/// claim falls through to the PDF, so text selection, links and scrolling keep working.
final class AnnotationOverlayView: NSView, NSTextViewDelegate, NSMenuItemValidation {
    private enum Handle: Equatable {
        case corner(atMaxX: Bool, atMaxY: Bool)
        case start, end
    }

    private enum Drag {
        case draw(start: CGPoint)
        case highlight(start: CGPoint, viewStart: CGPoint)
        case erase(last: CGPoint, erased: Bool)
        case move(original: SlideAnnotation, start: CGPoint, moved: Bool)
        case resize(original: SlideAnnotation, handle: Handle, resized: Bool)
    }

    private static let pasteboardType = NSPasteboard.PasteboardType("de.unipdf.slide-annotation")
    private static let selectionColor = NSColor(srgbRed: 0.16, green: 0.40, blue: 0.34, alpha: 1)
    private static let handleSize: CGFloat = 8
    private static let minimumSize: CGFloat = 4

    private let session: PDFSession
    private weak var pdfView: PDFView?
    private var observedClipView: NSClipView?
    private var annotations: [SlideAnnotation] = []
    private var pageIndex = 0
    private var onChange: (([SlideAnnotation]) -> Void)?
    private var drag: Drag?
    private var draft: SlideAnnotation?
    private var editor: NSTextView?
    private var editing: SlideAnnotation?
    private(set) var ownsCursor = false
    weak var highlightLayer: HighlightLayerView?
    /// The slide's characters while erasing, so that highlights lose whole characters.
    private var eraserCharacters: [CGRect]?
    /// Where the eraser outline is shown, in slide points.
    private var eraserPoint: CGPoint?

    init(session: PDFSession, pdfView: PDFView) {
        self.session = session
        self.pdfView = pdfView
        super.init(frame: .zero)
        // A zoomed slide reaches beyond the pane and must not paint over the toolbar.
        clipsToBounds = true
        for name in [Notification.Name.PDFViewScaleChanged, .PDFViewPageChanged, .PDFViewDisplayBoxChanged, .PDFViewDocumentChanged] {
            NotificationCenter.default.addObserver(self, selector: #selector(pageGeometryDidChange), name: name, object: pdfView)
        }
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Anmerkungen auf der Folie")
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("Not used from a coder") }

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }
    override var acceptsFirstResponder: Bool { true }

    // MARK: Model

    /// Shows the annotations of the current slide; ignored mid-gesture, which commits at its end.
    func show(_ new: [SlideAnnotation], pageIndex newIndex: Int, onChange change: @escaping ([SlideAnnotation]) -> Void) {
        if newIndex != pageIndex {
            // Before taking `change`, which belongs to the new slide.
            endEditing()
            drag = nil
            draft = nil
            select(nil)
            pageIndex = newIndex
            needsDisplay = true
        }
        onChange = change
        guard drag == nil, new != annotations else { return }
        annotations = new
        // An undo can remove the selection or change it, and the bar has to show what is there now.
        if let selected = session.selectedAnnotation {
            if annotation(selected) != nil { select(selected) }
            else if editing?.id != selected { select(nil) }
        }
        if let id = editing?.id, let current = annotation(id) { syncEditor(with: current) }
        needsDisplay = true
    }

    private func annotation(_ id: UUID?) -> SlideAnnotation? { annotations.first { $0.id == id } }

    private var selected: SlideAnnotation? { annotation(session.selectedAnnotation) }

    private func replace(_ annotation: SlideAnnotation) {
        if let index = annotations.firstIndex(where: { $0.id == annotation.id }) { annotations[index] = annotation }
        else { annotations.append(annotation) }
    }

    private func commit() {
        onChange?(annotations)
        needsDisplay = true
    }

    private func select(_ id: UUID?) {
        session.selectedAnnotation = id
        needsDisplay = true
        guard let annotation = annotation(id) else {
            session.selectedKind = nil
            return
        }
        switch annotation.content {
        case .ink(_, let color, let width), .shape(_, _, _, let color, let width):
            session.selectedKind = .stroke
            session.style.color = color
            session.style.lineWidth = width
        case .text(_, _, let style, let color):
            session.selectedKind = .text
            session.style.color = color
            session.style.text = style
        case .image:
            session.selectedKind = .image
        case .highlight(_, let color):
            session.selectedKind = .highlight
            session.style.highlightColor = color
        }
    }

    // MARK: Called from the toolbar

    func toolDidChange() {
        endEditing()
        if session.tool != .eraser { moveEraserOutline(to: nil) }
        if case .highlight = drag {
            drag = nil
            draft = nil
            needsDisplay = true
        }
        if session.tool != .select { select(nil) }
        window?.makeFirstResponder(self)
    }

    /// Also supports selecting text with the normal PDF tool, then pressing Textmarker.
    @discardableResult
    func highlightCurrentSelection() -> Bool {
        guard let pdfView, let page = pdfView.document?.page(at: pageIndex),
              let selection = pdfView.currentSelection,
              let highlight = PDFTextHighlight.annotation(for: selection, on: page, color: session.style.highlightColor) else { return false }
        annotations.append(highlight)
        pdfView.clearSelection()
        commit()
        return true
    }

    /// Applies the bar's settings to what is selected or being edited.
    func applyStyle() {
        let style = session.style
        func styled(_ annotation: SlideAnnotation) -> SlideAnnotation {
            var result = annotation
            switch annotation.content {
            case .ink(let points, _, _):
                result.content = .ink(points: points, color: style.color, width: style.lineWidth)
            case .shape(let shape, let start, let end, _, _):
                result.content = .shape(shape, start: start, end: end, color: style.color, width: style.lineWidth)
            case .text(let string, var frame, _, _):
                frame.size.height = AnnotationRenderer.textHeight(string, style: style.text, width: frame.width)
                result.content = .text(string, frame: frame, style: style.text, color: style.color)
            case .image:
                break
            case .highlight(let rects, _):
                result.content = .highlight(rects: rects, color: style.highlightColor)
            }
            return result
        }
        if let current = editing {
            let updated = styled(current)
            editing = updated
            syncEditor(with: updated)
            if annotation(updated.id) != nil {
                replace(updated)
                commit()
            }
        } else if let selected, styled(selected) != selected {
            replace(styled(selected))
            commit()
        }
    }

    func deleteSelection() {
        guard let id = session.selectedAnnotation else { return }
        endEditing()
        annotations.removeAll { $0.id == id }
        select(nil)
        commit()
    }

    func insertImage(_ data: Data) {
        let prepared: (data: Data, pixelSize: CGSize)
        do { prepared = try SlideImageImport.prepare(data) }
        catch {
            session.annotationError = error.localizedDescription
            return
        }
        guard let size = slideSize else { return }
        let scale = min(1, 0.6 * size.width / prepared.pixelSize.width, 0.6 * size.height / prepared.pixelSize.height)
        let imageSize = CGSize(width: prepared.pixelSize.width * scale, height: prepared.pixelSize.height * scale)
        let frame = CGRect(x: (size.width - imageSize.width) / 2, y: (size.height - imageSize.height) / 2,
                           width: imageSize.width, height: imageSize.height)
        place(SlideAnnotation(content: .image(prepared.data, frame: frame)))
    }

    private func place(_ annotation: SlideAnnotation) {
        session.tool = .select
        annotations.append(annotation)
        select(annotation.id)
        commit()
    }

    // MARK: Geometry

    private var slideSize: CGSize? { pdfView?.document?.page(at: pageIndex)?.displayedSlideSize }

    /// Where the slide is in this view, and how many view points one slide point takes.
    private var geometry: (rect: CGRect, scale: CGFloat)? {
        guard let pdfView, let page = pdfView.document?.page(at: pageIndex), pdfView.currentPage === page else { return nil }
        let rect = convert(pdfView.convert(page.bounds(for: pdfView.displayBox), from: page), from: pdfView)
        let width = page.displayedSlideSize.width
        guard width > 0, rect.width > 0 else { return nil }
        return (rect, rect.width / width)
    }

    private func viewRect(_ slide: CGRect) -> CGRect {
        guard let geometry else { return .zero }
        return CGRect(x: geometry.rect.minX + slide.minX * geometry.scale, y: geometry.rect.minY + slide.minY * geometry.scale,
                      width: slide.width * geometry.scale, height: slide.height * geometry.scale)
    }

    private func slidePoint(_ view: CGPoint, clamped: Bool = true) -> CGPoint {
        guard let geometry, let size = slideSize else { return view }
        let point = CGPoint(x: (view.x - geometry.rect.minX) / geometry.scale, y: (view.y - geometry.rect.minY) / geometry.scale)
        guard clamped else { return point }
        return CGPoint(x: min(max(point.x, 0), size.width), y: min(max(point.y, 0), size.height))
    }

    @objc func pageGeometryDidChange() {
        observeScrolling()
        if let current = editing { syncEditor(with: current) }
        needsDisplay = true
    }

    private func observeScrolling() {
        guard let pdfView, observedClipView == nil, let clipView = Self.scrollView(in: pdfView)?.contentView else { return }
        observedClipView = clipView
        clipView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(pageGeometryDidChange),
                                               name: NSView.boundsDidChangeNotification, object: clipView)
    }

    private static func scrollView(in view: NSView) -> NSScrollView? {
        for subview in view.subviews {
            if let scrollView = subview as? NSScrollView ?? scrollView(in: subview) { return scrollView }
        }
        return nil
    }

    // MARK: Drawing

    // The highlight layer has the same frame, so it repaints wherever this view does.
    override var needsDisplay: Bool {
        didSet { if needsDisplay { highlightLayer?.needsDisplay = true } }
    }

    override func setNeedsDisplay(_ invalidRect: NSRect) {
        super.setNeedsDisplay(invalidRect)
        highlightLayer?.setNeedsDisplay(invalidRect)
    }

    private func drawAnnotations(_ dirtyRect: NSRect, layer: AnnotationRenderer.Layer) {
        guard let geometry, let context = NSGraphicsContext.current?.cgContext else { return }
        var visible = annotations.filter { $0.id != editing?.id }
        if let draft { visible.append(draft) }
        visible.removeAll { !viewRect($0.visualBounds).insetBy(dx: -2, dy: -2).intersects(dirtyRect) }
        context.saveGState()
        context.clip(to: geometry.rect)
        context.translateBy(x: geometry.rect.minX, y: geometry.rect.minY)
        context.scaleBy(x: geometry.scale, y: geometry.scale)
        AnnotationRenderer.draw(visible, in: context, layer: layer)
        context.restoreGState()
    }

    func drawHighlights(_ dirtyRect: NSRect) { drawAnnotations(dirtyRect, layer: .highlights) }

    override func draw(_ dirtyRect: NSRect) {
        drawAnnotations(dirtyRect, layer: .marks)
        if let editing { drawFrame(viewRect(editing.bounds)) }
        else if let selected { drawSelection(of: selected) }
        if let eraser = eraserOutline {
            // Dark with a light halo, so it shows on dark slides as well as white ones.
            let circle = NSBezierPath(ovalIn: eraser)
            NSColor.white.withAlphaComponent(0.9).setStroke()
            circle.lineWidth = 3
            circle.stroke()
            NSColor.black.withAlphaComponent(0.6).setStroke()
            circle.lineWidth = 1
            circle.stroke()
        }
    }

    private var eraserOutline: CGRect? {
        guard session.tool == .eraser, let eraserPoint else { return nil }
        let radius = session.style.eraserRadius
        return viewRect(CGRect(x: eraserPoint.x - radius, y: eraserPoint.y - radius, width: 2 * radius, height: 2 * radius))
    }

    private func moveEraserOutline(to point: CGPoint?) {
        if let old = eraserOutline { setNeedsDisplay(old.insetBy(dx: -3, dy: -3)) }
        eraserPoint = point
        if let new = eraserOutline { setNeedsDisplay(new.insetBy(dx: -3, dy: -3)) }
    }

    /// Erases along the way from one pointer position to the next, so a quick stroke leaves no gaps.
    /// Returns whether anything changed.
    private func erase(from start: CGPoint, to end: CGPoint) -> Bool {
        let radius = session.style.eraserRadius
        let steps = max(1, Int((hypot(end.x - start.x, end.y - start.y) / (radius / 2)).rounded(.up)))
        let whole = session.style.erasesWholeStrokes
        var changed = false
        for step in 0...steps {
            let t = CGFloat(step) / CGFloat(steps)
            let center = CGPoint(x: start.x + (end.x - start.x) * t, y: start.y + (end.y - start.y) * t)
            let erased = annotations.flatMap { annotation -> [SlideAnnotation] in
                guard annotation.isErasable else { return [annotation] }
                let rest = annotation.erasing(around: center, radius: radius, characters: eraserCharacters)
                // The stroke eraser takes the whole of whatever it touches.
                return whole && rest != [annotation] ? [] : rest
            }
            if erased != annotations {
                annotations = erased
                changed = true
            }
        }
        if changed { needsDisplay = true }
        return changed
    }

    private func drawSelection(of annotation: SlideAnnotation) {
        if case .shape(.line, _, _, _, _) = annotation.content {} else { drawFrame(viewRect(annotation.bounds)) }
        for (_, point) in handles(of: annotation) {
            let center = viewRect(CGRect(origin: point, size: .zero)).origin
            let dot = NSBezierPath(ovalIn: CGRect(x: center.x - Self.handleSize / 2, y: center.y - Self.handleSize / 2,
                                                  width: Self.handleSize, height: Self.handleSize))
            NSColor.white.setFill()
            dot.fill()
            Self.selectionColor.setStroke()
            dot.lineWidth = 1.5
            dot.stroke()
        }
    }

    private func drawFrame(_ rect: CGRect) {
        let frame = NSBezierPath(rect: rect.insetBy(dx: -0.5, dy: -0.5))
        frame.setLineDash([4, 3], count: 2, phase: 0)
        frame.lineWidth = 1
        Self.selectionColor.setStroke()
        frame.stroke()
    }

    private func invalidateDraft() {
        guard let draft else { return }
        setNeedsDisplay(viewRect(draft.visualBounds).insetBy(dx: -4, dy: -4))
    }

    // MARK: Hit testing

    private func handles(of annotation: SlideAnnotation) -> [(Handle, CGPoint)] {
        if case .shape(.line, let start, let end, _, _) = annotation.content { return [(.start, start), (.end, end)] }
        let box = annotation.bounds
        return [
            (.corner(atMaxX: false, atMaxY: false), CGPoint(x: box.minX, y: box.minY)),
            (.corner(atMaxX: true, atMaxY: false), CGPoint(x: box.maxX, y: box.minY)),
            (.corner(atMaxX: false, atMaxY: true), CGPoint(x: box.minX, y: box.maxY)),
            (.corner(atMaxX: true, atMaxY: true), CGPoint(x: box.maxX, y: box.maxY))
        ]
    }

    private func handle(at view: CGPoint) -> Handle? {
        guard let selected else { return nil }
        for (handle, point) in handles(of: selected) {
            let center = viewRect(CGRect(origin: point, size: .zero)).origin
            if hypot(center.x - view.x, center.y - view.y) <= Self.handleSize { return handle }
        }
        return nil
    }

    private func annotation(at view: CGPoint) -> SlideAnnotation? {
        guard let geometry else { return nil }
        let point = slidePoint(view, clamped: false)
        let tolerance = 5 / geometry.scale
        if let selected, selected.bounds.insetBy(dx: -tolerance, dy: -tolerance).contains(point) { return selected }
        let hits = annotations.filter { $0.contains(point, tolerance: tolerance) }
        // Match the renderer: text, strokes and images sit above text highlights.
        return hits.last {
            if case .highlight = $0.content { return false }
            return true
        } ?? hits.last
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let superview else { return nil }
        let local = convert(point, from: superview)
        if let editor, editor.frame.contains(local) { return super.hitTest(point) }
        // Everything else, such as scrolling and zooming, belongs to the PDF.
        switch NSApp.currentEvent?.type {
        case .leftMouseDown:
            guard let geometry else { return nil }
            if session.tool != .select { return geometry.rect.contains(local) ? self : nil }
            if session.selectedAnnotation != nil { return pdfView?.hitTest(point) is NSScroller ? nil : self }
            return annotation(at: local) == nil ? nil : self
        case .rightMouseDown:
            return annotation(at: local) == nil ? nil : self
        default:
            return nil
        }
    }

    // MARK: Mouse

    override func mouseDown(with event: NSEvent) {
        let view = convert(event.locationInWindow, from: nil)
        // Also ends text editing.
        window?.makeFirstResponder(self)
        guard geometry != nil else { return }
        let point = slidePoint(view)
        switch session.tool {
        case .eraser:
            eraserCharacters = pdfView?.document?.page(at: pageIndex).map(PDFTextHighlight.characterRects)
            moveEraserOutline(to: point)
            drag = .erase(last: point, erased: erase(from: point, to: point))
        case .highlight:
            guard let pdfView, let page = pdfView.document?.page(at: pageIndex) else { return }
            guard let text = page.string, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                session.annotationError = "Diese Folie enthält keinen auswählbaren PDF-Text. Für gescannte Folien kannst du den Stift verwenden."
                return
            }
            pdfView.clearSelection()
            drag = .highlight(start: pdfView.convert(convert(view, to: pdfView), to: page), viewStart: view)
        case .select:
            if let handle = handle(at: view), let selected {
                drag = .resize(original: selected, handle: handle, resized: false)
            } else if let hit = annotation(at: view) {
                select(hit.id)
                if event.clickCount == 2, case .text = hit.content {
                    beginEditing(hit)
                } else {
                    drag = .move(original: hit, start: point, moved: false)
                }
            } else {
                select(nil)
            }
        case .pen:
            draft = SlideAnnotation(content: .ink(points: [Self.rounded(point)], color: session.style.color, width: session.style.lineWidth))
            drag = .draw(start: point)
            invalidateDraft()
        case .shape(let shape):
            draft = SlideAnnotation(content: .shape(shape, start: point, end: point, color: session.style.color, width: session.style.lineWidth))
            drag = .draw(start: point)
        case .text:
            session.tool = .select
            if let hit = annotation(at: view), case .text = hit.content {
                select(hit.id)
                beginEditing(hit)
            } else {
                beginNewText(at: point)
            }
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        let point = slidePoint(location)
        let shift = event.modifierFlags.contains(.shift)
        switch drag {
        case .erase(let last, let erased):
            moveEraserOutline(to: point)
            let changed = erase(from: last, to: point)
            drag = .erase(last: point, erased: erased || changed)
        case .highlight(let start, let viewStart):
            invalidateDraft()
            draft = nil
            guard hypot(location.x - viewStart.x, location.y - viewStart.y) >= 2,
                  let pdfView, let page = pdfView.document?.page(at: pageIndex) else { return }
            let end = pdfView.convert(convert(location, to: pdfView), to: page)
            if let selection = page.selection(from: start, to: end) {
                draft = PDFTextHighlight.annotation(for: selection, on: page, color: session.style.highlightColor)
            }
            invalidateDraft()
        case .draw(let start):
            invalidateDraft()
            guard let current = draft, let geometry else { return }
            switch current.content {
            case .ink(var points, let color, let width):
                // One point per view point is all that can be seen, at any zoom.
                if let last = points.last, hypot(last.x - point.x, last.y - point.y) * geometry.scale >= 1 {
                    points.append(Self.rounded(point))
                    draft?.content = .ink(points: points, color: color, width: width)
                }
            case .shape(let shape, _, _, let color, let width):
                draft?.content = .shape(shape, start: start, end: constrained(shape, from: start, to: point, shift: shift), color: color, width: width)
            default:
                break
            }
            invalidateDraft()
        case .move(let original, let start, let moved):
            guard moved || hypot(point.x - start.x, point.y - start.y) * (geometry?.scale ?? 1) >= 2 else { return }
            replace(original.moved(by: clamped(CGVector(dx: point.x - start.x, dy: point.y - start.y), for: original)))
            drag = .move(original: original, start: start, moved: true)
            needsDisplay = true
        case .resize(let original, let handle, _):
            replace(resized(original, handle: handle, to: point, shift: shift))
            drag = .resize(original: original, handle: handle, resized: true)
            needsDisplay = true
        case nil:
            break
        }
    }

    override func mouseUp(with event: NSEvent) {
        // A quick gesture may not have reported its last position.
        mouseDragged(with: event)
        defer { drag = nil }
        switch drag {
        case .erase(_, let erased):
            eraserCharacters = nil
            // One undo step for the whole stroke of the eraser.
            if erased { commit() }
        case .highlight:
            guard let finished = draft else { return }
            draft = nil
            annotations.append(finished)
            commit()
        case .draw:
            guard let finished = draft else { return }
            draft = nil
            needsDisplay = true
            if case .shape = finished.content {
                // A click without a drag draws nothing.
                let box = finished.bounds
                guard hypot(box.width, box.height) >= Self.minimumSize else { return }
                place(finished)
            } else {
                annotations.append(finished)
                commit()
            }
        case .move(_, _, let moved):
            if moved { commit() }
        case .resize(_, _, let resized):
            if resized { commit() }
        case nil:
            break
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let hit = annotation(at: convert(event.locationInWindow, from: nil)) else { return super.rightMouseDown(with: event) }
        window?.makeFirstResponder(self)
        select(hit.id)
        let menu = NSMenu()
        menu.addItem(withTitle: "Ausschneiden", action: #selector(cut(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Kopieren", action: #selector(copy(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Löschen", action: #selector(delete(_:)), keyEquivalent: "")
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                       owner: self))
    }

    override func mouseMoved(with event: NSEvent) {
        let view = convert(event.locationInWindow, from: nil)
        var cursor: NSCursor?
        if let geometry, geometry.rect.contains(view), editor == nil {
            switch session.tool {
            case .pen, .shape, .eraser: cursor = .crosshair
            case .text, .highlight: cursor = .iBeam
            case .select: cursor = handle(at: view) != nil ? .crosshair : annotation(at: view) != nil ? .openHand : nil
            }
        }
        ownsCursor = cursor != nil
        cursor?.set()
        moveEraserOutline(to: geometry?.rect.contains(view) == true ? slidePoint(view) : nil)
    }

    override func mouseExited(with event: NSEvent) {
        ownsCursor = false
        moveEraserOutline(to: nil)
    }

    // MARK: Gestures

    private static func rounded(_ point: CGPoint) -> CGPoint {
        CGPoint(x: (point.x * 100).rounded() / 100, y: (point.y * 100).rounded() / 100)
    }

    private func constrained(_ shape: SlideShape, from start: CGPoint, to point: CGPoint, shift: Bool) -> CGPoint {
        let dx = point.x - start.x, dy = point.y - start.y
        if shape == .line {
            guard shift else { return point }
            // To the nearest 45° step, at the same length.
            let angle = (atan2(dy, dx) / (.pi / 4)).rounded() * (.pi / 4)
            let length = hypot(dx, dy)
            return clampedOnRay(from: start, CGVector(dx: cos(angle) * length, dy: sin(angle) * length))
        }
        guard shape.keepsAspect || shift else { return point }
        let side = max(abs(dx), abs(dy))
        return clampedOnRay(from: start, CGVector(dx: dx < 0 ? -side : side, dy: dy < 0 ? -side : side))
    }

    /// Shortens a vector so that it ends on the slide, keeping its direction.
    private func clampedOnRay(from start: CGPoint, _ vector: CGVector) -> CGPoint {
        guard let size = slideSize else { return start }
        var factor: CGFloat = 1
        if vector.dx > 0 { factor = min(factor, (size.width - start.x) / vector.dx) }
        if vector.dx < 0 { factor = min(factor, -start.x / vector.dx) }
        if vector.dy > 0 { factor = min(factor, (size.height - start.y) / vector.dy) }
        if vector.dy < 0 { factor = min(factor, -start.y / vector.dy) }
        return CGPoint(x: start.x + vector.dx * factor, y: start.y + vector.dy * factor)
    }

    /// Keeps a moved annotation on the slide.
    private func clamped(_ delta: CGVector, for annotation: SlideAnnotation) -> CGVector {
        guard let size = slideSize else { return delta }
        let box = annotation.bounds
        return CGVector(dx: max(-box.minX, min(size.width - box.maxX, delta.dx)),
                        dy: max(-box.minY, min(size.height - box.maxY, delta.dy)))
    }

    private func resized(_ original: SlideAnnotation, handle: Handle, to point: CGPoint, shift: Bool) -> SlideAnnotation {
        var result = original
        switch (handle, original.content) {
        case (.start, .shape(let shape, _, let end, let color, let width)):
            result.content = .shape(shape, start: constrained(shape, from: end, to: point, shift: shift), end: end, color: color, width: width)
        case (.end, .shape(let shape, let start, _, let color, let width)):
            result.content = .shape(shape, start: start, end: constrained(shape, from: start, to: point, shift: shift), color: color, width: width)
        case (.corner(let atMaxX, let atMaxY), _):
            guard let size = slideSize else { return original }
            let box = original.bounds
            let anchor = CGPoint(x: atMaxX ? box.minX : box.maxX, y: atMaxY ? box.minY : box.maxY)
            var width = max(atMaxX ? point.x - anchor.x : anchor.x - point.x, Self.minimumSize)
            var height = max(atMaxY ? point.y - anchor.y : anchor.y - point.y, Self.minimumSize)
            var keepsAspect = shift
            switch original.content {
            case .image: keepsAspect = true
            case .shape(let shape, _, _, _, _): keepsAspect = keepsAspect || shape.keepsAspect
            default: break
            }
            if keepsAspect, box.width > 0, box.height > 0 {
                let available = min((atMaxX ? size.width - anchor.x : anchor.x) / box.width,
                                    (atMaxY ? size.height - anchor.y : anchor.y) / box.height)
                let factor = max(min(max(width / box.width, height / box.height), available), Self.minimumSize / min(box.width, box.height))
                width = box.width * factor
                height = box.height * factor
            }
            if case .text(let string, _, let style, _) = original.content {
                // The width sets the line breaks; the height follows from them.
                width = max(width, 30)
                let frame = CGRect(x: atMaxX ? anchor.x : anchor.x - width, y: box.minY, width: width,
                                   height: AnnotationRenderer.textHeight(string, style: style, width: width))
                return original.resized(to: frame)
            }
            return original.resized(to: CGRect(x: atMaxX ? anchor.x : anchor.x - width, y: atMaxY ? anchor.y : anchor.y - height,
                                               width: width, height: height))
        default:
            break
        }
        return result
    }

    // MARK: Keyboard

    override func keyDown(with event: NSEvent) {
        let step: CGFloat = event.modifierFlags.contains(.shift) ? 10 : 1
        let selected = selected
        switch event.keyCode {
        case 51 where selected != nil, 117 where selected != nil:
            deleteSelection()
        case 53 where selected != nil || session.tool != .select:
            session.tool = .select
            select(nil)
        case 36 where selected != nil:
            if let selected, case .text = selected.content { beginEditing(selected) }
        case 123 where selected != nil: nudge(CGVector(dx: -step, dy: 0))
        case 124 where selected != nil: nudge(CGVector(dx: step, dy: 0))
        case 125 where selected != nil: nudge(CGVector(dx: 0, dy: step))
        case 126 where selected != nil: nudge(CGVector(dx: 0, dy: -step))
        default:
            pdfView?.keyDown(with: event)
        }
    }

    private func nudge(_ delta: CGVector) {
        guard let selected else { return }
        replace(selected.moved(by: clamped(delta, for: selected)))
        commit()
    }

    // MARK: Editing commands

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(copy(_:)), #selector(cut(_:)), #selector(delete(_:)): selected != nil
        case #selector(paste(_:)): true
        default: true
        }
    }

    @objc func copy(_ sender: Any?) { copySelection(to: .general) }

    func copySelection(to board: NSPasteboard) {
        guard let selected, let data = try? JSONEncoder().encode(selected) else { return }
        board.clearContents()
        board.setData(data, forType: Self.pasteboardType)
        if case .text(let string, _, _, _) = selected.content { board.setString(string, forType: .string) }
    }

    @objc func cut(_ sender: Any?) {
        copy(sender)
        deleteSelection()
    }

    @objc func delete(_ sender: Any?) { deleteSelection() }

    @objc func paste(_ sender: Any?) { paste(from: .general) }

    func paste(from board: NSPasteboard) {
        if let data = board.data(forType: Self.pasteboardType), let copy = try? JSONDecoder().decode(SlideAnnotation.self, from: data), copy.isValid {
            let moved = copy.moved(by: clamped(CGVector(dx: 16, dy: 16), for: copy))
            place(SlideAnnotation(content: moved.content))
        } else if let files = board.readObjects(forClasses: [NSURL.self], options: [.urlReadingContentsConformToTypes: [UTType.image.identifier]]) as? [URL],
                  let file = files.first, let data = try? Data(contentsOf: file) {
            insertImage(data)
        } else if let data = board.data(forType: .png) ?? board.data(forType: .tiff) {
            insertImage(data)
        } else if let string = board.string(forType: .string), !string.isEmpty, let size = slideSize {
            let width = textWidth(for: size)
            let style = session.style.text
            let frame = CGRect(x: (size.width - width) / 2, y: size.height / 3, width: width,
                               height: AnnotationRenderer.textHeight(string, style: style, width: width))
            place(SlideAnnotation(content: .text(string, frame: frame, style: style, color: session.style.color)))
        }
    }

    // MARK: Text editing

    private func textWidth(for size: CGSize) -> CGFloat { size.width / 3 }

    private func beginNewText(at point: CGPoint) {
        guard let size = slideSize else { return }
        let style = session.style.text
        let lineHeight = AnnotationRenderer.textHeight("", style: style, width: size.width)
        let width = textWidth(for: size)
        // The first line sits where the click was.
        let frame = CGRect(x: min(point.x, max(size.width - width, 0)), y: max(point.y - lineHeight / 2, 0), width: width, height: lineHeight)
        select(nil)
        beginEditing(SlideAnnotation(content: .text("", frame: frame, style: style, color: session.style.color)))
    }

    private func beginEditing(_ annotation: SlideAnnotation) {
        guard case .text(let string, _, _, _) = annotation.content else { return }
        endEditing()
        drag = nil
        let textView = NSTextView(frame: .zero)
        textView.delegate = self
        textView.isRichText = false
        textView.drawsBackground = false
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.heightTracksTextView = false
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = false
        // Every change goes through the document, whose binding already registers undo.
        textView.allowsUndo = false
        textView.string = string
        textView.setAccessibilityLabel("Textfeld auf der Folie")
        editor = textView
        editing = annotation
        session.selectedAnnotation = annotation.id
        session.selectedKind = .text
        addSubview(textView)
        syncEditor(with: annotation)
        window?.makeFirstResponder(textView)
        textView.selectAll(nil)
        needsDisplay = true
    }

    /// Positions the editor over its box. It lays out in slide points, scaled like the slide,
    /// so that the line breaks are the ones that get drawn and exported.
    private func syncEditor(with annotation: SlideAnnotation) {
        guard let editor, case .text(let string, let frame, let style, let color) = annotation.content else { return }
        editing = annotation
        if editor.string != string { editor.string = string }
        editor.frame = viewRect(frame)
        editor.bounds = CGRect(origin: .zero, size: frame.size)
        editor.textContainer?.containerSize = CGSize(width: frame.width, height: .greatestFiniteMagnitude)
        let attributes = AnnotationRenderer.textAttributes(style: style, color: color)
        editor.typingAttributes = attributes
        editor.textStorage?.setAttributes(attributes, range: NSRange(location: 0, length: editor.textStorage?.length ?? 0))
        editor.insertionPointColor = color.nsColor
        editor.needsDisplay = true
    }

    func textDidChange(_ notification: Notification) {
        guard let editor, let current = editing, case .text(_, var frame, let style, let color) = current.content else { return }
        let string = editor.string
        frame.size.height = AnnotationRenderer.textHeight(string, style: style, width: frame.width)
        var updated = current
        updated.content = .text(string, frame: frame, style: style, color: color)
        syncEditor(with: updated)
        // Written while typing, so that saving mid-sentence loses nothing. Blank boxes are not kept.
        if string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { annotations.removeAll { $0.id == updated.id } }
        else { replace(updated) }
        commit()
    }

    func textDidEndEditing(_ notification: Notification) { endEditing() }

    func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        guard selector == #selector(cancelOperation(_:)) else { return false }
        endEditing()
        window?.makeFirstResponder(self)
        return true
    }

    private func endEditing() {
        guard let textView = editor, let id = editing?.id else { return }
        editor = nil
        editing = nil
        textView.delegate = nil
        textView.removeFromSuperview()
        select(annotation(id) == nil ? nil : id)
    }
}
