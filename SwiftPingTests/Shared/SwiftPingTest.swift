//
//  SwiftPingTest.swift
//  SwiftPing
//
//  Created by Kevin Ross on 6/6/21.
//  Copyright © 2021 Ankit Thakur. All rights reserved.
//

import XCTest
@testable import SwiftPing

class SwiftPingTest: XCTestCase {

    private var pinger: SwiftPing?

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        print("pinger: \(String(describing: pinger))")
    }

    func testExample() throws {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct results.
        let hostname = "24mountains.com"
        guard let ping = SwiftPing(host: hostname, configuration: PingConfiguration(pInterval: 5, withTimeout: 30), queue: DispatchQueue.main, completion: {
            response in
            print("\(response.duration) ms")
            print("\(response.ipAddress ?? "InvalidIP")")
            if let error = response.error  {
                print("\(String(describing: error))")
                if error.code == NSURLErrorCannotFindHost {
                    print("NSURLErrorCannotFindHost")
                }
                else if error.code == NSURLErrorCannotDecodeRawData {
                    print("NSURLErrorCannotDecodeRawData")
                }
                XCTFail()
            }
        })
        else {
            XCTFail()
            return
        }
        pinger = ping

        DispatchQueue.main.async { self.pinger?.start() }
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 111))
    }

//    func testPerformanceExample() throws {
//        // This is an example of a performance test case.
//        self.measure {
//            // Put the code you want to measure the time of here.
//        }
//    }

}
