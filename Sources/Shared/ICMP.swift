//
//  ICMP.swift
//  SwiftPing
//
//  Created by Ankit Thakur on 28/06/16.
//  Copyright © 2016 Ankit Thakur. All rights reserved.
//

import Foundation

struct IPHeader {
	var versionAndHeaderLength: UInt8
	var differentiatedServices: UInt8
	var totalLength: UInt16
	var identification: UInt16
	var flagsAndFragmentOffset: UInt16
	var timeToLive: UInt8
	var `protocol`: UInt8
	var headerChecksum: UInt16
	var sourceAddress: [UInt8]
	var destinationAddress: [UInt8]
}


struct ICMPHeader {

	var type:UInt8      /* type of message*/
	var code:UInt8      /* type sub code */
	var checkSum:UInt16 /* ones complement cksum of struct */
	var identifier:UInt16
	var sequenceNumber:UInt16

	var data:timeval
}

// ICMP type and code combinations:

enum ICMPType:UInt8{
	case EchoReply   = 0           // code is always 0
	case EchoRequest = 8            // code is always 0
}


//static inline uint16_t in_cksum(const void *buffer, size_t bufferLen)

@inline(__always) func checkSum(buffer:UnsafeMutableRawPointer, bufLen:Int) -> UInt16 {

	var bufLen = bufLen
	var checksum:UInt32 = 0
	var buf = buffer.assumingMemoryBound(to: UInt16.self)

	while bufLen > 1 {
		checksum += UInt32(buf.pointee)
		buf = buf.successor()
		bufLen -= MemoryLayout<UInt16>.size
	}

	if bufLen == 1 {
		checksum += UInt32(UnsafeMutablePointer<UInt16>(buf).pointee)
	}
	checksum = (checksum >> 16) + (checksum & 0xFFFF)
	checksum += checksum >> 16
	return ~UInt16(checksum)
	
}

// helper

@inline(__always) func ICMPPackageCreate(identifier: UInt16, sequenceNumber: UInt16, payloadSize: UInt32) -> NSData? {
    //let packet:String = "\(arc4random()) bottles of beer on the wall sdnwjdn  dskjwebdkjb wekjdnqkjdb wekjdbqewkjdbkjewvb wekjbdkqjwbdkjqbvkj bkjbdkqjwbdkqjwb webdwbeo23oeh08eobqwkjbkjwd bkj2bqkjfbcwkdvbwekj bwkejbdqjkwdbqkjwbc wekjqbfkjqwbdqkjevb wekjbfkj bwekjqwbdkqjbvkjwdb kwbfqhwebd12douc2wevb qbdkjqwbd"
    //let packet:String = "FEEEDFACEDEEADBEEFFEEEDFACEDEEADBEEFFEEEDFACEDEEADBEEFFEEEDFACEDEEADBEEFFEEEDFACEDEEADBEEFFEEEDFACEDEEADBEEFFEEEDFACEDEEADBEEFFEEEDFACEDEEADBEEFFEEEDFACEDEEADBEEFFEEEDFACEDEEADBEEFFEEEDFACEDEEADBEEFFEEEDFACEDEEADBEEFFEEEDFACEDEEADBEEFFEEEDFACEDEEADBEEFFEEEDFACEDEEADBEEFFEEEDFACEDEEA"
    let packet:String = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"

	// Construct the ping packet.
	var payload:NSData = NSData(data: packet.data(using: String.Encoding.utf8)!)
    payload = payload.subdata(with: NSMakeRange(0, Int(payloadSize))) as NSData
	let package:NSMutableData = NSMutableData(capacity: MemoryLayout<ICMPHeader>.size+payload.length)!


    let mutableBytes = package.mutableBytes;
    
    let header:ICMPHeader = mutableBytes.assumingMemoryBound(to: ICMPHeader.self).pointee

	var icmpHeader:ICMPHeader = header

	icmpHeader.type = ICMPType.EchoRequest.rawValue
	icmpHeader.code = 0
	icmpHeader.checkSum = 0
	icmpHeader.identifier = CFSwapInt16HostToBig(identifier)
	icmpHeader.sequenceNumber = CFSwapInt16HostToBig(sequenceNumber)

	withUnsafeMutableBytes(of: &icmpHeader) { pointer -> Void in
		memcpy(pointer.baseAddress! + 1, payload.bytes, payload.length)
	}


	// The IP checksum returns a 16-bit number that's already in correct byte order
	// (due to wacky 1's complement maths), so we just put it into the packet as a
	// 16-bit unit.

	let bytes = package.mutableBytes

	icmpHeader.checkSum = checkSum(buffer: bytes, bufLen: package.length)
    
    var byteBuffer = [UInt8]()
    withUnsafeBytes(of: &icmpHeader) {
        (bytes: UnsafeRawBufferPointer) in byteBuffer += bytes
    }
    package.replaceBytes(in: NSMakeRange(0, byteBuffer.count), withBytes: byteBuffer)
    package.replaceBytes(in: NSMakeRange(byteBuffer.count, payload.length), withBytes: payload.bytes)
    print("ping package: \(package)")
    
	return package;
}

func IMCPPacketSize() -> Int {
	MemoryLayout<IPHeader>.size+MemoryLayout<ICMPHeader>.size
}

@inline(__always) func ICMPExtractResponseFromData(data:NSData, ipHeaderData:AutoreleasingUnsafeMutablePointer<NSData?>, ipData:AutoreleasingUnsafeMutablePointer<NSData?>, icmpHeaderData:AutoreleasingUnsafeMutablePointer<NSData?>, icmpData:AutoreleasingUnsafeMutablePointer<NSData?>)-> Bool{

	let combinedHeaderSize = MemoryLayout<IPHeader>.size + MemoryLayout<ICMPHeader>.size
	//let buffer:NSMutableData = (data.subdata(with: NSMakeRange(0, combinedHeaderSize))  as NSData).mutableCopy() as! NSMutableData
	let buffer:NSMutableData = data.mutableCopy() as! NSMutableData

	if buffer.length < combinedHeaderSize {
		return false
	}
	print("buffer: \(buffer)")

	let ipHeaderBuffer = buffer.subdata(with: NSMakeRange(0, MemoryLayout<IPHeader>.size)) as NSData
	print("ipHeaderBuffer: \(ipHeaderBuffer)")

	let ipHeaderMutableBuffer = ipHeaderBuffer.mutableCopy() as! NSMutableData
	var mutableBytes = buffer.mutableBytes

	var bindMemory = mutableBytes.bindMemory(to: IPHeader.self, capacity: 1)
	print("bindMemory: \(bindMemory)")

	let pointer: OpaquePointer = OpaquePointer(ipHeaderMutableBuffer.mutableBytes)
	let castMutablePointer: UnsafeMutablePointer<IPHeader> = UnsafeMutablePointer<IPHeader>(pointer)
	print("testIPHeader: \(castMutablePointer)")
/// Returns the bits of the given instance, interpreted as having the specified
/// type.
///
/// Use this function only to convert the instance passed as `x` to a
/// layout-compatible type when conversion through other means is not
/// possible. Common conversions supported by the Swift standard library
/// include the following:
///
/// - Value conversion from one integer type to another. Use the destination
///   type's initializer or the `numericCast(_:)` function.
/// - Bitwise conversion from one integer type to another. Use the destination
///   type's `init(truncatingIfNeeded:)` or `init(bitPattern:)` initializer.
/// - Conversion from a pointer to an integer value with the bit pattern of the
///   pointer's address in memory, or vice versa. Use the `init(bitPattern:)`
///   initializer for the destination type.
/// - Casting an instance of a reference type. Use the casting operators (`as`,
///   `as!`, or `as?`) or the `unsafeDowncast(_:to:)` function. Do not use
///   `unsafeBitCast(_:to:)` with class or pointer types; doing so may
///   introduce undefined behavior.
///
/// - Parameters:
///   - x: The instance to cast to `type`.
///   - type: The type to cast `x` to. `type` and the type of `x` must have the
///     same size of memory representation and compatible memory layout.
/// - Returns: A new instance of type `U`, cast from `x`.
	print("MemoryLayout<IPHeader>.size: \(MemoryLayout<IPHeader>.size)")
	print("MemoryLayout<UnsafeMutableRawPointer>.size: \(MemoryLayout<UnsafeMutablePointer<IPHeader>>.size)")

//	let ipHeader = Unmanaged<IPHeader>.fromOpaque(ipHeaderMutableBuffer.mutableBytes).takeRetainedValue()

	let ipHeader: IPHeader = unsafeBitCast(ipHeaderMutableBuffer.mutableBytes.assumingMemoryBound(to: IPHeader.self), to: IPHeader.self)
//	var ipHeader = withUnsafeBytes(of: &mutableBytes) {
//		(pointer: UnsafeRawBufferPointer) in
//		unsafeBitCast(pointer, to: IPHeader.self)
//	}
//	let ipHeader = (withUnsafePointer(to: mutableBytes) { (temp) in
//		unsafeBitCast(temp, to: IPHeader.self)
//	})

	assert((ipHeader.versionAndHeaderLength & 0xF0) == 0x40)     // IPv4
	assert(ipHeader.protocol == 1)                               // ICMP

	let ipHeaderLength:UInt8 = (ipHeader.versionAndHeaderLength & 0x0F) * UInt8(MemoryLayout<UInt32>.size)

	let range:NSRange = NSMakeRange(0, MemoryLayout<IPHeader>.size)
	ipHeaderData.pointee = buffer.subdata(with: range) as NSData?


	if (buffer.length >= MemoryLayout<IPHeader>.size + Int(ipHeaderLength)) {
		ipData.pointee = buffer.subdata(with:NSMakeRange(MemoryLayout<IPHeader>.size, Int(ipHeaderLength))) as NSData?
	}

	if (buffer.length < Int(ipHeaderLength) + MemoryLayout<ICMPHeader>.size) {
		return false
	}

	let icmpHeaderOffset:size_t = size_t(ipHeaderLength);

	var headerBuffer = mutableBytes.assumingMemoryBound(to: UInt8.self) + icmpHeaderOffset

	 let icmpheader: ICMPHeader = (withUnsafePointer(to: &headerBuffer) { (temp) in
		return unsafeBitCast(temp, to: ICMPHeader.self)
		})

	var icmpHeader = icmpheader

	let receivedChecksum:UInt16 = icmpHeader.checkSum;
	icmpHeader.checkSum = 0;
	let calculatedChecksum:UInt16 = checkSum(buffer: &icmpHeader, bufLen: buffer.length - icmpHeaderOffset);
	icmpHeader.checkSum = receivedChecksum;

	if (receivedChecksum != calculatedChecksum) {
		print("invalid ICMP header. Checksums did not match");
		return false;
	}


	let icmpDataRange = NSMakeRange(icmpHeaderOffset + MemoryLayout<ICMPHeader>.size, buffer.length - (icmpHeaderOffset + MemoryLayout<ICMPHeader>.size))
	icmpHeaderData.pointee = buffer.subdata(with: NSMakeRange(icmpHeaderOffset, MemoryLayout<ICMPHeader>.size)) as NSData?
	icmpData.pointee = buffer.subdata(with:icmpDataRange) as NSData?

	return true
}
