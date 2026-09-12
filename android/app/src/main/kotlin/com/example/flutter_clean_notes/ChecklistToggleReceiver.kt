package com.example.flutter_clean_notes

import android.appwidget.AppWidgetManager
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import es.antonborri.home_widget.HomeWidgetBackgroundWorker
import es.antonborri.home_widget.HomeWidgetPlugin
import io.flutter.FlutterInjector
import org.json.JSONArray

class ChecklistToggleReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val uri: Uri? = intent.data
        if (uri != null && uri.scheme == "clean-notes" && uri.host == "toggle-check") {
            val indexStr = uri.getQueryParameter("index")
            val index = indexStr?.toIntOrNull()

            // 1. Instant optimistic update in SharedPreferences & RemoteViews (~5-20ms)
            if (index != null) {
                try {
                    val prefs = HomeWidgetPlugin.getData(context)
                    val checklistJson = prefs.getString("widget_pinned_checklist", "[]") ?: "[]"
                    val jsonArray = JSONArray(checklistJson)
                    if (index in 0 until jsonArray.length()) {
                        val item = jsonArray.getJSONObject(index)
                        val isDone = item.optBoolean("done", false)
                        item.put("done", !isDone)
                        val updatedJson = jsonArray.toString()
                        prefs.edit().putString("widget_pinned_checklist", updatedJson).commit()

                        val appWidgetManager = AppWidgetManager.getInstance(context)
                        val component = ComponentName(context, PinnedNoteWidget::class.java)
                        val appWidgetIds = appWidgetManager.getAppWidgetIds(component)
                        if (appWidgetIds.isNotEmpty()) {
                            val widget = PinnedNoteWidget()
                            widget.onUpdate(context, appWidgetManager, appWidgetIds, prefs)
                        }
                    }
                } catch (_: Exception) {
                    // Fall back to background worker
                }
            }
        }

        // 2. Dispatch to Flutter Background Worker to update SQLite persistence
        try {
            val flutterLoader = FlutterInjector.instance().flutterLoader()
            flutterLoader.startInitialization(context)
            flutterLoader.ensureInitializationComplete(context, null)
            HomeWidgetBackgroundWorker.enqueueWork(context, intent)
        } catch (_: Exception) {
            // Background dispatch fallback
        }
    }
}
