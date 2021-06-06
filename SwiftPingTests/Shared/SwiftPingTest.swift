//
//  SwiftPingTest.swift
//  SwiftPing
//
//  Created by Kevin Ross on 6/6/21.
//  Copyright © 2021 Ankit Thakur. All rights reserved.
//

import XCTest
import SwiftPing

class SwiftPingTest: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testExample() throws {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct results.
        guard let ping = SwiftPing(host: "8.8.8.8", configuration: PingConfiguration(pInterval: 5, withTimeout: 30), queue: DispatchQueue.global(), completion: {
            response in
            print("\(response.duration * 1000) ms")
            print("\(response.ipAddress)")
            print("\(response.error)")
        })
        else {
            XCTFail()
            return
        }

        DispatchQueue.main.async { ping.start() }
        RunLoop.main.run()
    }

//    func testPerformanceExample() throws {
//        // This is an example of a performance test case.
//        self.measure {
//            // Put the code you want to measure the time of here.
//        }
//    }

}
