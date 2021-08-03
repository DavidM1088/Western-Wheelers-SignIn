import Foundation
import os.log
import SystemConfiguration

class NetworkReachability: ObservableObject {
    @Published private(set) var reachable: Bool = false
    private let reachability = SCNetworkReachabilityCreateWithName(nil, "www.google.com")

    init() {
        self.reachable = checkConnection()
    }

    private func isNetworkReachable(with flags: SCNetworkReachabilityFlags) -> Bool {
        let isReachable = flags.contains(.reachable)
        let connectionRequired = flags.contains(.connectionRequired)
        let canConnectAutomatically = flags.contains(.connectionOnDemand) || flags.contains(.connectionOnTraffic)
        let canConnectWithoutIntervention = canConnectAutomatically && !flags.contains(.interventionRequired)
        return isReachable && (!connectionRequired || canConnectWithoutIntervention)
    }

    func checkConnection() -> Bool {
        var flags = SCNetworkReachabilityFlags()
        SCNetworkReachabilityGetFlags(reachability!, &flags)
        return isNetworkReachable(with: flags)
    }
}

class WAApi : ObservableObject {

    //static private var shared:WAApi! = nil
    private var token: String! = nil
    private var accountId:String! = nil

    var apiCallNum = 0
    
    enum ApiType {
        case LoadMembers, AuthenticateUser, None
    }
        
    func apiKey(key:String) -> String {
        let path = Bundle.main.path(forResource: "api_keys.txt", ofType: nil)!
        do {
            let fileData = try String(contentsOfFile: path, encoding: String.Encoding.utf8)
            let dict = try JSONSerialization.jsonObject(with: fileData.data(using: .utf8)!, options: []) as? [String:String]
            return dict?[key] ?? ""
        } catch {
            return ""
        }
    }
            
    func runTask(req:URLRequest) -> Data? {
        let semaphore: DispatchSemaphore = DispatchSemaphore(value: 0)
        var result:Data? = nil
        
        let task = URLSession.shared.dataTask(with: req) { data, response, error in
            if let error = error {
                Messages.instance.reportError(context: "WAApi", msg: error.localizedDescription)
            }
            else {
                if let response = response as? HTTPURLResponse {
                    if response.statusCode != 200 && response.statusCode != 501 {
                        Messages.instance.reportError(context: "WAApi", msg: "http status \(response.statusCode)")
                    }
                    else {
                        if let data = data {
                            result = data
                        }
                        else {
                            Messages.instance.reportError(context: "WAApi", msg: "no data in response")
                        }
                    }
                }
            }
            semaphore.signal()
        }
        task.resume()
        semaphore.wait()
        return result
    }
    
    func apiCall(url:String, username:String?, password:String?,
                 completion: @escaping (Data) -> (), fail: @escaping (String) -> ()) {
        apiCallNum += 1

        var user = ""
        var pwd = ""
        if let uname = username {
            user = uname
            pwd = password!
        }
        else {
            user = apiKey(key: "WA_username")
            pwd = apiKey(key: "WA_pwd")
            pwd = pwd+pwd+pwd
        }
        
        //get API token
        let tokenUrl = "https://oauth.wildapricot.org/auth/token"
        var tokenRequest = URLRequest(url: URL(string: tokenUrl)!)

        let wwAuth = "Basic aXNleTBqYWZwOTplYzMxdDN1Zjl1dWFha2h6cXB3NXFsYWF1ZTFnaTY="
        tokenRequest.setValue(wwAuth, forHTTPHeaderField: "Authorization")
        tokenRequest.httpMethod = "POST"
        let postString = "grant_type=password&username=\(user)&password=\(pwd)&scope=auto"
        tokenRequest.httpBody = postString.data(using: String.Encoding.utf8);
        
        let data = self.runTask(req: tokenRequest)
        
        guard let tokenData = data else {
            let msg = "did not receive API token"
            Messages.instance.reportError(context: "WAApi", msg: msg)
            fail(msg)
            return
        }
        var token:String?
        var accountId:String?
        
        do {
            let json = try JSONSerialization.jsonObject(with: tokenData, options: []) //as? [String: Any]
            if let data = json as? [String: Any] {
                if let tk = data["access_token"] as? String {
                    token = tk
                }
                if let perms = data["Permissions"] as? [[String: Any]] {
                    accountId = "\(perms[0]["AccountId"] as! NSNumber)"
                }
            }
        }
        catch {
            Messages.instance.reportError(context: "WAApi", msg: "cannot parse token data")
        }
        
        //make the API call with the token
        let components = url.components(separatedBy: "$id")
        let apiUrl = components[0]+accountId!+components[1]
        var request = URLRequest(url: URL(string: apiUrl)!)
        let tokenAuth = "Bearer \(token ?? "")"
        request.setValue(tokenAuth, forHTTPHeaderField: "Authorization")
        let apiData = self.runTask(req: request)
        if let data = apiData {
            completion(data)
        }
        else {
            Messages.instance.reportError(context: "WAApi", msg: "no data returned")
        }
    }
}


