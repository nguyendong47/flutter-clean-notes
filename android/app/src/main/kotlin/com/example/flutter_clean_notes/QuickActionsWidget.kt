package com.example.flutter_clean_notes

import android.app.ActivityOptions
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.net.Uri
import android.os.Build
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
                setOnClickPendingIntent(
                    R.id.widget_btn_new,
                    createLaunchIntent(context, Uri.parse("clean-notes://new"), 101)
                )
                setOnClickPendingIntent(
                    R.id.widget_btn_checklist,
                    createLaunchIntent(context, Uri.parse("clean-notes://new?template=checklist"), 102)
                )
                setOnClickPendingIntent(
                    R.id.widget_btn_search,
                    createLaunchIntent(context, Uri.parse("clean-notes://search"), 103)
                )
                setOnClickPendingIntent(
                    R.id.widget_btn_pinned,
                    createLaunchIntent(context, Uri.parse("clean-notes://pinned"), 104)
                )
            }
            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }

    private fun createLaunchIntent(context: Context, uri: Uri, requestCode: Int): PendingIntent {
        val intent = Intent(context, MainActivity::class.java).apply {
            data = uri
            action = HomeWidgetLaunchIntent.HOME_WIDGET_LAUNCH_ACTION
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        var flags = PendingIntent.FLAG_UPDATE_CURRENT
        if (Build.VERSION.SDK_INT >= 23) {
            flags = flags or PendingIntent.FLAG_IMMUTABLE
        }
        if (Build.VERSION.SDK_INT >= 34) {
            val options = ActivityOptions.makeBasic()
            if (Build.VERSION.SDK_INT >= 35) {
                options.setPendingIntentCreatorBackgroundActivityStartMode(
                    ActivityOptions.MODE_BACKGROUND_ACTIVITY_START_ALLOWED
                )
            } else {
                options.pendingIntentBackgroundActivityStartMode =
                    ActivityOptions.MODE_BACKGROUND_ACTIVITY_START_ALLOWED
            }
            return PendingIntent.getActivity(context, requestCode, intent, flags, options.toBundle())
        }
        return PendingIntent.getActivity(context, requestCode, intent, flags)
    }
}
