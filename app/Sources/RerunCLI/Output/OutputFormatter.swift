import Foundation

struct OutputFormatter {
    let forceJSON: Bool
    let noColor: Bool

    var isTTY: Bool {
        isatty(STDOUT_FILENO) != 0
    }

    var useJSON: Bool {
        forceJSON || !isTTY
    }

    init(json: Bool = false, noColor: Bool = false) {
        self.forceJSON = json
        self.noColor = noColor || ProcessInfo.processInfo.environment["NO_COLOR"] != nil
    }

    func printJSON<T: Encodable>(_ value: T) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(value)
        if let string = String(data: data, encoding: .utf8) {
            print(string)
        }
    }

    func printLines(_ lines: [String]) {
        for line in lines {
            print(line)
        }
    }
}
