
import Foundation
import os.log

//TODO verify identity via ww sign in

class WAApi : ObservableObject {

    static private var shared:WAApi! = nil
    private var token: String! = nil
    private var accountId:String! = nil
    var apiCallNum = 0
    
    enum ApiType {
        case LoadMembers, None
    }
    
    static func instance() -> WAApi {
        
        if shared == nil {
            shared = WAApi()
        }
        return shared
    }
    
    init() {
        loadMembers()
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
        
    func parseMembers(jsonData: Any, raw: Data, apiType: ApiType, usrMsg:String, tellUsers:Bool) {
        var responseComplete = false
        var resultsUrl:String? = nil
        var memberList:[Rider] = []
        var cnt = 0
        
        if let contacts = try! JSONSerialization.jsonObject(with: raw, options: []) as? [String: Any] {
            for (key, val) in contacts {
                if key == "ResultUrl" {
                    resultsUrl = (val as! String)
                }
                if key == "State" {
                    responseComplete = (val as! String == "Complete")
                }
                if key == "Contacts" {
                    let members = val as! NSArray
                    for member in members {
                        let memberDict = member as! NSDictionary

                        if let val = memberDict["Status"]  {
                            //TODO check with Vito this is right selector
                            let active = val as! NSString == "Active"
                            if !active {
                                continue
                            }
                        }
                        else {
                            continue
                        }
                        //if
                        let name = memberDict["DisplayName"] as! String
                        let id = memberDict["Id"] as! Int
                        var homePhone = ""
                        var cellPhone = ""
                        var emergencyPhone = ""
                        var email = ""

                        let keys = memberDict["FieldValues"] as! NSArray
                        var c = 0
                        for k in keys {
                            let fields = k as! NSDictionary
                            let fieldName = fields["FieldName"]
                            let fieldValue = fields["Value"]
                            c = c+1
                            if fieldName as! String == "Home Phone" {
                                if let e = fieldValue as? String {
                                    homePhone = e
                                }
                            }
                            if fieldName as! String == "Cell Phone" {
                                if let e = fieldValue as? String {
                                    cellPhone = e
                                }
                            }
                            if fieldName as! String == "Emergency Phone" {
                                if let e = fieldValue as? String {
                                    emergencyPhone = e
                                }
                            }
                            if fieldName as! String == "e-Mail" {
                                if let e = fieldValue as? String {
                                    email = e
                                }
                            }

                        }
                        var phone = cellPhone
                        if phone == "" {
                            phone = homePhone
                        }
                        cnt += 1
                        memberList.append(Rider(id: String(id), name: name, phone: phone, emrg: emergencyPhone, email: email))
                    }
                }
            }
        }
        if memberList.count > 0 {
            ClubMembers.instance.updateList(updList: memberList)
            responseComplete = true
        }
        else {
            if responseComplete {
                //the first response says the query results are 'complete' so go fetch them now
                DispatchQueue.global(qos: .userInitiated).async {
                    //load the members from the result URL
                    self.apiCall(path: resultsUrl!, withToken: true, usrMsg: usrMsg, completion: self.parseMembers, apiType: apiType, tellUsers: tellUsers)
                }
            }
            else {
                DispatchQueue.global(qos: .userInitiated).async {
                    sleep(2)
                    self.apiCall(path: resultsUrl!, withToken: true, usrMsg: usrMsg, completion: self.parseMembers, apiType: apiType, tellUsers: tellUsers)

                }
            }
        }
    }
    
    func contactsQuery() {
        //let id = 11111
        var url = ""
        //url = "https://api.wildapricot.org/v2.1/accounts/41275/contactfields"
        //url = "https://api.wildapricot.org/v2/accounts/"+self.accountId+"/contacts"
        //url = "https://api.wildapricot.org/v2.1/Accounts/"+self.accountId+"/Contacts/?$async=false&$select='First name','Email','Organization'"
        
        //this is utterly broken, adding email drops the number of 'FieldValues' from 47 down to 5 but has no effect on fields outside the 'FieldValues' array
        //url = "https://api.wildapricot.org/v2.1/Accounts/"+self.accountId+"/Contacts/?$select='Email'"
        //adding 'async=false mysterioulsy means the status field of a member is never returned
        //url = "https://api.wildapricot.org/v2.1/Accounts/"+self.accountId+"/Contacts/?$async=false&$select='Email'"
        //url = "https://api.wildapricot.org/v2.2/Accounts/"+self.accountId+"/Contacts/?$select='Email','Status','Home%20Phone','Cell%20Phone','Emergency%20Phone'"
        //url = "https://api.wildapricot.org/v2.2/Accounts/"+self.accountId+"/Contacts/?$select='Email','Status','Home%20Phone','Cell%20Phone','Emergency%20Phone','Access%20to%20profile%20by%20others')"
        //setting fields to filter has unpredicatable effects on which fields actually get reutnred. So go for every field below, slower but safer
        url = "https://api.wildapricot.org/v2.2/Accounts/"+self.accountId+"/Contacts"
        apiCall(path: url, withToken: true, usrMsg: "", completion: parseMembers, apiType: ApiType.LoadMembers, tellUsers: true)
    }
    
    func parseAccessToken(json: Any, raw: Any, apiType: ApiType, usrMsg:String, tellUsers:Bool) {
        if let data = json as? [String: Any] {
            if let tk = data["access_token"] as? String {
                self.token = tk
            }
            if let perms = data["Permissions"] as? [[String: Any]] {
                self.accountId = "\(perms[0]["AccountId"] as! NSNumber)"
                self.contactsQuery()
            }
        }
    }
    
    func apiCall(path: String, withToken:Bool, usrMsg:String, completion: @escaping (Any, Data, ApiType, String, Bool) -> (), apiType: ApiType, tellUsers:Bool) {
        apiCallNum += 1
        if apiCallNum % 5 == 0 {
            print(apiCallNum, path)
        }
        let user = apiKey(key: "WA_username")
        //let user = "ios"
        //TODO private data is exposed, e.g. phone numbers, emails
        var pwd = apiKey(key: "WA_pwd")
        pwd = pwd+pwd+pwd

        let url = URL(string: path)
        var request = URLRequest(url: url!)

        if withToken {
            let tokenAuth = "Bearer \(token ?? "")"
            request.setValue(tokenAuth, forHTTPHeaderField: "Authorization")
        }
        else {
            //decoded client_id:client_secret  = isey0jafp9:ec31t3uf9uuaakhzqpw5qlaaue1gi6
            let wwAuth = "Basic aXNleTBqYWZwOTplYzMxdDN1Zjl1dWFha2h6cXB3NXFsYWF1ZTFnaTY="
            request.setValue(wwAuth, forHTTPHeaderField: "Authorization")
            request.httpMethod = "POST"
            let postString = "grant_type=password&username=\(user)&password=\(pwd)&scope=auto"
            request.httpBody = postString.data(using: String.Encoding.utf8);
        }
        
        let task = URLSession.shared.dataTask(with: request) { rawData, response, error in
            guard let rawData = rawData, let response = response as? HTTPURLResponse, error == nil else {
                Messages.instance.reportError(context: "WAApi", msg: usrMsg)
                return
            }

            guard (200 ... 299) ~= response.statusCode else {
                var msg = ""
                if response.statusCode == 400 {
                    msg = "Unexpected Wild Apricot HTTP Status:\(response.statusCode)"
                    Messages.instance.reportError(context: "WAApi", msg: msg)
                }
                Messages.instance.reportError(context: "WAApi", msg: "http \(response.statusCode) for \(path)")
                return
            }
            do {
                if let jsonData = try JSONSerialization.jsonObject(with: rawData, options: []) as? [String: Any] {
                    completion(jsonData, rawData, apiType, usrMsg, tellUsers)
                }
            } catch let error as NSError {
                let msg = "Cannot parse json"
                Messages.instance.reportError(context: "WAApi", msg: msg+" "+error.localizedDescription)
            }
        }
        task.resume()
    }

    func loadMembers () {
        let url = "https://oauth.wildapricot.org/auth/token"
        apiCall(path: url, withToken: false, usrMsg: "Authenticating Wild Apricot Account", completion: parseAccessToken, apiType: ApiType.LoadMembers, tellUsers: false)
    }    
}

