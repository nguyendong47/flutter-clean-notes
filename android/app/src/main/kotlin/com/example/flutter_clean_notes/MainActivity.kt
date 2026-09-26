package com.example.flutter_clean_notes

import android.content.Intent
import android.util.Log
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onNewIntent(intent: Intent) {
        setIntent(intent)
        super.onNewIntent(intent)
        Log.d("MainActivity", "onNewIntent delivered: data=" + intent.data + " action=" + intent.action)
    }
}
