import UIKit
import RxSwift
import CardFlight

class CardHandler: NSObject, CFTTransactionDelegate {

    private let _cardStatus = PublishSubject<String>()
    private var transaction: CFTTransaction?
    private var cardReader: CFTCardReaderInfo?

    var cardStatus: Observable<String> {
        return _cardStatus.asObservable()
    }

    var cardFlightCredentials: CFTCredentials {
        let credentials = CFTCredentials()
        credentials.setup(apiKey: self.APIKey, accountToken: self.APIToken, completion: nil)
        return credentials
    }

    var card: (cardInfo: CFTCardInfo, token: String)?


    let APIKey: String
    let APIToken: String

    init(apiKey: String, accountToken: String){
        APIKey = apiKey
        APIToken = accountToken

        super.init()

        self.transaction = CFTTransaction(delegate: self)
    }

    deinit {
        self.end()
    }

    func startSearching() {
        _cardStatus.onNext("Starting search...")
        let tokenizationParameters = CFTTokenizationParameters(customerId: nil, credentials: self.cardFlightCredentials)
        self.transaction?.beginTokenizing(tokenizationParameters: tokenizationParameters)
    }

    func end() {
        transaction?.select(processOption: CFTProcessOption.abort)
        transaction = nil
    }

    func transaction(_ transaction: CFTTransaction, didUpdate state: CFTTransactionState, error: Error?) {
        switch state {
        case .completed:
            _cardStatus.onNext("Transaction completed")
        case .processing:
            _cardStatus.onNext("Transaction processing")
        case .deferred:
            _cardStatus.onNext("Transaction deferred")
        case .pendingCardInput:
            _cardStatus.onNext("Pending card input")
            transaction.select(cardReaderInfo: cardReader, cardReaderModel: cardReader?.cardReaderModel ?? .unknown)
        case .pendingTransactionParameters:
            _cardStatus.onNext("Pending transaction parameters")
        case .unknown:
            _cardStatus.onNext("Unknown transactionstate")
        case .pendingProcessOption:
            break
        }
    }

    func transaction(_ transaction: CFTTransaction, didComplete historicalTransaction: CFTHistoricalTransaction) {
        if let cardInfo = historicalTransaction.cardInfo, let token = historicalTransaction.cardToken {
            self.card = (cardInfo: cardInfo, token: token)
            _cardStatus.onNext("Got Card")
            _cardStatus.onCompleted()
        } else {
            _cardStatus.onNext("Card Flight Error – could not retrieve card data.");
            if let error = historicalTransaction.error {
                _cardStatus.onNext("response Error \(error)");
                logger.log("CardReader got a response it cannot handle")
            }
            startSearching()
        }
    }

    func transaction(_ transaction: CFTTransaction, didReceive cardReaderEvent: CFTCardReaderEvent, cardReaderInfo: CFTCardReaderInfo?) {
        _cardStatus.onNext(cardReaderEvent.statusMessage)
    }

    func transaction(_ transaction: CFTTransaction, didUpdate cardReaderArray: [CFTCardReaderInfo]) {
        self.cardReader = cardReaderArray.first
        _cardStatus.onNext("Received new card reader availability, number of readers: \(cardReaderArray.count)")
    }

    func transaction(_ transaction: CFTTransaction, didRequestProcessOption cardInfo: CFTCardInfo) {
        logger.log("Received request for processing option, will process transaction.")
        _cardStatus.onNext("Request for process option, automatically processing...")
        transaction.select(processOption: .process)
        // TODO: CardFlight docs says we're supposed to confirm with the user before proceeding with the transaction,
        // but that's silly because we're only tokenizing and not not making an authorization or a charge.
    }

    func transaction(_ transaction: CFTTransaction, didRequestDisplay message: CFTMessage) {
        let message = message.primary ?? message.secondary ?? "Unknown message"
        logger.log("Received request to display message: \(message)")
        _cardStatus.onNext("Received message for user: \(message)")
        // TODO: Present message to user somehow
        // TODO: We want to show the user the custom messages but not messages confirming the transaction (see above,
        // it's not appropriate for tokenization). So we need to show the user _most_ messages but not messages
        // confirming transactions (that don't exist).
    }
}

typealias UnhandledDelegateCallbacks = CardHandler
/// We don't expect any of these functions to be called, but they are required for the delegate protocol.
extension UnhandledDelegateCallbacks {
    func transaction(_ transaction: CFTTransaction, didDefer transactionData: Data) {
        logger.log("Transaction has been deferred.")
        _cardStatus.onNext("Transaction deferred")
    }

    public func transaction(_ transaction: CFTTransaction, didRequest cvm: CFTCVM) {
        logger.log("Transaction requested signature from user, ignoring.")
        _cardStatus.onNext("Ignoring user signature request from CardFlight")
    }
}

extension CFTCardReaderEvent {
    var statusMessage: String {
        switch self {
        case .unknown:
            return "Unknown card event"
        case .disconnected:
            return "Reader is disconnected"
        case .connected:
            return "Reader is connected"
        case .connectionErrored:
            return "Connection error occurred"
        case .cardSwiped:
            return "Card swiped"
        case .cardSwipeErrored:
            return "Card swipe error"
        case .cardInserted:
            return "Card inserted"
        case .cardInsertErrored:
            return "Card insertion error"
        case .cardRemoved:
            return "Card removed"
        case .cardTapped:
            return "Card tapped"
        case .cardTapErrored:
            return "Card tap error"
        case .updateStarted:
            return "Update started"
        case .updateCompleted:
            return "Updated completed"
        case .audioRecordingPermissionNotGranted:
            return "iOS audio permissions no granted"
        case .fatalError:
            return "Fatal error"
        case .connecting:
            return "connecting"
        case .batteryStatusUpdated:
            return "battery status updated"
        }
    }
}
