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

// Get document directory
func getDocumentsDirectory() -> URL {
    guard let path = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
        fatalError("Could not find the document directory.")
    }
    return path
}

// Resource download
class ResourceDownload {
    var isStartDownloadedOnSuitcaseConnected: Bool = true // First download When Suitcase is Connected
    var isStartDownloadedOnSuitcaseUnconnected: Bool = true // First download When Suitcase is not Connected
    var m5HashValue: String = "" // hash Value
    private let md5HashKey = "Md5HashKey"
    
    // Download Resources When Suitcase is Connected. Call only once when app start.
    func startDownloadResourceOnSuitcaseConnected(modelData: CaBotAppModel) {
        if isStartDownloadedOnSuitcaseConnected {
            isStartDownloadedOnSuitcaseConnected = false
            self.startFileDownload(modelData: modelData)
        }
    }
    
    // Download Resources When Suitcase is not Connected. Call only once when app start.
    func startDownloadResourceOnSuitcaseUnconnected(modelData: CaBotAppModel) {
        if isStartDownloadedOnSuitcaseUnconnected {
            isStartDownloadedOnSuitcaseUnconnected = false
            self.startFileDownload(modelData: modelData)
        }
    }
    
    // Call the file download method when the app starts
    func startFileDownload(modelData: CaBotAppModel) {
        let hashFileName = "app-resource-md5"
        let resourceFileName = "app-resource.zip"
        
        self.downloadFile(fileType: "HashFile", fileNmae: hashFileName, modelData: modelData) {result in
            switch result {
            case .success(let data):
                self.processHashFile(data, modelData: modelData, resourceFileName: resourceFileName)
            case .failure(let error):
                DispatchQueue.main.async {
                    self.SpeechErrorMessage(modelData: modelData)
                }
                NSLog("Failed to download hash file: \(error.localizedDescription)")
            }
        }
    }
    
    func processHashFile(_ data: Data, modelData: CaBotAppModel, resourceFileName: String) {
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
            let newHashValue = String(components[0])
            let storedHashValue = UserDefaults.standard.string(forKey: md5HashKey)
            
            if newHashValue == storedHashValue {
                DispatchQueue.main.async {
                    modelData.resourceManager.updateResources()
                    if modelData.resourceManager.resources.count > 0 {
                        modelData.resource = modelData.resourceManager.resources[0]
                    }
                }
                NSLog("MD5 hash matched: \(newHashValue) === \(String(describing: storedHashValue))")
            } else {
                handleHashMismatch(newHashValue: newHashValue, resourceFileName: resourceFileName, modelData: modelData)
            }
        }
    }
    
    func handleHashMismatch(newHashValue: String, resourceFileName: String, modelData: CaBotAppModel) {
        NSLog("MD5 hashes don't match: \(newHashValue)")
        deleteResourceFile()
        UserDefaults.standard.setValue(newHashValue, forKey: md5HashKey)
        downloadFile(fileType: "ResourceFile", fileNmae: resourceFileName, modelData: modelData) { result in
            switch result {
            case .success(let data):
                NSLog("Download succeeded. Data received: \(data)")
            case .failure(let error):
                DispatchQueue.main.async {
                    self.SpeechErrorMessage(modelData: modelData)
                }
                NSLog("Download failed with error: \(error.localizedDescription)")
            }
        }
    }
    
    func downloadFile(fileType: String, fileNmae: String, retries: Int = 3, timeout: TimeInterval = 2, modelData: CaBotAppModel, completion: @escaping (Result<Data, Error>) -> Void) {
        NSLog("Start obtaining hash value. \(modelData.getCurrentAddress())")
        if let filePath = URL(string: "http://\(modelData.getCurrentAddress()):9090/map/\(fileNmae)") {
            // Configure the URLSession with timeout
            let configuration = URLSessionConfiguration.default
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            configuration.timeoutIntervalForRequest = timeout
            let session = URLSession(configuration: configuration)
            let task = session.dataTask(with: filePath) { (data, response, error) in
                if let error = error {
                    if retries > 0 {
                        NSLog("Download failed. Attempt to retry. Remaining number of retries: \(retries)")
                        self.downloadFile(fileType: fileType, fileNmae: fileNmae, retries: retries - 1, timeout: timeout, modelData: modelData, completion: completion)
                    } else {
                        completion(.failure(error))
                    }
                    return
                }
                guard let data = data else {
                    _ = NSError(domain: "FileDownloader", code: -1, userInfo: [NSLocalizedDescriptionKey: "No data received"])
                    return
                }
                if fileType == "ResourceFile" {
                    // Save the downloaded data to a file in Documents directory
                    self.saveResourceFile(data: data, modelData: modelData, completion: completion)
                }
                completion(.success(data))
            }
            task.resume()
        }
    }
    
    private func saveResourceFile(data: Data, modelData: CaBotAppModel, completion: @escaping (Result<Data, Error>) -> Void) {
        let documentsURL = getDocumentsDirectory()
        let fileURL = documentsURL.appendingPathComponent("app-resource.zip")
        
        do {
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try FileManager.default.removeItem(at: fileURL)
                NSLog("Deleted existing file at \(fileURL)")
            }
            try data.write(to: fileURL)
            NSLog("File saved successfully at \(fileURL)")
            self.unzipFile(at: fileURL, to: documentsURL, modelData: modelData)
        } catch {
            NSLog("Failed to save file: \(error.localizedDescription)")
            completion(.failure(error))
            return
        }
        
        completion(.success(data))
    }
    
    // Process of unzipping a ZIP resource file
    func unzipFile(at sourceURL: URL, to destinaltionURL: URL, modelData: CaBotAppModel) {
        let fileManager = FileManager()
        let unzipFileName = "app-resource" // Resource file name
        let unzipedFilePath = destinaltionURL.appendingPathComponent(unzipFileName) // Unzipped resource file URL
        do {
            // Delete previously unzipped files if they exist
            if FileManager.default.fileExists(atPath: unzipedFilePath.path) {
                try FileManager.default.removeItem(at: unzipedFilePath)
                NSLog("Existing unzipped files deleted \(unzipedFilePath)")
            }
            // Thawing process
            try fileManager.createDirectory(at: destinaltionURL, withIntermediateDirectories: true, attributes: nil)
            try fileManager.unzipItem(at: sourceURL, to: destinaltionURL)
            NSLog("Unzipping completed！\(destinaltionURL)")
            // Delete the ZIP file if it exists after unzipping it
            if FileManager.default.fileExists(atPath: sourceURL.path) {
                try FileManager.default.removeItem(at: sourceURL)
                NSLog("ZIP file deleted after unzipping")
            }
            DispatchQueue.main.async {
                modelData.resourceManager.updateResources()
                if modelData.resourceManager.resources.count > 0 {
                    modelData.resource = modelData.resourceManager.resources[0]
                }
            }
        } catch {
            NSLog("An error occurred while unzipping！")
        }
    }
    
    func SpeechErrorMessage(modelData: CaBotAppModel) {
        DispatchQueue.main.async {
            NSLog("Error message read out loud")
            let message = CustomLocalizedString("Retry Alert", lang: modelData.resourceLang)
            modelData.speak(message) {}
        }
    }
    
    // Delete hash files on retry
    func deleteHashKey() {
        UserDefaults.standard.removeObject(forKey: self.md5HashKey)
    }
    // Delete Resource files
    func deleteResourceFile() {
        let resourceFileName = "app-resource" // Resource file name saved within the app
        let resourceFileURL = getDocumentsDirectory().appendingPathComponent(resourceFileName)
        if FileManager.default.fileExists(atPath: resourceFileURL.path) {
            do {
                NSLog("Resource file deletion completed: \(resourceFileURL.path)")
                try FileManager.default.removeItem(at: resourceFileURL)
            } catch {
                NSLog("Resource file deletion failed: \(error.localizedDescription)")
            }
        }
    }
}

// Display error message and retry button when resource download fails
struct ResourceDownloadRetryUIView: View {
    @EnvironmentObject var modelData: CaBotAppModel
    var body: some View {
        if modelData.suitcaseConnected {
            let _ = modelData.resourceDownload.startDownloadResourceOnSuitcaseConnected(modelData: modelData)
        } else {
            let _ = modelData.resourceDownload.startDownloadResourceOnSuitcaseUnconnected(modelData: modelData)
        }
        // If download fails, an error message and retry will be displayed
        if modelData.resource == nil {
            Section(header: Text("Resource Download")) {
                Text("Retry Alert")
                    .font(.body)
                    .foregroundColor(.red)
                    .lineLimit(1)
                Button(action: {
                    modelData.resourceDownload.deleteHashKey()
                    modelData.resourceDownload.deleteResourceFile()
                    modelData.resourceDownload.startFileDownload(modelData: modelData)
                }, label: {
                    Text("Retry")
                })
            }
        }
    }
}
