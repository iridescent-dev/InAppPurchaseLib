//
//  IAPReceiptService.swift
//  InAppPurchaseLib
//
//  Created by Veronique on 30/04/2020.
//  Copyright © 2020 Iridescent. All rights reserved.
//

import Foundation
import StoreKit

private let HAS_ALREADY_PURCHASED_KEY = "HasAlreadyPurchased"

class IAPReceiptService: NSObject, SKRequestDelegate {
    
    /* MARK: - Properties */
    private var lastValidationDate: Date?
    private var validatorUrlString: String?
    
    
    /* MARK: - Main methods */
    // Init Fovea.Billing validator URL, and validate App Store receipt.
    func initialize(validatorUrlString: String){
        self.validatorUrlString = validatorUrlString
        self.validateReceipt()
    }
    
    // Checks if the user has already purchased at least one product.
    func hasAlreadyPurchased() -> Bool{
        return UserDefaults.standard.bool(forKey: HAS_ALREADY_PURCHASED_KEY)
    }
    
    // Checks if the user currently own (or is subscribed to) a given product.
    func hasActivePurchase(for productId: String) -> Bool{
        switch InAppPurchase.getType(for: productId) {
        case .nonConsumable:
            let purchaseDate = getPurchaseDate(for: productId)
            return purchaseDate != nil
            
        case .subscription, .autoRenewableSubscription:
            let nextExpiryDate = getNextExpiryDate(for: productId)
            return nextExpiryDate != nil && nextExpiryDate! > Date()
            
        default:
            return false
        }
    }
    
    // Returns the latest purchased date for a given product.
    func getPurchaseDate(for productId: String) -> Date? {
        return UserDefaults.standard.object(forKey: "\(productId)_purchaseDate") as? Date
    }
    
    // Returns the quantity purchased for a given product.
    func getPurchasedQuantity(for productId: String) -> Int? {
        return UserDefaults.standard.object(forKey: "\(productId)_quantity") as? Int
    }
    
    // Returns the expiry date for a subcription. May be past or future.
    func getExpiryDate(for productId: String) -> Date? {
        return UserDefaults.standard.object(forKey: "\(productId)_expiryDate") as? Date
    }
    
    // Returns the expiry date for an active subcription. It returns nil if the subscription is expired.
    func getNextExpiryDate(for productId: String) -> Date? {
        return UserDefaults.standard.object(forKey: "\(productId)_nextExpiryDate") as? Date
    }
    
    // Validate App Store receipt using Fovea.Billing validator.
    @objc func validateReceipt(){
        guard let appStoreReceiptURL = Bundle.main.appStoreReceiptURL, FileManager.default.fileExists(atPath: appStoreReceiptURL.path) else {
            refreshReceipt()
            // validateReceipt will be called again after receipt refreshing finishes.
            return
        }
        
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else {
            print("[receipt error] Bundle Identifier invalid.")
            return
        }
        
        guard let url = URL(string: validatorUrlString!) else {
            print("[receipt error] Validator URL String invalid: \(validatorUrlString ?? "nil")")
            return
        }
        
        // do not call validator more than 1 time by 2 seconds
        let date = Calendar.current.date(byAdding: .second, value: -2, to: Date())
        if lastValidationDate == nil || lastValidationDate! < date! {
            lastValidationDate = Date()
            
            let receiptData = try? Data(contentsOf: appStoreReceiptURL).base64EncodedString()
            let requestData = [
                "id" : bundleIdentifier,
                "type" : "application",
                "device": [
                    "plugin": " iridescent-iap-swift-lib/\(InAppPurchase.versionNumber)",
                    "platform": UIDevice.current.systemName,
                    "version": UIDevice.current.systemVersion,
                    "model": UIDevice.current.model
                ],
                "transaction" : [
                    "type" : "ios-appstore",
                    "id" : bundleIdentifier,
                    "appStoreReceipt" : receiptData
                ],
                "additionalData" : [
                    "applicationUsername" : InAppPurchase.applicationUsername ?? nil
                ]
                ] as [String : Any]
            
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("Application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONSerialization.data(withJSONObject: requestData, options: [])
            
            URLSession.shared.dataTask(with: request) { (data, response, error) in
                DispatchQueue.main.async {
                    if data != nil {
                        if let json = try? JSONSerialization.jsonObject(with: data!, options: .allowFragments){
                            self.parseReceipt(json as! Dictionary<String, Any>)
                            return
                        }
                    } else {
                        print("[receipt error] Failed to validate receipt: \(error?.localizedDescription ?? "")")
                    }
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(name: .iapReceiptValidationFailed, object: error)
                    }
                }
            }.resume()
        }
    }
    
    
    // MARK: - SKReceipt Refresh Request Delegate
    func requestDidFinish(_ request: SKRequest) {
        if request is SKReceiptRefreshRequest {
            self.validateReceipt()
        }
    }
    
    func request(_ request: SKRequest, didFailWithError error: Error){
        if request is SKReceiptRefreshRequest {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .iapRefreshReceiptFailed, object: error)
            }
        }
        print("[receipt error] \(error.localizedDescription)")
    }
    
    
    /* MARK: - Private methods. */
    private func refreshReceipt(){
        let request = SKReceiptRefreshRequest(receiptProperties: nil)
        request.delegate = self
        request.start()
    }
    
    // Get user purchases informations from Fovea.Billing validator
    // (subscription expiration date, eligibility for introductory price, ...)
    private func parseReceipt(_ json : Dictionary<String, Any>) {
        guard let data = json["data"] as? [String: Any], let collection = data["collection"] as? [[String: Any]] else {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .iapReceiptValidationFailed, object: nil)
            }
            return
        }
        
        IAPProductService.refreshIneligibleForIntroPriceProduct(identifiers: data["ineligible_for_intro_price"] as? [String] ?? [])
        
        UserDefaults.standard.set(!collection.isEmpty, forKey: HAS_ALREADY_PURCHASED_KEY)
        
        for product in InAppPurchase.getProducts() {
            let receipt = collection.first{ $0["id"] as? String == product.productIdentifier }
            let oldPurchaseDate = UserDefaults.standard.object(forKey: "\(product.productIdentifier)_purchaseDate") as? Date
            
            var purchaseDate: Date? = nil
            var quantity: Int? = nil
            var expiryDate: Date? = nil
            var nextExpiryDate: Date? = nil
            
            if receipt != nil {
                // Save the purchase date.
                var milliseconds = receipt!["purchaseDate"] as? TimeInterval ?? 0
                if  milliseconds != 0 {
                    purchaseDate = Date(timeIntervalSince1970: (milliseconds / 1000.0))
                }
                
                // Save the quantity.
                quantity = receipt!["quantity"] as? Int ?? 1
                
                // Save the expiry date if the product is a non-expired subscription.
                milliseconds = receipt!["expiryDate"] as? TimeInterval ?? 0
                let isExpired = receipt!["isExpired"] as? Bool ?? true
                if  milliseconds != 0 {
                    expiryDate = Date(timeIntervalSince1970: (milliseconds / 1000.0))
                    if  !isExpired {
                        nextExpiryDate = expiryDate
                    }
                }
            }
            
            // Save receipt informations for the product.
            UserDefaults.standard.set(purchaseDate, forKey: "\(product.productIdentifier)_purchaseDate")
            UserDefaults.standard.set(expiryDate, forKey: "\(product.productIdentifier)_expiryDate")
            UserDefaults.standard.set(nextExpiryDate, forKey: "\(product.productIdentifier)_nextExpiryDate")
            UserDefaults.standard.set(quantity, forKey: "\(product.productIdentifier)_quantity")
            
            // If the product is a consumable or is newly purchased/restored and still active, send a notification.
            // - Consumables should always be processed if present in the receipt
            if  (InAppPurchase.getType(for: product.productIdentifier) == IAPProductType.consumable && receipt != nil)
                // - Other products must have been updated and still be active to be processed
                || (oldPurchaseDate != purchaseDate && hasActivePurchase(for: product.productIdentifier)) {
                
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .iapProductPurchased, object: product)
                }
            }
        }
        
        // Notify the end of receipt validation.
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .iapReceiptValidationSuccessful, object: nil)
        }
    }
}
