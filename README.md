<p align="center">
  <img src="InAppPurchaseLib.png" width="640" title="InAppPurchaseLib">
</p>

InAppPurchaseLib is an easy-to-use library for In-App Purchases, using Fovea.Billing for receipts validation.

- [Features](#features)
- [Getting Started](#getting-started)
  - [Requirements](#requirements)
  - [Installation](#installation)
- [Usage](#usage)
  - [Initialization](#initialization)
  - [Displaying products](#displaying-products)
  - [Displaying subscriptions](#displaying-subscriptions)
  - [Refreshing](#refreshing)
  - [Purchasing](#purchasing)
    - [Making a purchase](#making-a-purchase)
    - [Processing purchases](#processing-purchases)
  - [Restoring purchases](#restoring-purchases)
  - [Purchased products](#purchased-products)
  - [Notifications](#notifications)
  - [Purchases information](#purchases-information)
- [Server integration](#server-integration)
- [Xcode Demo Project](#xcode-demo-project)
- [References](#references)
- [Troubleshooting](#troubleshooting)
- [License](#license)


## Features

* ✅ Purchase a product 
* ✅ Restore purchased products
* ✅ Verify transactions with the App Store on Fovea.Billing server
* ✅ Handle and notify payment transaction states
* ✅ Retreive products information from the App Store
* ✅ Support all product types (consumable, non-consumable, auto-renewable subscription, non-renewing subscription)
* ✅ Status of purchases available when offline
* ✅ Server integration with a Webhook

## Getting Started
If you haven't already, I highly recommend your read the *Overview* and *Preparing* section of Apple's [In-App Purchase official documentation](https://developer.apple.com/in-app-purchase)

### Requirements
* Configure your App and Xcode to support In-App Purchases.
  * [AppStore Connect Setup](https://help.apple.com/app-store-connect/#/devb57be10e7)
* Create and configure your [Fovea.Billing](https://billing.fovea.cc) project account:
  * Set your bundle ID
  * The iOS Shared Secret (or shared key) is to be retrieved from [AppStoreConnect](https://appstoreconnect.apple.com/)
  * The iOS Subscription Status URL (only if you want subscriptions)

### Installation
* [Download](https://github.com/iridescent-dev/iap-swift-lib/archive/master.zip) and extract.
* Drag the `InAppPurchaseLib` folder to your project tree in XCode. When asked, set options as follows:
  * Select *Copy items if needed*.
  * Select *Create groups*.
  * Make sure your project is selected in *add to target*.

## Usage

The process of implementing in-app purchases involves several steps:
1. Displaying the list of purchasable products
2. Initiating a purchase
3. Delivering and finalizing a purchase
4. Checking the current ownership of non-consumables and subscriptions
5. Implementing the Restore Purchases button

### Initialization

Before everything else the library must be initialized. This has to happen as soon as possible. A good way is to call the `InAppPurchase.initialize()` method when the application did finish launching. In the background, this will load your products and refresh the status of purchases and subscriptions.

`InAppPurchase.initialize()` accepts the following arguments:
* `iapProducts` - An array of **IAPProduct** (REQUIRED)
* `validatorUrlString` - The validator url retrieved from [Fovea](https://billing.fovea.cc) (REQUIRED)
* `applicationUsername` - The user name, if your app implements user login (optional)

Each **IAPProduct** contains the following fields:
* `productIdentifier` - The product unique identifier 
* `productType` - The **IAPProductType** (`consumable`, `nonConsumable`, `nonRenewingSubscription` or `autoRenewableSubscription`)

*Example:*

``` swift
InAppPurchase.initialize(
  iapProducts: [
    IAPProduct(productIdentifier: "monthly_plan", productType: .autoRenewableSubscription),
    IAPProduct(productIdentifier: "yearly_plan",  productType: .autoRenewableSubscription),
    IAPProduct(productIdentifier: "disable_ads",  productType: .nonConsumable)
  ],
  validatorUrlString: "https://validator.fovea.cc/v1/validate?appName=demo&apiKey=12345678")
```

A good place is generally in your application delegate's `didFinishLaunchingWithOptions` function, like below:

``` swift
func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
  // ... initialize here
}
```

You should also call the `stop` method when the application will terminate, for proper cleanup.
``` swift
func applicationWillTerminate(_ application: UIApplication) {
  InAppPurchase.stop()
}
```

For more advanced use cases, in particular when you have implemented user login, see the [Server integration](#server-integration) section.

*Tip:* If initialization was successful, you should see a new receipt validation event in [Fovea's Dashboard](https://billing-dashboard.fovea.cc/events).

### Displaying products
Let's start with the simplest case: you have a single product.

You can retrieve all information about this product using the function `InAppPurchase.getProductBy(identifier: "my_product_id")`. This returns an [SKProduct](https://developer.apple.com/documentation/storekit/skproduct) extended with helpful methods.

Those are the most important:
 - `productIdentifier: String` - The string that identifies the product to the Apple AppStore.
 - `localizedTitle: String` - The name of the product, in the language of the device, as retrieved from the AppStore.
 - `localizedDescription: String` - A description of the product, in the language of the device, as retrieved from the AppStore.
 - `localizedCurrentPrice: String` - Current cost of the product in the local currency (_read-only property added by this library_).

*Example*:

You can add a function similar to this to your view.

``` swift
@objc func refreshView() {
  guard let product: SKProduct = InAppPurchase.getProductBy(identifier: "my_product_id") else {
    self.titleLabel.text = "Product unavailable"
    return
  }
  self.titleLabel.text = product.localizedTitle
  self.descriptionLabel.text = product.localizedDescription
  self.priceLabel.text = product.localizedCurrentPrice
}
```

This example assumes `self.titleLabel` is a UILabel, etc.

Make sure to call this function when the view appears on screen, for instance by calling it from [`viewWillAppear`](https://developer.apple.com/documentation/uikit/uiviewcontroller/1621510-viewwillappear).

``` swift
override func viewWillAppear(_ animated: Bool) {
  self.refreshView()
}
```

### Displaying subscriptions

For subscription products, you also have some data about subscription periods and introductory offers.

 - `func hasIntroductoryPriceEligible() -> Bool` - The product has an introductory price the user is eligible to.
 - `localizedCurrentPeriod: String?` - The current period of the subscription.
 - `localizedInitialPrice: String` -  The initial cost of the subscription in the local currency.
 - `localizedInitialPeriod: String?` - The initial period of the subscription.
 - `localizedIntroductoryPricePeriod: String?` - The period of the introductory price.

Notice that `localizedCurrentPrice` already applied introductory prices if they are available. 

**Example**

``` swift
@objc func refreshView() {
  guard let product: SKProduct = InAppPurchase.getProductBy(identifier: "my_product_id") else {
    self.titleLabel.text = "Product unavailable"
    return
  }
  self.titleLabel.text = product.localizedTitle
  self.descriptionLabel.text = product.localizedDescription

  // Format price text. Example: "0,99€ / month for 3 months (then 3,99 € / month)"
  var priceText = "\(product.localizedCurrentPrice) / \(product.localizedCurrentPeriod!)"
  if product.hasIntroductoryPriceEligible() {
    priceText = "\(priceText) for \(product.localizedIntroductoryPricePeriod!)" +
      " (then \(product.localizedInitialPrice) / \(product.localizedInitialPeriod!))"
  }
  self.priceLabel.text = priceText
}
```

*Note:* You have to `import StoreKit` wherever you use `SKProduct`.

### Refreshing
Data might change or not be yet available when your "product" view is presented. In order to properly handle those cases, you should add an observer to the `iapProductsLoaded` notification.

The library loads in-app products metadata at startup, so they're immediately available when needed. But it is also a good idea to refresh the prices when you show your products view, in case the price has changed since app startup. You want to be sure you're displaying up-to-date information.

To achieve this, call `InAppPurchase.refresh()` when your view is presented.

``` swift
override func viewWillAppear(_ animated: Bool) {
  self.refreshView()
  NotificationCenter.default.addObserver(self, selector: #selector(refreshView), name: .iapProductsLoaded, object: nil)
  InAppPurchase.refresh()
}
override func viewWillDisappear(_ animated: Bool) {
  NotificationCenter.default.removeObserver(self)
}
```

### Purchasing
The purchase process is generally a little bit more involving that people would expect. Why is it not just: purchase &rarr; on success unlock the feature?

Several reasons:
- In-app purchases can be initiated outside the app
- In-app purchases can be deferred, pending parental approval
- Apple wants to be sure you delivered the product before charging the user

That is why the process looks like so:
- being ready to handle purchase events from app startup
- finalizing transactions when product delivery is complete
- sending purchase request, for which successful doesn't mean complete

#### Making a purchase
To make a purchase, use the `InAppPurchase.purchase()` function. It takes the `productIdentifier` and a `callback` function, called when the purchase has been processed.

**Important**: This callback is not meant to unlock the feature. **purchase processed ≠ purchase successful**

From this callback, you can for example unlock the UI by hiding your loading indicator.

*Example:*
``` swift
do {
    self.loaderView.show()
    try InAppPurchase.purchase(
        productIdentifier: productIdentifier,
        callback: { self.loaderView.hide() }
    )
} catch IAPError.productNotFound {
    print("IAPError: the product was not found on the App Store and cannot be purchased.")
} catch {
    print("An error occurred: \(error)")
}
```

#### Processing purchases
When a purchase is approved, money isn't yet to reach your bank account. You have to acknowledge delivery of the (virtual) item to finalize the transaction.

To achieve this, you have to add an [observer](https://developer.apple.com/documentation/foundation/notificationcenter/1415360-addobserver) of `iapProductPurchased` notifications. **Important:** Setup this handler **before** calling `InAppPurchase.initialize()`: purchase events can occur very early, as soon as your app starts.

Keep in mind that purchase notifications might occur even if you never called the `InAppPurchase.purchase()` function: purchases can be made from another device or the AppStore, they can be approved by parents when the app isn't running, purchase flows can be interupted, etc.

*Example:*

When the application did launch (*generally in the application delegate's `application didFinishLaunchingWithOptions` function*), we add our observer:
``` swift
func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
  NotificationCenter.default.addObserver(self, selector: #selector(productPurchased(_:)), name: .iapProductPurchased, object: nil)
  InAppPurchase.initialize(...)
}
```

Then define the handler:
``` swift
@objc func productPurchased(_ notification: Notification){
  // Get the product from the notification object.
  guard let product = notification.object as? SKProduct else {
      return
  }
  
  // Unlock product related content.


  // Finish the product transactions.
  InAppPurchase.finishTransactions(for: product.productIdentifier)
}
```

In simple cases, you can rely on the library to provide you with information about past purchases and no specific action is needed to unlock the product, just call `InAppPurchase.finishTransactions()`.

The last known state of the user's purchases is stored as [UserDefaults](https://developer.apple.com/documentation/foundation/userdefaults). As such, their status is always available to your app, even when offline. The `InAppPurchase.hasActivePurchase(for: productIdentifier)` method lets you to retrieve the ownership status of a product or subscription.

For more advanced use cases, implement your own unlocking logic and call `InAppPurchase.finishTransactions()` afterward.

*Note:* `iapProductPurchased` is emitted when a purchase has been confirmed by Fovea's receipt validator. If you have a server, it has probably already been notified of this purchase using the webhook.

*Tip:* After a successful purchase, you should now see a new transaction in [Fovea's dashboard](https://billing-dashboard.fovea.cc/transactions).

### Restoring purchases
Except if you only sell consumable products, Apple requires that you provide a "Restore Purchases" button to your users. In general, it is found in your application settings.

Call this method when this button is pressed.

``` swift
func restorePurchases() {
  self.loaderView.show()
  InAppPurchase.restorePurchases(callback: {
      self.loaderView.hide()
  })
}
```

The `callback` method is called once the operation is complete. You can use it to unlock the UI, by hiding your loader for example.

### Purchased products
As mentioned earlier, the library provides access to the state of the users purchases. See the [purchases information](#purchases-information) section.

Use `InAppPurchase.hasActivePurchase(for: productIdentifier)` to checks if the user currently own (or is subscribed to) a given product (nonConsumable or autoRenewableSubscription).


### Notifications
This is the list of notifications published to the by the library to the default NotificationCenter, for different events.

| name                             | description                                          | notification.object                                                                               |
| -------------------------------- | ---------------------------------------------------- | ------------------------------------------------------------------------------------------------- |
| `iapProductsLoaded`              | Products are loaded from the App Store.              |                                                                                                   |
| `iapRefreshProductsFailed`       | Failed to refresh products from the App Store.       | [`Error`](https://developer.apple.com/documentation/swift/error)                                  |
| `iapTransactionFailed`           | The transaction failed. See [`SKError.Code`](https://developer.apple.com/documentation/storekit/skerror/code). | [`SKPaymentTransaction`](https://developer.apple.com/documentation/storekit/skpaymenttransaction) |
| `iapTransactionDeferred`         | The transaction is deferred.                         | [`SKPaymentTransaction`](https://developer.apple.com/documentation/storekit/skpaymenttransaction) |
| `iapRestorationCompleted`        | All restorable transactions have been processed.     |                                                                                                   |
| `iapProductPurchased`            | The product is purchased.                            | [`SKProduct`](https://developer.apple.com/documentation/storekit/skproduct)                       |
| `iapRefreshReceiptFailed`        | Failed to refresh the App Store receipt.             | [`Error`](https://developer.apple.com/documentation/swift/error)                                  |
| `iapReceiptValidationFailed`     | Failed to validate the App Store receipt with Fovea. | May contain the [`Error`](https://developer.apple.com/documentation/swift/error)                  |
| `iapReceiptValidationSuccessful` | The App Store receipt is validated.                  |                                                                                                   |

See an example of using [iapProductPurchased](#processing-purchases) notifications.

**Example**

Register an [observer](https://developer.apple.com/documentation/foundation/notificationcenter/1415360-addobserver) for `iapTransactionFailed` notifications:
``` swift
NotificationCenter.default.addObserver(self, selector: #selector(transactionFailed(_:)), name: .iapTransactionFailed, object: nil)
```

Define your handler:
``` swift
@objc func transactionFailed(_ notification: Notification){
    guard let transaction = notification.object as? SKPaymentTransaction else {
        return
    }

    // Use the value of the error property to present a message to the user.
    // For a list of error constants, see https://developer.apple.com/documentation/storekit/skerror/code
    let errorCode = (transaction.error as? SKError)?.code
    switch errorCode {
    case .paymentCancelled:
        print("transactionFailed: The user canceled the payment request.")
    default:
        print("transactionFailed: \(errorCode!.rawValue).")
    }
}
```


### Purchases information
For convenience, the library provides some utility functions to check for your past purchases data (date, expiry date) and agregate information (has active subscription, ...).

- `func hasAlreadyPurchased() -> Bool` is a handy method that checks if the user has already purchased at least one product.
  ``` swift
  InAppPurchase.hasAlreadyPurchased()
  ```

- `func hasActivePurchase(for productIdentifier: String) -> Bool` checks if the user currently own (or is subscribed to) a given product (nonConsumable or autoRenewableSubscription).
``` swift
InAppPurchase.hasActivePurchase(for: productIdentifier)
```

- `func hasActiveSubscription() -> Bool` checks if the user has an active subscription.
  ``` swift
  InAppPurchase.hasActiveSubscription()
  ```

- `func getPurchaseDate(for productIdentifier: String) -> Date?` returns the latest purchased date for a given product.
  ``` swift
  InAppPurchase.getPurchaseDate(for: productIdentifier)
  ```

- `func getExpiryDate(for productIdentifier: String) -> Date?` returns the expiry date for a subcription. May be past or future.
  ``` swift
  InAppPurchase.getExpiryDate(for: productIdentifier)
  ```


## Server integration

In more advanced use cases, you have a server component. Users are logged in and you'll like to unlock the content for this user on your server. The safest approach is to setup a [Webhook on Fovea](https://billing.fovea.cc/documentation/webhook/). You'll receive notifications from Fovea that transaction have been processed and/or subscriptions updated.

The information sent from Fovea has been verified from Apple's server, which makes it way more trustable than information sent from your app itself.

To take advantage of this, you have to inform the library of your application username. This `applicationUsername` can be provided as a parameter of the `InAppPurchase.initialize` method and updated later by changing the associated property.

*Example:*
``` swift
InAppPurchase.initialize(
  iapProducts: [...],
  validatorUrlString: "..."),
  applicationUsername: UserSession.getUserId())

// later ...
InAppPurchase.applicationUsername = UserSession.getUserId()
```

Of course, in this case, you will want to delay calls to `InAppPurchase.initialize()` to when your user's session is ready.

## Xcode Demo Project
Do not hesitate to check the demo project available on here: [iap-swift-demo](https://github.com/iridescent-dev/iap-swift-demo).

## References
- TODO: API documentation - using https://github.com/swiftdocorg/swift-doc (?)
- [StoreKit Documentation](https://developer.apple.com/documentation/storekit/in-app_purchase)

## Troubleshooting
Common issues are covered here: https://github.com/iridescent-dev/iap-swift-lib/wiki/Troubleshooting

## License
InAppPurchaseLib is open-sourced library licensed under the MIT License. See [LICENSE](LICENSE) for details.
