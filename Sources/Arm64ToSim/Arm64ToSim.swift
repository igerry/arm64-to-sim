import Foundation
import MachO

// support checking for Mach-O `cmd` and `cmdsize` properties
extension Data {
  var loadCommand: UInt32 {
    let lc: load_command = withUnsafeBytes { $0.load(as: load_command.self) }
    return lc.cmd
  }

  var commandSize: Int {
    let lc: load_command = withUnsafeBytes { $0.load(as: load_command.self) }
    return Int(lc.cmdsize)
  }

  func asStruct<T>(fromByteOffset offset: Int = 0) -> T {
    return withUnsafeBytes { $0.load(fromByteOffset: offset, as: T.self) }
  }
}

extension Array where Element == Data {
  func merge() -> Data {
    return reduce(into: Data()) { $0.append($1) }
  }
}

// support peeking at Data contents
extension FileHandle {
  func peek(upToCount count: Int) throws -> Data? {
    // persist the current offset, since `upToCount` doesn't guarantee all bytes will be read
    let originalOffset = offsetInFile
    let data = try read(upToCount: count)
    try seek(toOffset: originalOffset)
    return data
  }
}

public struct FileOpenError: LocalizedError {
  public let path: String

  public var errorDescription: String? {
    "Cannot open a handle for the file at \(path). Aborting."
  }
}

public struct IncorrectBinaryError: LocalizedError {
  public var errorDescription: String? {
    "The file is not a correct arm64 binary. Try thinning (via lipo) or unarchiving (via ar) first."
  }
}

public struct LcBuildVersionCommandAlreadyExistError: LocalizedError {
  public var errorDescription: String? {
    "This arm64 binary already contains an LC_BUILD_VERSION load command!"
  }
}

enum Transmogrifier {
  private static func readBinary(atPath path: String) throws -> (Data, [Data], Data) {
    guard let handle = FileHandle(forReadingAtPath: path) else {
      throw FileOpenError(path: path)
    }

    // chop up the file into a relevant number of segments
    let headerData = try handle.read(upToCount: MemoryLayout<mach_header_64>.stride)!

    let header: mach_header_64 = headerData.asStruct()
    if header.magic != MH_MAGIC_64 || header.cputype != CPU_TYPE_ARM64 {
      throw IncorrectBinaryError()
    }

    let loadCommandsData: [Data] = try (0..<header.ncmds).map { _ in
      let loadCommandPeekData = try handle.peek(upToCount: MemoryLayout<load_command>.stride)
      return try handle.read(upToCount: Int(loadCommandPeekData!.commandSize))!
    }

    // discard 8 empty bytes that should exist here
    let bytesToDiscard = abs(MemoryLayout<build_version_command>.stride - MemoryLayout<version_min_command>.stride)
    _ = handle.readData(ofLength: bytesToDiscard)

    let programData = try handle.readToEnd()!

    try handle.close()

    return (headerData, loadCommandsData, programData)
  }

  private static func updateVersionMin(_ data: Data, _ offset: UInt32, _ platform: UInt32) -> Data {
    var command = build_version_command(cmd: UInt32(LC_BUILD_VERSION),
                                        cmdsize: UInt32(MemoryLayout<build_version_command>.stride),
                                        platform: platform,
                                        minos: 13 << 16 | 0 << 8 | 0,
                                        sdk: 13 << 16 | 0 << 8 | 0,
                                        ntools: 0)

    return Data(bytes: &command, count: MemoryLayout<build_version_command>.stride)
  }

  static func processBinary(atPath path: String) throws {
    let (headerData, loadCommandsData, programData) = try readBinary(atPath: path)

    // `offset` is kind of a magic number here, since we know that's the only meaningful change to binary size
    // having a dynamic `offset` requires two passes over the load commands and is left as an exercise to the reader
    let offset = UInt32(abs(MemoryLayout<build_version_command>.stride - MemoryLayout<version_min_command>.stride))

    let editedCommandsData = try loadCommandsData
      .map { (lc) -> Data in
        switch lc.loadCommand {
        case UInt32(LC_VERSION_MIN_IPHONEOS):
          return updateVersionMin(lc, offset, UInt32(PLATFORM_IOSSIMULATOR))
        case UInt32(LC_VERSION_MIN_TVOS):
          return updateVersionMin(lc, offset, UInt32(PLATFORM_TVOSSIMULATOR))
        case UInt32(LC_BUILD_VERSION):
          return lc
        default:
          return lc
        }
      }
      .merge()

    var header: mach_header_64 = headerData.asStruct()
    header.sizeofcmds = UInt32(editedCommandsData.count)

    // reassemble the binary
    let reworkedData = [
      Data(bytes: &header, count: MemoryLayout<mach_header_64>.stride),
      editedCommandsData,
      programData
    ].merge()

    // save back to disk
    try reworkedData.write(to: URL(fileURLWithPath: path))
  }
}

public func arm64ToSim(_ path: String) throws {
  try Transmogrifier.processBinary(atPath: path)
}
