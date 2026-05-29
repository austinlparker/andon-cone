import Foundation
import StoreKit

@MainActor
final class TipStore: ObservableObject {
    static let productIDs = [
        "io.aparker.andoncone.tip.small",
        "io.aparker.andoncone.tip.medium",
        "io.aparker.andoncone.tip.large",
    ]

    @Published private(set) var products: [Product] = []
    @Published private(set) var isLoading = false
    @Published private(set) var purchaseInProgressProductID: String?
    @Published private(set) var completedPurchaseCount = 0
    @Published var message: String?

    private static let productIDSet = Set(productIDs)
    private let productOrder: [String: Int] = Dictionary(
        uniqueKeysWithValues: productIDs.enumerated().map { index, id in (id, index) }
    )
    private var updatesTask: Task<Void, Never>?
    private var finishedTransactionIDs: Set<UInt64> = []

    init() {
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                await self?.handle(update)
            }
        }
    }

    deinit {
        updatesTask?.cancel()
    }

    func loadProducts() async {
        guard products.isEmpty, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let fetched = try await Product.products(for: Self.productIDs)
            products = fetched.sorted {
                productOrder[$0.id, default: Int.max] < productOrder[$1.id, default: Int.max]
            }

            if products.isEmpty {
                message = "Tips are not available yet."
            }
        } catch {
            message = "Tips are unavailable right now."
        }
    }

    func purchase(_ product: Product) async {
        guard purchaseInProgressProductID == nil else { return }
        purchaseInProgressProductID = product.id
        defer { purchaseInProgressProductID = nil }

        do {
            let result = try await product.purchase()

            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await finish(transaction)
            case .userCancelled:
                break
            case .pending:
                message = "Purchase pending approval."
            @unknown default:
                message = "Purchase could not be completed."
            }
        } catch {
            message = "Purchase could not be completed."
        }
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .verified(let value):
            return value
        case .unverified:
            throw StoreError.failedVerification
        }
    }

    private func handle(_ result: VerificationResult<Transaction>) async {
        do {
            let transaction = try checkVerified(result)
            guard Self.productIDSet.contains(transaction.productID) else { return }
            await finish(transaction)
        } catch {
            message = "Purchase could not be verified."
        }
    }

    private func finish(_ transaction: Transaction) async {
        guard finishedTransactionIDs.insert(transaction.id).inserted else { return }
        await transaction.finish()
        message = "Thanks for supporting Andon Cone."
        completedPurchaseCount += 1
    }
}

private enum StoreError: Error {
    case failedVerification
}
