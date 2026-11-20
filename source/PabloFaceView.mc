import Toybox.Activity;
import Toybox.ActivityMonitor;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.WatchUi;

// Esfera "Pablo Face": hora grande, fecha, pulso, pasos con anillo de objetivo y bateria.
// Funciona en pantallas redondas, cuadradas, MIP y AMOLED (con modo de bajo consumo).
class PabloFaceView extends WatchUi.WatchFace {

    const ACCENT = 0xFF8800;   // naranja
    const SOFT   = 0xAAAAAA;   // gris claro
    const RING_BG = 0x333333;  // fondo del anillo

    private var _lowPower as Boolean = false;

    function initialize() {
        WatchFace.initialize();
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        var cy = h / 2;

        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        var timeStr = getTimeString();

        // AMOLED en reposo: dibujo minimo para respetar la proteccion contra quemado.
        if (_lowPower && needsBurnInProtection()) {
            var t = Time.now().value();
            var dx = (t / 60) % 7 - 3;   // desplazamiento lento para no quemar pixeles
            dc.setColor(SOFT, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx + dx, cy + dx, Graphics.FONT_MEDIUM, timeStr,
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            return;
        }

        // Anillo de progreso de pasos
        var info = ActivityMonitor.getInfo();
        var steps = (info.steps != null) ? info.steps as Number : 0;
        var goal = (info.stepGoal != null && (info.stepGoal as Number) > 0) ? info.stepGoal as Number : 10000;
        var frac = steps.toFloat() / goal.toFloat();
        if (frac > 1.0) { frac = 1.0; }

        var r = ((w < h) ? w : h) / 2 - 6;
        dc.setPenWidth(6);
        dc.setColor(RING_BG, Graphics.COLOR_TRANSPARENT);
        dc.drawCircle(cx, cy, r);
        if (frac >= 1.0) {
            dc.setColor(ACCENT, Graphics.COLOR_TRANSPARENT);
            dc.drawCircle(cx, cy, r);
        } else if (frac > 0.0) {
            dc.setColor(ACCENT, Graphics.COLOR_TRANSPARENT);
            var endDeg = 90 - (360.0 * frac).toNumber();
            dc.drawArc(cx, cy, r, Graphics.ARC_CLOCKWISE, 90, endDeg);
        }
        dc.setPenWidth(1);

        // Fecha
        var now = Gregorian.info(Time.now(), Time.FORMAT_MEDIUM);
        var dateStr = Lang.format("$1$ $2$ $3$", [now.day_of_week, now.day, now.month]);
        dc.setColor(SOFT, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, cy - (h * 0.30).toNumber(), Graphics.FONT_SMALL, dateStr,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // Hora
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, cy - (h * 0.04).toNumber(), Graphics.FONT_NUMBER_HOT, timeStr,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // Pulso y pasos
        var hr = getHeartRate();
        var hrStr = (hr != null) ? hr.toString() : "--";
        dc.setColor(ACCENT, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx - (w * 0.17).toNumber(), cy + (h * 0.20).toNumber(), Graphics.FONT_SMALL, hrStr,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx + (w * 0.17).toNumber(), cy + (h * 0.20).toNumber(), Graphics.FONT_SMALL, steps.toString(),
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        dc.setColor(SOFT, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx - (w * 0.17).toNumber(), cy + (h * 0.29).toNumber(), Graphics.FONT_XTINY, "PPM",
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.drawText(cx + (w * 0.17).toNumber(), cy + (h * 0.29).toNumber(), Graphics.FONT_XTINY, "PASOS",
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // Bateria
        var battery = System.getSystemStats().battery;
        var batStr = battery.toNumber().toString() + "%";
        dc.setColor((battery < 20.0) ? Graphics.COLOR_RED : SOFT, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, cy + (h * 0.39).toNumber(), Graphics.FONT_XTINY, batStr,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    private function getTimeString() as String {
        var clock = System.getClockTime();
        var hour = clock.hour;
        if (!System.getDeviceSettings().is24Hour) {
            hour = hour % 12;
            if (hour == 0) { hour = 12; }
        }
        return Lang.format("$1$:$2$", [hour.format("%02d"), clock.min.format("%02d")]);
    }

    private function getHeartRate() as Number? {
        var act = Activity.getActivityInfo();
        if (act != null && act.currentHeartRate != null) {
            return act.currentHeartRate;
        }
        if (ActivityMonitor has :getHeartRateHistory) {
            var it = ActivityMonitor.getHeartRateHistory(1, true);
            var sample = it.next();
            if (sample != null && sample.heartRate != ActivityMonitor.INVALID_HR_SAMPLE) {
                return sample.heartRate;
            }
        }
        return null;
    }

    private function needsBurnInProtection() as Boolean {
        var s = System.getDeviceSettings();
        if (s has :requiresBurnInProtection) {
            return s.requiresBurnInProtection;
        }
        return false;
    }

    function onEnterSleep() as Void {
        _lowPower = true;
        WatchUi.requestUpdate();
    }

    function onExitSleep() as Void {
        _lowPower = false;
        WatchUi.requestUpdate();
    }
}
