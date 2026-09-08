import Foundation

/// Which column of a nutrition panel the numbers describe.
///
/// This is the single most consequential thing to get right when reading a
/// label: the same figure means very different things per 100 g and per
/// serving, and guessing wrong silently doubles or halves everything.
nonisolated enum LabelBasis: Hashable, Sendable {
    /// European style — "Typical values per 100 g".
    case per100
    /// US style — "Nutrition Facts", everything per serving.
    case perServing

    var title: String {
        switch self {
        case .per100: "per 100"
        case .perServing: "per serving"
        }
    }
}

/// Which fields a scan actually managed to read, so the confirm screen can show
/// what was found rather than implying the whole panel was understood.
nonisolated enum LabelField: String, CaseIterable, Sendable, Identifiable {
    case energy, protein, carbohydrate, fat, saturatedFat, sugar, fibre, sodium, serving

    var id: String { rawValue }

    var title: String {
        switch self {
        // "Energy" is what European panels print, but it is not what anyone
        // counting them calls the number. The app says calories throughout.
        case .energy: "Calories"
        case .protein: "Protein"
        case .carbohydrate: "Carbs"
        case .fat: "Fat"
        case .saturatedFat: "Saturates"
        case .sugar: "Sugars"
        case .fibre: "Fibre"
        case .sodium: "Sodium"
        case .serving: "Serving"
        }
    }
}

/// What was read off a nutrition panel.
///
/// Every value is optional and stays that way: a panel that does not print
/// fibre must not produce a zero, because zero is a claim the label never made.
nonisolated struct NutritionLabelReading: Hashable, Sendable {
    var energyKilocalories: Double?
    var proteinGrams: Double?
    var carbohydrateGrams: Double?
    var fatGrams: Double?
    var saturatedFatGrams: Double?
    var sugarGrams: Double?
    var fibreGrams: Double?
    var sodiumMilligrams: Double?
    /// The weight of one serving, when the panel states it.
    var servingGrams: Double?
    var basis: LabelBasis = .per100
    /// True when the panel measures in millilitres.
    var isLiquid: Bool = false

    var found: Set<LabelField> {
        var fields: Set<LabelField> = []
        if energyKilocalories != nil { fields.insert(.energy) }
        if proteinGrams != nil { fields.insert(.protein) }
        if carbohydrateGrams != nil { fields.insert(.carbohydrate) }
        if fatGrams != nil { fields.insert(.fat) }
        if saturatedFatGrams != nil { fields.insert(.saturatedFat) }
        if sugarGrams != nil { fields.insert(.sugar) }
        if fibreGrams != nil { fields.insert(.fibre) }
        if sodiumMilligrams != nil { fields.insert(.sodium) }
        if servingGrams != nil { fields.insert(.serving) }
        return fields
    }

    /// Enough to be worth showing: energy plus at least one macro.
    ///
    /// Energy alone is usually a misread of some other number on the packet, and
    /// macros with no energy cannot be checked for sense.
    var isUsable: Bool {
        guard energyKilocalories != nil else { return false }
        return proteinGrams != nil || carbohydrateGrams != nil || fatGrams != nil
    }

    /// Whether the energy printed agrees with the macros printed.
    ///
    /// Protein and carbohydrate carry 4 kcal per gram and fat 9, so a panel that
    /// was read correctly adds up. A misread digit usually does not, which makes
    /// this the one honest check available without a second opinion.
    var energyAgreesWithMacros: Bool? {
        guard let energy = energyKilocalories, energy > 0,
              let protein = proteinGrams,
              let carbohydrate = carbohydrateGrams,
              let fat = fatGrams else { return nil }
        let implied = protein * 4 + carbohydrate * 4 + fat * 9
        guard implied > 0 else { return nil }
        // Labels round every line independently and may count fibre or polyols
        // differently, so a quarter either way is normal rather than suspicious.
        return abs(implied - energy) / energy < 0.25
    }

    /// The reading expressed per 100, which is how every food in the app is held.
    ///
    /// Returns nil for a per-serving panel whose serving weight was not read —
    /// without it there is genuinely no way to convert, and inventing a serving
    /// size would corrupt every portion calculated from it afterwards.
    func per100Facts() -> NutritionFacts? {
        let basisGrams: Double
        switch basis {
        case .per100:
            basisGrams = 100
        case .perServing:
            guard let servingGrams, servingGrams > 0 else { return nil }
            basisGrams = servingGrams
        }

        let factor = 100 / basisGrams
        return NutritionFacts(
            energyKilocalories: (energyKilocalories ?? 0) * factor,
            proteinGrams: (proteinGrams ?? 0) * factor,
            carbohydrateGrams: (carbohydrateGrams ?? 0) * factor,
            fatGrams: (fatGrams ?? 0) * factor,
            saturatedFatGrams: saturatedFatGrams.map { $0 * factor },
            sugarGrams: sugarGrams.map { $0 * factor },
            fibreGrams: fibreGrams.map { $0 * factor },
            sodiumMilligrams: sodiumMilligrams.map { $0 * factor }
        )
    }

    /// Combines two passes over the same panel, keeping what each one found.
    ///
    /// A phone is never perfectly still and one frame rarely resolves a whole
    /// panel: the top half reads on one frame and the bottom on the next. Values
    /// already found are kept rather than overwritten, so a number does not
    /// flicker between readings while the camera settles.
    func merging(_ other: NutritionLabelReading) -> NutritionLabelReading {
        var merged = self
        merged.energyKilocalories = energyKilocalories ?? other.energyKilocalories
        merged.proteinGrams = proteinGrams ?? other.proteinGrams
        merged.carbohydrateGrams = carbohydrateGrams ?? other.carbohydrateGrams
        merged.fatGrams = fatGrams ?? other.fatGrams
        merged.saturatedFatGrams = saturatedFatGrams ?? other.saturatedFatGrams
        merged.sugarGrams = sugarGrams ?? other.sugarGrams
        merged.fibreGrams = fibreGrams ?? other.fibreGrams
        merged.sodiumMilligrams = sodiumMilligrams ?? other.sodiumMilligrams
        merged.servingGrams = servingGrams ?? other.servingGrams
        // The basis is a property of the panel, not of the frame, so the first
        // frame that had an opinion keeps it.
        merged.isLiquid = isLiquid || other.isLiquid
        return merged
    }
}

/// Reads a nutrition panel out of lines of recognised text.
///
/// Written against the two layouts that cover almost every packet: the US
/// "Nutrition Facts" panel, which is per serving, and the European "per 100 g"
/// table. Both print the same nutrients under different names, in different
/// orders, with the numbers sometimes on the same line as the label and
/// sometimes in a column of their own.
nonisolated enum NutritionLabelParser {
    /// A number and the unit written next to it.
    private struct Token {
        var value: Double
        var unit: String
    }

    private static let knownUnits: Set<String> = ["g", "mg", "kcal", "kj", "ml", "cal", "mcg", "oz"]

    // MARK: - Entry point

    static func parse(lines: [String]) -> NutritionLabelReading {
        let cleaned = lines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !cleaned.isEmpty else { return NutritionLabelReading() }

        let lowered = cleaned.map { $0.lowercased() }
        let joined = lowered.joined(separator: " ")

        var reading = NutritionLabelReading()
        reading.basis = detectBasis(in: joined)
        reading.isLiquid = joined.contains("100 ml") || joined.contains("100ml") || joined.contains("fl oz")

        // Lines are claimed as they are used, so the value belonging to
        // "saturated fat" cannot later be read a second time as plain "fat".
        var consumed = Set<Int>()

        // Most specific first. "Saturated fat" has to be taken off the table
        // before "fat" is looked for, or every panel reports its saturates as
        // its total fat — the single most common way a label parser goes wrong.
        reading.saturatedFatGrams = value(
            for: ["of which saturates", "saturated fat", "saturates", "sat fat", "saturated"],
            in: lowered, consumed: &consumed, preferring: ["g", "mg"]
        )
        reading.sugarGrams = value(
            for: ["of which sugars", "total sugars", "added sugars", "sugars", "sugar"],
            in: lowered, consumed: &consumed, preferring: ["g", "mg"]
        )
        reading.fibreGrams = value(
            for: ["dietary fiber", "dietary fibre", "fibre", "fiber"],
            in: lowered, consumed: &consumed, preferring: ["g"]
        )
        reading.carbohydrateGrams = value(
            for: ["total carbohydrate", "carbohydrates", "carbohydrate", "total carbs", "carbs"],
            in: lowered, consumed: &consumed, preferring: ["g"]
        )
        reading.proteinGrams = value(
            for: ["protein"],
            in: lowered, consumed: &consumed, preferring: ["g"]
        )
        reading.fatGrams = value(
            for: ["total fat", "fat"],
            in: lowered, consumed: &consumed, preferring: ["g"]
        )

        // Sodium is printed directly on US panels and as salt in Europe.
        if let sodium = value(for: ["sodium"], in: lowered, consumed: &consumed, preferring: ["mg", "g"], keepUnit: true) {
            reading.sodiumMilligrams = sodium.unit == "g" ? sodium.value * 1_000 : sodium.value
        } else if let salt = value(for: ["salt"], in: lowered, consumed: &consumed, preferring: ["g", "mg"], keepUnit: true) {
            // Salt is sodium chloride: sodium is 40% of it by weight.
            let grams = salt.unit == "mg" ? salt.value / 1_000 : salt.value
            reading.sodiumMilligrams = grams * 400
        }

        reading.energyKilocalories = energy(in: lowered, consumed: &consumed)
        reading.servingGrams = servingSize(in: lowered)

        return sanitised(reading)
    }

    // MARK: - Basis

    private static func detectBasis(in joined: String) -> LabelBasis {
        // An explicit per-100 column wins outright: European panels say so, and
        // some US packets print both columns.
        let per100Markers = ["per 100", "/100", "100 g", "100g", "100 ml", "100ml", "je 100", "por 100"]
        if per100Markers.contains(where: joined.contains) { return .per100 }

        let servingMarkers = ["nutrition facts", "serving size", "per serving", "amount per serving", "servings per"]
        if servingMarkers.contains(where: joined.contains) { return .perServing }

        // Packaged food in the app's food database is overwhelmingly European,
        // where per 100 is the legal requirement.
        return .per100
    }

    // MARK: - Field extraction

    private struct Measured {
        var value: Double
        var unit: String
    }

    private static func value(
        for keywords: [String],
        in lines: [String],
        consumed: inout Set<Int>,
        preferring units: [String]
    ) -> Double? {
        value(for: keywords, in: lines, consumed: &consumed, preferring: units, keepUnit: true)?.value
    }

    private static func value(
        for keywords: [String],
        in lines: [String],
        consumed: inout Set<Int>,
        preferring units: [String],
        keepUnit: Bool
    ) -> Measured? {
        for keyword in keywords {
            for (index, line) in lines.enumerated() where !consumed.contains(index) {
                guard let range = line.range(of: keyword) else { continue }

                // The number usually sits after the name on the same line.
                let after = String(line[range.upperBound...])
                if let token = pick(from: tokens(in: after), units: units) {
                    consumed.insert(index)
                    return Measured(value: token.value, unit: token.unit)
                }

                // Some panels put the name and its value in separate columns,
                // which arrive as separate lines. Only the next couple of lines
                // are considered, and only if they are essentially just a number
                // — otherwise a nutrient with no value would steal the next
                // nutrient's figure.
                for offset in 1...2 {
                    let next = index + offset
                    guard next < lines.count, !consumed.contains(next) else { continue }
                    guard isBareValue(lines[next]) else { break }
                    if let token = pick(from: tokens(in: lines[next]), units: units) {
                        consumed.insert(index)
                        consumed.insert(next)
                        return Measured(value: token.value, unit: token.unit)
                    }
                }

                // The name was found but carried no readable number. The line is
                // still claimed so a later, less specific keyword cannot match it.
                consumed.insert(index)
            }
        }
        return nil
    }

    /// True when a line is just a measurement, with no nutrient name of its own.
    private static func isBareValue(_ line: String) -> Bool {
        let stripped = line.filter { !$0.isNumber && !$0.isWhitespace }
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "<", with: "")
            .replacingOccurrences(of: "%", with: "")
        return stripped.count <= 4
    }

    private static func pick(from tokens: [Token], units: [String]) -> Token? {
        for unit in units {
            if let match = tokens.first(where: { $0.unit == unit }) { return match }
        }
        // A number with no unit beside a nutrient name is still almost always
        // that nutrient in grams — but a percentage of daily value is not, and
        // those are filtered out before this point.
        return tokens.first { $0.unit.isEmpty }
    }

    // MARK: - Energy

    private static func energy(in lines: [String], consumed: inout Set<Int>) -> Double? {
        // Kilocalories are what the app stores, so they are looked for first and
        // kilojoules used only when the packet prints nothing else.
        for (index, line) in lines.enumerated() {
            guard line.contains("calorie") || line.contains("kcal") || line.contains("energy") else { continue }
            let all = tokens(in: line)
            if let kcal = all.first(where: { $0.unit == "kcal" || $0.unit == "cal" }) {
                consumed.insert(index)
                return kcal.value
            }
        }

        for (index, line) in lines.enumerated() {
            guard line.contains("calorie") || line.contains("energy") || line.contains("kcal") else { continue }

            let all = tokens(in: line)
            // "Energy 1234 kJ / 295 kcal" — when both are on the line the kcal
            // figure was already taken above, so anything left is kilojoules.
            if let kj = all.first(where: { $0.unit == "kj" }) {
                consumed.insert(index)
                return kj.value / 4.184
            }
            if let plain = all.first(where: { $0.unit.isEmpty }) {
                consumed.insert(index)
                return plain.value
            }

            // "Calories" on its own line, with the number underneath.
            for offset in 1...2 where index + offset < lines.count {
                let next = index + offset
                guard isBareValue(lines[next]) else { break }
                if let token = tokens(in: lines[next]).first {
                    consumed.insert(index)
                    consumed.insert(next)
                    return token.unit == "kj" ? token.value / 4.184 : token.value
                }
            }
        }
        return nil
    }

    // MARK: - Serving size

    private static func servingSize(in lines: [String]) -> Double? {
        for line in lines {
            guard line.contains("serving size") || line.contains("per serving")
                || line.contains("portion") || line.contains("serving") else { continue }
            let all = tokens(in: line)
            // "Serving size 2/3 cup (55g)" — the gram figure is the only one
            // that can be used, so a token with a weight unit is required.
            if let weight = all.first(where: { $0.unit == "g" || $0.unit == "ml" }) {
                return weight.value
            }
        }
        return nil
    }

    // MARK: - Tokenising

    /// Every number in a line, with the unit written beside it.
    ///
    /// Percentages are dropped: the "% Daily Value" column of a US panel sits
    /// right next to the grams and would otherwise be read as the nutrient.
    private static func tokens(in text: String) -> [Token] {
        var result: [Token] = []
        let characters = Array(text)
        var index = 0

        while index < characters.count {
            guard characters[index].isNumber else {
                index += 1
                continue
            }

            var digits = ""
            while index < characters.count,
                  characters[index].isNumber || characters[index] == "." || characters[index] == "," {
                digits.append(characters[index])
                index += 1
            }

            var cursor = index
            while cursor < characters.count, characters[cursor] == " " { cursor += 1 }

            var letters = ""
            var probe = cursor
            while probe < characters.count, characters[probe].isLetter, letters.count < 4 {
                letters.append(characters[probe])
                probe += 1
            }

            let unit = letters.lowercased()
            let isPercent = cursor < characters.count && characters[cursor] == "%"

            if knownUnits.contains(unit) {
                index = probe
                if let value = number(from: digits, unit: unit) {
                    result.append(Token(value: value, unit: unit == "cal" ? "kcal" : unit))
                }
            } else if isPercent {
                index = cursor + 1
            } else if let value = number(from: digits, unit: "") {
                result.append(Token(value: value, unit: ""))
            }
        }
        return result
    }

    /// Turns the digits as printed into a number.
    ///
    /// A comma is a decimal point on most of the world's packaging, so it is
    /// treated as one — except in a kilojoule figure, where a group of exactly
    /// three digits after a separator is a thousands mark rather than a
    /// fractional part no energy value has ever been printed to.
    private static func number(from digits: String, unit: String) -> Double? {
        var text = digits
        while let last = text.last, last == "." || last == "," {
            text.removeLast()
        }
        guard !text.isEmpty else { return nil }

        let separators = text.filter { $0 == "." || $0 == "," }
        if separators.count > 1 {
            // "1.234,5" or "1,234.5" — the last separator is the decimal one.
            if let lastSeparator = text.lastIndex(where: { $0 == "." || $0 == "," }) {
                let whole = text[text.startIndex..<lastSeparator].filter(\.isNumber)
                let fraction = text[text.index(after: lastSeparator)...]
                text = whole + "." + fraction
            }
        } else if let separatorIndex = text.firstIndex(where: { $0 == "." || $0 == "," }) {
            let fraction = text[text.index(after: separatorIndex)...]
            if unit == "kj", fraction.count == 3 {
                text = text.filter(\.isNumber)
            } else {
                text = text.replacingOccurrences(of: ",", with: ".")
            }
        }

        return Double(text)
    }

    // MARK: - Sanity

    /// Throws out values no food can have, so a misread digit becomes a blank
    /// the athlete can fill in rather than a number they might trust.
    private static func sanitised(_ reading: NutritionLabelReading) -> NutritionLabelReading {
        var checked = reading
        // Per 100 g nothing can exceed 100 g, and the densest food on earth is
        // pure fat at 900 kcal.
        let macroCeiling: Double = reading.basis == .per100 ? 100 : 2_000
        let energyCeiling: Double = reading.basis == .per100 ? 900 : 5_000

        func clean(_ value: Double?, ceiling: Double) -> Double? {
            guard let value, value >= 0, value <= ceiling else { return nil }
            return value
        }

        checked.energyKilocalories = clean(reading.energyKilocalories, ceiling: energyCeiling)
        checked.proteinGrams = clean(reading.proteinGrams, ceiling: macroCeiling)
        checked.carbohydrateGrams = clean(reading.carbohydrateGrams, ceiling: macroCeiling)
        checked.fatGrams = clean(reading.fatGrams, ceiling: macroCeiling)
        checked.saturatedFatGrams = clean(reading.saturatedFatGrams, ceiling: macroCeiling)
        checked.sugarGrams = clean(reading.sugarGrams, ceiling: macroCeiling)
        checked.fibreGrams = clean(reading.fibreGrams, ceiling: macroCeiling)
        checked.sodiumMilligrams = clean(reading.sodiumMilligrams, ceiling: 100_000)
        checked.servingGrams = clean(reading.servingGrams, ceiling: 5_000)

        // A part of something cannot exceed the whole it belongs to.
        if let saturated = checked.saturatedFatGrams, let fat = checked.fatGrams, saturated > fat + 0.5 {
            checked.saturatedFatGrams = nil
        }
        if let sugar = checked.sugarGrams, let carbs = checked.carbohydrateGrams, sugar > carbs + 0.5 {
            checked.sugarGrams = nil
        }
        return checked
    }
}
