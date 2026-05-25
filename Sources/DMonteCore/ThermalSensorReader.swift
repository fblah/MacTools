import Foundation
import Darwin

private typealias IOHIDEventSystemClient = OpaquePointer
private typealias IOHIDServiceClient = OpaquePointer
private typealias IOHIDEvent = OpaquePointer

private typealias IOHIDEventSystemClientCreate = @convention(c) (CFAllocator?) -> IOHIDEventSystemClient?
private typealias IOHIDEventSystemClientCopyServices = @convention(c) (IOHIDEventSystemClient?) -> Unmanaged<CFArray>?
private typealias IOHIDServiceClientCopyEvent = @convention(c) (IOHIDServiceClient?, Int64, Int32, Int64) -> IOHIDEvent?
private typealias IOHIDEventGetFloatValue = @convention(c) (IOHIDEvent?, Int64) -> Double
private typealias IOHIDServiceClientCopyProperty = @convention(c) (IOHIDServiceClient?, CFString) -> Unmanaged<CFTypeRef>?

final class ThermalSensorReader {
    private static let temperatureEventType: Int64 = 15
    private static let temperatureEventField: Int64 = temperatureEventType << 16

    private let createClient: IOHIDEventSystemClientCreate?
    private let copyServices: IOHIDEventSystemClientCopyServices?
    private let copyEvent: IOHIDServiceClientCopyEvent?
    private let getFloatValue: IOHIDEventGetFloatValue?
    private let copyProperty: IOHIDServiceClientCopyProperty?
    private let client: IOHIDEventSystemClient?

    init() {
        let handle = dlopen(nil, RTLD_NOW)
        let createClient: IOHIDEventSystemClientCreate? = Self.symbol("IOHIDEventSystemClientCreate", from: handle)
        self.createClient = createClient
        copyServices = Self.symbol("IOHIDEventSystemClientCopyServices", from: handle)
        copyEvent = Self.symbol("IOHIDServiceClientCopyEvent", from: handle)
        getFloatValue = Self.symbol("IOHIDEventGetFloatValue", from: handle)
        copyProperty = Self.symbol("IOHIDServiceClientCopyProperty", from: handle)
        client = createClient?(kCFAllocatorDefault)
    }

    deinit {
        if let client {
            Self.release(client)
        }
    }

    func cpuTemperatureCelsius() -> Double? {
        guard let copyServices,
              let copyEvent,
              let getFloatValue,
              let copyProperty,
              let client,
              let services = copyServices(client)?.takeRetainedValue() else {
            return nil
        }

        var temperatures: [Double] = []

        for index in 0..<CFArrayGetCount(services) {
            guard let rawService = CFArrayGetValueAtIndex(services, index) else {
                continue
            }

            let service = OpaquePointer(rawService)
            let product = copyProperty(service, "Product" as CFString)?.takeRetainedValue() as? String
            guard product?.localizedCaseInsensitiveContains("tdie") == true,
                  let event = copyEvent(service, Self.temperatureEventType, 0, 0) else {
                continue
            }
            defer {
                Self.release(event)
            }

            let celsius = getFloatValue(event, Self.temperatureEventField)
            guard celsius > 0, celsius < 130 else {
                continue
            }

            temperatures.append(celsius)
        }

        guard !temperatures.isEmpty else {
            return nil
        }

        return temperatures.reduce(0, +) / Double(temperatures.count)
    }

    private static func symbol<T>(_ name: String, from handle: UnsafeMutableRawPointer?) -> T? {
        guard let pointer = dlsym(handle, name) else {
            return nil
        }

        return unsafeBitCast(pointer, to: T.self)
    }

    private static func release(_ pointer: OpaquePointer) {
        Unmanaged<CFTypeRef>.fromOpaque(UnsafeRawPointer(pointer)).release()
    }
}
