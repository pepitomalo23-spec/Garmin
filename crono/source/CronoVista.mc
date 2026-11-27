import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Timer;
import Toybox.WatchUi;

// Pantalla principal (280 × 280, redonda, sin táctil).
//   CRONO ●            ← nombre y punto de sincronización
//   EN MARCHA          ← estado
//   05:07.42           ← tiempo (grande) con centésimas
//   Vuelta 3  1:02.1   ← vuelta en curso
//   Anterior 1:01.88   ← última vuelta cerrada
//   Último 12:34.56    ← último registro guardado
//   Sincronizado       ← estado del envío a pj.fire
// La pantalla se repinta cada 50 ms en marcha y cada segundo parada; el
// tiempo no depende de eso (Cronometro calcula el tiempo real).
class CronoVista extends WatchUi.View {

    private var _timer;
    private var _periodo as Number = 0;

    function initialize() {
        View.initialize();
        _timer = new Timer.Timer();
    }

    function onShow() as Void {
        _periodo = 0;
        ajustarTimer();
        app().sincro.intentar(false);
        avisarDirecto(false);
    }

    function onHide() as Void {
        _timer.stop();
        _periodo = 0;
    }

    function ajustarTimer() as Void {
        var p = (app().crono.estado == E_MARCHA) ? 50 : 1000;
        if (p != _periodo) {
            _timer.stop();
            _timer.start(method(:tick), p, true);
            _periodo = p;
        }
    }

    function tick() as Void {
        var c = app().crono as Cronometro;
        c.afinarAncla();
        if (app().directo != null) {
            var d = app().directo as Directo;
            d.afinarBase();
            d.alTick(c);
        }
        var s = app().sincro as SincroPrimerPlano;
        if (s.pend > 0 && !s.enviando) { s.intentar(false); }
        WatchUi.requestUpdate();
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        var c = app().crono as Cronometro;
        var s = app().sincro as SincroPrimerPlano;
        var t = c.transcurrido();
        var J = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;

        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        // Nombre y punto de sincronización
        var est = estadoSincro(s);
        var yT = h * 11 / 100;
        var tw = dc.getTextWidthInPixels("CRONO", Graphics.FONT_XTINY);
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx - 7, yT, Graphics.FONT_XTINY, "CRONO", J);
        dc.setColor(est[1] as Number, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(cx - 7 + tw / 2 + 10, yT, 5);

        // Estado
        var yE = h * 21 / 100;
        var txtE = "PREPARADO";
        var colE = Graphics.COLOR_LT_GRAY;
        if (c.estado == E_MARCHA) { txtE = "EN MARCHA"; colE = Graphics.COLOR_GREEN; }
        else if (c.estado == E_PAUSA) { txtE = "PAUSA"; colE = Graphics.COLOR_ORANGE; }
        dc.setColor(colE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, yE, Graphics.FONT_TINY, txtE, J);

        // Tiempo grande
        dibujarTiempo(dc, cx, h * 43 / 100, w - 44, t,
            (c.estado == E_PAUSA) ? Graphics.COLOR_ORANGE : Graphics.COLOR_WHITE);

        // Vueltas / ayuda
        var y1 = h * 63 / 100;
        var y2 = h * 72 / 100;
        var nv = c.parciales.size();
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        if (c.estado == E_LISTO) {
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, y1, Graphics.FONT_XTINY, "START para empezar", J);
        } else if (nv > 0) {
            dc.drawText(cx, y1, Graphics.FONT_TINY, "Vuelta " + (nv + 1).toString() + "  " + textoTiempo(c.vueltaActual()), J);
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, y2, Graphics.FONT_XTINY, "Anterior " + textoTiempo(c.ultimaVuelta()), J);
        } else {
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, y1, Graphics.FONT_XTINY, (c.estado == E_MARCHA) ? "BACK marca vuelta" : "Sin vueltas", J);
        }

        // Último registro
        var y3 = h * 81 / 100;
        if (s.mensaje != null) {
            dc.setColor(Graphics.COLOR_RED, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, y3, Graphics.FONT_XTINY, s.mensaje as String, J);
        } else if (c.estado == E_LISTO && c.ultimo != null) {
            var u = c.ultimo as Dictionary;
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, y3, Graphics.FONT_XTINY, "Último " + textoTiempo(Almacen.num(u["dur"])), J);
        } else if (c.estado == E_PAUSA) {
            dc.setColor(Graphics.COLOR_ORANGE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, y3, Graphics.FONT_XTINY, "START sigue - BACK fin", J);
        }

        // Sincronización
        dc.setColor(est[1] as Number, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 89 / 100, Graphics.FONT_XTINY, est[0] as String, J);
    }

    // Minutos:segundos en grande y las centésimas más pequeñas a la derecha.
    // Elige la letra más grande que quepa en «ancho».
    function dibujarTiempo(dc as Graphics.Dc, cx as Number, cy as Number, ancho as Number, ms as Number, color) as Void {
        var p = partesTiempo(ms);
        var principal = p[0] as String;
        var cent = p[1] as String;
        var grandes = [Graphics.FONT_NUMBER_THAI_HOT, Graphics.FONT_NUMBER_HOT, Graphics.FONT_NUMBER_MEDIUM, Graphics.FONT_NUMBER_MILD];
        var peques = [Graphics.FONT_NUMBER_MEDIUM, Graphics.FONT_NUMBER_MILD, Graphics.FONT_NUMBER_MILD, Graphics.FONT_SMALL];
        var fG = grandes[3];
        var fP = peques[3];
        var wG = 0;
        var wP = 0;
        for (var i = 0; i < grandes.size(); i++) {
            fG = grandes[i];
            fP = peques[i];
            wG = dc.getTextWidthInPixels(principal, fG);
            wP = dc.getTextWidthInPixels(cent, fP);
            if (wG + 10 + wP <= ancho) { break; }
        }
        var hG = dc.getFontHeight(fG);
        var hP = dc.getFontHeight(fP);
        var x0 = cx - (wG + 10 + wP) / 2;
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x0, cy, fG, principal, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        // centésimas alineadas abajo con los números grandes
        var yP = cy + (hG - hP) * 30 / 100;
        dc.fillCircle(x0 + wG + 4, yP + hP * 22 / 100, 3);
        dc.drawText(x0 + wG + 10, yP, fP, cent, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
    }
}

// [texto, color] del estado de sincronización.
function estadoSincro(s as SincroPrimerPlano) as Array {
    var gris = Graphics.COLOR_LT_GRAY;
    var naranja = Graphics.COLOR_ORANGE;
    var rojo = Graphics.COLOR_RED;
    var verde = Graphics.COLOR_GREEN;
    var cod = s.ultimoCod;
    var n = s.pend;
    if (Almacen.clave().length() < 20) { return ["Falta la clave", rojo]; }
    if (s.enviando) { return ["Enviando...", Graphics.COLOR_BLUE]; }
    if (cod == 401) { return ["Clave no válida", rojo]; }
    if (n > 0) {
        if (cod == Almacen.SIN_MOVIL || cod == -104 || cod == -2 || cod == -3) {
            return ["Sin móvil - " + n.toString() + " pend.", naranja];
        }
        if (cod >= 500) { return ["Error servidor - " + n.toString(), naranja]; }
        return [n.toString() + " sin enviar", naranja];
    }
    if (cod == 200) { return ["Sincronizado", verde]; }
    if (cod == Almacen.SIN_MOVIL || cod == -104) { return ["Sin móvil", gris]; }
    if (cod == 404) { return ["Dirección mal", rojo]; }
    if (cod != 0) { return ["Sin conexión (" + cod.toString() + ")", gris]; }
    return ["Nada pendiente", gris];
}
