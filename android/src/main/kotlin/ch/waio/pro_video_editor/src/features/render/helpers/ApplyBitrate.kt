import android.media.MediaCodecInfo
import android.media.MediaCodecList
import android.util.Log
import androidx.media3.common.util.UnstableApi
import androidx.media3.transformer.DefaultEncoderFactory
import androidx.media3.transformer.VideoEncoderSettings

/**
 * Configures video encoder bitrate settings.
 *
 * Validates bitrate against codec capabilities and selects optimal bitrate mode:
 * - CBR (Constant Bitrate) if supported - predictable file size
 * - VBR (Variable Bitrate) fallback - better quality at same average bitrate
 *
 * If no bitrate is specified, a sensible default is calculated based on resolution.
 *
 * @param encoderFactoryBuilder Encoder factory to configure
 * @param mimeType Video MIME type (e.g., "video/avc" for H.264)
 * @param requestedBitrate Target bitrate in bits per second (can be null)
 * @param width Video width for default bitrate calculation
 * @param height Video height for default bitrate calculation
 */
@UnstableApi
fun applyBitrate(
    encoderFactoryBuilder: DefaultEncoderFactory.Builder,
    mimeType: String?,
    requestedBitrate: Int?,
    width: Int? = null,
    height: Int? = null
) {
    // Determine target bitrate
    val bitrate = requestedBitrate ?: if (width != null && height != null) {
        val maxDim = maxOf(width, height)
        val calculated = when {
            maxDim > 1920 -> 15_000_000 // 4K-ish -> 15 Mbps
            maxDim > 1280 -> 10_000_000 // 1080p -> 10 Mbps
            maxDim > 960 -> 6_000_000  // 720p -> 6 Mbps
            maxDim > 640 -> 3_000_000  // 540p -> 3 Mbps
            else -> 1_500_000         // 480p or less -> 1.5 Mbps
        }
        Log.d(RENDER_TAG, "No bitrate specified. Using default for ${width}x${height}: ${calculated / 1000} kbps")
        calculated
    } else {
        return // Can't determine bitrate
    }

    Log.d(RENDER_TAG, "Configuring bitrate: ${bitrate / 1000} kbps")

    val codecInfo = MediaCodecList(MediaCodecList.ALL_CODECS)
        .codecInfos
        .firstOrNull { it.isEncoder && it.supportedTypes.contains(mimeType) }

    if (codecInfo == null) {
        Log.e(RENDER_TAG, "No encoder found for $mimeType")
        return
    }

    val capabilities = codecInfo.getCapabilitiesForType(mimeType)
    val bitrateRange = capabilities.videoCapabilities.bitrateRange
    val supportsCBR = capabilities.encoderCapabilities
        .isBitrateModeSupported(MediaCodecInfo.EncoderCapabilities.BITRATE_MODE_CBR)

    if (!bitrateRange.contains(bitrate)) {
        Log.e(
            RENDER_TAG,
            "Bitrate ${bitrate / 1000} kbps outside supported range: ${bitrateRange.lower / 1000}-${bitrateRange.upper / 1000} kbps"
        )
        return
    }

    val bitrateMode = if (supportsCBR) {
        Log.d(RENDER_TAG, "Using CBR (Constant Bitrate) mode")
        MediaCodecInfo.EncoderCapabilities.BITRATE_MODE_CBR
    } else {
        Log.d(RENDER_TAG, "CBR not supported, using VBR (Variable Bitrate) mode")
        MediaCodecInfo.EncoderCapabilities.BITRATE_MODE_VBR
    }

    val builder = VideoEncoderSettings.Builder()
        .setBitrateMode(bitrateMode)
        .setBitrate(bitrate)

    encoderFactoryBuilder.setRequestedVideoEncoderSettings(builder.build())
}
