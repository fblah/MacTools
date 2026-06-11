import XCTest
import CoreAudio
@testable import DMonteCore

/// Pure tests for the Volume Mixer render loop's buffer copy — in particular
/// the channel mapping between the (stereo) tap and outputs with a different
/// frame layout (mono USB speakers, 5.1/7.1 HDMI TVs and AVRs). A raw
/// interleaved copy smears frames across channels on such devices, which is
/// heard as quieter, garbled routed playback; these assert the per-frame
/// mapping instead. No audio hardware is touched — buffers are built by hand.
final class AppVolumeMixerRenderTests: XCTestCase {

    /// One interleaved float buffer wrapped in an AudioBufferList.
    private final class BufferList {
        let list: UnsafeMutableAudioBufferListPointer
        let data: UnsafeMutablePointer<Float32>
        let capacity: Int

        init(channels: Int, samples: [Float32]) {
            capacity = samples.count
            data = UnsafeMutablePointer<Float32>.allocate(capacity: max(capacity, 1))
            for (index, sample) in samples.enumerated() {
                data[index] = sample
            }
            list = AudioBufferList.allocate(maximumBuffers: 1)
            list[0] = AudioBuffer(
                mNumberChannels: UInt32(channels),
                mDataByteSize: UInt32(capacity * MemoryLayout<Float32>.size),
                mData: UnsafeMutableRawPointer(data)
            )
        }

        convenience init(channels: Int, count: Int, fill: Float32) {
            self.init(channels: channels, samples: [Float32](repeating: fill, count: count))
        }

        var samples: [Float32] {
            (0..<capacity).map { data[$0] }
        }

        var byteSize: UInt32 { list[0].mDataByteSize }

        deinit {
            free(list.unsafeMutablePointer)
            data.deallocate()
        }
    }

    private func render(input: BufferList, output: BufferList, gain: Float) {
        AppVolumeMixerAudioEngine.render(
            inputData: UnsafePointer(input.list.unsafeMutablePointer),
            outputData: output.list.unsafeMutablePointer,
            gain: gain
        )
    }

    // MARK: - Matched layouts (raw copy fast path)

    func testMatchedStereoUnityGainIsBitExact() {
        let input = BufferList(channels: 2, samples: [0.1, -0.2, 0.3, -0.4])
        let output = BufferList(channels: 2, count: 4, fill: 9)
        render(input: input, output: output, gain: 1)
        XCTAssertEqual(output.samples, [0.1, -0.2, 0.3, -0.4])
        XCTAssertEqual(output.byteSize, 16)
    }

    func testMatchedStereoAppliesGain() {
        let input = BufferList(channels: 2, samples: [0.5, -0.5, 1.0, -1.0])
        let output = BufferList(channels: 2, count: 4, fill: 9)
        render(input: input, output: output, gain: 0.5)
        XCTAssertEqual(output.samples, [0.25, -0.25, 0.5, -0.5])
    }

    // MARK: - Stereo tap into a multichannel output

    func testStereoToFiveOneFeedsFrontsAndSilencesRest() {
        // Two stereo frames (L, R) must land on the first two channels of each
        // 6-channel frame — not be smeared across the first 4 samples.
        let input = BufferList(channels: 2, samples: [0.1, 0.2, 0.3, 0.4])
        let output = BufferList(channels: 6, count: 12, fill: 9)
        render(input: input, output: output, gain: 1)
        XCTAssertEqual(output.samples, [
            0.1, 0.2, 0, 0, 0, 0,
            0.3, 0.4, 0, 0, 0, 0
        ])
        XCTAssertEqual(output.byteSize, 48)
    }

    func testStereoToFiveOneAppliesGain() {
        let input = BufferList(channels: 2, samples: [0.5, -0.5])
        let output = BufferList(channels: 6, count: 6, fill: 9)
        render(input: input, output: output, gain: 0.5)
        XCTAssertEqual(output.samples, [0.25, -0.25, 0, 0, 0, 0])
    }

    func testStereoToFiveOneZeroGainIsSilence() {
        let input = BufferList(channels: 2, samples: [0.5, -0.5, 0.5, -0.5])
        let output = BufferList(channels: 6, count: 12, fill: 9)
        render(input: input, output: output, gain: 0)
        XCTAssertEqual(output.samples, [Float32](repeating: 0, count: 12))
    }

    func testStereoIntoLongerMultichannelBufferZeroFillsTail() {
        // One stereo input frame, room for two 6-channel output frames: the
        // unfed second frame must be silence, and the reported byte size must
        // cover only the rendered frames (mirroring the raw-copy path).
        let input = BufferList(channels: 2, samples: [0.1, 0.2])
        let output = BufferList(channels: 6, count: 12, fill: 9)
        render(input: input, output: output, gain: 1)
        XCTAssertEqual(output.samples, [
            0.1, 0.2, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0
        ])
        XCTAssertEqual(output.byteSize, 24)
    }

    // MARK: - Mono endpoints

    func testStereoToMonoAveragesThePair() {
        let input = BufferList(channels: 2, samples: [0.4, 0.2, -0.4, -0.2])
        let output = BufferList(channels: 1, count: 2, fill: 9)
        render(input: input, output: output, gain: 1)
        XCTAssertEqual(output.samples[0], 0.3, accuracy: 1e-6)
        XCTAssertEqual(output.samples[1], -0.3, accuracy: 1e-6)
    }

    func testStereoToMonoAppliesGain() {
        let input = BufferList(channels: 2, samples: [0.4, 0.2])
        let output = BufferList(channels: 1, count: 1, fill: 9)
        render(input: input, output: output, gain: 0.5)
        XCTAssertEqual(output.samples[0], 0.15, accuracy: 1e-6)
    }

    func testMonoToStereoFansOutToBothChannels() {
        let input = BufferList(channels: 1, samples: [0.5, -0.25])
        let output = BufferList(channels: 2, count: 4, fill: 9)
        render(input: input, output: output, gain: 1)
        XCTAssertEqual(output.samples, [0.5, 0.5, -0.25, -0.25])
    }
}
