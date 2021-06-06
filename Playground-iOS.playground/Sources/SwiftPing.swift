//
//  SwiftPing.swift
//  SwiftPing
//
//  Created by Ankit Thakur on 20/06/16.
//  Copyright © 2016 Ankit Thakur. All rights reserved.
//

import Foundation
import Darwin

public let sharedPingController = SwiftPing(host: "0.0.0.0", configuration: PingConfiguration(pInterval: 3, withTimeout: 4), queue: DispatchQueue.main) {
    (response: PingResponse) in
    print("\(response.duration * 1000) ms")
    print("\(response.ipAddress ?? "InvalidIP")")
    print("\(response.error)")
}


public func getIPv4AddressFromHost(host:String, error:AutoreleasingUnsafeMutablePointer<NSError?>) -> Data?{
    var streamError:CFStreamError = CFStreamError()
    let cfhost = CFHostCreateWithName(nil, host as CFString).takeRetainedValue()
    let status = CFHostStartInfoResolution(cfhost, .addresses, &streamError)
    var data:Data?

    if status == false {
        if Int32(streamError.domain)  == kCFStreamErrorDomainNetDB {
            error.pointee = NSError(domain: kCFErrorDomainCFNetwork as String, code: Int(CFNetworkErrors.cfHostErrorUnknown.rawValue) , userInfo: [(kCFGetAddrInfoFailureKey as NSObject) as! String : "error in host name or address lookup"])
        }
        else{
            error.pointee = NSError(domain: kCFErrorDomainCFNetwork as String, code: Int(CFNetworkErrors.cfHostErrorUnknown.rawValue) , userInfo: nil)
        }
    }
    else {
        var success: DarwinBoolean = false
        guard let addresses = CFHostGetAddressing(cfhost, &success)?.takeUnretainedValue() as NSArray?
        else {
            error.pointee = NSError(domain: kCFErrorDomainCFNetwork as String, code: Int(CFNetworkErrors.cfHostErrorHostNotFound.rawValue), userInfo: [NSLocalizedDescriptionKey: "failed to retrieve the known addresses from the given host"])
            return nil
        }

        for address in addresses {
            let addressData = address as! NSData
            let addrin = addressData.bytes.assumingMemoryBound(to: sockaddr.self).pointee
            if addressData.length >= MemoryLayout<sockaddr>.size && addrin.sa_family == UInt8(AF_INET) {
                data = addressData as Data
                break
            }
        }

        if data?.count == 0 || data == nil {
            error.pointee = NSError(domain: kCFErrorDomainCFNetwork as String, code: Int(CFNetworkErrors.cfHostErrorHostNotFound.rawValue) , userInfo: nil)
        }
    }

    return data

}

public typealias Observer = (( _ ping:SwiftPing, _ response:PingResponse) -> Void)
public typealias ErrorClosure = ((_ ping:SwiftPing, _ error:NSError) -> Void)
public class SwiftPing: NSObject {

    var host:String?
    var ip:String?
    var configuration:PingConfiguration?

    public var observer:Observer?

    var errorClosure:ErrorClosure?

    var identifier:UInt32?

    private var hasScheduledNextPing:Bool = false
    private var ipv4address:Data?
    private var socket:CFSocket?
    private var socketSource:CFRunLoopSource?

    private var isPinging:Bool = false
    private var currentSequenceNumber:UInt64 = 0
    private var currentStartDate:Date?

    private var timeoutBlock:(() -> Void)?

    private var currentQueue:DispatchQueue?

    // MARK: Public APIs

    /// init a new ping object pointed at the host url, with provided configuration.
    ///
    /// - parameters:
    ///   - host: url string, to ping.
    ///   - configuration: PingConfiguration object so as to define ping interval, time interval
    ///   - completion: Closure of the format `(ping:SwiftPing?, error:NSError?) -> Void` format
    public convenience init?(host:String, configuration:PingConfiguration, queue:DispatchQueue, completion:@escaping (_ response:PingResponse) -> Void)  {
        var error:NSError?;
        guard let ipv4Address: Data = getIPv4AddressFromHost(host:host, error: &error)
        else {
            print("Failed to get IPv4 address from host: \(host) because \(error?.localizedDescription ?? "an unknown error occurred")")
            return nil
        }
        self.init(host: host, ipv4Address: ipv4Address, configuration: configuration, queue: queue)
        observer = { ping, response in
            completion(response)
        }
    }

    public class func pinger(host:String, configuration:PingConfiguration, queue:DispatchQueue, completion:@escaping (_ response:PingResponse) -> Void) -> SwiftPing? {
        var error:NSError?;
        guard let ipv4Address: Data = getIPv4AddressFromHost(host:host, error: &error)
        else {
            return nil
        }


        let ping = SwiftPing(host: host, ipv4Address: ipv4Address, configuration: configuration, queue: queue)
        ping.observer = {(ping:SwiftPing, response:PingResponse) -> Void in
            //ping.stop()
            //ping.observer = nil
            completion(response);
        }
        //ping.start()
        return ping
    }

    /// pinging to the host url, with provided configuration.
    ///
    /// - parameters:
    ///   - host: url string, to ping.
    ///   - configuration: PingConfiguration object so as to define ping interval, time interval
    ///   - completion: Closure of the format `(ping:SwiftPing?, error:NSError?) -> Void` format
    public class func ping(host:String, configuration:PingConfiguration, queue:DispatchQueue, completion:@escaping (_ ping:SwiftPing?, _ error:NSError?) -> Void) -> Void{

        print(queue)
        DispatchQueue.global().async{
            var error:NSError?;
            let ipv4Address:Data? = getIPv4AddressFromHost(host:host, error: &error)

            queue.async {
                if (error != nil) {
                    completion(nil, error)
                }
                else{
                    completion(SwiftPing(host: host, ipv4Address: ipv4Address!, configuration: configuration, queue: queue), nil)
                }
            }

        }
    }

    /// pinging to the host url only once, with provided configuration
    ///
    /// - parameters:
    ///   - host: url string, to ping.
    ///   - configuration: PingConfiguration object so as to define ping interval, time interval
    ///   - completion: Closure of the format `(ping:SwiftPing?, error:NSError?) -> Void` format

    public class func pingOnce(host:String, configuration:PingConfiguration, queue:DispatchQueue, completion:@escaping (_ response:PingResponse) -> Void) -> Void{

        let date = Date()

        SwiftPing.ping(host: host, configuration: configuration, queue: queue) { (ping, error) in
            if error != nil {
                let response = PingResponse(id: 0, ipAddress: nil, sequenceNumber: 1, duration: Date().timeIntervalSince(date), error: error)

                completion(response);
            }
            else {
                let ping:SwiftPing = ping!

                // add observer to stop the ping, if already recieved once.
                // start the ping.
                ping.observer = {(ping:SwiftPing, response:PingResponse) -> Void in
                    ping.stop()
                    ping.observer = nil
                    completion(response);
                }
                ping.start()

            }
        }
    }

    // MARK: PRIVATE
    func socketCallback(socket: CFSocket!, type:CFSocketCallBackType, address:CFData!, data:UnsafeRawPointer, info:UnsafeMutableRawPointer) {
        // Conditional cast from 'SwiftPing' to 'SwiftPing' always succeeds

        // 1
        var info:UnsafeMutableRawPointer = info
        let ping:SwiftPing = (withUnsafePointer(to: &info) { (temp) in
            return unsafeBitCast(temp, to: SwiftPing.self)
        })

//        guard let ping:SwiftPing = (withUnsafePointer(to: &info) { (temp) in
//            return unsafeBitCast(temp, to: SwiftPing.self)
//        })else{
//            print("ping callback object is nil")
//            return
//        }

        if (type as CFSocketCallBackType) == CFSocketCallBackType.dataCallBack {
            let fData = data.assumingMemoryBound(to: UInt8.self)
            let bytes = UnsafeBufferPointer<UInt8>(start: fData, count: MemoryLayout<UInt8>.size)
            let cfdata:Data = Data(buffer: bytes)
            ping.socket(socket: socket, didReadData: cfdata)
        }
    }

    func initialize(host:String, ipv4Address:Data, configuration:PingConfiguration, queue:DispatchQueue){
        self.host = host;
        ipv4address = ipv4Address;
        self.configuration = configuration;
        identifier = UInt32(arc4random_uniform(UInt32(UInt16.max)));
        currentQueue = queue

        let socketAddress:sockaddr_in = (ipv4Address as NSData).bytes.assumingMemoryBound(to: sockaddr_in.self).pointee
        ip = String(cString: inet_ntoa(socketAddress.sin_addr), encoding: String.Encoding.ascii)!

        var context = CFSocketContext()
//        var context = CFSocketContext(version: 0, info: <#T##UnsafeMutableRawPointer!##Swift.UnsafeMutableRawPointer!#>)
        context.version = 0

//        context.info = unsafeBitCast(self, to: UnsafeMutableRawPointer.self);
        context.info = (withUnsafePointer(to: self) {
            (temp) in
            UnsafeMutableRawPointer(mutating: temp)
        })

        socket = CFSocketCreate(kCFAllocatorDefault, AF_INET, SOCK_DGRAM, IPPROTO_ICMP, CFSocketCallBackType.dataCallBack.rawValue,  {
            (socket, type, address, data, info )  in
            if type == CFSocketCallBackType.dataCallBack {
                print("CFSocketCallBackType.dataCallBack")
                guard let socket = socket,
                      //let address = address,
                      let data = data,
                      var info = info
                else { return }
                print("infoPtr: \(info)")

//                let ping = unsafeBitCast(&info, to: SwiftPing.self)
                let ping:SwiftPing = (withUnsafePointer(to: &info) {
                    (temp) in
                    unsafeBitCast(temp, to: SwiftPing.self)
                })

                print("ping - \(ping) ")

                let fData = data.assumingMemoryBound(to: UInt8.self)
                let bytes = UnsafeBufferPointer<UInt8>(start: fData, count: MemoryLayout<UInt8>.size)
                let cfdata:Data = Data(buffer: bytes)
                ping.socket(socket: socket, didReadData: cfdata)
            }

        }, &context )

        print("context.info: \(context.info)")

        socketSource = CFSocketCreateRunLoopSource(nil, socket, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), socketSource, CFRunLoopMode.commonModes)
    }

    // Designated Intializer

    init(host:String, ipv4Address:Data, configuration:PingConfiguration, queue:DispatchQueue){
        super.init()
        initialize(host: host, ipv4Address: ipv4Address, configuration: configuration, queue: queue)
    }

    convenience init(ipv4Address:String, config configuration:PingConfiguration, queue:DispatchQueue) {
        var socketAddress = sockaddr_in(sin_len: UInt8(MemoryLayout<sockaddr_in>.size),
                                        sin_family: UInt8(AF_INET),
                                        sin_port: 0,
                                        sin_addr: in_addr(s_addr: inet_addr(ipv4Address.cString(using: String.Encoding.utf8))),
                                        sin_zero: (0, 0, 0, 0, 0, 0, 0, 0))

        let data = NSData(bytes: &socketAddress, length: MemoryLayout<sockaddr_in>.size)

        // calling designated initializer
        self.init(host: ipv4Address, ipv4Address: data as Data, configuration: configuration, queue: queue)
    }

    deinit {
        print("deinit")
        CFRunLoopSourceInvalidate(socketSource)
        socketSource = nil
        socket = nil
    }

    // MARK: Start and Stop the pings
    public func start() {
        if isPinging == false {
            let error = CFSocketConnectToAddress(socket, ipv4address! as CFData, configuration?.timeOutInterval ?? 5)
            if error == CFSocketError.success {
                isPinging = true
                currentSequenceNumber = 0
                currentStartDate = nil
                sendPing()
            }
            else if error == CFSocketError.error {
                print("Error connecting socket to host!")
            }
            else if error == CFSocketError.timeout {
                print("Timeout connecting socket to host!")
            }
        }
    }

    public func stop() {
        isPinging = false
        currentSequenceNumber = 0
        currentStartDate = nil

        if timeoutBlock != nil {
            timeoutBlock = nil
        }
    }

    func scheduleNextPing()
    {
        if (hasScheduledNextPing == false) {
            return;
        }

        hasScheduledNextPing = true
        if (timeoutBlock != nil) {
            timeoutBlock = nil;
        }

        let dispatchTime: DispatchTime = DispatchTime.now() + Double(Int64((configuration?.pingInterval)! * Double(NSEC_PER_SEC)))

        currentQueue?.asyncAfter(deadline: dispatchTime) {
            self.hasScheduledNextPing = false
        }
    }


    func socket(socket:CFSocket, didReadData data:Data?) {

        var ipHeaderData:NSData?
        var ipData:NSData?
        var icmpHeaderData:NSData?
        var icmpData:NSData?

        let extractIPAddressBlock: () -> String? = {
            if ipHeaderData == nil {
                return nil
            }

            var bytes:UnsafeRawPointer = (ipHeaderData?.bytes)!
            let ipHeader:IPHeader = (withUnsafePointer(to: &bytes) { (temp) in
                unsafeBitCast(temp, to: IPHeader.self)
            })

            let sourceAddr:[UInt8] = ipHeader.sourceAddress

            print("\(sourceAddr[0]).\(sourceAddr[1]).\(sourceAddr[2]).\(sourceAddr[3])")

            return "\(sourceAddr[0]).\(sourceAddr[1]).\(sourceAddr[2]).\(sourceAddr[3])"
        }

        if !ICMPExtractResponseFromData(data: data! as NSData, ipHeaderData: &ipHeaderData, ipData: &ipData, icmpHeaderData: &icmpHeaderData, icmpData: &icmpData) {
            print("ICMPExtractResponseFromData")
            if (ipHeaderData != nil && self.ip == extractIPAddressBlock()) {
                return
            }
        }

        let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorCannotDecodeRawData, userInfo: nil)
        let response:PingResponse = PingResponse(id: identifier!, ipAddress: nil, sequenceNumber: Int64(currentSequenceNumber), duration: Date().timeIntervalSince(currentStartDate!), error: error)
        if observer != nil {
            observer!(self, response)
        }

        return scheduleNextPing()
    }



    func sendPing()
    {
        if (!isPinging) {
            return;
        }

        currentSequenceNumber += 1;
        currentStartDate = Date();

        let icmpPackage:NSData = ICMPPackageCreate(identifier: UInt16(identifier!), sequenceNumber: UInt16(currentSequenceNumber), payloadSize: UInt32(configuration!.payloadSize))!;

        let socketError:CFSocketError = CFSocketSendData(socket!, /*ipv4address! as CFData*/nil, icmpPackage as CFData, configuration!.timeOutInterval)
        if socketError == CFSocketError.success {
            let response:PingResponse = PingResponse(id: identifier!, ipAddress: nil, sequenceNumber: Int64(currentSequenceNumber), duration: Date().timeIntervalSince(currentStartDate!), error: nil)
            if observer != nil {
                observer!(self, response)
            }

            return scheduleNextPing()
        }
        else if socketError == CFSocketError.error {
            let error = NSError(domain: NSURLErrorDomain, code:NSURLErrorCannotFindHost, userInfo: [:])
            let response:PingResponse = PingResponse(id: identifier!, ipAddress: nil, sequenceNumber: Int64(currentSequenceNumber), duration: Date().timeIntervalSince(currentStartDate!), error: error)
            if observer != nil {
                observer!(self, response)
            }

            return scheduleNextPing()
        }
        else if socketError == CFSocketError.timeout {
            let error = NSError(domain: NSURLErrorDomain, code:NSURLErrorTimedOut, userInfo: [:])
            let response:PingResponse = PingResponse(id: identifier!, ipAddress: nil, sequenceNumber: Int64(currentSequenceNumber), duration: Date().timeIntervalSince(currentStartDate!), error: error)
            if observer != nil {
                observer!(self, response)
            }

            return scheduleNextPing()
        }

        let sequenceNumber:UInt64 = currentSequenceNumber;
        timeoutBlock = { () -> Void in
            if (sequenceNumber != self.currentSequenceNumber) {
                return;
            }

            self.timeoutBlock = nil
            let error = NSError(domain: NSURLErrorDomain, code:NSURLErrorTimedOut, userInfo: [:])
            let response:PingResponse = PingResponse(id: self.identifier!, ipAddress: nil, sequenceNumber: Int64(self.currentSequenceNumber), duration: Date().timeIntervalSince(self.currentStartDate!), error: error)
            if self.observer != nil {
                self.observer!(self, response)
            }
            self.scheduleNextPing()
        }


        typealias Block = @convention(block) () -> ()
        let block: Block = timeoutBlock as! Block
        let dispatchTime: DispatchTime = DispatchTime.now() + Double(Int64((configuration?.pingInterval)! * Double(NSEC_PER_SEC)))

        currentQueue?.asyncAfter(deadline: dispatchTime, execute: block)
    }
}
