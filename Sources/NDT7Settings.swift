//
//  NDT7Settings.swift
//  NDT7
//
//  Created by NietoGuillen, Miguel on 4/18/19.
//  Copyright © 2019 M-Lab. All rights reserved.
//

import Foundation

/// Settings needed for NDT7.
/// Can be used with default values: NDT7Settings()
public struct NDT7Settings {

    /// URL for Web Socket.
    public var url: NDT7URL

    /// Timeouts
    public let timeout: NDT7Timeouts

    /// Skipt TLS certificate verification.
    public let skipTLSCertificateVerification: Bool

    /// Use geo options to get a list of Mlab servers vs the closer one with false.
    public let useGeoOptions: Bool

    /// Define all the headers needed for NDT7 request.
    public let headers: [String: String]

    /// Initialization.
    public init(url: NDT7URL = NDT7URL(hostname: ""),
                timeout: NDT7Timeouts = NDT7Timeouts(),
                skipTLSCertificateVerification: Bool = true,
                useGeoOptions: Bool = false,
                headers: [String: String] = [NDT7WebSocketConstants.Request.headerProtocolKey: NDT7WebSocketConstants.Request.headerProtocolValue]) {
        self.url = url
        self.skipTLSCertificateVerification = skipTLSCertificateVerification
        self.useGeoOptions = useGeoOptions
        self.timeout = timeout
        self.headers = headers
    }
}

/// URL settings.
public struct NDT7URL {

    /// Mlab Server:
    public var server: NDT7Server?

    /// Server to connect.
    public var hostname: String

    /// Patch for download test.
    public let downloadPath: String

    /// Patch for upload test.
    public let uploadPath: String

    /// Define if it is wss or ws.
    public let wss: Bool

    /// Download URL
    public var download: String {
        return server?.results.first?.urls?.downloadUrl ?? ""
    }

    /// Upload URL
    public var upload: String {
        return server?.results.first?.urls?.uploadUrl ?? ""
    }

    /// Initialization.
    public init(hostname: String,
                downloadPath: String? = nil,
                uploadPath: String? = nil,
                wss: Bool = true) {
        self.hostname = hostname
        self.downloadPath = downloadPath ?? ""
        self.uploadPath = uploadPath ?? ""
        self.wss = wss
    }
}

/// Timeout settings.
public struct NDT7Timeouts {

    /// Define the interval between messages.
    /// When downloading, the server is expected to send measurement to the client,
    /// and when uploading, conversely, the client is expected to send measurements to the server.
    /// Measurements SHOULD NOT be sent more frequently than every 250 ms
    /// This parameter deine the frequent to send messages.
    /// If it is initialize with less than 250 ms, it's going to be overwritten to 250 ms
    public let measurement: TimeInterval

    /// ioTimeout is the timeout in seconds for I/O operations.
    public let ioTimeout: TimeInterval

    /// Define the max among of time used for a download test before to force to finish.
    public let downloadTimeout: TimeInterval

    /// Define the max among of time used for a upload test before to force to finish.
    public let uploadTimeout: TimeInterval

    /// Initialization.
    public init(measurement: TimeInterval = NDT7WebSocketConstants.Request.updateInterval,
                ioTimeout: TimeInterval = NDT7WebSocketConstants.Request.ioTimeout,
                downloadTimeout: TimeInterval = NDT7WebSocketConstants.Request.downloadTimeout,
                uploadTimeout: TimeInterval = NDT7WebSocketConstants.Request.uploadTimeout) {
        self.measurement = measurement >= NDT7WebSocketConstants.Request.updateInterval ? measurement : NDT7WebSocketConstants.Request.updateInterval
        self.ioTimeout = ioTimeout
        self.downloadTimeout = downloadTimeout
        self.uploadTimeout = uploadTimeout
    }
}

/// Mlab NDT7 Server.
public struct NDT7Server: Codable {

    /// Last server got from MLab
    static var lastServer: NDT7Server?

    /// ip array
    public var ip: [String]?

    /// country
    public var country: String?

    /// city
    public var city: String?

    /// results.first?.machine
    public var fqdn: String?

    /// site
    public var site: String?
    
    /// results
    public var results = [ServerResult]()
}
public struct ServerResult: Codable {
    ///host
    public var machine: String?
    
    /// location
    public var location = Location()
    
    public var urls: URLs?
}

public struct Location: Codable {
    public var city: String?
    public var country: String?
}

public struct URLs: Codable {
    public var uploadUrl: String?
    public var downloadUrl: String?
    
    enum Keys: String, CodingKey {
        case upload = "wss:///ndt/v7/upload"
        case download = "wss:///ndt/v7/download"
    }
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Keys.self)
        try container.encode(uploadUrl, forKey: .upload)
        try container.encode(downloadUrl, forKey: .download)
    }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: Keys.self)
        uploadUrl = try values.decodeIfPresent(String.self, forKey: .upload)
        downloadUrl = try values.decodeIfPresent(String.self, forKey: .download)
    }
}

/// This extension provides helper methods to discover Mlab servers availables.
extension NDT7Server {

    /// Discover the closer Mlab server available or using geo location to get a random server from a list of the closer servers.
    /// - parameter session: URLSession object used to request servers, using URLSession.shared object as default session.
    /// - parameter geoOptions: true to use a list of servers based in geo location, otherwise the function will work trying to get the closer server.
    /// - parameter retray: true to use a list of servers based in geo location, otherwise the function will work trying to get the closer server.
    /// - parameter geoOptionsChangeInRetray: Alternate geo options for retray.
    /// - parameter useNDT7ServerCache: uses the NDT7 Server cached if exist and if the request/s fail.
    /// - parameter completion: callback to get the NDT7Server and error message.
    /// - parameter server: NDT7Server object representing the Mlab server.
    /// - parameter error: if any error happens, this parameter returns the error.
    public static func discover<T: URLSessionNDT7>(session: T = URLSession.shared as! T,
                                                   withGeoOptions geoOptions: Bool,
                                                   retray: UInt = 0,
                                                   geoOptionsChangeInRetray: Bool = false,
                                                   useNDT7ServerCache: Bool = false,
                                                   _ completion: @escaping (_ server: NDT7Server?, _ error: NSError?) -> Void) -> URLSessionTaskNDT7 {
        let retray = min(retray, 4)
        let request = Networking.urlRequest(geoOptions ? NDT7WebSocketConstants.MlabServerDiscover.urlWithGeoOption : NDT7WebSocketConstants.MlabServerDiscover.url)
        let task = session.dataTask(with: request as URLRequest) { (data, _, error) -> Void in
            OperationQueue.current?.name = "net.measurementlab.NDT7.MlabServer.discover"
            guard error?.localizedDescription != "cancelled" else {
                completion(nil, NDT7TestConstants.cancelledError)
                return
            }
            guard error == nil else {
                if retray > 0 {
                    logNDT7("NDT7 Mlab error, cannot find a suitable mlab server, retray: \(retray)", .info)
                    DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
                        _ = discover(session: session,
                                     withGeoOptions: geoOptionsChangeInRetray ? !geoOptions : geoOptions,
                                     retray: retray - 1,
                                     geoOptionsChangeInRetray: geoOptionsChangeInRetray,
                                     useNDT7ServerCache: useNDT7ServerCache,
                                     completion)
                    }
                } else if retray == 0, useNDT7ServerCache, let server = lastServer {
                    logNDT7("NDT7 Mlab server \(String(describing: server.results.first?.machine!))\(error == nil ? "" : " error: \(error!.localizedDescription)")", .info)
                    completion(server, server.results.first?.machine == nil ? NDT7WebSocketConstants.MlabServerDiscover.noMlabServerError : nil)
                }
                return
            }
            if let server = decode(data: data, fromUrl: request.url?.absoluteString), server.results.first?.machine != nil  && server.results.first?.machine! != "" {
                lastServer = server
                logNDT7("NDT7 Mlab server \(String(describing: server.results.first?.machine!))\(error == nil ? "" : " error: \(error!.localizedDescription)")", .info)
                completion(server, server.results.first?.machine == nil ? NDT7WebSocketConstants.MlabServerDiscover.noMlabServerError : nil)
            } else if retray > 0 {
                logNDT7("NDT7 Mlab cannot find a suitable mlab server, retray: \(retray)", .info)
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
                    _ = discover(session: session,
                                 withGeoOptions: geoOptionsChangeInRetray ? !geoOptions : geoOptions,
                                 retray: retray - 1,
                                 geoOptionsChangeInRetray: geoOptionsChangeInRetray,
                                 useNDT7ServerCache: useNDT7ServerCache,
                                 completion)
                }
            } else if retray == 0, useNDT7ServerCache, let server = lastServer {
                logNDT7("NDT7 Mlab server \(String(describing: server.results.first?.machine!))\(error == nil ? "" : " error: \(error!.localizedDescription)")", .info)
                completion(server, server.results.first?.machine == nil ? NDT7WebSocketConstants.MlabServerDiscover.noMlabServerError : nil)
            } else {
                logNDT7("NDT7 Mlab cannot find a suitable mlab server, retray: \(retray)", .info)
                completion(nil, NDT7WebSocketConstants.MlabServerDiscover.noMlabServerError)
            }
        }
        task.resume()
        return task
    }

    static func decode(data: Data?, fromUrl url: String?) -> NDT7Server? {
        guard let data = data, let url = url else { return nil }
        switch url {
        case NDT7WebSocketConstants.MlabServerDiscover.url:
            return try? JSONDecoder().decode(NDT7Server.self, from: data)
        case NDT7WebSocketConstants.MlabServerDiscover.urlWithGeoOption:
            let decoded = try? JSONDecoder().decode([NDT7Server].self, from: data)
            let server = decoded?.first(where: { (server) -> Bool in
                return server.results.first?.machine != nil && !(server.results.first?.machine!.isEmpty)!
            })
            return server
        default:
            return nil
        }
    }
}
