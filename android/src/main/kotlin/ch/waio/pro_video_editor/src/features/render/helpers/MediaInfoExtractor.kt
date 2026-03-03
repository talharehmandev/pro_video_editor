package ch.waio.pro_video_editor.src.features.render.helpers

import RENDER_TAG
import android.media.MediaExtractor
import android.media.MediaFormat
import android.util.Log
import androidx.media3.common.util.UnstableApi

/**
 * Utility class for extracting media information from video and audio files.
 *
 * Provides methods to extract duration, channel count, and sample rate
 * using Android's MediaExtractor API.
 */
@UnstableApi
object MediaInfoExtractor {

    /**
     * Retrieves video duration from file.
     *
     * @param videoPath Absolute path to video file
     * @return Duration in microseconds, or 0 if not found
     */
    fun getVideoDuration(videoPath: String): Long {
        return try {
            val extractor = MediaExtractor()
            extractor.setDataSource(videoPath)
            var duration = 0L

            for (i in 0 until extractor.trackCount) {
                val format = extractor.getTrackFormat(i)
                val mime = format.getString(MediaFormat.KEY_MIME) ?: ""
                if (mime.startsWith("video/")) {
                    duration = format.getLong(MediaFormat.KEY_DURATION)
                    break
                }
            }

            extractor.release()
            duration
        } catch (e: Exception) {
            Log.e(RENDER_TAG, "Failed to get video duration for $videoPath: ${e.message}")
            0L
        }
    }

    /**
     * Retrieves video dimensions from file.
     *
     * @param videoPath Absolute path to video file
     * @return Pair of (width, height), or null if not found
     */
    fun getVideoDimensions(videoPath: String): Pair<Int, Int>? {
        return try {
            val extractor = MediaExtractor()
            extractor.setDataSource(videoPath)
            var dimensions: Pair<Int, Int>? = null

            for (i in 0 until extractor.trackCount) {
                val format = extractor.getTrackFormat(i)
                val mime = format.getString(MediaFormat.KEY_MIME) ?: ""
                if (mime.startsWith("video/")) {
                    val width = format.getInteger(MediaFormat.KEY_WIDTH)
                    val height = format.getInteger(MediaFormat.KEY_HEIGHT)
                    dimensions = Pair(width, height)
                    break
                }
            }

            extractor.release()
            dimensions
        } catch (e: Exception) {
            Log.e(RENDER_TAG, "Failed to get video dimensions for $videoPath: ${e.message}")
            null
        }
    }

    /**
     * Retrieves audio duration from file.
     *
     * @param audioPath Absolute path to audio file
     * @return Duration in microseconds, or 0 if not found
     */
    fun getAudioDuration(audioPath: String): Long {
        return try {
            val extractor = MediaExtractor()
            extractor.setDataSource(audioPath)
            var duration = 0L

            for (i in 0 until extractor.trackCount) {
                val format = extractor.getTrackFormat(i)
                val mime = format.getString(MediaFormat.KEY_MIME) ?: ""
                if (mime.startsWith("audio/")) {
                    duration = format.getLong(MediaFormat.KEY_DURATION)
                    Log.d(RENDER_TAG, "Audio duration: ${duration / 1000} ms")
                    break
                }
            }

            extractor.release()
            duration
        } catch (e: Exception) {
            Log.e(RENDER_TAG, "Failed to get audio duration: ${e.message}")
            0L
        }
    }

    /**
     * Detects the number of audio channels in a video file.
     *
     * @param videoPath Absolute path to video file
     * @return Number of channels (1=mono, 2=stereo, 6=5.1), or null if not found
     */
    fun getAudioChannelCount(videoPath: String): Int? {
        return try {
            val extractor = MediaExtractor()
            extractor.setDataSource(videoPath)
            var channelCount: Int? = null

            for (i in 0 until extractor.trackCount) {
                val format = extractor.getTrackFormat(i)
                val mime = format.getString(MediaFormat.KEY_MIME) ?: ""
                if (mime.startsWith("audio/")) {
                    channelCount = format.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
                    Log.d(RENDER_TAG, "File $videoPath: $channelCount audio channels")
                    break
                }
            }

            extractor.release()
            channelCount
        } catch (e: Exception) {
            Log.e(RENDER_TAG, "Failed to detect audio channels for $videoPath: ${e.message}")
            null
        }
    }

    /**
     * Detects sample rate of an audio file.
     *
     * @param audioPath Absolute path to audio file
     * @return Sample rate in Hz (e.g., 48000), or 0 if not found
     */
    fun getAudioSampleRate(audioPath: String): Int {
        return try {
            val extractor = MediaExtractor()
            extractor.setDataSource(audioPath)
            var sampleRate = 0

            for (i in 0 until extractor.trackCount) {
                val format = extractor.getTrackFormat(i)
                val mime = format.getString(MediaFormat.KEY_MIME) ?: ""
                if (mime.startsWith("audio/")) {
                    sampleRate = format.getInteger(MediaFormat.KEY_SAMPLE_RATE)
                    Log.d(RENDER_TAG, "Audio sample rate: $sampleRate Hz")
                    break
                }
            }

            extractor.release()
            sampleRate
        } catch (e: Exception) {
            Log.e(RENDER_TAG, "Failed to detect audio sample rate: ${e.message}")
            0
        }
    }
}
