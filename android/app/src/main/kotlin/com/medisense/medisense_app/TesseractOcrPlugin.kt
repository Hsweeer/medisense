package com.medisense.medisense_app

import android.graphics.BitmapFactory
import android.os.Handler
import android.os.Looper
import com.googlecode.tesseract.android.TessBaseAPI
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import java.io.File

/**
 * Direct native bridge to the real Tesseract OCR engine.
 *
 * This talks straight to Tesseract4Android's TessBaseAPI, which is a
 * compiled build of the actual tesseract-ocr/tesseract + tesseract-ocr/
 * leptonica C++ source (see https://github.com/adaptech-cz/Tesseract4Android,
 * itself a maintained fork of Google's tess-two). No Flutter/Dart OCR
 * package is involved anywhere in this path — this class + its Dart-side
 * MethodChannel counterpart (lib/core/services/native_tesseract_ocr.dart)
 * ARE the whole integration.
 */
class TesseractOcrPlugin : FlutterPlugin, MethodCallHandler {

    private lateinit var channel: MethodChannel
    private val mainHandler = Handler(Looper.getMainLooper())

    companion object {
        const val CHANNEL = "com.medisense.medisense_app/tesseract_ocr"
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, CHANNEL)
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "extractText" -> extractText(call, result)
            else -> result.notImplemented()
        }
    }

    private fun extractText(call: MethodCall, result: Result) {
        val imagePath = call.argument<String>("imagePath")
        val tessdataParentPath = call.argument<String>("tessdataParentPath")
        val language = call.argument<String>("language")

        if (imagePath == null || tessdataParentPath == null || language == null) {
            result.error(
                "BAD_ARGS",
                "imagePath, tessdataParentPath and language are all required",
                null
            )
            return
        }

        // Tesseract's native calls are blocking and must not run on the
        // Flutter/UI thread, so we do the work on a plain background
        // thread and hop back to the main thread only to deliver the
        // MethodChannel result (required by the Flutter engine).
        Thread {
            try {
                val text = runTesseract(imagePath, tessdataParentPath, language)
                mainHandler.post { result.success(text) }
            } catch (e: Exception) {
                mainHandler.post {
                    result.error("OCR_FAILED", e.message ?: e.toString(), null)
                }
            }
        }.start()
    }

    private fun runTesseract(
        imagePath: String,
        tessdataParentPath: String,
        language: String
    ): String {
        val bitmap = BitmapFactory.decodeFile(imagePath)
            ?: throw IllegalArgumentException("Could not decode image at $imagePath")

        // TessBaseAPI expects `tessdataParentPath` to be the folder that
        // CONTAINS a "tessdata" subfolder — it looks for
        // "<tessdataParentPath>/tessdata/<language>.traineddata" itself.
        val tessDataDir = File(tessdataParentPath, "tessdata")
        val langFile = File(tessDataDir, "$language.traineddata")
        if (!langFile.exists()) {
            throw IllegalStateException(
                "Missing language data: ${langFile.absolutePath} — this language " +
                    "hasn't been downloaded/installed yet."
            )
        }

        val api = TessBaseAPI()
        try {
            // tessdata_fast files (what this app downloads) only contain
            // LSTM-engine data, so we must force OEM_LSTM_ONLY — the
            // default combined/legacy engine mode fails on these files.
            val initialized =
                api.init(tessdataParentPath, language, TessBaseAPI.OEM_LSTM_ONLY)
            if (!initialized) {
                throw IllegalStateException(
                    "Tesseract failed to initialize for '$language'. Check that " +
                        "${langFile.absolutePath} is a valid, complete .traineddata file."
                )
            }
            api.pageSegMode = TessBaseAPI.PageSegMode.PSM_AUTO
            api.setImage(bitmap)
            return api.getUTF8Text() ?: ""
        } finally {
            bitmap.recycle()
        }
    }
}