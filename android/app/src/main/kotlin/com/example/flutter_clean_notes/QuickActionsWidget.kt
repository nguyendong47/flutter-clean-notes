package com.example.flutter_clean_notes

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

class QuickActionsWidget : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        appWidgetIds.forEach { widgetId ->
            val views = RemoteViews(context.packageName, R.layout.widget_quick_actions).apply {
                val newNoteIntent = HomeWidgetLaunchIntent.getActivity(
                    context,
                    MainActivity::class.java,
                    Uri.parse("clean-notes://new")
                )
                setOnClickPendingIntent(R.id.widget_btn_new, newNoteIntent)

                val checklistIntent = HomeWidgetLaunchIntent.getActivity(
                    context,
                    MainActivity::class.java,
                    Uri.parse("clean-notes://new?template=checklist")
                )
                setOnClickPendingIntent(R.id.widget_btn_checklist, checklistIntent)

                val searchIntent = HomeWidgetLaunchIntent.getActivity(
                    context,
                    MainActivity::class.java,
                    Uri.parse("clean-notes://search")
                )
                setOnClickPendingIntent(R.id.widget_btn_search, searchIntent)

                val pinnedIntent = HomeWidgetLaunchIntent.getActivity(
                    context,
                    MainActivity::class.java,
                    Uri.parse("clean-notes://pinned")
                )
                setOnClickPendingIntent(R.id.widget_btn_pinned, pinnedIntent)
            }
            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }
}
