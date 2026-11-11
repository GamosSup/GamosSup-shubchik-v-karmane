package io.github.gamossup.shubchik

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews

class PlannerWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        for (id in ids) {
            val views = RemoteViews(context.packageName, R.layout.shubchik_widget)
            views.setOnClickPendingIntent(R.id.widget_tasks, launch(context, "planner", 1))
            views.setOnClickPendingIntent(R.id.widget_focus, launch(context, "focus", 2))
            manager.updateAppWidget(id, views)
        }
    }

    private fun launch(context: Context, section: String, code: Int): PendingIntent {
        val intent = Intent(context, MainActivity::class.java)
            .putExtra("widget_section", section)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        return PendingIntent.getActivity(
            context, code, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }
}
