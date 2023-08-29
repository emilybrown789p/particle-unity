//
//  UnityManager.swift
//  UnityFramework
//
//  Created by link on 2022/6/30.
//

import Base58_swift
import Foundation
import RxSwift
import SwiftyJSON
import UnityFramework

import ParticleAuthAdapter
import ParticleAuthService
import ParticleBiconomy
import ParticleNetworkBase
import ParticleWalletAPI
import ParticleWalletConnect
import ParticleWalletGUI

import ConnectCommon
import ParticleConnect

#if canImport(ConnectEVMAdapter)
import ConnectEVMAdapter
#endif

#if canImport(ConnectSolanaAdapter)
import ConnectSolanaAdapter
#endif

#if canImport(ConnectPhantomAdapter)
import ConnectPhantomAdapter
#endif

#if canImport(ConnectWalletConnectAdapter)
import ConnectWalletConnectAdapter
#endif

#if canImport(ParticleAuthCore)
import AuthCoreAdapter
import ParticleAuthCore
import ParticleMPCCore
import Thresh
#endif

import UIKit

@objcMembers
class UnityManager: NSObject, UnityFrameworkListener, NativeCallsProtocol {
    let bag = DisposeBag()
    
    static var shared = UnityManager()
    
    var ufw: UnityFramework?
    
    static let authSystemName = "ParticleAuthService"
    static let connectSystemName = "ParticleConnect"
    static let guiSystemName = "ParticleWalletGUI"
    static let aaSystemName = "ParticleAA"
    
    // work with connect sdk
    var latestPublicAddress: String?
    var latestWalletType: WalletType?
    let biconomy = BiconomyService()
    
#if canImport(ParticleAuthCore)
    let auth = Auth()
    static let authCoreSystemName = "ParticleAuthCore"
#endif
    
    override init() {
        super.init()
    }
    
    func startGame() {
        let ufw = unityFrameworkLoad()
        self.ufw = ufw
        ufw?.register(self)
        FrameworkLibAPI.registerAPIforNativeCalls(self)
        ufw?.runEmbedded(withArgc: CommandLine.argc, argv: CommandLine.unsafeArgv, appLaunchOpts: [:])
    }
    
    func unityFrameworkLoad() -> UnityFramework? {
        let bundlePath = Bundle.main.bundlePath.appending("/Frameworks/UnityFramework.framework")
        if let bundle = Bundle(path: bundlePath) {
            if !bundle.isLoaded {
                bundle.load()
            }
            if let ufw = (bundle.principalClass as? UnityFramework.Type)?.getInstance() {
                if ufw.appController() == nil {
                    ufw.setExecuteHeader(mhExecHeaderPtr)
                }
                return ufw
            }
        }

        return nil
    }
}

// MARK: - Particle Network Base

extension UnityManager {
    func initialize(_ json: String) {
        let data = JSON(parseJSON: json)
        let name = data["chain_name"].stringValue.lowercased()
        let chainId = data["chain_id"].intValue
        guard let chainInfo = ParticleNetwork.searchChainInfo(by: chainId) else {
            return print("initialize error, can't find right chain for \(name), chainId \(chainId)")
        }
        let env = data["env"].stringValue.lowercased()
        var devEnv: ParticleNetwork.DevEnvironment = .production
        if env == "dev" {
            devEnv = .debug
        } else if env == "staging" {
            devEnv = .staging
        } else if env == "production" {
            devEnv = .production
        }
        
        let config = ParticleNetworkConfiguration(chainInfo: chainInfo, devEnv: devEnv)
        ParticleNetwork.initialize(config: config)
    }
    
    func getDevEnv() -> Int {
        return ParticleNetwork.getDevEnv().rawValue
    }
    
    func setChainInfo(_ json: String) -> Bool {
        let data = JSON(parseJSON: json)
        let chainId = data["chain_id"].intValue
        guard let chainInfo = ParticleNetwork.searchChainInfo(by: chainId) else { return false }
        ParticleNetwork.setChainInfo(chainInfo)
        return true
    }
    
    func getChainInfo() -> String {
        let chainInfo = ParticleNetwork.getChainInfo()
        return ["chain_name": chainInfo.name, "chain_id": chainInfo.chainId, "chain_id_name": chainInfo.network].jsonString() ?? ""
    }
    
    func setLanguage(_ json: String) {
        /**
         ZH_CN,
         ZH_TW,
         EN,
         JA,
         KO,
         */
        
        if let language = getLanguage(from: json) {
            ParticleNetwork.setLanguage(language)
        }
    }
    
    func setWebAuthConfig(_ json: String) {
        let data = JSON(parseJSON: json)
        let appearanceString = data["appearance"].stringValue.lowercased()
        let displayWallet = data["display_wallet"].boolValue
        
        var appearance: UIUserInterfaceStyle = .unspecified
        if appearanceString == "system" {
            appearance = UIUserInterfaceStyle.unspecified
        } else if appearanceString == "light" {
            appearance = UIUserInterfaceStyle.light
        } else if appearanceString == "dark" {
            appearance = UIUserInterfaceStyle.dark
        }
        
        ParticleAuthService.setWebAuthConfig(options: .init(isDisplayWallet: displayWallet, appearance: appearance))
    }
    
    func setAppearance(_ json: String) {
        /**
         SYSTEM,
         LIGHT,
         DARK,
         */
        var appearance: UIUserInterfaceStyle = .unspecified
        if json.lowercased() == "system" {
            appearance = UIUserInterfaceStyle.unspecified
        } else if json.lowercased() == "light" {
            appearance = UIUserInterfaceStyle.light
        } else if json.lowercased() == "dark" {
            appearance = UIUserInterfaceStyle.dark
        }
        ParticleNetwork.setAppearance(appearance)
    }
    
    func setSecurityAccountConfig(_ json: String) {
        let data = JSON(parseJSON: json)
        let promptSettingWhenSign = data["prompt_setting_when_sign"].intValue
        let promptMasterPasswordSettingWhenLogin = data["prompt_master_password_setting_when_login"].intValue
        ParticleNetwork.setSecurityAccountConfig(config: .init(promptSettingWhenSign: promptSettingWhenSign, promptMasterPasswordSettingWhenLogin: promptMasterPasswordSettingWhenLogin))
    }
}

// MARK: - Particle Auth Service

extension UnityManager {
    func login(_ json: String) {
        let data = JSON(parseJSON: json)
        let loginType = LoginType(rawValue: data["loginType"].stringValue.lowercased()) ?? .email
        var supportAuthTypeArray: [SupportAuthType] = []
        
        let array = data["supportAuthTypeValues"].arrayValue.map {
            $0.stringValue.lowercased()
        }
        if array.contains("all") {
            supportAuthTypeArray = [.all]
        } else {
            array.forEach {
                if $0 == "email" {
                    supportAuthTypeArray.append(.email)
                } else if $0 == "phone" {
                    supportAuthTypeArray.append(.phone)
                } else if $0 == "apple" {
                    supportAuthTypeArray.append(.apple)
                } else if $0 == "google" {
                    supportAuthTypeArray.append(.google)
                } else if $0 == "facebook" {
                    supportAuthTypeArray.append(.facebook)
                } else if $0 == "github" {
                    supportAuthTypeArray.append(.github)
                } else if $0 == "twitch" {
                    supportAuthTypeArray.append(.twitch)
                } else if $0 == "microsoft" {
                    supportAuthTypeArray.append(.microsoft)
                } else if $0 == "linkedin" {
                    supportAuthTypeArray.append(.linkedin)
                } else if $0 == "discord" {
                    supportAuthTypeArray.append(.discord)
                } else if $0 == "twitter" {
                    supportAuthTypeArray.append(.twitter)
                }
            }
        }
        
        var account = data["account"].string
        if account != nil, account!.isEmpty {
            account = nil
        }
        let socialLoginPromptString = data["socialLoginPrompt"].stringValue.lowercased()
        var socialLoginPrompt: SocialLoginPrompt?
        if socialLoginPromptString == "none" {
            socialLoginPrompt = SocialLoginPrompt.none
        } else if socialLoginPromptString == "consent" {
            socialLoginPrompt = SocialLoginPrompt.consent
        } else if socialLoginPromptString == "selectaccount" {
            socialLoginPrompt = SocialLoginPrompt.selectAccount
        }
        
        let authorizationJson = data["authorization"]
        var loginAuthorization: LoginAuthorization?
        
        if authorizationJson == JSON.null {
            loginAuthorization = nil
        } else {
            let message: String? = authorizationJson["message"].stringValue
            let isUnique: Bool? = authorizationJson["uniq"].boolValue
            
            loginAuthorization = .init(message: message, isUnique: isUnique)
        }
        
        subscribeAndCallback(observable: ParticleAuthService.login(type: loginType, account: account, supportAuthType: supportAuthTypeArray, socialLoginPrompt: socialLoginPrompt, authorization: loginAuthorization).map { userInfo in
            let userInfoJsonString = userInfo?.jsonStringFullSnake()
            let newUserInfo = JSON(parseJSON: userInfoJsonString ?? "")
            return newUserInfo
        }, unityName: UnityManager.authSystemName)
    }
    
    func logout() {
        subscribeAndCallback(observable: ParticleAuthService.logout(), unityName: UnityManager.authSystemName)
    }
    
    func fastLogout() {
        subscribeAndCallback(observable: ParticleAuthService.fastLogout(), unityName: UnityManager.authSystemName)
    }
    
    func isLogin() -> Bool {
        return ParticleAuthService.isLogin()
    }
    
    func isLoginAsync() {
        subscribeAndCallback(observable: ParticleAuthService.isLoginAsync(), unityName: UnityManager.authSystemName)
    }
    
    func signMessage(_ message: String) {
        var serializedMessage = ""
        switch ParticleNetwork.getChainInfo().chain {
        case .solana:
            serializedMessage = Base58.encode(message.data(using: .utf8)!)
        default:
            serializedMessage = message
        }
        
        subscribeAndCallback(observable: ParticleAuthService.signMessage(serializedMessage), unityName: UnityManager.authSystemName)
    }
    
    func signMessageUnique(_ message: String) {
        subscribeAndCallback(observable: ParticleAuthService.signMessageUnique(message), unityName: UnityManager.authSystemName)
    }
    
    func signTransaction(_ transaction: String) {
        subscribeAndCallback(observable: ParticleAuthService.signTransaction(transaction), unityName: UnityManager.authSystemName)
    }
    
    func signAllTransactions(_ transactions: String) {
        let transactions = JSON(parseJSON: transactions).arrayValue.map { $0.stringValue }
        
        subscribeAndCallback(observable: ParticleAuthService.signAllTransactions(transactions), unityName: UnityManager.authSystemName)
    }
    
    func signAndSendTransaction(_ json: String) {
        let data = JSON(parseJSON: json)
        let transaction = data["transaction"].stringValue
        let mode = data["fee_mode"]["option"].stringValue
        var feeMode: Biconomy.FeeMode = .native
        if mode == "native" {
            feeMode = .native
        } else if mode == "gasless" {
            feeMode = .gasless
        } else if mode == "token" {
            let feeQuoteJson = JSON(data["fee_mode"]["fee_quote"].dictionaryValue)
            let tokenPaymasterAddress = data["fee_mode"]["token_paymaster_address"].stringValue
            let feeQuote = Biconomy.FeeQuote(json: feeQuoteJson, tokenPaymasterAddress: tokenPaymasterAddress)

            feeMode = .token(feeQuote)
        }
                
        let wholeFeeQuoteData = (try? data["fee_mode"]["whole_fee_quote"].rawData()) ?? Data()
        let wholeFeeQuote = try? JSONDecoder().decode(Biconomy.WholeFeeQuote.self, from: wholeFeeQuoteData)
                
        let biconomy = ParticleNetwork.getBiconomyService()
        var sendObservable: Single<String>
        if ParticleNetwork.getChainInfo().chain != .solana, biconomy != nil, biconomy!.isBiconomyModeEnable() {
            sendObservable = biconomy!.quickSendTransactions([transaction], feeMode: feeMode, messageSigner: self, wholeFeeQuote: wholeFeeQuote)
        } else {
            sendObservable = ParticleAuthService.signAndSendTransaction(transaction, feeMode: feeMode)
        }
        
        if ParticleNetwork.getChainInfo().chain != .solana {
            latestPublicAddress = ParticleAuthService.getAddress()
            latestWalletType = .particle
        }
        
        subscribeAndCallback(observable: sendObservable, unityName: UnityManager.authSystemName)
    }
    
    func batchSendTransactions(_ json: String) {
        let data = JSON(parseJSON: json)
        let transactions = data["transactions"].arrayValue.map {
            $0.stringValue
        }
        let mode = data["fee_mode"]["option"].stringValue
        var feeMode: Biconomy.FeeMode = .native
        if mode == "native" {
            feeMode = .native
        } else if mode == "gasless" {
            feeMode = .gasless
        } else if mode == "token" {
            let feeQuoteJson = JSON(data["fee_mode"]["fee_quote"].dictionaryValue)
            let tokenPaymasterAddress = data["fee_mode"]["token_paymaster_address"].stringValue
            let feeQuote = Biconomy.FeeQuote(json: feeQuoteJson, tokenPaymasterAddress: tokenPaymasterAddress)

            feeMode = .token(feeQuote)
        }
                
        let wholeFeeQuoteData = (try? data["fee_mode"]["whole_fee_quote"].rawData()) ?? Data()
        let wholeFeeQuote = try? JSONDecoder().decode(Biconomy.WholeFeeQuote.self, from: wholeFeeQuoteData)
                
        guard let biconomy = ParticleNetwork.getBiconomyService() else {
            print("biconomy is not init")
            return
        }
                
        guard biconomy.isBiconomyModeEnable() else {
            print("biconomy is not enable")
            return
        }
        
        latestPublicAddress = ParticleAuthService.getAddress()
        latestWalletType = .particle
        
        let sendObservable: Single<String> = biconomy.quickSendTransactions(transactions, feeMode: feeMode, messageSigner: self, wholeFeeQuote: wholeFeeQuote)
                
        subscribeAndCallback(observable: sendObservable, unityName: UnityManager.authSystemName)
    }
    
    func signTypedData(_ json: String) {
        let data = JSON(parseJSON: json)
        let message = data["message"].stringValue
        let version = data["version"].stringValue.lowercased()
        var signTypedDataVersion: EVMSignTypedDataVersion?
        if version == "v1" {
            signTypedDataVersion = .v1
        } else if version == "v3" {
            signTypedDataVersion = .v3
        } else if version == "v4" {
            signTypedDataVersion = .v4
        } else if version == "v4unique" {
            signTypedDataVersion = .v4Unique
        }
        
        subscribeAndCallback(observable: ParticleAuthService.signTypedData(message, version: signTypedDataVersion ?? .v4), unityName: UnityManager.authSystemName)
    }
    
    func getAddress() -> String {
        return ParticleAuthService.getAddress()
    }
    
    func getUserInfo() -> String {
        guard let userInfo = ParticleAuthService.getUserInfo() else {
            return ""
        }
        let userInfoJsonString = userInfo.jsonStringFullSnake()
        let newUserInfo = JSON(parseJSON: userInfoJsonString)
        let data = try! JSONEncoder().encode(newUserInfo)
        let json = String(data: data, encoding: .utf8)
        return json ?? ""
    }
    
    func getSecurityAccount() {
        subscribeAndCallback(observable: ParticleAuthService.getSecurityAccount().map { securityAccountInfo in
            
            let dict = ["phone": securityAccountInfo.phone,
                        "email": securityAccountInfo.email,
                        "has_set_master_password": securityAccountInfo.hasSetMasterPassword,
                        "has_set_payment_password": securityAccountInfo.hasSetPaymentPassword] as [String: Any?]
            let json = JSON(dict)
            return json
        }, unityName: UnityManager.authSystemName)
    }
    
    func setChainInfoAsync(_ json: String) {
        let data = JSON(parseJSON: json)
        let chainId = data["chain_id"].intValue
        guard let chainInfo = ParticleNetwork.searchChainInfo(by: chainId) else { return }
        if ParticleAuthService.isLogin() == false {
            ParticleNetwork.setChainInfo(chainInfo)
            let null: String? = nil
            let statusModel = UnityStatusModel(status: true, data: null)
            let data = try! JSONEncoder().encode(statusModel)
            guard let json = String(data: data, encoding: .utf8) else { return }
            callBackMessage(json, unityName: UnityManager.authSystemName)
            
        } else {
            subscribeAndCallback(observable: ParticleAuthService.switchChain(chainInfo).map { userInfo in
                let userInfoJsonString = userInfo?.jsonStringFullSnake()
                let newUserInfo = JSON(parseJSON: userInfoJsonString ?? "")
                return newUserInfo
            }, unityName: UnityManager.authSystemName)
        }
    }
    
    func setModalPresentStyle(_ style: String) {
        if style.lowercased() == "fullscreen" {
            ParticleAuthService.setModalPresentStyle(.fullScreen)
        } else {
            ParticleAuthService.setModalPresentStyle(.formSheet)
        }
    }
    
    func setMediumScreen(_ isMedium: Bool) {
        if #available(iOS 15.0, *) {
            ParticleAuthService.setMediumScreen(isMedium)
        } else {
            // Fallback on earlier versions
        }
    }
    
    func openWebWallet(_ json: String) {
        ParticleAuthService.openWebWallet(styleJsonString: json)
    }
    
    func openAccountAndSecurity() {
        subscribeAndCallback(observable: ParticleAuthService.openAccountAndSecurity().map { "" }, unityName: UnityManager.authSystemName)
    }
}

// MARK: - Particle Wallet GUI

extension UnityManager {
    func navigatorWallet(_ display: Int) {
        if display != 0 {
            PNRouter.navigatorWallet(display: .nft)
        } else {
            PNRouter.navigatorWallet(display: .token)
        }
    }
    
    func navigatorTokenReceive(_ json: String?) {
        PNRouter.navigatorTokenReceive(tokenReceiveConfig: TokenReceiveConfig(tokenAddress: json))
    }
    
    func navigatorTokenSend(_ json: String?) {
        if let json = json {
            let data = JSON(parseJSON: json)
            let tokenAddress = data["token_address"].string
            let toAddress = data["to_address"].string
            let amount = data["amount"].string
            let config = TokenSendConfig(tokenAddress: tokenAddress, toAddress: toAddress, amountString: amount)
            
            PNRouter.navigatorTokenSend(tokenSendConfig: config)
        } else {
            PNRouter.navigatorTokenSend()
        }
    }
    
    func navigatorTokenTransactionRecords(_ json: String?) {
        if let json = json {
            let config = TokenTransactionRecordsConfig(tokenAddress: json)
            PNRouter.navigatorTokenTransactionRecords(tokenTransactionRecordsConfig: config)
        } else {
            PNRouter.navigatorTokenTransactionRecords()
        }
    }
    
    func navigatorNFTSend(_ json: String) {
        let data = JSON(parseJSON: json)
        let address = data["mint"].stringValue
        let tokenId = data["token_id"].stringValue
        let toAddress = data["receiver_address"].string
        let amount = data["amount"].int
        let config = NFTSendConfig(address: address, toAddress: toAddress, tokenId: tokenId, amount: BInt(amount ?? 1))
        PNRouter.navigatorNFTSend(nftSendConfig: config)
    }
    
    func navigatorNFTDetails(_ json: String) {
        let data = JSON(parseJSON: json)
        let address = data["mint"].stringValue
        let tokenId = data["token_id"].stringValue
        let config = NFTDetailsConfig(address: address, tokenId: tokenId)
        PNRouter.navigatorNFTDetails(nftDetailsConfig: config)
    }
    
    func navigatorBuyCrypto(_ json: String) {
        let data = JSON(parseJSON: json)
        let walletAddress = data["wallet_address"].string
        let networkString = data["network"].stringValue.lowercased()
        var network: OpenBuyNetwork?
        
        if networkString == "solana" {
            network = .solana
        } else if networkString == "ethereum" {
            network = .ethereum
        } else if networkString == "binancesmartchain" {
            network = .binanceSmartChain
        } else if networkString == "optimism" {
            network = .optimism
        } else if networkString == "polygon" {
            network = .polygon
        } else if networkString == "tron" {
            network = .tron
        } else if networkString == "arbitrumOne" {
            network = .arbitrumOne
        } else {
            network = nil
        }
        if network == nil {
            let chainInfo = ParticleNetwork.getChainInfo()
            switch chainInfo.chain {
            case .solana:
                network = OpenBuyNetwork.solana
            case .ethereum:
                network = OpenBuyNetwork.ethereum
            case .bsc:
                network = OpenBuyNetwork.binanceSmartChain
            case .optimism:
                network = OpenBuyNetwork.optimism
            case .polygon:
                network = OpenBuyNetwork.polygon
            case .tron:
                network = OpenBuyNetwork.tron
            case .arbitrum:
                if chainInfo == .arbitrum(.one) {
                    network = OpenBuyNetwork.arbitrumOne
                } else {
                    network = nil
                }
            default:
                network = nil
            }
        }
        let fiatCoin = data["fiat_coin"].string
        let fiatAmt = data["fiat_amt"].int
        let cryptoCoin = data["crypto_coin"].string
        let fixCryptoCoin = data["fix_crypto_coin"].boolValue
        let fixFiatAmt = data["fix_fiat_amt"].boolValue
        let fixFiatCoin = data["fix_fiat_coin"].boolValue
        let theme = data["theme"].stringValue.lowercased()
        let language = getLanguage(from: data["language"].stringValue.lowercased())
        
        var buyConfig = BuyCryptoConfig()
        buyConfig.network = network
        buyConfig.walletAddress = walletAddress
        buyConfig.cryptoCoin = cryptoCoin ?? TokenInfo.nativeToken.symbol
        buyConfig.fiatAmt = fiatAmt
        if fiatCoin != nil {
            buyConfig.fiatCoin = fiatCoin!
        }
        buyConfig.fixCryptoCoin = fixCryptoCoin
        buyConfig.fixFiatCoin = fixFiatCoin
        buyConfig.fixFiatAmt = fixFiatAmt
        buyConfig.theme = theme
        buyConfig.language = language?.rawValue ?? Language.en.rawValue
        
        PNRouter.navigatorBuy(buyCryptoConfig: buyConfig)
    }
    
    func navigatorSwap(_ json: String?) {
        if let json = json {
            let data = JSON(parseJSON: json)
            let fromTokenAddress = data["from_token_address"].string
            let toTokenAddress = data["to_token_address"].string
            let amount = data["amount"].string
            let config = SwapConfig(fromTokenAddress: fromTokenAddress, toTokenAddress: toTokenAddress, fromTokenAmountString: amount)
            
            PNRouter.navigatorSwap(swapConfig: config)
        } else {
            PNRouter.navigatorSwap()
        }
    }
    
    func setShowTestNetwork(_ show: Bool) {
        ParticleWalletGUI.setShowTestNetwork(show)
    }
    
    func setShowManageWallet(_ show: Bool) {
        ParticleWalletGUI.setShowManageWallet(show)
    }
    
    func setSupportChain(_ json: String) {
        let chains = JSON(parseJSON: json).arrayValue.map {
            $0["chain_id"].intValue
        }.compactMap {
            ParticleNetwork.searchChainInfo(by: $0)?.chain
        }
        ParticleWalletGUI.setSupportChain(chains)
    }
    
    func setSwapDisabled(_ disabled: Bool) {
        ParticleWalletGUI.setSwapDisabled(disabled)
    }
    
    func getSwapDisabled() -> Bool {
        ParticleWalletGUI.getSwapDisabled()
    }
    
    func setPayDisabled(_ disabled: Bool) {
        ParticleWalletGUI.setPayDisabled(disabled)
    }
    
    func getPayDisabled() -> Bool {
        ParticleWalletGUI.getPayDisabled()
    }
    
    func navigatorLoginList(_ json: String?) {
        var observable: Single<(WalletType, Account?)>
        if let json = json {
            let array = JSON(parseJSON: json).arrayValue.map {
                $0.stringValue.lowercased()
            }
            
            var loginListPageSupportType: [LoginListSupportType] = []
            
            if array.contains("all") {
                loginListPageSupportType = LoginListSupportType.allCases
            } else {
                array.forEach { if $0 == "email" {
                    loginListPageSupportType.append(.email)
                } else if $0 == "phone" {
                    loginListPageSupportType.append(.phone)
                } else if $0 == "apple" {
                    loginListPageSupportType.append(.apple)
                } else if $0 == "google" {
                    loginListPageSupportType.append(.google)
                } else if $0 == "facebook" {
                    loginListPageSupportType.append(.facebook)
                } else if $0 == "github" {
                    loginListPageSupportType.append(.github)
                } else if $0 == "twitch" {
                    loginListPageSupportType.append(.twitch)
                } else if $0 == "microsoft" {
                    loginListPageSupportType.append(.microsoft)
                } else if $0 == "linkedin" {
                    loginListPageSupportType.append(.linkedin)
                } else if $0 == "discord" {
                    loginListPageSupportType.append(.discord)
                } else if $0 == "privatekey" {
                    loginListPageSupportType.append(.privateKey)
                } else if $0 == "metamask" {
                    loginListPageSupportType.append(.metamask)
                } else if $0 == "rainbow" {
                    loginListPageSupportType.append(.rainbow)
                } else if $0 == "trust" {
                    loginListPageSupportType.append(.trust)
                } else if $0 == "imtoken" {
                    loginListPageSupportType.append(.imtoken)
                } else if $0 == "bitkeep" {
                    loginListPageSupportType.append(.bitkeep)
                } else if $0 == "walletConnect" {
                    loginListPageSupportType.append(.walletConnect)
                } else if $0 == "twitter" {
                    loginListPageSupportType.append(.twitter)
                }
                }
            }
            if loginListPageSupportType.isEmpty {
                observable = PNRouter.navigatorLoginList()
            } else {
                observable = PNRouter.navigatorLoginList(supportTypes: loginListPageSupportType)
            }
        } else {
            observable = PNRouter.navigatorLoginList()
        }
        subscribeAndCallback(observable: observable.map { walletType, account in
            let unityLoginListModel = UnityLoginListModel(walletType: walletType.stringValue, account: account)
            return unityLoginListModel
        }, unityName: UnityManager.guiSystemName, methodName: "loginList")
    }
    
    func switchWallet(_ json: String) {
        let data = JSON(parseJSON: json)
        let walletTypeString = data["wallet_type"].stringValue
        let publicAddress = data["public_address"].stringValue
        
        if let walletType = map2WalletType(from: walletTypeString) {
            let result = ParticleWalletGUI.switchWallet(walletType: walletType, publicAddress: publicAddress)
            
            let statusModel = UnityStatusModel(status: true, data: result == true ? "success" : "failed")
            
            let data = try! JSONEncoder().encode(statusModel)
            guard let json = String(data: data, encoding: .utf8) else { return }
            callBackMessage(json, unityName: UnityManager.guiSystemName, methodName: "switchWallet")
        } else {
            print("walletType \(walletTypeString) is not existed")
            let response = UnityResponseError(code: nil, message: "walletType \(walletTypeString) is not existed", data: nil)
            let statusModel = UnityStatusModel(status: false, data: response)
            let data = try! JSONEncoder().encode(statusModel)
            guard let json = String(data: data, encoding: .utf8) else { return }
            callBackMessage(json, unityName: UnityManager.guiSystemName, methodName: "switchWallet")
        }
    }
    
    private func getLanguage(from json: String) -> Language? {
        var language: Language?
        if json.lowercased() == "en" {
            language = Language.en
        } else if json.lowercased() == "zh_cn" {
            language = Language.zh_Hans
        } else if json.lowercased() == "zh_tw" {
            language = Language.zh_Hant
        } else if json.lowercased() == "ko" {
            language = Language.ko
        } else if json.lowercased() == "ja" {
            language = Language.ja
        }
        return language
    }
    
    func setShowLanguageSetting(_ show: Bool) {
        ParticleWalletGUI.setShowLanguageSetting(show)
    }
    
    func setShowAppearanceSetting(_ show: Bool) {
        ParticleWalletGUI.setShowAppearanceSetting(show)
    }
    
    func setSupportWalletConnect(_ enable: Bool) {
        ParticleWalletGUI.setSupportWalletConnect(enable)
    }
    
    func setSupportDappBrowser(_ enable: Bool) {
        ParticleWalletGUI.setSupportDappBrowser(enable)
    }
    
    func particleWalletConnectInitialize(_ json: String) {
        let data = JSON(parseJSON: json)
        let name = data["name"].stringValue
        let iconString = data["icon"].stringValue
        let urlString = data["url"].stringValue
        let description = data["description"].string
        
        let walletConnectV2ProjectId = data["walletConnectProjectId"].stringValue
        
        let icon = URL(string: iconString) != nil ? URL(string: iconString)! : URL(string: "https://static.particle.network/wallet-icons/Particle.png")!
        
        let url = URL(string: urlString) != nil ? URL(string: urlString)! : URL(string: "https://static.particle.network")!
        
        let walletMetaData = WalletMetaData(name: name, icon: icon, url: url, description: description)
        
        ParticleWalletConnect.initialize(walletMetaData)
        ParticleWalletConnect.setWalletConnectV2ProjectId(walletConnectV2ProjectId)
    }
    
    func setSupportAddToken(_ enable: Bool) {
        ParticleWalletGUI.setSupportAddToken(enable)
    }
    
    func setDisplayTokenAddresses(_ json: String) {
        let data = JSON(parseJSON: json)
        let tokenAddresses = data.arrayValue.map {
            $0.stringValue
        }
        ParticleWalletGUI.setDisplayTokenAddresses(tokenAddresses)
    }

    func setDisplayNFTContractAddresses(_ json: String) {
        let data = JSON(parseJSON: json)
        let nftContractAddresses = data.arrayValue.map {
            $0.stringValue
        }
        ParticleWalletGUI.setDisplayNFTContractAddresses(nftContractAddresses)
    }
    
    func setPriorityTokenAddresses(_ json: String) {
        let data = JSON(parseJSON: json)
        let tokenAddresses = data.arrayValue.map {
            $0.stringValue
        }
        ParticleWalletGUI.setPriorityTokenAddresses(tokenAddresses)
    }

    func setPriorityNFTContractAddresses(_ json: String) {
        let data = JSON(parseJSON: json)
        let nftContractAddresses = data.arrayValue.map {
            $0.stringValue
        }
        ParticleWalletGUI.setPriorityNFTContractAddresses(nftContractAddresses)
    }

    func setFiatCoin(_ json: String) {
        /*
         USD, CNY, JPY, HKD, INR, KRW.
         */
        
        if json.lowercased() == "usd" {
            ParticleNetwork.setFiatCoin(.usd)
        } else if json.lowercased() == "cny" {
            ParticleNetwork.setFiatCoin(.cny)
        } else if json.lowercased() == "jpy" {
            ParticleNetwork.setFiatCoin(.jpy)
        } else if json.lowercased() == "hkd" {
            ParticleNetwork.setFiatCoin(.hkd)
        } else if json.lowercased() == "inr" {
            ParticleNetwork.setFiatCoin(.inr)
        } else if json.lowercased() == "krw" {
            ParticleNetwork.setFiatCoin(.krw)
        }
    }

    func loadCustomUIJsonString(_ json: String) {
        let jsonString = json
        do {
            try ParticleWalletGUI.loadCustomUIJsonString(jsonString)
        } catch {
            print("loadCustomUIJsonString error = \(error)")
        }
    }
    
    func setCustomWalletName(_ json: String) {
        let data = JSON(parseJSON: json)

        let name = data["name"].stringValue
        let icon = data["icon"].stringValue

        ConnectManager.setCustomWalletName(walletType: .particle, name: .init(name: name, icon: icon))
        ConnectManager.setCustomWalletName(walletType: .authCore, name: .init(name: name, icon: icon))
    }
    
    func setCustomLocalizable(_ json: String) {
        let data = JSON(parseJSON: json).dictionaryValue
        
        var localizables: [Language: [String: String]] = [:]
        
        for (key, value) in data {
            let language = getLanguage(from: key.lowercased())
            if language == nil {
                continue
            }
            
            let itemLocalizables = value.dictionaryValue.mapValues { json in
                json.stringValue
            }
            localizables[language!] = itemLocalizables
        }
         
        ParticleWalletGUI.setCustomLocalizable(localizables)
    }
}

// MARK: - Particle Connect

extension UnityManager {
    func particleConnectInitialize(_ json: String) {
        let data = JSON(parseJSON: json)
        let chainName = data["chain_name"].stringValue.lowercased()
        let chainId = data["chain_id"].intValue
        guard let chainInfo = ParticleNetwork.searchChainInfo(by: chainId) else {
            return print("initialize error, can't find right chain for \(chainName), chainId \(chainId)")
        }
        let env = data["env"].stringValue.lowercased()
        var devEnv: ParticleNetwork.DevEnvironment = .production
        if env == "dev" {
            devEnv = .debug
        } else if env == "staging" {
            devEnv = .staging
        } else if env == "production" {
            devEnv = .production
        }
        
        let walletConnectProjectId = data["metadata"]["walletConnectProjectId"].stringValue
        ParticleConnect.setWalletConnectV2ProjectId(walletConnectProjectId)
        let dAppName = data["metadata"]["name"].stringValue
        let dAppIconString = data["metadata"]["icon"].stringValue
        let dAppUrlString = data["metadata"]["url"].stringValue
        
        let dAppIconUrl = URL(string: dAppIconString) != nil ? URL(string: dAppIconString)! : URL(string: "https://static.particle.network/wallet-icons/Particle.png")!
        
        let dAppUrl = URL(string: dAppUrlString) != nil ? URL(string: dAppUrlString)! : URL(string: "https://static.particle.network")!
        let description = data["metaData"]["description"].stringValue
        
        let dAppData = DAppMetaData(name: dAppName, icon: dAppIconUrl, url: dAppUrl, description: description)
        
        var adapters: [ConnectAdapter] = [ParticleAuthAdapter()]
#if canImport(ConnectEVMAdapter)
        let evmRpcUrl = data["rpc_url"]["evm_url"].stringValue
        if evmRpcUrl.isEmpty {
            adapters.append(EVMConnectAdapter())
        } else {
            adapters.append(EVMConnectAdapter(rpcUrl: evmRpcUrl))
        }
#endif
        
#if canImport(ConnectSolanaAdapter)
        let solanaRpcUrl = data["rpc_url"]["sol_url"].stringValue
        if solanaRpcUrl.isEmpty {
            adapters.append(SolanaConnectAdapter())
        } else {
            adapters.append(SolanaConnectAdapter(rpcUrl: solanaRpcUrl))
        }
#endif
        
#if canImport(ConnectPhantomAdapter)
        adapters.append(PhantomConnectAdapter())
#endif
        
#if canImport(ConnectWalletConnectAdapter)
        adapters.append(contentsOf: [
            MetaMaskConnectAdapter(),
            RainbowConnectAdapter(),
            BitkeepConnectAdapter(),
            ImtokenConnectAdapter(),
            TrustConnectAdapter(),
            WalletConnectAdapter()
        ])
        
        let moreAdapterClasses: [WalletConnectAdapter.Type] =
            [ZerionConnectAdapter.self,
             MathConnectAdapter.self,
             OmniConnectAdapter.self,
             Inch1ConnectAdapter.self,
             ZengoConnectAdapter.self,
             AlphaConnectAdapter.self,
             BitpieConnectAdapter.self]

        adapters.append(contentsOf: moreAdapterClasses.map {
            $0.init()
        })
#endif
        
        ParticleConnect.initialize(env: devEnv, chainInfo: chainInfo, dAppData: dAppData) {
            adapters
        }
    }
    
    func adapterGetAccounts(_ json: String) -> String {
        let walletTypeString = json
        guard let walletType = map2WalletType(from: walletTypeString) else {
            print("walletType \(walletTypeString) is not existed ")
            let response = UnityResponseError(code: nil, message: "walletType \(walletTypeString) is not existed", data: nil)
            let statusModel = UnityStatusModel(status: false, data: response)
            let data = try! JSONEncoder().encode(statusModel)
            guard let json = String(data: data, encoding: .utf8) else { return "" }
            return json
        }
        guard let adapter = map2ConnectAdapter(from: walletType) else {
            print("adapter for \(walletTypeString) is not init ")
            let response = UnityResponseError(code: nil, message: "adapter for \(walletTypeString) is not init", data: nil)
            let statusModel = UnityStatusModel(status: false, data: response)
            let data = try! JSONEncoder().encode(statusModel)
            guard let json = String(data: data, encoding: .utf8) else { return "" }
            return json
        }
        
        let accounts = adapter.getAccounts()
        let statusModel = UnityStatusModel(status: true, data: accounts)
        let data = try! JSONEncoder().encode(statusModel)
        let json = String(data: data, encoding: .utf8) ?? ""
        
        return json
    }
    
    func adapterConnect(_ json: String, configJson: String) {
        let walletTypeString = json
        
        var connectConfig: ParticleAuthConfig?
        if !configJson.isEmpty {
            let data = JSON(parseJSON: configJson)
            let loginType = LoginType(rawValue: data["loginType"].stringValue.lowercased()) ?? .email
            var supportAuthTypeArray: [SupportAuthType] = []
            
            let array = data["supportAuthTypeValues"].arrayValue.map {
                $0.stringValue.lowercased()
            }
            if array.contains("all") {
                supportAuthTypeArray = [.all]
            } else {
                array.forEach { if $0 == "email" {
                    supportAuthTypeArray.append(.email)
                } else if $0 == "phone" {
                    supportAuthTypeArray.append(.phone)
                } else if $0 == "apple" {
                    supportAuthTypeArray.append(.apple)
                } else if $0 == "google" {
                    supportAuthTypeArray.append(.google)
                } else if $0 == "facebook" {
                    supportAuthTypeArray.append(.facebook)
                } else if $0 == "github" {
                    supportAuthTypeArray.append(.github)
                } else if $0 == "twitch" {
                    supportAuthTypeArray.append(.twitch)
                } else if $0 == "microsoft" {
                    supportAuthTypeArray.append(.microsoft)
                } else if $0 == "linkedin" {
                    supportAuthTypeArray.append(.linkedin)
                } else if $0 == "discord" {
                    supportAuthTypeArray.append(.discord)
                } else if $0 == "twitter" {
                    supportAuthTypeArray.append(.twitter)
                }
                }
            }
            
            var account = data["account"].string
            
            if account != nil, account!.isEmpty {
                account = nil
            }
            
            let socialLoginPromptString = data["socialLoginPrompt"].stringValue.lowercased()
            var socialLoginPrompt: SocialLoginPrompt?
            if socialLoginPromptString == "none" {
                socialLoginPrompt = SocialLoginPrompt.none
            } else if socialLoginPromptString == "consent" {
                socialLoginPrompt = SocialLoginPrompt.consent
            } else if socialLoginPromptString == "selectaccount" {
                socialLoginPrompt = SocialLoginPrompt.selectAccount
            }
            
            let authorizationJson = data["authorization"]
            var loginAuthorization: LoginAuthorization?
            
            if authorizationJson == JSON.null {
                loginAuthorization = nil
            } else {
                let message: String? = authorizationJson["message"].stringValue
                let isUnique: Bool? = authorizationJson["uniq"].boolValue
                
                loginAuthorization = .init(message: message, isUnique: isUnique)
            }

            connectConfig = ParticleAuthConfig(loginType: loginType, supportAuthType: supportAuthTypeArray, phoneOrEmailAccount: account, socialLoginPrompt: socialLoginPrompt, authorization: loginAuthorization)
        }
        
        guard let walletType = map2WalletType(from: walletTypeString) else {
            print("walletType \(walletTypeString) is not existed ")
            return
        }
        guard let adapter = map2ConnectAdapter(from: walletType) else {
            print("adapter for \(walletTypeString) is not init ")
            return
        }
        
        guard let vc = ufw?.appController().rootViewController else {
            print("unity root view controller is nil")
            return
        }
        
        var observable: Single<Account?>
        if walletType == .walletConnect {
            observable = (adapter as! WalletConnectAdapter).connectWithQrCode(from: vc)
        } else if walletType == .particle {
            observable = adapter.connect(connectConfig)
        } else {
            observable = adapter.connect(ConnectConfig.none)
        }
        
        subscribeAndCallback(observable: observable, unityName: UnityManager.connectSystemName, methodName: "connect")
    }
    
    func adapterDisconnect(_ json: String) {
        let data = JSON(parseJSON: json)
        let walletTypeString = data["wallet_type"].stringValue
        let publicAddress = data["public_address"].stringValue
        
        guard let walletType = map2WalletType(from: walletTypeString) else {
            print("walletType \(walletTypeString) is not existed ")
            return
        }
        guard let adapter = map2ConnectAdapter(from: walletType) else {
            print("adapter for \(walletTypeString) is not init ")
            return
        }
        
        subscribeAndCallback(observable: adapter.disconnect(publicAddress: publicAddress), unityName: UnityManager.connectSystemName, methodName: "disconnect")
    }
    
    func adapterIsConnected(_ json: String) -> Bool {
        let data = JSON(parseJSON: json)
        let walletTypeString = data["wallet_type"].stringValue
        let publicAddress = data["public_address"].stringValue
        
        guard let walletType = map2WalletType(from: walletTypeString) else {
            print("walletType \(walletTypeString) is not existed ")
            return false
        }
        guard let adapter = map2ConnectAdapter(from: walletType) else {
            print("adapter for \(walletTypeString) is not init ")
            return false
        }
        
        return adapter.isConnected(publicAddress: publicAddress)
    }
    
    func adapterSignAndSendTransaction(_ json: String) {
        let data = JSON(parseJSON: json)
        let walletTypeString = data["wallet_type"].stringValue
        let publicAddress = data["public_address"].stringValue
        let transaction = data["transaction"].stringValue
                
        guard let walletType = map2WalletType(from: walletTypeString) else {
            print("walletType \(walletTypeString) is not existed ")
            return
        }
                
        let mode = data["fee_mode"]["option"].stringValue
        var feeMode: Biconomy.FeeMode = .native
        if mode == "native" {
            feeMode = .native
        } else if mode == "gasless" {
            feeMode = .gasless
        } else if mode == "token" {
            let feeQuoteJson = JSON(data["fee_mode"]["fee_quote"].dictionaryValue)
            let tokenPaymasterAddress = data["fee_mode"]["token_paymaster_address"].stringValue
            let feeQuote = Biconomy.FeeQuote(json: feeQuoteJson, tokenPaymasterAddress: tokenPaymasterAddress)

            feeMode = .token(feeQuote)
        }
                
        let wholeFeeQuoteData = (try? data["fee_mode"]["whole_fee_quote"].rawData()) ?? Data()
        let wholeFeeQuote = try? JSONDecoder().decode(Biconomy.WholeFeeQuote.self, from: wholeFeeQuoteData)
        
        guard let adapter = map2ConnectAdapter(from: walletType) else {
            print("adapter for \(walletTypeString) is not init ")
            return
        }
        if ParticleNetwork.getChainInfo().chain != .solana {
            latestPublicAddress = publicAddress
            latestWalletType = walletType
        }
        
        let biconomy = ParticleNetwork.getBiconomyService()
        var sendObservable: Single<String>
        if biconomy != nil, biconomy!.isBiconomyModeEnable() {
            sendObservable = biconomy!.quickSendTransactions([transaction], feeMode: feeMode, messageSigner: self, wholeFeeQuote: wholeFeeQuote)
        } else {
            sendObservable = adapter.signAndSendTransaction(publicAddress: publicAddress, transaction: transaction, feeMode: feeMode)
        }
                
        subscribeAndCallback(observable: sendObservable, unityName: UnityManager.connectSystemName, methodName: "signAndSendTransaction")
    }
    
    func adapterBatchSendTransactions(_ json: String) {
        let data = JSON(parseJSON: json)
        let transactions = data["transactions"].arrayValue.map {
            $0.stringValue
        }
        let walletTypeString = data["wallet_type"].stringValue
        let publicAddress = data["public_address"].stringValue
                
        guard let walletType = map2WalletType(from: walletTypeString) else {
            print("walletType \(walletTypeString) is not existed ")
            return
        }
                
        let mode = data["fee_mode"]["option"].stringValue
        var feeMode: Biconomy.FeeMode = .native
        if mode == "native" {
            feeMode = .native
        } else if mode == "gasless" {
            feeMode = .gasless
        } else if mode == "token" {
            let feeQuoteJson = JSON(data["fee_mode"]["fee_quote"].dictionaryValue)
            let tokenPaymasterAddress = data["fee_mode"]["token_paymaster_address"].stringValue
            let feeQuote = Biconomy.FeeQuote(json: feeQuoteJson, tokenPaymasterAddress: tokenPaymasterAddress)

            feeMode = .token(feeQuote)
        }
                
        let wholeFeeQuoteData = (try? data["fee_mode"]["whole_fee_quote"].rawData()) ?? Data()
        let wholeFeeQuote = try? JSONDecoder().decode(Biconomy.WholeFeeQuote.self, from: wholeFeeQuoteData)
        guard let biconomy = ParticleNetwork.getBiconomyService() else {
            print("aa is not init")
            return
        }
                
        guard biconomy.isBiconomyModeEnable() else {
            print("aa is not enable")
            return
        }
              
        latestPublicAddress = publicAddress
        latestWalletType = walletType
                
        let sendObservable = biconomy.quickSendTransactions(transactions, feeMode: feeMode, messageSigner: self, wholeFeeQuote: wholeFeeQuote)
        subscribeAndCallback(observable: sendObservable, unityName: UnityManager.connectSystemName, methodName: "batchSendTransactions")
    }
    
    func adapterSignTransaction(_ json: String) {
        let data = JSON(parseJSON: json)
        let walletTypeString = data["wallet_type"].stringValue
        let publicAddress = data["public_address"].stringValue
        let transaction = data["transaction"].stringValue
        
        guard let walletType = map2WalletType(from: walletTypeString) else {
            print("walletType \(walletTypeString) is not existed ")
            return
        }
        guard let adapter = map2ConnectAdapter(from: walletType) else {
            print("adapter for \(walletTypeString) is not init ")
            return
        }
        
        subscribeAndCallback(observable: adapter.signTransaction(publicAddress: publicAddress, transaction: transaction), unityName: UnityManager.connectSystemName, methodName: "signTransaction")
    }
    
    func adapterSignAllTransactions(_ json: String) {
        let data = JSON(parseJSON: json)
        let walletTypeString = data["wallet_type"].stringValue
        let publicAddress = data["public_address"].stringValue
        
        let transactions = data["transactions"].arrayValue.map {
            $0.stringValue
        }
        
        guard let walletType = map2WalletType(from: walletTypeString) else {
            print("walletType \(walletTypeString) is not existed ")
            return
        }
        
        guard let adapter = map2ConnectAdapter(from: walletType) else {
            print("adapter for \(walletTypeString) is not init ")
            return
        }
        
        subscribeAndCallback(observable: adapter.signAllTransactions(publicAddress: publicAddress, transactions: transactions), unityName: UnityManager.connectSystemName, methodName: "signAllTransactions")
    }
    
    func adapterSignMessage(_ json: String) {
        let data = JSON(parseJSON: json)
        let walletTypeString = data["wallet_type"].stringValue
        let publicAddress = data["public_address"].stringValue
        let message = data["message"].stringValue
        
        guard let walletType = map2WalletType(from: walletTypeString) else {
            print("walletType \(walletTypeString) is not existed ")
            return
        }
        
        guard let adapter = map2ConnectAdapter(from: walletType) else {
            print("adapter for \(walletTypeString) is not init ")
            return
        }
        
        subscribeAndCallback(observable: adapter.signMessage(publicAddress: publicAddress, message: message), unityName: UnityManager.connectSystemName, methodName: "signMessage")
    }
    
    func adapterSignTypedData(_ json: String) {
        let data = JSON(parseJSON: json)
        let walletTypeString = data["wallet_type"].stringValue
        let publicAddress = data["public_address"].stringValue
        let message = data["message"].stringValue
        
        guard let walletType = map2WalletType(from: walletTypeString) else {
            print("walletType \(walletTypeString) is not existed ")
            return
        }
        
        guard let adapter = map2ConnectAdapter(from: walletType) else {
            print("adapter for \(walletTypeString) is not init ")
            return
        }
        
        subscribeAndCallback(observable: adapter.signTypedData(publicAddress: publicAddress, data: message), unityName: UnityManager.connectSystemName, methodName: "signTypedData")
    }
    
    func adapterImportWallet(fromPrivateKey json: String) {
        let data = JSON(parseJSON: json)
        let walletTypeString = data["wallet_type"].stringValue
        let privateKey = data["private_key"].stringValue
        
        guard let walletType = map2WalletType(from: walletTypeString) else {
            print("walletType \(walletTypeString) is not existed ")
            return
        }
        
        guard walletType == WalletType.evmPrivateKey || walletType == WalletType.solanaPrivateKey else {
            print("walletType \(walletTypeString) is not support import from private key ")
            return
        }
        
        guard let adapter = map2ConnectAdapter(from: walletType) else {
            print("adapter for \(walletTypeString) is not init ")
            return
        }
        
        subscribeAndCallback(observable: (adapter as! LocalAdapter).importWalletFromPrivateKey(privateKey), unityName: UnityManager.connectSystemName, methodName: "importWalletFromPrivateKey")
    }
    
    func adapterImportWallet(fromMnemonic json: String) {
        let data = JSON(parseJSON: json)
        let walletTypeString = data["wallet_type"].stringValue
        let mnemonic = data["mnemonic"].stringValue
        
        guard let walletType = map2WalletType(from: walletTypeString) else {
            print("walletType \(walletTypeString) is not existed ")
            return
        }
        
        guard walletType == WalletType.evmPrivateKey || walletType == WalletType.solanaPrivateKey else {
            print("walletType \(walletTypeString) is not support import from mnemonic ")
            return
        }
        
        guard let adapter = map2ConnectAdapter(from: walletType) else {
            print("adapter for \(walletTypeString) is not init ")
            return
        }
        
        subscribeAndCallback(observable: (adapter as! LocalAdapter).importWalletFromMnemonic(mnemonic), unityName: UnityManager.connectSystemName, methodName: "importWalletFromMnemonic")
    }
    
    func adapterExportWalletPrivateKey(_ json: String) {
        let data = JSON(parseJSON: json)
        let walletTypeString = data["wallet_type"].stringValue
        let publicAddress = data["public_address"].stringValue
        
        guard let walletType = map2WalletType(from: walletTypeString) else {
            print("walletType \(walletTypeString) is not existed ")
            return
        }
        
        guard walletType == WalletType.evmPrivateKey || walletType == WalletType.solanaPrivateKey else {
            print("walletType \(walletTypeString) is not support import from mnemonic ")
            return
        }
        
        guard let adapter = map2ConnectAdapter(from: walletType) else {
            print("adapter for \(walletTypeString) is not init ")
            return
        }
        
        subscribeAndCallback(observable: (adapter as! LocalAdapter).exportWalletPrivateKey(publicAddress: publicAddress), unityName: UnityManager.connectSystemName, methodName: "exportWalletPrivateKey")
    }
    
    func adapterLogin(_ json: String) {
        let data = JSON(parseJSON: json)
        let walletTypeString = data["wallet_type"].stringValue
        let publicAddress = data["public_address"].stringValue
        let domain = data["domain"].stringValue
        guard let uri = URL(string: data["uri"].stringValue) else { return }
        
        guard let walletType = map2WalletType(from: walletTypeString) else {
            print("walletType \(walletTypeString) is not existed ")
            return
        }
        
        guard let adapter = map2ConnectAdapter(from: walletType) else {
            print("adapter for \(walletTypeString) is not init ")
            return
        }
        
        guard let siwe = try? SiweMessage(domain: domain, address: publicAddress, uri: uri) else {
            print("domain \(domain), address \(publicAddress), uri \(uri) is not valid data")
            return
        }
        
        subscribeAndCallback(observable: adapter.login(config: siwe, publicAddress: publicAddress).map { sourceMessage, signedMessage in
            UnityConnectLoginResult(message: sourceMessage, signature: signedMessage)
        }, unityName: UnityManager.connectSystemName, methodName: "login")
    }
    
    func adapterVerify(_ json: String) {
        let data = JSON(parseJSON: json)
        let walletTypeString = data["wallet_type"].stringValue
        let message = data["message"].stringValue

        var signature = data["signature"].stringValue
                
        if ConnectManager.getChainType() == .solana {
            signature = Base58.encode(Data(base64Encoded: signature)!)
        }
                
        guard let walletType = map2WalletType(from: walletTypeString) else {
            print("walletType \(walletTypeString) is not existed ")
            return
        }
        
        guard let adapter = map2ConnectAdapter(from: walletType) else {
            print("adapter for \(walletTypeString) is not init ")
            return
        }
        
        guard let siwe = try? SiweMessage(message) else {
            print("message is not valid siwe")
            return
        }
        
        subscribeAndCallback(observable: adapter.verify(message: siwe, against: signature), unityName: UnityManager.connectSystemName, methodName: "verify")
    }
    
    func adapterAddEthereumChain(_ json: String) {
        let data = JSON(parseJSON: json)
        
        let walletTypeString = data["wallet_type"].stringValue
        let publicAddress = data["public_address"].stringValue
        let chainId = data["chain_id"].intValue
        let chainName = data["chain_name"].string
        let rpcUrl = data["rpc_url"].string
        let blockExplorerUrl = data["block_explorer_url"].string
        let nativeCurrencyName = data["native_currency"]["name"].string
        let nativeCurrencySymbol = data["native_currency"]["symbol"].string
        let nativeCurrencyDecimals = data["native_currency"]["decimals"].uInt8
        
        var nativeCurrency: NativeCurrency?
        if nativeCurrencyName != nil, nativeCurrencySymbol != nil, nativeCurrencyDecimals != nil {
            nativeCurrency = NativeCurrency(name: nativeCurrencyName!, symbol: nativeCurrencySymbol!, decimals: nativeCurrencyDecimals!)
        }
        
        guard let walletType = map2WalletType(from: walletTypeString) else {
            print("walletType \(walletTypeString) is not existed ")
            return
        }
        
        guard let adapter = map2ConnectAdapter(from: walletType) else {
            print("adapter for \(walletTypeString) is not init ")
            return
        }
        
        subscribeAndCallback(observable: adapter.addEthereumChain(publicAddress: publicAddress, chainId: chainId, chainName: chainName, nativeCurrency: nativeCurrency, rpcUrl: rpcUrl, blockExplorerUrl: blockExplorerUrl), unityName: UnityManager.connectSystemName, methodName: "addEthereumChain")
    }
    
    func adapterSwitchEthereumChain(_ json: String) {
        let data = JSON(parseJSON: json)
            
        let walletTypeString = data["wallet_type"].stringValue
        let publicAddress = data["public_address"].stringValue
        let chainId = data["chain_id"].intValue
        
        guard let walletType = map2WalletType(from: walletTypeString) else {
            print("walletType \(walletTypeString) is not existed ")
            return
        }
        
        guard let adapter = map2ConnectAdapter(from: walletType) else {
            print("adapter for \(walletTypeString) is not init ")
            return
        }
        
        subscribeAndCallback(observable: adapter.switchEthereumChain(publicAddress: publicAddress, chainId: chainId), unityName: UnityManager.connectSystemName, methodName: "switchEthereumChain")
    }
    
    func adapterWalletReadyState(_ json: String) -> String {
        let data = JSON(parseJSON: json)
        let walletTypeString = data["wallet_type"].stringValue

        guard let walletType = map2WalletType(from: walletTypeString) else {
            print("walletType \(walletTypeString) is not existed ")
            let response = UnityResponseError(code: nil, message: "walletType \(walletTypeString) is not existed", data: nil)
            let statusModel = UnityStatusModel(status: false, data: response)
            let data = try! JSONEncoder().encode(statusModel)
            guard let json = String(data: data, encoding: .utf8) else { return "" }
            return json
        }
        guard let adapter = map2ConnectAdapter(from: walletType) else {
            print("adapter for \(walletTypeString) is not init ")
            let response = UnityResponseError(code: nil, message: "adapter for \(walletTypeString) is not init", data: nil)
            let statusModel = UnityStatusModel(status: false, data: response)
            let data = try! JSONEncoder().encode(statusModel)
            guard let json = String(data: data, encoding: .utf8) else { return "" }
            return json
        }

        var str: String
        switch adapter.readyState {
        case .installed:
            str = "installed"
        case .notDetected:
            str = "notDetected"
        case .loadable:
            str = "loadable"
        case .unsupported:
            str = "unsupported"
        case .undetectable:
            str = "undetectable"
        @unknown default:
            str = "undetectable"
        }

        return str
    }

    func setWalletConnectV2SupportChainInfos(_ json: String) {
        let chainInfos = JSON(parseJSON: json).arrayValue.map {
            $0["chain_id"].intValue
        }.compactMap {
            ParticleNetwork.searchChainInfo(by: $0)
        }
        ParticleConnect.setWalletConnectV2SupportChainInfos(chainInfos)
    }
}

// MARK: - Particle AA

extension UnityManager {
    func particleAAInitialize(_ json: String) {
        let data = JSON(parseJSON: json)
        
        let dappAppKeysDict = data["dapp_api_keys"].dictionaryValue
        var dappAppKeys: [Int: String] = [:]
        
        for (key, value) in dappAppKeysDict {
            if let chainId = Int(key) {
                dappAppKeys[chainId] = value.stringValue
            }
        }
        
        BiconomyService.initialize(dappApiKeys: dappAppKeys)
        ParticleNetwork.setBiconomyService(biconomy)
    }
    
    func enableAAMode() {
        biconomy.enableBiconomyMode()
    }
    
    func disableAAMode() {
        biconomy.disableBiconomyMode()
    }
    
    func isAAModeEnable() -> Bool {
        return biconomy.isBiconomyModeEnable()
    }
    
    func isDeploy(_ json: String) {
        let eoaAddress = json
        subscribeAndCallback(observable: biconomy.isDeploy(eoaAddress: eoaAddress), unityName: UnityManager.aaSystemName)
    }
    
    func rpcGetFeeQuotes(_ json: String) {
        let data = JSON(parseJSON: json)
        let eoaAddress = data["eoa_address"].stringValue
        let transactions = data["transactions"].arrayValue.map {
            $0.stringValue
        }
               
        subscribeAndCallback(observable: biconomy.rpcGetFeeQuotes(eoaAddress: eoaAddress, transactions: transactions), unityName: UnityManager.aaSystemName)
    }
    
    func isSupportChainInfo(_ json: String) -> Bool {
        let data = JSON(parseJSON: json)
        let chainId = data["chain_id"].intValue
        guard let chainInfo = ParticleNetwork.searchChainInfo(by: chainId) else {
            return false
        }
        let result = biconomy.isSupportChainInfo(chainInfo)
        return result
    }
}

// MARK: - Particle Auth Core

extension UnityManager {
    func authCoreInitialize() {
#if canImport(ParticleAuthCore)
        ConnectManager.setMoreAdapters([AuthCoreAdapter()])
#endif
    }
    
    func authCoreConnect(_ json: String) {
#if canImport(ParticleAuthCore)
        let jwt = json
        let observable = Single<Void>.fromAsync { try await self.auth.connect(jwt: jwt) }.map { userInfo in
            
            let userInfoJsonString = userInfo.jsonStringFullSnake()
            let newUserInfo = JSON(parseJSON: userInfoJsonString)
            return newUserInfo
        }
        
        subscribeAndCallback(observable: observable, unityName: UnityManager.authCoreSystemName, methodName: "connect")
        
#endif
    }
    
    func authCoreDisconnect() {
#if canImport(ParticleAuthCore)
        let observable = Single<Void>.fromAsync { try await self.auth.disconnect() }
        
        subscribeAndCallback(observable: observable, unityName: UnityManager.authCoreSystemName, methodName: "disconnect")
        
#endif
    }
    
    func authCoreIsConnected() {
#if canImport(ParticleAuthCore)
        let observable = Single<Void>.fromAsync { try await self.auth.isConnected() }
        
        subscribeAndCallback(observable: observable, unityName: UnityManager.authCoreSystemName, methodName: "isConnected")
        
#endif
    }
    
    func authCoreGetUserInfo() -> String {
#if canImport(ParticleAuthCore)
        guard let userInfo = auth.getUserInfo() else {
            return ""
        }
        
        let userInfoJsonString = userInfo.jsonStringFullSnake()
        let newUserInfo = JSON(parseJSON: userInfoJsonString)

        let data = try! JSONEncoder().encode(newUserInfo)
        let json = String(data: data, encoding: .utf8)
        return json ?? ""
#endif
    }
    
    func authCoreSwitchChain(_ json: String) {
#if canImport(ParticleAuthCore)
        let data = JSON(parseJSON: json)

        let chainId = data["chain_id"].intValue
        guard let chainInfo = ParticleNetwork.searchChainInfo(by: chainId) else {
            return
        }
                
        let observable = Single<Bool>.fromAsync { try await self.auth.switchChain(chainInfo: chainInfo) }.catch { _ in
            .just(false)
        }
        
        subscribeAndCallback(observable: observable, unityName: UnityManager.authCoreSystemName, methodName: "switchChain")
        
#endif
    }
    
    func authCoreChangeMasterPassword() {
#if canImport(ParticleAuthCore)
        let observable = Single<Bool>.fromAsync { try await self.auth.changeMasterPassword() }
        
        subscribeAndCallback(observable: observable, unityName: UnityManager.authCoreSystemName, methodName: "changeMasterPassword")
#endif
    }
    
    func authCoreHasMasterPassword() -> Bool {
#if canImport(ParticleAuthCore)
        do {
            let result = try auth.hasMasterPassword()
            return result
        } catch {
            print(error)
            return false
        }
#else
        return false
#endif
    }
    
    func authCoreHasPaymentPassword() -> Bool {
#if canImport(ParticleAuthCore)
        
        do {
            let result = try auth.hasPaymentPassword()
            return result
        } catch {
            print(error)
            return false
        }
#else
        return false
#endif
    }
    
    func authCoreOpenAccountAndSecurity() {
#if canImport(ParticleAuthCore)
        let observable = Single<Void>.fromAsync { try self.auth.openAccountAndSecurity() }.map {
            ""
        }
        
        subscribeAndCallback(observable: observable, unityName: UnityManager.authCoreSystemName, methodName: "openAccountAndSecurity")
#endif
    }
    
    func authCoreOpenWebWallet(_ json: String) {
#if canImport(ParticleAuthCore)
        auth.openWebWallet(styleJsonString: json)
#endif
    }
    
    func authCoreEvmGetAddress() -> String {
#if canImport(ParticleAuthCore)
        return auth.evm.getAddress() ?? ""
#else
        return ""
#endif
    }
    
    func authCoreEvmPersonalSign(_ json: String) {
#if canImport(ParticleAuthCore)
        let observable = Single<Void>.fromAsync { try await self.auth.evm.personalSign(json) }
        
        subscribeAndCallback(observable: observable, unityName: UnityManager.authCoreSystemName, methodName: "evmPersonalSign")
#endif
    }
    
    func authCoreEvmPersonalSignUnique(_ json: String) {
#if canImport(ParticleAuthCore)
        let observable = Single<Void>.fromAsync { try await self.auth.evm.personalSignUnique(json) }
        
        subscribeAndCallback(observable: observable, unityName: UnityManager.authCoreSystemName, methodName: "evmPersonalSign")
#endif
    }
    
    func authCoreEvmSignTypedData(_ json: String) {
#if canImport(ParticleAuthCore)
        let observable = Single<Void>.fromAsync { try await self.auth.evm.signTypedData(json) }
        
        subscribeAndCallback(observable: observable, unityName: UnityManager.authCoreSystemName, methodName: "evmSignTypedData")
#endif
    }
    
    func authCoreEvmSignTypedDataUnique(_ json: String) {
#if canImport(ParticleAuthCore)
        let observable = Single<Void>.fromAsync { try await self.auth.evm.signTypedDataUnique(json) }
        
        subscribeAndCallback(observable: observable, unityName: UnityManager.authCoreSystemName, methodName: "evmSignTypedDataUnique")
#endif
    }
    
    func authCoreEvmSendTransaction(_ json: String) {
#if canImport(ParticleAuthCore)
        let data = JSON(parseJSON: json)
        let transaction = data["transaction"].stringValue
        let mode = data["fee_mode"]["option"].stringValue
        var feeMode: Biconomy.FeeMode = .native
        if mode == "native" {
            feeMode = .native
        } else if mode == "gasless" {
            feeMode = .gasless
        } else if mode == "token" {
            let feeQuoteJson = JSON(data["fee_mode"]["fee_quote"].dictionaryValue)
            let tokenPaymasterAddress = data["fee_mode"]["token_paymaster_address"].stringValue
            let feeQuote = Biconomy.FeeQuote(json: feeQuoteJson, tokenPaymasterAddress: tokenPaymasterAddress)

            feeMode = .token(feeQuote)
        }
                
        let wholeFeeQuoteData = (try? data["fee_mode"]["whole_fee_quote"].rawData()) ?? Data()
        let wholeFeeQuote = try? JSONDecoder().decode(Biconomy.WholeFeeQuote.self, from: wholeFeeQuoteData)
                
        let biconomy = ParticleNetwork.getBiconomyService()
        var sendObservable: Single<String>
        if biconomy != nil, biconomy!.isBiconomyModeEnable() {
            sendObservable = biconomy!.quickSendTransactions([transaction], feeMode: feeMode, messageSigner: self, wholeFeeQuote: wholeFeeQuote)
        } else {
            sendObservable = Single<Void>.fromAsync { try await self.auth.evm.sendTransaction(transaction, feeMode: feeMode) }
        }
        
        latestWalletType = .authCore
        latestPublicAddress = auth.evm.getAddress()
        
        subscribeAndCallback(observable: sendObservable, unityName: UnityManager.authCoreSystemName, methodName: "evmPersonalSign")
      
#endif
    }
    
    func authCoreEvmBatchSendTransactions(_ json: String) {
#if canImport(ParticleAuthCore)
        let data = JSON(parseJSON: json)
        let transactions = data["transactions"].arrayValue.map {
            $0.stringValue
        }
        let mode = data["fee_mode"]["option"].stringValue
        var feeMode: Biconomy.FeeMode = .native
        if mode == "native" {
            feeMode = .native
        } else if mode == "gasless" {
            feeMode = .gasless
        } else if mode == "token" {
            let feeQuoteJson = JSON(data["fee_mode"]["fee_quote"].dictionaryValue)
            let tokenPaymasterAddress = data["fee_mode"]["token_paymaster_address"].stringValue
            let feeQuote = Biconomy.FeeQuote(json: feeQuoteJson, tokenPaymasterAddress: tokenPaymasterAddress)

            feeMode = .token(feeQuote)
        }
                
        let wholeFeeQuoteData = (try? data["fee_mode"]["whole_fee_quote"].rawData()) ?? Data()
        let wholeFeeQuote = try? JSONDecoder().decode(Biconomy.WholeFeeQuote.self, from: wholeFeeQuoteData)
                
        guard let biconomy = ParticleNetwork.getBiconomyService() else {
            print("biconomy is not init")
            return
        }
                
        guard biconomy.isBiconomyModeEnable() else {
            print("biconomy is not enable")
            return
        }
        
        latestPublicAddress = auth.evm.getAddress()
        latestWalletType = .authCore
        
        let sendObservable: Single<String> = biconomy.quickSendTransactions(transactions, feeMode: feeMode, messageSigner: self, wholeFeeQuote: wholeFeeQuote)
                
        subscribeAndCallback(observable: sendObservable, unityName: UnityManager.authCoreSystemName, methodName: "batchSendTransactions")
#endif
    }
    
    func authCoreSolanaGetAddress() -> String {
#if canImport(ParticleAuthCore)
        return auth.solana.getAddress() ?? ""
#else
        return ""
#endif
    }
    
    func authCoreSolanaSignMessage(_ message: String) {
#if canImport(ParticleAuthCore)
        let serializedMessage = Base58.encode(message.data(using: .utf8)!)
        
        let observable = Single<Void>.fromAsync { try await self.auth.solana.signMessage(serializedMessage) }
    
        subscribeAndCallback(observable: observable, unityName: UnityManager.authCoreSystemName, methodName: "solanaSignMessage")
#endif
    }
    
    func authCoreSolanaSignTransaction(_ json: String) {
#if canImport(ParticleAuthCore)
        
        let observable = Single<Void>.fromAsync { try await self.auth.solana.signTransaction(json) }
        subscribeAndCallback(observable: observable, unityName: UnityManager.authCoreSystemName, methodName: "solanaSignTransaction")
#endif
    }
    
    func authCoreSolanaSignAllTransactions(_ json: String) {
#if canImport(ParticleAuthCore)
        
        let transactions = JSON(parseJSON: json).arrayValue.map { $0.stringValue }
        let observable = Single<Void>.fromAsync { try await self.auth.solana.signAllTransactions(transactions) }
        
        subscribeAndCallback(observable: observable, unityName: UnityManager.authCoreSystemName, methodName: "solanaSignAllTransactions")
        
#endif
    }
    
    func authCoreSolanaSignAndSendTransaction(_ json: String) {
#if canImport(ParticleAuthCore)
        let transaction = json
        
        let observable = Single<Void>.fromAsync { try await self.auth.solana.signAndSendTransaction(transaction) }
        subscribeAndCallback(observable: observable, unityName: UnityManager.authCoreSystemName, methodName: "solanaSignAndSendTransaction")
#endif
    }
}

// MARK: - Help methods

extension UnityManager {
    func callBackMessage(_ message: String, unityName: String, methodName: String = #function) {
        var methodName = methodName.replacingOccurrences(of: "\\([\\w\\s:]*\\)", with: "", options: .regularExpression)
        methodName = methodName.prefix(1).uppercased() + methodName.dropFirst() + "CallBack"
        ufw?.sendMessageToGO(withName: unityName, functionName: methodName, message: message)
    }
}

extension Dictionary {
    /// - Parameter prettify: set true to prettify string (default is false).
    /// - Returns: optional JSON String (if applicable).
    func jsonString(prettify: Bool = false) -> String? {
        guard JSONSerialization.isValidJSONObject(self) else { return nil }
        let options = (prettify == true) ? JSONSerialization.WritingOptions.prettyPrinted : JSONSerialization.WritingOptions()
        guard let jsonData = try? JSONSerialization.data(withJSONObject: self, options: options) else { return nil }
        return String(data: jsonData, encoding: .utf8)
    }
}

extension UnityManager {
    private func ResponseFromError(_ error: Error) -> UnityResponseError {
        if let responseError = error as? ParticleNetwork.ResponseError {
            return UnityResponseError(code: responseError.code, message: responseError.message ?? "", data: responseError.data)
        } else if let error = error as? ConnectError {
            return UnityResponseError(code: error.code, message: error.message!, data: nil)
        } else {
            return UnityResponseError(code: nil, message: String(describing: error), data: nil)
        }
    }
    
    private func map2WalletType(from string: String) -> WalletType? {
        /* Define in unity
         Particle,
         AuthCore,
         EvmPrivateKey,
         SolanaPrivateKey,
         MetaMask,
         Rainbow,
         Trust,
         ImToken,
         BitKeep,
         WalletConnect,
         Phantom,
         */
        let str = string.lowercased()
        var walletType: WalletType?
        if str == "particle" {
            walletType = .particle
        } else if str == "authcore" {
            walletType = .authCore
        } else if str == "evmprivatekey" {
            walletType = .evmPrivateKey
        } else if str == "solanaprivatekey" {
            walletType = .solanaPrivateKey
        } else if str == "metamask" {
            walletType = .metaMask
        } else if str == "rainbow" {
            walletType = .rainbow
        } else if str == "trust" {
            walletType = .trust
        } else if str == "imtoken" {
            walletType = .imtoken
        } else if str == "bitkeep" {
            walletType = .bitkeep
        } else if str == "walletconnect" {
            walletType = .walletConnect
        } else if str == "phantom" {
            walletType = .phantom
        } else if str == "zerion" {
            walletType = .zerion
        } else if str == "math" {
            walletType = .math
        } else if str == "omni" {
            walletType = .omni
        } else if str == "zengo" {
            walletType = .zengo
        } else if str == "alpha" {
            walletType = .alpha
        } else if str == "bitpie" {
            walletType = .bitpie
        } else if str == "inch1" {
            walletType = .inch1
        } else {
            walletType = nil
        }
        
        return walletType
    }
    
    private func map2ConnectAdapter(from walletType: WalletType) -> ConnectAdapter? {
        let adapters = ParticleConnect.getAllAdapters().filter {
            $0.walletType == walletType
        }
        let adapter = adapters.first
        return adapter
    }
}

extension UnityManager: MessageSigner {
    public func signMessage(_ message: String) -> RxSwift.Single<String> {
        guard let walletType = latestWalletType else {
            print("walletType is nil")
            return .error(ParticleNetwork.ResponseError(code: nil, message: "walletType is nil"))
        }
        
        if walletType == .particle {
            return ParticleAuthService.signMessage(message)
        } else if walletType == .authCore {
#if canImport(ParticleAuthCore)
            return Single<String>.fromAsync {
                try await self.auth.evm.personalSign(message)
            }
#else
            print("authCore framework is not added")
            return .error(ParticleNetwork.ResponseError(code: nil, message: "authCore framework is not added"))
#endif
        } else {
            guard let adapter = map2ConnectAdapter(from: walletType) else {
                print("adapter for \(walletType) is not init")
                return .error(ParticleNetwork.ResponseError(code: nil, message: "adapter for \(walletType) is not init"))
            }
        
            return adapter.signMessage(publicAddress: getEoaAddress(), message: message)
        }
    }
    
    public func getEoaAddress() -> String {
        return latestPublicAddress ?? ""
    }
}

struct UnityResponseError: Codable {
    let code: Int?
    let message: String?
    let data: String?
}

struct UnityStatusModel<T: Codable>: Codable {
    let status: Bool
    let data: T?
}

struct UnityLoginListModel: Codable {
    let walletType: String
    let account: Account?
}

struct UnityConnectLoginResult: Codable {
    let message: String
    let signature: String
}

extension UnityManager {
    private func subscribeAndCallback<T: Codable>(observable: Single<T>, unityName: String, methodName: String = #function) {
        observable.subscribe { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .failure(let error):
                let response = self.ResponseFromError(error)
                let statusModel = UnityStatusModel(status: false, data: response)
                let data = try! JSONEncoder().encode(statusModel)
                guard let json = String(data: data, encoding: .utf8) else { return }
                self.callBackMessage(json, unityName: unityName, methodName: methodName)
            case .success(let signedMessage):
                let statusModel = UnityStatusModel(status: true, data: signedMessage)
                let data = try! JSONEncoder().encode(statusModel)
                guard let json = String(data: data, encoding: .utf8) else { return }
                self.callBackMessage(json, unityName: unityName, methodName: methodName)
            }
        }.disposed(by: bag)
    }
}

extension Single {
    static func fromAsync<T>(_ fn: @escaping () async throws -> T) -> Single<T> {
        .create { observer in
            let task = Task {
                do { try await observer(.success(fn())) }
                catch { observer(.failure(error)) }
            }
            return Disposables.create { task.cancel() }
        }.observe(on: MainScheduler.instance)
    }
}
