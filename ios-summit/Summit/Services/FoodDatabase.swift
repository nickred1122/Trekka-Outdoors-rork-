import Foundation

/// Why a food lookup came back with nothing.
nonisolated enum FoodLookupError: LocalizedError, Equatable {
    /// The barcode is not in the database — common for local and own-brand goods.
    case notFound
    /// The product exists but nobody has filled in its nutrition panel yet.
    case noNutrition
    case network

    var errorDescription: String? {
        switch self {
        case .notFound:
            "That barcode isn't in the food database yet. You can add it by hand instead."
        case .noNutrition:
            "That product is in the database, but its nutrition panel is blank. You can enter it by hand."
        case .network:
            "Couldn't reach the food database. Check your connection and try again."
        }
    }
}

/// Looks food up in Open Food Facts — an open, crowd-sourced database of
/// packaged food with no API key and no per-call cost.
///
/// Two different services sit behind this, because Open Food Facts splits them:
/// barcodes resolve against the main product API, while free-text search runs on
/// their dedicated search service. The older text-search endpoint on the main
/// host is retired and answers 503, so it is deliberately not used.
///
/// An actor, so parsing a page of results never runs on the main thread.
actor FoodDatabase {
    static let shared = FoodDatabase()

    /// Open Food Facts asks every caller to identify itself so they can contact
    /// an app that misbehaves; anonymous traffic gets blocked.
    private static let userAgent = "Trekka/1.0 (iOS; https://rork.app)"

    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 20
        configuration.waitsForConnectivity = false
        session = URLSession(configuration: configuration)
    }

    /// The product behind a scanned barcode.
    func product(barcode: String) async throws -> FoodItem {
        let fields = "code,product_name,product_name_en,generic_name,brands,quantity,serving_size,serving_quantity,image_small_url,nutriments"
        var components = URLComponents(string: "https://world.openfoodfacts.org/api/v2/product/\(barcode).json")
        components?.queryItems = [URLQueryItem(name: "fields", value: fields)]
        guard let url = components?.url else { throw FoodLookupError.notFound }

        let data = try await load(url)
        let response: ProductResponse
        do {
            response = try JSONDecoder().decode(ProductResponse.self, from: data)
        } catch {
            throw FoodLookupError.notFound
        }
        guard response.status == 1, let product = response.product else {
            throw FoodLookupError.notFound
        }
        guard let item = product.asFoodItem(fallbackBarcode: barcode) else {
            throw FoodLookupError.noNutrition
        }
        return item
    }

    /// Free-text search, e.g. "porridge oats".
    ///
    /// Results with an empty nutrition panel are dropped rather than listed:
    /// a food the app cannot count is not a search result, it is a dead end.
    func search(_ query: String, limit: Int = 30) async throws -> [FoodItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return [] }

        var components = URLComponents(string: "https://search.openfoodfacts.org/search")
        components?.queryItems = [
            URLQueryItem(name: "q", value: trimmed),
            URLQueryItem(name: "page_size", value: String(limit)),
        ]
        guard let url = components?.url else { return [] }

        let data = try await load(url)
        let response: SearchResponse
        do {
            response = try JSONDecoder().decode(SearchResponse.self, from: data)
        } catch {
            throw FoodLookupError.network
        }
        return response.hits.compactMap { $0.asFoodItem(fallbackBarcode: nil) }
    }

    private func load(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                // A 404 from the product API is a genuine "no such barcode";
                // anything else is the service being unavailable.
                throw http.statusCode == 404 ? FoodLookupError.notFound : FoodLookupError.network
            }
            return data
        } catch let error as FoodLookupError {
            throw error
        } catch {
            throw FoodLookupError.network
        }
    }
}

// MARK: - Open Food Facts payloads

private nonisolated struct ProductResponse: Decodable {
    let status: Int
    let product: OFFProduct?

    private enum CodingKeys: String, CodingKey {
        case status, product
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // `status` has been seen as both a number and a string in the wild.
        if let value = try? container.decode(Int.self, forKey: .status) {
            status = value
        } else if let text = try? container.decode(String.self, forKey: .status), let value = Int(text) {
            status = value
        } else {
            status = 0
        }
        product = try? container.decode(OFFProduct.self, forKey: .product)
    }
}

private nonisolated struct SearchResponse: Decodable {
    let hits: [OFFProduct]
}

/// One product, decoded by hand.
///
/// Open Food Facts is crowd-sourced and its shapes vary between the two
/// services and between records: numbers arrive as strings, brands as either a
/// string or a list. Everything here is read defensively, because a single odd
/// record must not take the whole page of results down with it.
private nonisolated struct OFFProduct: Decodable {
    let code: String?
    let name: String?
    let brand: String?
    let quantity: String?
    let servingSize: String?
    let servingGrams: Double?
    let imageURL: URL?
    let facts: NutritionFacts

    private struct Key: CodingKey {
        var stringValue: String
        var intValue: Int?
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: Key.self)

        func string(_ name: String) -> String? {
            guard let key = Key(stringValue: name) else { return nil }
            if let value = try? container.decode(String.self, forKey: key) {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
            // The search service returns brands as a list.
            if let values = try? container.decode([String].self, forKey: key) {
                let joined = values.joined(separator: ", ").trimmingCharacters(in: .whitespacesAndNewlines)
                return joined.isEmpty ? nil : joined
            }
            return nil
        }

        func number(_ name: String) -> Double? {
            guard let key = Key(stringValue: name) else { return nil }
            if let value = try? container.decode(Double.self, forKey: key) { return value }
            if let text = try? container.decode(String.self, forKey: key) { return Double(text) }
            return nil
        }

        code = string("code")
        name = string("product_name") ?? string("product_name_en") ?? string("generic_name")
        brand = string("brands")
        quantity = string("quantity")
        servingSize = string("serving_size")
        servingGrams = number("serving_quantity")
        imageURL = string("image_small_url").flatMap(URL.init(string:))

        if let key = Key(stringValue: "nutriments"),
           let nutriments = try? container.decode(Nutriments.self, forKey: key) {
            facts = nutriments.facts
        } else {
            facts = .zero
        }
    }

    /// Turns a database record into something the app can log, or nothing at
    /// all when the record is too thin to be useful.
    func asFoodItem(fallbackBarcode: String?) -> FoodItem? {
        guard let name, !name.isEmpty, !facts.isEmpty else { return nil }

        let isLiquid = Self.looksLikeDrink(quantity: quantity, servingSize: servingSize)
        var portions: [FoodPortion] = []
        if let servingGrams, servingGrams > 0, servingGrams < 5_000 {
            let label = servingSize.map { "Serving (\($0))" } ?? "Serving"
            portions.append(FoodPortion(name: label, grams: servingGrams))
        }
        portions.append(FoodPortion(name: "100 \(isLiquid ? "ml" : "g")", grams: 100))

        return FoodItem(
            name: name,
            brand: brand,
            barcode: code ?? fallbackBarcode,
            per100: facts,
            portions: portions,
            isLiquid: isLiquid,
            imageURL: imageURL,
            source: .openFoodFacts
        )
    }

    /// Drinks are measured in millilitres. Open Food Facts has no flag for it,
    /// so the packet size is the tell — and getting it wrong only changes the
    /// unit printed, never the arithmetic.
    private static func looksLikeDrink(quantity: String?, servingSize: String?) -> Bool {
        let text = [quantity, servingSize].compactMap { $0 }.joined(separator: " ").lowercased()
        guard !text.isEmpty else { return false }
        return text.contains("ml") || text.contains("cl") || text.contains("litre") || text.contains("liter")
    }
}

/// The nutrition panel, per 100 g or 100 ml.
private nonisolated struct Nutriments: Decodable {
    let facts: NutritionFacts

    private struct Key: CodingKey {
        var stringValue: String
        var intValue: Int?
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: Key.self)

        func number(_ name: String) -> Double? {
            guard let key = Key(stringValue: name) else { return nil }
            if let value = try? container.decode(Double.self, forKey: key) { return value }
            if let text = try? container.decode(String.self, forKey: key) { return Double(text) }
            return nil
        }

        // Many records carry only kilojoules, which is what most of the world's
        // labels lead with; one calorie is 4.184 kJ.
        let kilocalories = number("energy-kcal_100g")
            ?? number("energy-kj_100g").map { $0 / 4.184 }
            ?? 0

        facts = NutritionFacts(
            energyKilocalories: max(0, kilocalories),
            proteinGrams: max(0, number("proteins_100g") ?? 0),
            carbohydrateGrams: max(0, number("carbohydrates_100g") ?? 0),
            fatGrams: max(0, number("fat_100g") ?? 0),
            saturatedFatGrams: number("saturated-fat_100g"),
            sugarGrams: number("sugars_100g"),
            fibreGrams: number("fiber_100g"),
            // Open Food Facts publishes sodium in grams; labels read milligrams.
            sodiumMilligrams: number("sodium_100g").map { $0 * 1_000 }
        )
    }
}
