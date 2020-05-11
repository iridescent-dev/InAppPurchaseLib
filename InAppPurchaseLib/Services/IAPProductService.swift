//
//  IAPProductService.swift
//  InAppPurchaseLib
//
//  Created by Veronique on 30/04/2020.
//  Copyright © 2020 Iridescent. All rights reserved.
//

import Foundation
import StoreKit

private let INELIGIBLE_FOR_INTRO_PRICE_PRODUCT_IDS_KEY = "IneligibleForIntroPriceProductIDs"

class IAPProductService: NSObject, SKProductsRequestDelegate {
    
    /* MARK: - Properties */
    @objc private var products : Array<SKProduct>?
    private var productIDs: Set<String> = []
    
    
    /* MARK: - Main methods */
    // Init productIDs list, and load Products from the App Store.
    func initialize(productIDs: Set<String>){
        self.productIDs = productIDs
        self.loadProducts()
    }
    
    // Load Products from the App Store.
    @objc func loadProducts(){
        let request = SKProductsRequest.init(productIdentifiers: self.productIDs)
        request.delegate = self
        request.start()
    }
    
    // Returns all products retrieved from the App Store.
    func getProducts() -> Array<SKProduct> {
        return self.products ?? []
    }
    
    // Gets the product by its identifier from the list of products retrieved from the App Store.
    func getProduct(identifier: String) -> SKProduct? {
        return self.products?.filter { $0.productIdentifier.contains(identifier) }.first
    }
    
    // Refresh the list of products ineligible for introductory price.
    static func refreshIneligibleForIntroPriceProduct(identifiers: [String]){
        var ineligibleForIntroPriceProductIDs: Set<String> = []
        
        for productId in identifiers {
            // Checks if the product exists and if it has not already been added to the list
            if !ineligibleForIntroPriceProductIDs.contains(productId),
                let product = InAppPurchase.getProduct(identifier: productId) {
                
                if product.isAutoRenewableSubscription() {
                    // Only one introductory offer can be activated within a group of auto-renewable subscriptions
                    // Add all the identifiers of the group's products
                    let groupProductIDs = InAppPurchase.getProducts().filter { $0.isAutoRenewableSubscription()
                        && $0.subscriptionGroupIdentifier == product.subscriptionGroupIdentifier }
                        .map { $0.productIdentifier }
                    
                    ineligibleForIntroPriceProductIDs = ineligibleForIntroPriceProductIDs.union(groupProductIDs)
                    
                } else {
                    // Add the product identifier.
                    ineligibleForIntroPriceProductIDs.insert(product.productIdentifier)
                }
            }
        }
        UserDefaults.standard.set(ineligibleForIntroPriceProductIDs.map{$0}, forKey: INELIGIBLE_FOR_INTRO_PRICE_PRODUCT_IDS_KEY)
    }
    
    
    /* MARK: - SKProducts Request Delegate */
    public func productsRequest(_ request: SKProductsRequest, didReceive response: SKProductsResponse) {
        products = response.products
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .iapProductsLoaded, object: nil)
        }
    }
}


extension SKProduct {
    // Checks if the product is a subscription.
    func isSubscription() -> Bool {
        // subscriptionPeriod is nil if the product is not a subscription.
        return subscriptionPeriod != nil
    }
    
    // Checks if the product is an auto-renewable subscription..
    func isAutoRenewableSubscription() -> Bool {
        // All auto-renewable subscriptions must be a part of a group.
        // subscriptionGroupIdentifier is nil if the product is not an auto-renewable subscription.
        return subscriptionGroupIdentifier != nil
    }
    
    // Checks if the product has an introductory price the user is eligible to.
    func hasIntroductoryPriceEligible() -> Bool {
        let ineligibleForIntroPriceProductIDs = UserDefaults.standard.object(forKey: INELIGIBLE_FOR_INTRO_PRICE_PRODUCT_IDS_KEY) as? [String] ?? [String]()
        return !ineligibleForIntroPriceProductIDs.contains(productIdentifier) && introductoryPrice != nil
    }
    
    // Returns a localized string with the current cost of the product, with reduction if available, in the local currency.
    var localizedCurrentPrice: String {
        if hasIntroductoryPriceEligible() {
            return getLocalizedPrice(locale: introductoryPrice!.priceLocale, price: introductoryPrice!.price)
        } else {
            return getLocalizedPrice(locale: priceLocale, price: price)
        }
    }
    
    // Returns a localized string with the current period of the subscription product.
    var localizedCurrentPeriod: String? {
        let period = hasIntroductoryPriceEligible() ? introductoryPrice!.subscriptionPeriod : subscriptionPeriod
        return getLocalizedSubscriptionPeriod(subscriptionPeriod: period)
    }
    
    // Returns a localized string with the initial cost of the product in the local currency.
    var localizedInitialPrice: String {
        return getLocalizedPrice(locale: priceLocale, price: price)
    }
    
    // Returns a localized string with the initial period of the subscription product.
    var localizedInitialPeriod: String? {
        return getLocalizedSubscriptionPeriod(subscriptionPeriod: subscriptionPeriod)
    }
    
    // Returns a localized string with the period of the introductory price.
    var localizedIntroductoryPricePeriod: String? {
        if hasIntroductoryPriceEligible() {
            return getLocalizedPeriod(unit: introductoryPrice!.subscriptionPeriod.unit, numberOfUnits: introductoryPrice!.numberOfPeriods)
        }
        return nil
    }
    
    
    /* MARK: - Private method. Returns formatted product Price and Period */
    private func getLocalizedPrice(locale: Locale, price: NSDecimalNumber) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = locale
        return formatter.string(from: price)!
    }
    
    private func getLocalizedSubscriptionPeriod(subscriptionPeriod: SKProductSubscriptionPeriod?) -> String? {
        if subscriptionPeriod != nil {
            return getLocalizedPeriod(unit: subscriptionPeriod!.unit, numberOfUnits: subscriptionPeriod!.numberOfUnits, dropOne: true)
        }
        return nil
    }
    
    private func getLocalizedPeriod(unit: SKProduct.PeriodUnit, numberOfUnits: Int, dropOne: Bool = false) -> String {
        let formatter = DateComponentsFormatter()
        formatter.maximumUnitCount = 1
        formatter.unitsStyle = .full
        formatter.zeroFormattingBehavior = .dropAll
        
        let calendarUnit = unit.toCalendarUnit()
        var dateComponents = DateComponents()
        dateComponents.calendar = Calendar.current
        formatter.allowedUnits = [calendarUnit]
        
        switch calendarUnit {
        case .day: dateComponents.setValue(numberOfUnits, for: .day)
        case .weekOfMonth: dateComponents.setValue(numberOfUnits, for: .weekOfMonth)
        case .month: dateComponents.setValue(numberOfUnits, for: .month)
        case .year: dateComponents.setValue(numberOfUnits, for: .year)
        default:
            debugPrint("Unknown period unit")
            return ""
        }
        
        var period = formatter.string(from: dateComponents)!
        
        if numberOfUnits == 1 && dropOne {
            period = period.replacingOccurrences(of: "1", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return period
    }
}

@available(iOS 11.2, *)
extension SKProduct.PeriodUnit {
    func toCalendarUnit() -> NSCalendar.Unit {
        switch self {
        case .day: return .day
        case .month: return .month
        case .week: return .weekOfMonth
        case .year: return .year
        @unknown default:
            debugPrint("Unknown period unit")
        }
        return .day
    }
}
