import AVFoundation
import Foundation

/// Determines the appropriate AVAssetExportSession preset based on requested bitrate.
///
/// Since AVAssetExportSession doesn't support direct bitrate control, this function
/// maps bitrate values to the closest quality preset. Higher bitrates select higher
/// resolution/quality presets.
///
/// - Parameters:
///   - requestedBitrate: Target bitrate in bits per second. If nil, returns highest quality.
///   - sourceResolution: The resolution of the source video, used to pick a sensible default.
///   - presetHint: Optional preset hint (currently unused).
/// - Returns: AVAssetExportPreset string matching the requested quality level.
public func applyBitrate(
    requestedBitrate: Int?,
    sourceResolution: CGSize? = nil,
    presetHint: String? = nil
) -> String {
    if let bitrate = requestedBitrate {
        print("[\(Tags.render)] 📊 Requested bitrate: \(bitrate) bps (\(String(format: "%.1f", Double(bitrate) / 1_000_000)) Mbps)")
        print("[\(Tags.render)] ⚠️ AVAssetExportSession does not support custom bitrate directly - using closest preset")
    }

    if let bitrate = requestedBitrate {
        if bitrate >= 50_000_000 {
            if #available(macOS 12.1, *) {
                return AVAssetExportPresetHEVC7680x4320 // 8K
            }
        } else if bitrate >= 40_000_000 {
            if #available(macOS 10.13, *) {
                return AVAssetExportPresetHEVC3840x2160 // 4K HEVC
            } else {
                return AVAssetExportPreset3840x2160 // 4K H264
            }
        } else if bitrate >= 30_000_000 {
            if #available(macOS 10.13, *) {
                return AVAssetExportPresetHEVC1920x1080 // 1080p HEVC
            } else {
                return AVAssetExportPreset1920x1080 // 1080p H264
            }
        } else if bitrate >= 20_000_000 {
            if #available(macOS 10.13, *) {
                return AVAssetExportPresetHEVCHighestQuality
            } else {
                return AVAssetExportPresetHighestQuality
            }
        } else if bitrate >= 10_000_000 {
            return AVAssetExportPresetHighestQuality
        } else if bitrate >= 7_000_000 {
            return AVAssetExportPreset1920x1080
        } else if bitrate >= 5_000_000 {
            return AVAssetExportPreset1280x720
        } else if bitrate >= 3_000_000 {
            return AVAssetExportPreset960x540
        } else if bitrate >= 2_000_000 {
            return AVAssetExportPreset640x480
        } else if bitrate >= 1_000_000 {
            return AVAssetExportPresetMediumQuality
        } else {
            return AVAssetExportPresetLowQuality
        }
    }

    // Default path when no bitrate is specified: Pick preset matching source resolution
    if let resolution = sourceResolution {
        let maxDim = max(resolution.width, resolution.height)
        print("[\(Tags.render)] ℹ️ No bitrate specified. Choosing preset based on source resolution (\(Int(resolution.width))x\(Int(resolution.height)))")
        
        if maxDim > 3840 {
            if #available(macOS 12.1, *) { return AVAssetExportPresetHEVC7680x4320 }
        } else if maxDim > 1920 {
            if #available(macOS 10.13, *) { return AVAssetExportPresetHEVC3840x2160 }
            return AVAssetExportPreset3840x2160
        } else if maxDim > 1280 {
            return AVAssetExportPreset1920x1080
        } else if maxDim > 960 {
            return AVAssetExportPreset1280x720
        } else if maxDim > 640 {
            return AVAssetExportPreset960x540
        }
        
        return AVAssetExportPresetMediumQuality
    }

    return AVAssetExportPresetHighestQuality
}
