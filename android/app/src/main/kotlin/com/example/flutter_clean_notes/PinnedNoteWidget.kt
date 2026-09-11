package com.example.flutter_clean_notes

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider
import org.json.JSONArray

class PinnedNoteWidget : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        val hasPinned = widgetData.getBoolean("widget_has_pinned", false)
        val noteId = widgetData.getString("widget_pinned_id", "") ?: ""
        val title = widgetData.getString("widget_pinned_title", "") ?: ""
        val content = widgetData.getString("widget_pinned_content", "") ?: ""
        val checklistJson = widgetData.getString("widget_pinned_checklist", "[]") ?: "[]"

        appWidgetIds.forEach { widgetId ->
            val views = RemoteViews(context.packageName, R.layout.widget_pinned_note).apply {
                if (hasPinned) {
                    setViewVisibility(R.id.widget_pinned_active_layout, View.VISIBLE)
                    setViewVisibility(R.id.widget_pinned_empty_layout, View.GONE)

                    setTextViewText(
                        R.id.widget_pinned_title,
                        if (title.isNotBlank()) title else "Ghi chú đã ghim"
                    )

                    val bodyText = formatBodyText(content, checklistJson)
                    setTextViewText(R.id.widget_pinned_body, bodyText)

                    val targetUri = if (noteId.isNotBlank()) {
                        Uri.parse("clean-notes://note?id=$noteId")
                    } else {
                        Uri.parse("clean-notes://new")
                    }

                    val openNoteIntent = HomeWidgetLaunchIntent.getActivity(
                        context,
                        MainActivity::class.java,
                        targetUri
                    )
                    setOnClickPendingIntent(R.id.widget_pinned_root, openNoteIntent)
                    setOnClickPendingIntent(R.id.widget_pinned_active_layout, openNoteIntent)
                    setOnClickPendingIntent(R.id.widget_pinned_body, openNoteIntent)
                    setOnClickPendingIntent(R.id.widget_pinned_action_edit, openNoteIntent)
                } else {
                    setViewVisibility(R.id.widget_pinned_active_layout, View.GONE)
                    setViewVisibility(R.id.widget_pinned_empty_layout, View.VISIBLE)

                    val newNoteIntent = HomeWidgetLaunchIntent.getActivity(
                        context,
                        MainActivity::class.java,
                        Uri.parse("clean-notes://new")
                    )
                    setOnClickPendingIntent(R.id.widget_pinned_root, newNoteIntent)
                    setOnClickPendingIntent(R.id.widget_btn_empty_create, newNoteIntent)
                }
            }
            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }

    private fun formatBodyText(content: String, checklistJson: String): String {
        try {
            val jsonArray = JSONArray(checklistJson)
            if (jsonArray.length() > 0) {
                val sb = StringBuilder()
                for (i in 0 until jsonArray.length()) {
                    val item = jsonArray.getJSONObject(i)
                    val isDone = item.optBoolean("done", false)
                    val text = item.optString("text", "")
                    val icon = if (isDone) "☑ " else "☐ "
                    sb.append(icon).append(text)
                    if (i < jsonArray.length() - 1) sb.append("\n")
                }
                return sb.toString()
            }
        } catch (_: Exception) {
            // Fall back to plain content
        }
        return if (content.isNotBlank()) content else "Không có nội dung"
    }
}
