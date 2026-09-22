package com.example.flutter_clean_notes

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Intent
import android.util.Log
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onNewIntent(intent: Intent) {
        setIntent(intent)
        super.onNewIntent(intent)
        Log.d("MainActivity", "onNewIntent delivered: data=" + intent.data + " action=" + intent.action)
        if (intent.action == "clean-notes.action.PIN_QUICK_ACTIONS") {
            pinWidget(QuickActionsWidget::class.java)
        } else if (intent.action == "clean-notes.action.PIN_PINNED_NOTE") {
            pinWidget(PinnedNoteWidget::class.java)
        }
    }

    private fun pinWidget(cls: Class<*>) {
        val appWidgetManager = AppWidgetManager.getInstance(this)
        if (appWidgetManager.isRequestPinAppWidgetSupported) {
            val provider = ComponentName(this, cls)
            appWidgetManager.requestPinAppWidget(provider, null, null)
            Log.d("MainActivity", "requestPinAppWidget requested for " + cls.simpleName)
        }
    }
}
