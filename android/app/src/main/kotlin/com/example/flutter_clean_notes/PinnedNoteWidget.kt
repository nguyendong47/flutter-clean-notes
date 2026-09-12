package com.example.flutter_clean_notes

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
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

        val rowIds = intArrayOf(
            R.id.widget_item_row_0,
            R.id.widget_item_row_1,
            R.id.widget_item_row_2,
            R.id.widget_item_row_3,
            R.id.widget_item_row_4
        )
        val checkIds = intArrayOf(
            R.id.widget_item_check_0,
            R.id.widget_item_check_1,
            R.id.widget_item_check_2,
            R.id.widget_item_check_3,
            R.id.widget_item_check_4
        )
        val textIds = intArrayOf(
            R.id.widget_item_text_0,
            R.id.widget_item_text_1,
            R.id.widget_item_text_2,
            R.id.widget_item_text_3,
            R.id.widget_item_text_4
        )

        appWidgetIds.forEach { widgetId ->
            val views = RemoteViews(context.packageName, R.layout.widget_pinned_note).apply {
                if (hasPinned) {
                    setViewVisibility(R.id.widget_pinned_active_layout, View.VISIBLE)
                    setViewVisibility(R.id.widget_pinned_empty_layout, View.GONE)

                    setTextViewText(
                        R.id.widget_pinned_title,
                        if (title.isNotBlank()) title else "Ghi chú đã ghim"
                    )

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
                    setOnClickPendingIntent(R.id.widget_pinned_action_edit, openNoteIntent)

                    val jsonArray = try {
                        JSONArray(checklistJson)
                    } catch (_: Exception) {
                        JSONArray()
                    }

                    if (jsonArray.length() > 0) {
                        // Display interactive checklist rows
                        setViewVisibility(R.id.widget_pinned_body, View.GONE)
                        setViewVisibility(R.id.widget_pinned_checklist_container, View.VISIBLE)

                        for (i in 0 until 5) {
                            if (i < jsonArray.length()) {
                                setViewVisibility(rowIds[i], View.VISIBLE)
                                val item = jsonArray.getJSONObject(i)
                                val isDone = item.optBoolean("done", false)
                                val text = item.optString("text", "")

                                setTextViewText(textIds[i], text)
                                if (isDone) {
                                    setImageViewResource(checkIds[i], R.drawable.ic_widget_checkbox_checked)
                                    setTextColor(textIds[i], 0x80FFFFFF.toInt())
                                } else {
                                    setImageViewResource(checkIds[i], R.drawable.ic_widget_checkbox_unchecked)
                                    setTextColor(textIds[i], 0xE0FFFFFF.toInt())
                                }

                                // Interactive toggle click on checkbox
                                val toggleUri = Uri.parse("clean-notes://toggle-check?id=$noteId&index=$i")
                                val toggleIntent = Intent(context, ChecklistToggleReceiver::class.java).apply {
                                    data = toggleUri
                                    action = "es.antonborri.home_widget.action.BACKGROUND"
                                }
                                val requestCode = (noteId.hashCode() * 31 + i) and 0x7FFFFFFF
                                val togglePendingIntent = PendingIntent.getBroadcast(
                                    context,
                                    requestCode,
                                    toggleIntent,
                                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                                )
                                setOnClickPendingIntent(checkIds[i], togglePendingIntent)

                                // Tapping the text opens the note in editor
                                setOnClickPendingIntent(textIds[i], openNoteIntent)
                            } else {
                                setViewVisibility(rowIds[i], View.GONE)
                            }
                        }

                        if (jsonArray.length() > 5) {
                            setViewVisibility(R.id.widget_item_more, View.VISIBLE)
                            setTextViewText(R.id.widget_item_more, "+ ${jsonArray.length() - 5} mục khác...")
                            setOnClickPendingIntent(R.id.widget_item_more, openNoteIntent)
                        } else {
                            setViewVisibility(R.id.widget_item_more, View.GONE)
                        }
                    } else {
                        // Plain note preview
                        setViewVisibility(R.id.widget_pinned_checklist_container, View.GONE)
                        setViewVisibility(R.id.widget_pinned_body, View.VISIBLE)
                        setTextViewText(
                            R.id.widget_pinned_body,
                            if (content.isNotBlank()) content else "Không có nội dung"
                        )
                        setOnClickPendingIntent(R.id.widget_pinned_body, openNoteIntent)
                    }
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
}
