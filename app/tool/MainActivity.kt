package io.github.gamossup.shubchik

import android.Manifest
import android.app.NotificationManager
import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.provider.CalendarContract
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var pendingReminder: (() -> Unit)? = null
    private var pendingResult: MethodChannel.Result? = null
    private var widgetChannel: MethodChannel? = null
    private var pendingCalendar: (() -> Unit)? = null
    private var pendingCalendarResult: MethodChannel.Result? = null
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        widgetChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "shubchik/widget")
        widgetChannel?.setMethodCallHandler { call, result ->
            if (call.method == "getInitialSection") {
                val section = intent.getStringExtra("widget_section")
                intent.removeExtra("widget_section")
                result.success(section)
            } else {
                result.notImplemented()
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "shubchik/calendar")
            .setMethodCallHandler { call, result ->
                if (call.method == "listEvents") {
                    val from = call.argument<Number>("from")?.toLong()
                    val until = call.argument<Number>("until")?.toLong()
                    if (from == null || until == null || until <= from || until - from > 32L * 86400000) {
                        result.error("invalid_range", "Invalid calendar range", null)
                    } else {
                        listCalendarEvents(from, until, result)
                    }
                    return@setMethodCallHandler
                }
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
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "shubchik/reminders")
            .setMethodCallHandler { call, result ->
                if (call.method != "schedule" && call.method != "cancel") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val key = call.argument<String>("key")
                if (key == null || !key.matches(Regex("[a-zA-Z0-9_.:-]{1,100}"))) {
                    result.error("invalid_key", "Invalid reminder key", null)
                    return@setMethodCallHandler
                }
                if (call.method == "cancel") {
                    ReminderReceiver.cancel(this, key)
                    result.success(null)
                    return@setMethodCallHandler
                }
                val time = call.argument<Number>("time")?.toLong()
                if (time == null || time <= System.currentTimeMillis()) {
                    result.error("invalid_time", "Choose a future time", null)
                    return@setMethodCallHandler
                }
                val schedule = {
                    try {
                        if (time <= System.currentTimeMillis()) {
                            result.error("invalid_time", "Choose a future time", null)
                        } else if (!getSystemService(NotificationManager::class.java).areNotificationsEnabled()) {
                            result.error("notifications_disabled", "Notifications are disabled", null)
                        } else {
                            ReminderReceiver.schedule(this, key, time)
                            result.success(null)
                        }
                    } catch (_: Exception) {
                        result.error("schedule_failed", "Could not schedule the reminder", null)
                    }
                }
                if (Build.VERSION.SDK_INT >= 33 &&
                    checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
                ) {
                    if (pendingResult != null) {
                        result.error("permission_pending", "Notification permission request is in progress", null)
                    } else {
                        pendingResult = result
                        pendingReminder = schedule
                        requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 410)
                    }
                } else {
                    schedule()
                }
            }
    }

    private fun listCalendarEvents(from: Long, until: Long, result: MethodChannel.Result) {
        val read = {
            Thread {
                try {
                    val fields = arrayOf(
                        CalendarContract.Instances.BEGIN,
                        CalendarContract.Instances.END,
                        CalendarContract.Events.TITLE,
                        CalendarContract.Events.ALL_DAY,
                        CalendarContract.Calendars.CALENDAR_DISPLAY_NAME,
                    )
                    val events = mutableListOf<Map<String, Any>>()
                    CalendarContract.Instances.query(contentResolver, fields, from, until)?.use { cursor ->
                        while (events.size < 1000 && cursor.moveToNext()) {
                            events.add(mapOf(
                                "start" to cursor.getLong(0), "end" to cursor.getLong(1),
                                "title" to (cursor.getString(2) ?: ""),
                                "allDay" to (cursor.getInt(3) == 1),
                                "calendar" to (cursor.getString(4) ?: ""),
                            ))
                        }
                    }
                    runOnUiThread { result.success(events) }
                } catch (_: Exception) {
                    runOnUiThread { result.error("calendar_unavailable", "Cannot read calendar", null) }
                }
            }.start()
        }
        if (checkSelfPermission(Manifest.permission.READ_CALENDAR) == PackageManager.PERMISSION_GRANTED) {
            read()
        } else if (pendingCalendarResult == null) {
            pendingCalendar = read
            pendingCalendarResult = result
            requestPermissions(arrayOf(Manifest.permission.READ_CALENDAR), 411)
        } else {
            result.error("permission_pending", "Calendar permission request is in progress", null)
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val section = intent.getStringExtra("widget_section") ?: return
        widgetChannel?.invokeMethod("openSection", section, object : MethodChannel.Result {
            override fun success(result: Any?) { intent.removeExtra("widget_section") }
            override fun error(code: String, message: String?, details: Any?) {}
            override fun notImplemented() {}
        })
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 411) {
            val read = pendingCalendar
            val result = pendingCalendarResult
            pendingCalendar = null
            pendingCalendarResult = null
            if (grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED) {
                read?.invoke()
            } else {
                result?.error("calendar_denied", "Calendar permission was denied", null)
            }
            return
        }
        if (requestCode != 410) return
        val result = pendingResult
        val schedule = pendingReminder
        pendingResult = null
        pendingReminder = null
        if (grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED) {
            schedule?.invoke()
        } else {
            result?.error("notifications_disabled", "Notification permission was denied", null)
        }
    }
}
