import Toybox.Application;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.Time;

const E_LISTO = 0;
const E_MARCHA = 1;
const E_PAUSA = 2;
const MAX_VUELTAS = 200;
const VUELTA_MIN_MS = 400;      // dos pulsaciones más juntas = rebote del botón

// El cronómetro. No cuenta «ticks» de pantalla: guarda el momento en que
// arrancó (ancla) y calcula el tiempo real que ha pasado cada vez que se mira.
//   - Reloj fino: System.getTimer() (milisegundos desde que se encendió el reloj).
//   - Reloj de respaldo: Time.now() (segundos, hora real). Si el reloj se ha
//     reiniciado (getTimer vuelve a 0) o ha pasado algo raro, los dos no
//     cuadran y se usa el de respaldo: se pierden las centésimas de ese tramo,
//     pero no el tiempo.
// Todo se guarda en la memoria del reloj a cada cambio: si sales de la app, se
// apaga la pantalla o se reinicia el reloj, al volver sigue contando desde el
// mismo punto.
class Cronometro {

    var estado as Number = E_LISTO;
    var acum as Number = 0;          // ms contados antes del tramo actual
    var anclaT as Number = 0;        // System.getTimer() al arrancar el tramo
    var anclaE as Number = 0;        // Time.now() (s) al arrancar el tramo
    var inicio as Number = 0;        // hora real (s) de la primera salida
    var pausadoEn as Number = 0;     // hora real (s) de la última pausa
    var parciales as Array = [];     // ms acumulados en cada pulsación de vuelta
    var ultimo = null;               // último registro guardado (para la pantalla)

    function initialize() {
        cargar();
        var l = Almacen.ids();
        if (l.size() > 0) { ultimo = Almacen.leer(l[0] as String); }
    }

    function cargar() as Void {
        var d = Application.Storage.getValue("crono");
        if (!(d instanceof Dictionary)) { return; }
        estado = Almacen.num(d["e"]);
        acum = Almacen.num(d["a"]);
        anclaT = Almacen.num(d["aT"]);
        anclaE = Almacen.num(d["aE"]);
        inicio = Almacen.num(d["i"]);
        pausadoEn = Almacen.num(d["pE"]);
        parciales = (d["p"] instanceof Array) ? d["p"] as Array : [];
        if (estado != E_MARCHA && estado != E_PAUSA) { estado = E_LISTO; }
    }

    function persistir() as Void {
        Application.Storage.setValue("crono", {
            "e" => estado, "a" => acum, "aT" => anclaT, "aE" => anclaE,
            "i" => inicio, "pE" => pausadoEn, "p" => parciales
        });
    }

    // ms del tramo en marcha.
    function tramo() as Number {
        var dt = System.getTimer() - anclaT;
        var de = (Time.now().value() - anclaE) * 1000;
        var dif = dt - de;
        if (dif < 0) { dif = -dif; }
        if (dt >= 0 && dif <= 2000) { return dt; }
        return (de > 0) ? de : 0;
    }

    function transcurrido() as Number {
        return (estado == E_MARCHA) ? acum + tramo() : acum;
    }

    function anclar() as Void {
        anclaT = System.getTimer();
        anclaE = Time.now().value();
    }

    function iniciar() as Void {
        acum = 0;
        parciales = [];
        inicio = Time.now().value();
        pausadoEn = 0;
        anclar();
        estado = E_MARCHA;
        persistir();
    }

    function pausar() as Void {
        if (estado != E_MARCHA) { return; }
        acum = acum + tramo();
        pausadoEn = Time.now().value();
        estado = E_PAUSA;
        persistir();
    }

    function reanudar() as Void {
        if (estado != E_PAUSA) { return; }
        anclar();
        estado = E_MARCHA;
        persistir();
    }

    // Marca una vuelta. Devuelve false si se ignora (rebote o demasiadas).
    function vuelta() as Boolean {
        if (estado != E_MARCHA || parciales.size() >= MAX_VUELTAS) { return false; }
        var t = transcurrido();
        var antes = (parciales.size() > 0) ? parciales[parciales.size() - 1] as Number : 0;
        if (t - antes < VUELTA_MIN_MS) { return false; }
        parciales.add(t);
        persistir();
        return true;
    }

    function reiniciar() as Void {
        estado = E_LISTO;
        acum = 0;
        parciales = [];
        inicio = 0;
        pausadoEn = 0;
        persistir();
    }

    // Tiempo de la vuelta en curso y número de vuelta (1, 2, 3…).
    function vueltaActual() as Number {
        var antes = (parciales.size() > 0) ? parciales[parciales.size() - 1] as Number : 0;
        return transcurrido() - antes;
    }

    function ultimaVuelta() as Number {
        var n = parciales.size();
        if (n == 0) { return 0; }
        var a = parciales[n - 1] as Number;
        var b = (n > 1) ? parciales[n - 2] as Number : 0;
        return a - b;
    }

    // El registro para guardar (se llama en pausa).
    function registro(tipo as String) as Dictionary {
        var total = transcurrido();
        var vp = vueltasYParciales(parciales, total);
        var ahora = Time.now().value();
        var fin = (estado == E_PAUSA && pausadoEn > 0) ? pausadoEn : ahora;
        return {
            "id" => nuevoId(),
            "inicio" => (inicio > 0) ? inicio : ahora,
            "fin" => fin,
            "dur" => total,
            "vueltas" => vp[0],
            "parciales" => vp[1],
            "tipo" => tipo,
            "guardado" => ahora,
            "est" => Almacen.PENDIENTE
        };
    }
}

// Vueltas (lo que dura cada una) y parciales (acumulado al cerrar cada una).
// Si se ha pulsado vuelta al menos una vez, el tramo final hasta parar cuenta
// como la última vuelta. Sin pulsaciones: sin vueltas, solo el total.
function vueltasYParciales(par as Array, total as Number) as Array {
    var vueltas = [];
    var parc = [];
    if (par.size() == 0) { return [vueltas, parc]; }
    var antes = 0;
    for (var i = 0; i < par.size(); i++) {
        var p = par[i] as Number;
        vueltas.add(p - antes);
        parc.add(p);
        antes = p;
    }
    if (total > antes) {
        vueltas.add(total - antes);
        parc.add(total);
    }
    return [vueltas, parc];
}

// Id único del registro: hora + azar + temporizador (evita duplicados en el servidor).
function nuevoId() as String {
    var a = Math.rand() & 0xFFFFFF;
    var b = System.getTimer() & 0xFFFF;
    return "c" + Time.now().value().format("%x") + "-" + a.format("%06x") + b.format("%04x");
}

// [principal, centésimas]: "05:07" y "42"; con horas, "1:05:07" y "42".
function partesTiempo(ms as Number) as Array {
    if (ms < 0) { ms = 0; }
    var s = ms / 1000;
    var cs = (ms % 1000) / 10;
    var h = s / 3600;
    var m = (s % 3600) / 60;
    var seg = s % 60;
    var principal = (h > 0)
        ? h.toString() + ":" + m.format("%02d") + ":" + seg.format("%02d")
        : m.format("%02d") + ":" + seg.format("%02d");
    return [principal, cs.format("%02d")];
}

function textoTiempo(ms as Number) as String {
    var p = partesTiempo(ms);
    if (ms >= 3600000) { return p[0] as String; }
    return (p[0] as String) + "." + (p[1] as String);
}
