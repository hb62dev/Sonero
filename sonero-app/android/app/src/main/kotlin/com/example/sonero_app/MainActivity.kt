package com.example.sonero_app

import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMuxer
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.IOException
import java.nio.ByteBuffer
import kotlin.concurrent.thread

class MainActivity : com.ryanheise.audioservice.AudioServiceActivity() {
    private val CHANNEL = "com.example.sonero/media"

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "mergeVideoAndAudio") {
                val videoPath = call.argument<String>("videoPath")
                val audioPath = call.argument<String>("audioPath")
                val outputPath = call.argument<String>("outputPath")

                if (videoPath == null || audioPath == null || outputPath == null) {
                    result.error("INVALID_ARGUMENTS", "Path parameters cannot be null", null)
                    return@setMethodCallHandler
                }

                thread {
                    try {
                        val success = mergeAudioVideo(videoPath, audioPath, outputPath)
                        runOnUiThread {
                            if (success) {
                                result.success(true)
                            } else {
                                result.error("MUX_FAILED", "Muxing video and audio tracks failed", null)
                            }
                        }
                    } catch (e: Exception) {
                        runOnUiThread {
                            result.error("ERROR", e.message, null)
                        }
                    }
                }
            } else {
                result.notImplemented()
            }
        }
    }

    private fun mergeAudioVideo(videoPath: String, audioPath: String, outputPath: String): Boolean {
        var videoExtractor: MediaExtractor? = null
        var audioExtractor: MediaExtractor? = null
        var muxer: MediaMuxer? = null

        try {
            videoExtractor = MediaExtractor()
            videoExtractor.setDataSource(videoPath)

            audioExtractor = MediaExtractor()
            audioExtractor.setDataSource(audioPath)

            muxer = MediaMuxer(outputPath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)

            // Select video track
            var videoTrackIndex = -1
            for (i in 0 until videoExtractor.trackCount) {
                val format = videoExtractor.getTrackFormat(i)
                val mime = format.getString(MediaFormat.KEY_MIME) ?: ""
                if (mime.startsWith("video/")) {
                    videoExtractor.selectTrack(i)
                    videoTrackIndex = muxer.addTrack(format)
                    break
                }
            }

            // Select audio track
            var audioTrackIndex = -1
            for (i in 0 until audioExtractor.trackCount) {
                val format = audioExtractor.getTrackFormat(i)
                val mime = format.getString(MediaFormat.KEY_MIME) ?: ""
                if (mime.startsWith("audio/")) {
                    audioExtractor.selectTrack(i)
                    audioTrackIndex = muxer.addTrack(format)
                    break
                }
            }

            if (videoTrackIndex == -1 || audioTrackIndex == -1) {
                return false
            }

            muxer.start()

            // Mux video
            val videoBuffer = ByteBuffer.allocate(1024 * 1024)
            val videoBufferInfo = MediaCodec.BufferInfo()
            while (true) {
                videoBufferInfo.offset = 0
                videoBufferInfo.size = videoExtractor.readSampleData(videoBuffer, 0)
                if (videoBufferInfo.size < 0) {
                    videoBufferInfo.size = 0
                    break
                }
                videoBufferInfo.presentationTimeUs = videoExtractor.sampleTime
                videoBufferInfo.flags = videoExtractor.sampleFlags
                muxer.writeSampleData(videoTrackIndex, videoBuffer, videoBufferInfo)
                videoExtractor.advance()
            }

            // Mux audio
            val audioBuffer = ByteBuffer.allocate(1024 * 1024)
            val audioBufferInfo = MediaCodec.BufferInfo()
            while (true) {
                audioBufferInfo.offset = 0
                audioBufferInfo.size = audioExtractor.readSampleData(audioBuffer, 0)
                if (audioBufferInfo.size < 0) {
                    audioBufferInfo.size = 0
                    break
                }
                audioBufferInfo.presentationTimeUs = audioExtractor.sampleTime
                audioBufferInfo.flags = audioExtractor.sampleFlags
                muxer.writeSampleData(audioTrackIndex, audioBuffer, audioBufferInfo)
                audioExtractor.advance()
            }

            return true

        } catch (e: Exception) {
            e.printStackTrace()
            return false
        } finally {
            try {
                videoExtractor?.release()
                audioExtractor?.release()
                muxer?.stop()
                muxer?.release()
            } catch (e: Exception) {
                // ignore
            }
        }
    }
}
