import Foundation
import GoogleAPIClientForREST

class RideTemplate: Identifiable, Hashable, Equatable {
    var id = UUID()
    var name: String = ""
    var ident: String = ""
    var isSelected: Bool = false

    init(name: String, ident: String){
        self.name = name
        self.ident = ident
    }
    
    static func == (lhs: RideTemplate, rhs: RideTemplate) -> Bool {
        return lhs.name == rhs.name
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }
    
    func requestLoad(ident:String) {
        GoogleDrive.instance.readSheet(id: self.ident, onCompleted:loadData(data:))
    }
    func loadData(data:[[String]]) {
        for row in data {
            if row.count > 1 && (row[1] == "TRUE" || row[1] == "FALSE") { // and row.count == 2
                let rider = Rider(name: row[0], homePhone: "", cell: "", emrg: "")
                if row[1] == "TRUE" {
                    rider.isSelected = true
                }
                //TODO read phone number from template OR
                //TODO use member list to get phone numbers
                SignedInRiders.instance.list.append(rider)
            }
            else {
                var note = ""
                for fld in row {
                    note += fld
                }
                SignedInRiders.instance.notes.append(note)
            }
        }
    }
}

class RideTemplates : ObservableObject {
    static let instance = RideTemplates() //called when shared first referenced
    @Published var templates:[RideTemplate] = []

    private init() {
    }
    
    func setSelected(name: String) {
        for t in templates {
            if t.name == name {
                t.isSelected = true
            }
            else {
                t.isSelected = false
            }
        }
        //force an array change to publish the row change
        templates.append(RideTemplate(name: "", ident: ""))
        templates.remove(at: templates.count-1)
    }
    
    func loadTemplates() {
        if templates.count == 0 {
            let drive = GoogleDrive.instance
            drive.listFilesInFolder(onCompleted: self.saveTemplates)
        }
    }
    
    func saveTemplates(files: GTLRDrive_FileList?, error: Error?) {
        if let filesList : GTLRDrive_FileList = files {
            if let filesShow : [GTLRDrive_File] = filesList.files {
                for file in filesShow {
                    if let name = file.name {
                        self.templates.append(RideTemplate(name: name, ident: file.identifier!))
                    }
                }
            }
        }
    }
}
