import Foundation

// Compares the texts the compiler found in the source code with a translation table.
// Usage: swift scripts/check-localization.swift <directory of .stringsdata> <Localizable.strings>
let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    print("Usage: check-localization.swift <stringsdata directory> <Localizable.strings>")
    exit(2)
}
let directory = URL(fileURLWithPath: arguments[1], isDirectory: true)
let tableURL = URL(fileURLWithPath: arguments[2])

struct StringsData: Decodable {
    struct Entry: Decodable { let key: String }
    let source: String
    let tables: [String: [Entry]]
}

// The preview harness writes demo material, which is not part of the interface.
var keys: [String: String] = [:]
for file in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
    where file.pathExtension == "stringsdata" {
    let data = try JSONDecoder().decode(StringsData.self, from: Data(contentsOf: file))
    let source = URL(fileURLWithPath: data.source).lastPathComponent
    guard source != "PreviewHarness.swift" else { continue }
    for entry in data.tables["Localizable"] ?? [] where keys[entry.key] == nil { keys[entry.key] = source }
}
guard let table = NSDictionary(contentsOf: tableURL) as? [String: String] else {
    print("Cannot read \(tableURL.path)")
    exit(2)
}

func placeholders(_ text: String) -> [String] {
    let pattern = try! NSRegularExpression(pattern: #"%(?:\d+\$)?(@|lld|ld|d|f)"#)
    return pattern.matches(in: text, range: NSRange(text.startIndex..., in: text))
        .map { (text as NSString).substring(with: $0.range(at: 1)) }.sorted()
}

let missing = keys.keys.filter { table[$0] == nil }.sorted()
let unused = table.keys.filter { keys[$0] == nil }.sorted()
let mismatched = keys.keys.filter { key in table[key].map { placeholders($0) != placeholders(key) } ?? false }.sorted()
for key in missing { print("Missing (\(keys[key]!)): \(key.debugDescription)") }
for key in unused { print("Unused: \(key.debugDescription)") }
for key in mismatched { print("Placeholders differ: \(key.debugDescription)") }
print("\(keys.count) texts, \(missing.count) missing, \(unused.count) unused, \(mismatched.count) with different placeholders.")
exit(missing.isEmpty && unused.isEmpty && mismatched.isEmpty ? 0 : 1)
