// SwiftPing iOS Playground

import UIKit

var str = "Hello, playground"

let pingInterval:TimeInterval = 3
let timeoutInterval:TimeInterval = 4
let configuration = PingConfiguration(pInterval:pingInterval, withTimeout:  timeoutInterval)

print(configuration)

SwiftPing.ping(host: "24mountains.com", configuration: configuration, queue: DispatchQueue.main) {
    (ping, error) in
    print("\(ping)")
    print("\(error)")
    // start the ping.
    var count = 0;
    ping?.observer = {(ping:SwiftPing, response:PingResponse) -> Void in
        print("\(response.duration * 1000) ms")
        print("\(response.ipAddress ?? "InvalidIP")")
        print("\(response.error)")
        count += 1
        if count > 10 {
            print("stop")
            ping.stop()
            ping.observer = nil
        }
    }
    ping?.start()
}


SwiftPing.pingOnce(host: "google.com", configuration: configuration, queue: DispatchQueue.global()) {
    (response: PingResponse) in
    print("\(response.duration * 1000) ms")
    print("\(response.ipAddress ?? "InvalidIP")")
    print("\(response.error)")
    
}

RunLoop.main.run()
