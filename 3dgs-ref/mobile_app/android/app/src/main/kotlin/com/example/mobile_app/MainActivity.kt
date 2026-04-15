package com.example.mobile_app

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.IOException
import java.util.UUID

class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL_NAME = "com.example.mobile_app/native_camera"
        private const val REQUEST_CAPTURE_HIGH_QUALITY_VIDEO = 24051
    }

    private var pendingCaptureResult: MethodChannel.Result? = null
    private var pendingVideoFile: File? = null
    private var pendingVideoUri: Uri? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL_NAME,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "captureHighQualityVideo" -> launchHighQualityVideoCapture(call, result)
                else -> result.notImplemented()
            }
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == REQUEST_CAPTURE_HIGH_QUALITY_VIDEO) {
            handleVideoCaptureResult(resultCode)
            return
        }
        super.onActivityResult(requestCode, resultCode, data)
    }

    private fun launchHighQualityVideoCapture(call: MethodCall, result: MethodChannel.Result) {
        if (pendingCaptureResult != null) {
            result.error("already_active", "A native camera capture is already in progress.", null)
            return
        }

        val maxDurationSeconds =
            (call.argument<Number>("maxDurationSeconds")?.toInt() ?: 60).coerceAtLeast(1)

        val videoFile =
            try {
                createTemporaryVideoFile()
            } catch (error: IOException) {
                result.error("file_creation_failed", "Unable to create a temporary video file.", error.message)
                return
            }

        val videoUri =
            FileProvider.getUriForFile(
                this,
                "$packageName.native_camera_provider",
                videoFile,
            )

        val intent =
            Intent(MediaStore.ACTION_VIDEO_CAPTURE).apply {
                putExtra(MediaStore.EXTRA_OUTPUT, videoUri)
                putExtra(MediaStore.EXTRA_VIDEO_QUALITY, 1)
                putExtra(MediaStore.EXTRA_DURATION_LIMIT, maxDurationSeconds)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
            }

        grantUriPermissions(intent, videoUri)
        pendingCaptureResult = result
        pendingVideoFile = videoFile
        pendingVideoUri = videoUri

        try {
            startActivityForResult(intent, REQUEST_CAPTURE_HIGH_QUALITY_VIDEO)
        } catch (error: ActivityNotFoundException) {
            clearPendingCapture(deleteFile = true)
            result.error("no_available_camera", "No native camera app is available.", error.message)
        } catch (error: Exception) {
            clearPendingCapture(deleteFile = true)
            result.error("camera_launch_failed", "Unable to launch the native camera.", error.message)
        }
    }

    private fun handleVideoCaptureResult(resultCode: Int) {
        val result = pendingCaptureResult
        val videoFile = pendingVideoFile
        val videoUri = pendingVideoUri

        clearPendingCapture(deleteFile = resultCode != Activity.RESULT_OK)

        if (result == null) {
            return
        }

        if (videoUri != null) {
            revokeUriPermission(
                videoUri,
                Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION,
            )
        }

        if (resultCode == Activity.RESULT_OK && videoFile != null && videoFile.exists() && videoFile.length() > 0) {
            result.success(videoFile.absolutePath)
        } else {
            if (videoFile != null && videoFile.exists()) {
                videoFile.delete()
            }
            result.success(null)
        }
    }

    private fun clearPendingCapture(deleteFile: Boolean) {
        val staleFile = pendingVideoFile
        pendingCaptureResult = null
        pendingVideoFile = null
        pendingVideoUri = null
        if (deleteFile && staleFile != null && staleFile.exists()) {
            staleFile.delete()
        }
    }

    @Throws(IOException::class)
    private fun createTemporaryVideoFile(): File {
        val directory = File(cacheDir, "native_camera")
        if (!directory.exists()) {
            directory.mkdirs()
        }
        return File.createTempFile(UUID.randomUUID().toString(), ".mp4", directory)
    }

    private fun grantUriPermissions(intent: Intent, contentUri: Uri) {
        val compatibleActivities =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                packageManager.queryIntentActivities(
                    intent,
                    PackageManager.ResolveInfoFlags.of(PackageManager.MATCH_DEFAULT_ONLY.toLong()),
                )
            } else {
                @Suppress("DEPRECATION")
                packageManager.queryIntentActivities(intent, PackageManager.MATCH_DEFAULT_ONLY)
            }

        compatibleActivities.forEach { info ->
            grantUriPermission(
                info.activityInfo.packageName,
                contentUri,
                Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION,
            )
        }
    }
}
