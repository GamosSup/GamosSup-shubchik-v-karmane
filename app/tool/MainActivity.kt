package io.github.gamossup.shubchik

import android.content.ActivityNotFoundException
import android.content.Intent
import android.provider.CalendarContract
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "shubchik/calendar")
            .setMethodCallHandler { call, result ->
                if (call.method != "composeEvent") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val title = call.argument<String>("title")?.trim()
                val start = call.argument<Number>("start")?.toLong()
                val end = call.argument<Number>("end")?.toLong()
                if (title.isNullOrEmpty() || title.length > 120 || start == null || end == null || end <= start) {
                    result.error("invalid_event", "Invalid event details", null)
                    return@setMethodCallHandler
                }
                val intent = Intent(Intent.ACTION_INSERT, CalendarContract.Events.CONTENT_URI)
                    .putExtra(CalendarContract.Events.TITLE, title)
                    .putExtra(CalendarContract.EXTRA_EVENT_BEGIN_TIME, start)
                    .putExtra(CalendarContract.EXTRA_EVENT_END_TIME, end)
                try {
                    startActivity(intent)
                    result.success(null)
                } catch (_: ActivityNotFoundException) {
                    result.error("no_calendar", "No calendar app found", null)
                } catch (_: SecurityException) {
                    result.error("no_calendar", "The calendar app could not be opened", null)
                }
            }
    }
}
