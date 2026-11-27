import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.WatchUi;

const TIPOS = ["Libre", "Carrera", "Natación", "Series", "Fuerza", "Otro"];
const FILAS_REG = 4;     // vueltas a la vista en el detalle de un registro

// Botones de la pantalla principal (el Fenix 6X Pro no tiene pantalla táctil):
//   START (arriba dcha.)   preparado → empieza · en marcha → pausa · en pausa → sigue
//   BACK  (abajo dcha.)    en marcha → vuelta · en pausa → Guardar / Seguir / Descartar
//                          preparado → sale de la app
//   UP mantenido (MENU)    menú: registros, sincronizar, estado, salir
//   DOWN                   preparado → registros guardados en el reloj
class CronoDelegado extends WatchUi.BehaviorDelegate {

    function initialize() {
        BehaviorDelegate.initialize();
    }

    function onSelect() as Boolean {
        var a = app();
        var c = a.crono as Cronometro;
        var s = a.sincro as SincroPrimerPlano;
        s.mensaje = null;
        if (c.estado == E_LISTO) { c.iniciar(); aviso(1); }
        else if (c.estado == E_MARCHA) { c.pausar(); aviso(2); }
        else { c.reanudar(); aviso(1); }
        (a.vista as CronoVista).ajustarTimer();
        WatchUi.requestUpdate();
        return true;
    }

    function onBack() as Boolean {
        var c = app().crono as Cronometro;
        if (c.estado == E_MARCHA) {
            if (c.vuelta()) { aviso(3); }
            WatchUi.requestUpdate();
            return true;
        }
        if (c.estado == E_PAUSA) {
            abrirMenuFin();
            return true;
        }
        return false;   // preparado: salir de la app
    }

    function onMenu() as Boolean {
        abrirMenuPrincipal();
        return true;
    }

    function onNextPage() as Boolean {
        if ((app().crono as Cronometro).estado == E_LISTO) {
            abrirRegistros();
            return true;
        }
        return false;
    }
}

// ---------- Fin de la sesión (BACK en pausa) ----------
function abrirMenuFin() as Void {
    var m = new WatchUi.Menu2({:title => "Sesión"});
    m.addItem(new WatchUi.MenuItem("Guardar", "Elegir tipo y guardar", :guardar, null));
    m.addItem(new WatchUi.MenuItem("Seguir", "Reanudar el crono", :seguir, null));
    m.addItem(new WatchUi.MenuItem("Descartar", "Borrar sin guardar", :descartar, null));
    WatchUi.pushView(m, new MenuFinDelegado(), WatchUi.SLIDE_UP);
}

class MenuFinDelegado extends WatchUi.Menu2InputDelegate {
    function initialize() {
        Menu2InputDelegate.initialize();
    }

    function onSelect(item) as Void {
        var id = item.getId();
        WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);
        if (id == :guardar) {
            abrirMenuTipo();
        } else if (id == :seguir) {
            (app().crono as Cronometro).reanudar();
            aviso(1);
            (app().vista as CronoVista).ajustarTimer();
        } else if (id == :descartar) {
            WatchUi.pushView(new WatchUi.Confirmation("¿Descartar la sesión?"), new DescartarDelegado(), WatchUi.SLIDE_IMMEDIATE);
        }
        WatchUi.requestUpdate();
    }
}

class DescartarDelegado extends WatchUi.ConfirmationDelegate {
    function initialize() {
        ConfirmationDelegate.initialize();
    }

    function onResponse(respuesta) as Boolean {
        if (respuesta == WatchUi.CONFIRM_YES) {
            (app().crono as Cronometro).reiniciar();
            (app().vista as CronoVista).ajustarTimer();
            WatchUi.requestUpdate();
        }
        return true;
    }
}

// ---------- Tipo de sesión y guardar ----------
function abrirMenuTipo() as Void {
    var m = new WatchUi.Menu2({:title => "Tipo"});
    for (var i = 0; i < TIPOS.size(); i++) {
        m.addItem(new WatchUi.MenuItem(TIPOS[i] as String, null, i, null));
    }
    WatchUi.pushView(m, new MenuTipoDelegado(), WatchUi.SLIDE_UP);
}

class MenuTipoDelegado extends WatchUi.Menu2InputDelegate {
    function initialize() {
        Menu2InputDelegate.initialize();
    }

    function onSelect(item) as Void {
        var i = item.getId() as Number;
        WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);
        guardarSesion(TIPOS[i] as String);
    }
}

// Guarda en el reloj (primero) y luego intenta mandarlo. Si la memoria del
// reloj falla, el crono se queda en pausa con su tiempo: no se pierde nada.
function guardarSesion(tipo as String) as Void {
    var a = app();
    var c = a.crono as Cronometro;
    var s = a.sincro as SincroPrimerPlano;
    var reg = c.registro(tipo);
    try {
        Almacen.guardarNuevo(reg);
    } catch (e) {
        s.mensaje = "Memoria llena: sincroniza";
        WatchUi.requestUpdate();
        return;
    }
    c.reiniciar();
    c.ultimo = reg;
    s.mensaje = null;
    s.recontar();
    aviso(2);
    (a.vista as CronoVista).ajustarTimer();
    programarFondo();
    s.intentar(true);
    WatchUi.requestUpdate();
}

// ---------- Menú principal (UP mantenido) ----------
function abrirMenuPrincipal() as Void {
    var a = app();
    var c = a.crono as Cronometro;
    var s = a.sincro as SincroPrimerPlano;
    var m = new WatchUi.Menu2({:title => "Crono"});
    m.addItem(new WatchUi.MenuItem("Registros", Almacen.ids().size().toString() + " en el reloj", :registros, null));
    m.addItem(new WatchUi.MenuItem("Sincronizar ahora", s.pend.toString() + " sin enviar", :sincronizar, null));
    m.addItem(new WatchUi.MenuItem("Estado", "Clave, móvil, envíos", :estado, null));
    if (c.estado != E_LISTO) {
        m.addItem(new WatchUi.MenuItem("Salir", "El crono sigue contando", :salir, null));
    }
    WatchUi.pushView(m, new MenuPrincipalDelegado(), WatchUi.SLIDE_UP);
}

class MenuPrincipalDelegado extends WatchUi.Menu2InputDelegate {
    function initialize() {
        Menu2InputDelegate.initialize();
    }

    function onSelect(item) as Void {
        var id = item.getId();
        WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);
        if (id == :registros) {
            abrirRegistros();
        } else if (id == :sincronizar) {
            (app().sincro as SincroPrimerPlano).intentar(true);
        } else if (id == :estado) {
            WatchUi.pushView(new EstadoVista(), new WatchUi.BehaviorDelegate(), WatchUi.SLIDE_LEFT);
        } else if (id == :salir) {
            (app().crono as Cronometro).persistir();
            System.exit();
        }
    }
}

// ---------- Registros guardados en el reloj ----------
function fechaCorta(epoch as Number) as String {
    var d = Gregorian.info(new Time.Moment(epoch), Time.FORMAT_SHORT);
    return (d.day as Number).format("%02d") + "/" + (d.month as Number).format("%02d") + " " +
        (d.hour as Number).format("%02d") + ":" + (d.min as Number).format("%02d");
}

function textoEstado(r as Dictionary) as String {
    var e = Almacen.num(r["est"]);
    if (e == Almacen.ENVIADO) { return "enviado"; }
    if (e == Almacen.RECHAZADO) { return "rechazado"; }
    return "pendiente";
}

function abrirRegistros() as Void {
    var l = Almacen.ids();
    var m = new WatchUi.Menu2({:title => "Registros"});
    if (l.size() == 0) {
        m.addItem(new WatchUi.MenuItem("Sin registros", "Guarda una sesión", :nada, null));
    }
    for (var i = 0; i < l.size(); i++) {
        var r = Almacen.leer(l[i] as String);
        if (r != null) {
            m.addItem(new WatchUi.MenuItem(
                textoTiempo(Almacen.num(r["dur"])) + " " + (r["tipo"] as String),
                fechaCorta(Almacen.num(r["inicio"])) + " " + textoEstado(r),
                l[i], null));
        }
    }
    WatchUi.pushView(m, new RegistrosDelegado(), WatchUi.SLIDE_LEFT);
}

class RegistrosDelegado extends WatchUi.Menu2InputDelegate {
    function initialize() {
        Menu2InputDelegate.initialize();
    }

    function onSelect(item) as Void {
        var id = item.getId();
        if (!(id instanceof String)) { return; }
        var r = Almacen.leer(id as String);
        if (r == null) { return; }
        var v = new RegistroVista(r);
        WatchUi.pushView(v, new RegistroDelegado(v), WatchUi.SLIDE_LEFT);
    }
}

// Detalle de un registro: total, fecha y vueltas (UP/DOWN para moverse).
class RegistroVista extends WatchUi.View {
    var reg as Dictionary;
    var desde as Number = 0;

    function initialize(r as Dictionary) {
        View.initialize();
        reg = r;
    }

    function nVueltas() as Number {
        var v = reg["vueltas"];
        return (v instanceof Array) ? (v as Array).size() : 0;
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        var J = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 12 / 100, Graphics.FONT_XTINY, (reg["tipo"] as String) + " - " + textoEstado(reg), J);
        dc.drawText(cx, h * 21 / 100, Graphics.FONT_XTINY, fechaCorta(Almacen.num(reg["inicio"])), J);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 34 / 100, Graphics.FONT_MEDIUM, textoTiempo(Almacen.num(reg["dur"])), J);

        var n = nVueltas();
        if (n == 0) {
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, h * 55 / 100, Graphics.FONT_XTINY, "Sin vueltas", J);
        } else {
            var vs = reg["vueltas"] as Array;
            var ps = (reg["parciales"] instanceof Array) ? reg["parciales"] as Array : vs;
            for (var i = 0; i < FILAS_REG && desde + i < n; i++) {
                var k = desde + i;
                var y = h * (50 + i * 10) / 100;
                dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
                dc.drawText(cx - 58, y, Graphics.FONT_XTINY, "V" + (k + 1).toString(), J);
                dc.drawText(cx + 4, y, Graphics.FONT_XTINY, textoTiempo(Almacen.num(vs[k])), J);
                dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
                dc.drawText(cx + 70, y, Graphics.FONT_XTINY, (k < ps.size()) ? textoTiempo(Almacen.num(ps[k])) : "", J);
            }
            if (n > FILAS_REG) {
                dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
                dc.drawText(cx, h * 90 / 100, Graphics.FONT_XTINY, (desde + 1).toString() + "-" + (desde + FILAS_REG < n ? desde + FILAS_REG : n).toString() + " de " + n.toString(), J);
            }
        }
        if (Almacen.num(reg["est"]) == Almacen.RECHAZADO && reg["motivo"] instanceof String) {
            dc.setColor(Graphics.COLOR_RED, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, h * 90 / 100, Graphics.FONT_XTINY, reg["motivo"] as String, J);
        }
    }
}

class RegistroDelegado extends WatchUi.BehaviorDelegate {
    private var _v as RegistroVista;

    function initialize(v as RegistroVista) {
        BehaviorDelegate.initialize();
        _v = v;
    }

    function onNextPage() as Boolean {
        var max = _v.nVueltas() - FILAS_REG;
        if (_v.desde < max) { _v.desde = _v.desde + 1; WatchUi.requestUpdate(); }
        return true;
    }

    function onPreviousPage() as Boolean {
        if (_v.desde > 0) { _v.desde = _v.desde - 1; WatchUi.requestUpdate(); }
        return true;
    }
}

// Estado: versión, clave, móvil, pendientes y último envío.
class EstadoVista extends WatchUi.View {
    function initialize() {
        View.initialize();
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        var h = dc.getHeight();
        var cx = dc.getWidth() / 2;
        var J = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;
        var s = app().sincro as SincroPrimerPlano;
        var clave = Almacen.clave();
        var sy = Almacen.estadoSync();
        var ok = Almacen.num(sy["ok"]);
        var hace = "nunca";
        if (ok > 0) {
            var min = (Time.now().value() - ok) / 60;
            hace = (min < 1) ? "ahora mismo" : ((min < 60) ? "hace " + min.toString() + " min" : fechaCorta(ok));
        }
        var lineas = [
            "Crono pj.fire " + Almacen.VERSION_APP,
            (clave.length() >= 20) ? "Clave: ..." + clave.substring(clave.length() - 4, clave.length()) : "Clave: falta",
            System.getDeviceSettings().phoneConnected ? "Móvil: conectado" : "Móvil: no conectado",
            "Sin enviar: " + s.pend.toString(),
            "Último envío: " + hace,
            "Resultado: " + s.ultimoCod.toString()
        ];
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();
        for (var i = 0; i < lineas.size(); i++) {
            dc.setColor(i == 0 ? Graphics.COLOR_WHITE : Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, h * (22 + i * 11) / 100, Graphics.FONT_XTINY, lineas[i] as String, J);
        }
    }
}
