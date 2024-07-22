/*******************************************************************************
 * Copyright (c) 2021  Carnegie Mellon University
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 *******************************************************************************/

import UIKit
import Foundation
import CommonCrypto
import ZIPFoundation
import SwiftUI

//Get document directory
func getDocumentsDirectory() -> URL{
    guard let path = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
        fatalError("Could not find the document directory.")
    }
    return path
}

//Since there is no Hash file in the app, save it for the first time
func saveHashTextFile(fileName:String,content:String){
    let fileURL=getDocumentsDirectory().appendingPathComponent(fileName)
    
    //Check file existence
    if FileManager.default.fileExists(atPath: fileURL.path){
        //do nothing
    }else{//If the file does not exist, create a new one
        do{
            try content.write(to:fileURL, atomically: true, encoding: .utf8)
            NSLog("Saving of Hash file is completed:\(fileURL.path)")
        }catch{
            NSLog("Saving Hash file failed:\(error.localizedDescription)")
        }
    }
}


//Overwrite the existing Hash text file in the app
func overwriteHashTextFile(fileName:String,content:String){
    let fileURL=getDocumentsDirectory().appendingPathComponent(fileName)
    
    //Check file existence
    if FileManager.default.fileExists(atPath: fileURL.path){
        do{
            try content.write(to:fileURL, atomically: true, encoding: .utf8)
            NSLog("Hash file overwriting completed:\(fileURL.path)")
        }catch{
            NSLog("Hash file overwriting failed:\(error.localizedDescription)")
        }
        
    }
}
//Check Server
func checkServerStatus(url: URL, completion: @escaping (Bool) -> Void) {
    let task = URLSession.shared.dataTask(with: url) { data, response, error in
        if let error = error {
            NSLog("Error: \(error)")
            completion(false)
            return
        }
        
        if let httpResponse = response as? HTTPURLResponse {
            if httpResponse.statusCode == 200 {
                completion(true)
            } else {
                NSLog("ServerError: \(httpResponse.statusCode)")
                completion(false)
            }
        } else {
            NSLog("invalid response")
            completion(false)
        }
    }
    task.resume()
}


//resource download
class ResourceDownload {
    var isStartDownloadedOnSuitcaseConnected:Bool = true//First download When Suitcase is Connected
    var isStartDownloadedOnSuitcaseUnconnected:Bool = true//First download When Suitcase is not Connected
    var speakCount : Int = 0
    var m5HashValue:String = ""//hash Value
    //Download Resources When Suitcase is Connected. call only once when app start.
    func startDownloadResourceOnSuitcaseConnected(modelData: CaBotAppModel){
        if isStartDownloadedOnSuitcaseConnected{
            isStartDownloadedOnSuitcaseConnected = false
            self.startFileDownload(modelData: modelData)
        }
    }
    //Download Resources When Suitcase is not Connected. call only once when app start.
    func startDownloadResourceOnSuitcaseUnconnected(modelData: CaBotAppModel){
        if isStartDownloadedOnSuitcaseUnconnected{
            isStartDownloadedOnSuitcaseUnconnected = false
            self.startFileDownload(modelData: modelData)
        }
    }
    // Call the file download method when the app starts
    public func startFileDownload(modelData: CaBotAppModel) {
        let hashFileName = "hashFile.txt"
        self.downloadHashFile(modelData: modelData) { result in
            switch result {
            case .success(let data):
                guard let content = String(data: data, encoding: .utf8) else {
                    return
                }
                let lines = content.split(separator: "\n")
                for line in lines {
                    let components = line.split(separator: " ")
                    guard components.count == 1 else {
                        NSLog("Component count is not 1")
                        return
                    }
                    self.m5HashValue = String(components[0])
                    let fileURL = getDocumentsDirectory().appendingPathComponent(hashFileName)
                    if FileManager.default.fileExists(atPath: fileURL.path) {
                        if let hashFileContent = self.readHashTextFile(fileName: hashFileName) {
                            NSLog("File content:\(hashFileContent)")
                            //Hash value is the same
                            if hashFileContent == self.m5HashValue {
                                //Determine whether the server can be accessed
                                if let url = URL(string: "http://\(modelData.getCurrentAddress()):9090/map/app-resource.zip") {
                                    checkServerStatus(url: url) { isOnline in
                                        if isOnline {
                                            DispatchQueue.main.async{
                                                modelData.resourceManager.updateResources()
                                                if(modelData.resourceManager.resources.count>0){
                                                    modelData.resource = modelData.resourceManager.resources[0]
                                                }
                                            }
                                        } else {
                                            NSLog("The server is down")
                                        }
                                    }
                                }
                                
                                NSLog("MD5 hash matched: \(self.m5HashValue)")
                            } else {
                                NSLog("MD5 hashes don't match: \(self.m5HashValue)")
                                overwriteHashTextFile(fileName: hashFileName, content: self.m5HashValue)
                                self.downloadResouceFile(modelData: modelData){ result in
                                    switch result {
                                    case .success(let data):
                                        NSLog("Download succeeded. Data received: \(data)")
                                    case .failure(let error):
                                        DispatchQueue.main.async{
                                            self.speakCount = 0
                                            self.SpeechErrorMessage(modelData: modelData)
                                            self.deleteHashFile()
                                        }
                                        NSLog("Download failed with error: \(error.localizedDescription)")
                                    }
                                }
                            }
                        } else {
                            NSLog("Failed to get Hash value")
                        }
                    } else {
                        saveHashTextFile(fileName: hashFileName, content: self.m5HashValue)
                        self.downloadResouceFile(modelData: modelData){ result in
                            switch result {
                            case .success(let data):
                                NSLog("Download succeeded. Data received: \(data)")
                            case .failure(let error):
                                DispatchQueue.main.async{
                                    self.speakCount = 0
                                    self.SpeechErrorMessage(modelData: modelData)
                                    self.deleteHashFile()
                                }
                                NSLog("Download failed with error: \(error.localizedDescription)")
                            }
                        }
                    }
                }
            case .failure(let error):
                DispatchQueue.main.async{
                    self.speakCount = 0
                    self.SpeechErrorMessage(modelData: modelData)
                    self.deleteHashFile()
                }
                NSLog("Failed to download hash file：\(error)")
            }
        }
    }//startFileDownload end
    
    //Get hash value
    func downloadHashFile(retries: Int = 3,timeout: TimeInterval = 2,modelData: CaBotAppModel, completion: @escaping (Result<Data, Error>) -> Void) {
        
        NSLog("Start obtaining hash value. \(modelData.getCurrentAddress())")
        if let md5FileURL = URL(string: "http://\(modelData.getCurrentAddress()):9090/map/app-resource-md5"){
            
            // Configure the URLSession with timeout
            let configuration = URLSessionConfiguration.default
            configuration.timeoutIntervalForRequest = timeout
            let session = URLSession(configuration: configuration)
            
            let task = session.dataTask(with: md5FileURL) { (data, response, error) in
                
                if let error = error  {
                    if (error as NSError).code == NSURLErrorCannotConnectToHost {
                        NSLog("Failed to connect to host: \(md5FileURL). The server might not be running.")
                        let connectionError = NSError(domain: "FileDownloader", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to connect to host: \(md5FileURL). The server might not be running."])
                        completion(.failure(connectionError))
                    }else{
                        if retries > 0{
                            NSLog("Download failed. Attempt to retry. Remaining number of retries: \(retries)")
                            self.downloadHashFile( retries: retries - 1,timeout: timeout,modelData: modelData, completion: completion)
                        }else{
                            completion(.failure(error))
                        }
                    }
                    
                    return
                }
                
                guard let data = data else {
                    let error = NSError(domain: "FileDownloader", code: -1, userInfo: [NSLocalizedDescriptionKey: "No data received"])
                    if retries > 0 {
                        NSLog("No data received. Attempt to retry. Remaining number of retries: \(retries - 1)")
                        DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                            self.downloadHashFile(retries: retries - 1, timeout: timeout, modelData: modelData, completion: completion)
                        }
                    } else {
                        completion(.failure(error))
                    }
                    return
                }
                completion(.success(data))
            }
            task.resume()
        }
        
    }
    
    //Read Hash text file in app
    func readHashTextFile(fileName:String) -> String?{
        
        let fileURL=getDocumentsDirectory().appendingPathComponent(fileName)
        do{
            let content = try String(contentsOf:fileURL,encoding: .utf8)
            NSLog("Read Hash file")
            
            //self.downloadFailed = false
            return content
            
        }catch{
            NSLog("Reading Hash file failed:\(error.localizedDescription)")
            return nil
        }
    }
    
    
    func downloadResouceFile(retries: Int = 3,timeout: TimeInterval = 2,modelData: CaBotAppModel, completion: @escaping (Result<Data, Error>) -> Void) {
        
        NSLog("Start obtaining Resouce. \(modelData.getCurrentAddress())")
        if let resouceFileURL = URL(string: "http://\(modelData.getCurrentAddress()):9090/map/app-resource.zip"){
            
            let configuration = URLSessionConfiguration.default
            configuration.timeoutIntervalForRequest = timeout
            let session = URLSession(configuration: configuration)
            
            let task = session.dataTask(with: resouceFileURL) { (data, response, error) in
                if let error = error {
                    if retries > 0 {
                        NSLog("Download failed. Attempt to retry. Remaining number of retries: \(retries)")
                        self.downloadResouceFile(retries: retries - 1, timeout: timeout, modelData: modelData, completion: completion)
                    } else {
                        completion(.failure(error))
                    }
                    return
                }
                
                guard let data = data else {
                    let error = NSError(domain: "FileDownloader", code: -1, userInfo: [NSLocalizedDescriptionKey: "No data received"])
                    completion(.failure(error))
                    return
                }
                
                // Save the downloaded data to a file in Documents directory
                let documentsURL = getDocumentsDirectory()
                
                
                let fileURL = documentsURL.appendingPathComponent("app-resource.zip")
                
                // Delete existing file if present
                do {
                    if FileManager.default.fileExists(atPath: fileURL.path) {
                        try FileManager.default.removeItem(at: fileURL)
                        NSLog("Deleted existing file at \(fileURL)")
                    }
                } catch {
                    NSLog("Failed to delete existing file: \(error.localizedDescription)")
                    completion(.failure(error))
                    return
                }
                // Save new file
                do {
                    try data.write(to: fileURL)
                    NSLog("File saved successfully at \(fileURL)")
                    self.unzipFile(at: fileURL,to: documentsURL,modelData: modelData)
                } catch {
                    NSLog("Failed to save file: \(error.localizedDescription)")
                    completion(.failure(error))
                    return
                }
                
                completion(.success(data))
            }
            
            task.resume()
        }
    }
    
    
    //Process of unzipping a ZIP resource file
    func unzipFile(at sourceURL:URL,to destinaltionURL:URL,modelData: CaBotAppModel){
        let fileManager = FileManager()
        let unzipFileName = "app-resource"//resource file name
        let unzipedFilePath = destinaltionURL.appendingPathComponent(unzipFileName)//Unzipped resource file URL
        do{
            //Delete previously unzipped files if they exist
            if FileManager.default.fileExists(atPath: unzipedFilePath.path) {
                try FileManager.default.removeItem(at: unzipedFilePath)
                NSLog("Existing unzipped files deleted\(unzipedFilePath)")
                
            }
            
            //Thawing process
            try fileManager.createDirectory(at: destinaltionURL, withIntermediateDirectories: true,attributes:nil)
            try fileManager.unzipItem(at: sourceURL, to: destinaltionURL)
            
            NSLog("Unzipping completed！\(destinaltionURL)")
            //Delete the ZIP file if it exists after unzipping it
            if FileManager.default.fileExists(atPath: sourceURL.path) {
                try FileManager.default.removeItem(at: sourceURL)
                NSLog("ZIP file deleted after unzipping")
            }
            
            DispatchQueue.main.async{
                modelData.resourceManager.updateResources()
                if(modelData.resourceManager.resources.count>0){
                    modelData.resource = modelData.resourceManager.resources[0]
                }
            }
        }catch{
            NSLog("An error occurred while unzipping！")
        }
    }
    
    func SpeechErrorMessage(modelData: CaBotAppModel)
    {
        DispatchQueue.main.async {
            let _ = modelData.resourceDownload.speakCount += 1
            //Read-aloud is only once
            if modelData.resourceDownload.speakCount == 1
            {
                NSLog("Error message read out loud")
                let message = CustomLocalizedString("Retry Alert", lang: modelData.resourceLang)
                modelData.speak(message) {}
                
            }
        }
    }
    
    //Delete hash files on retry
    func deleteHashFile(){
        let hashFileName = "hashFile.txt"//Hash file name saved within the app
        let hashFileURL = getDocumentsDirectory().appendingPathComponent(hashFileName)
        //Delete if file already exists
        if FileManager.default.fileExists(atPath: hashFileURL.path) {
            do{
                NSLog("Hash file deletion completed:\(hashFileURL.path)")
                try FileManager.default.removeItem(at: hashFileURL)
            }catch{
                NSLog("Hash file deletion failed:\(error.localizedDescription)")
            }
            
        }
        let resourceFileName = "app-resource"//Resource file name saved within the app
        let resourceFileURL = getDocumentsDirectory().appendingPathComponent(resourceFileName)
        
        if FileManager.default.fileExists(atPath: resourceFileURL.path) {
            do{
                NSLog("Resource file deletion completed:\(resourceFileURL.path)")
                try FileManager.default.removeItem(at: resourceFileURL)
            }catch{
                NSLog("Resource file deletion failed:\(error.localizedDescription)")
            }
            
        }
    }
    
}//Class Resource End


//Display error message and retry button when resource download fails
struct ResourceDownloadRetryUIView :View {
    @EnvironmentObject var modelData: CaBotAppModel
    var body: some View {
        
        if modelData.suitcaseConnected{
            let _ =   modelData.resourceDownload.startDownloadResourceOnSuitcaseConnected(modelData: modelData)
        }else{
            let _ =   modelData.resourceDownload.startDownloadResourceOnSuitcaseUnconnected(modelData: modelData)
        }
        
        //If ownload fails, an error message and retry will be displayed
        if modelData.resource == nil
        {
            Section(header:  Text(CustomLocalizedString("Resource Download", lang: modelData.resourceLang))){
                
                Text(CustomLocalizedString("Retry Alert", lang: modelData.resourceLang)).font(.body).foregroundColor(.red).lineLimit(1)
                
                Button(action: {
                    let _: () = modelData.resourceDownload.startFileDownload(modelData: modelData)
                },label: {
                    Text(CustomLocalizedString("Retry", lang: modelData.resourceLang)).foregroundColor(.blue)
                })
            }
        }
    }
}
