import Toybox.Application;
import Toybox.Lang;
import Toybox.System;
import Toybox.Test;
import Toybox.Time;

// Pruebas automáticas (solo en el simulador: monkeyc --unit-test + monkeydo -t).
// No entran en la app que va al reloj.

(:test)
function pruebaFormatoTiempo(logger as Logger) as Boolean {
    var a = partesTiempo(307420);          // 5:07.42
    var b = partesTiempo(3723456);         // 1:02:03.45
    var c = partesTiempo(0);
    logger.debug(a[0] + "." + a[1] + " | " + b[0] + "." + b[1] + " | " + textoTiempo(61990));
    return (a[0] as String).equals("05:07") && (a[1] as String).equals("42")
        && (b[0] as String).equals("1:02:03") && (b[1] as String).equals("45")
        && (c[0] as String).equals("00:00") && (c[1] as String).equals("00")
        && textoTiempo(61990).equals("01:01.99");
}

(:test)
function pruebaVueltasYParciales(logger as Logger) as Boolean {
    var vp = vueltasYParciales([60100, 122130], 185230);
    var v = vp[0] as Array;
    var p = vp[1] as Array;
    logger.debug("vueltas " + v.toString() + " parciales " + p.toString());
    var sinVueltas = vueltasYParciales([], 45000);
    return v.size() == 3 && v[0] == 60100 && v[1] == 62030 && v[2] == 63100
        && p.size() == 3 && p[2] == 185230
        && (sinVueltas[0] as Array).size() == 0;
}

// Tiempo real: el tramo se calcula desde el ancla, no desde la pantalla.
(:test)
function pruebaTiempoReal(logger as Logger) as Boolean {
    var c = new Cronometro();
    c.estado = E_MARCHA;
    c.acum = 1000;
    c.anclaT = System.getTimer() - 5000;
    c.anclaE = Time.now().value() - 5;
    var t1 = c.transcurrido();               // ~6000 con el temporizador fino
    // Reloj reiniciado: getTimer «vuelve a empezar» (el ancla queda en el futuro).
    c.anclaT = System.getTimer() + 100000;
    c.anclaE = Time.now().value() - 3600;
    var t2 = c.transcurrido();               // 1000 + 3 600 000 con la hora real
    logger.debug("normal " + t1.toString() + " tras reinicio " + t2.toString());
    return t1 >= 5900 && t1 <= 7100 && t2 >= 3600000 && t2 <= 3603000;
}

(:test)
function pruebaPausaYVueltas(logger as Logger) as Boolean {
    var c = new Cronometro();
    c.iniciar();
    c.anclaT = c.anclaT - 2000;              // como si llevara 2 s
    c.anclaE = c.anclaE - 2;
    var ok1 = c.vuelta();
    var ok2 = c.vuelta();                     // rebote: ignorada
    c.pausar();
    var enPausa = c.transcurrido();
    var reg = c.registro("Carrera");
    logger.debug("pausa " + enPausa.toString() + " reg " + reg.toString());
    c.reiniciar();
    return ok1 && !ok2 && enPausa >= 1900 && enPausa <= 3100
        && (reg["vueltas"] as Array).size() >= 1 && (reg["tipo"] as String).equals("Carrera")
        && reg["est"] == Almacen.PENDIENTE && c.estado == E_LISTO;
}

// Nunca se borra un pendiente al podar; los enviados viejos sí.
(:test)
function pruebaAlmacen(logger as Logger) as Boolean {
    Application.Storage.clearValues();
    var base = Time.now().value();
    for (var i = 0; i < 45; i++) {
        Almacen.guardarNuevo({
            "id" => "test" + i.format("%04d"), "inicio" => base + i, "fin" => base + i + 10,
            "dur" => 10000, "vueltas" => [], "parciales" => [], "tipo" => "Libre",
            "guardado" => base + i, "est" => Almacen.PENDIENTE
        });
        if (i < 30 && i % 2 == 0) { Almacen.marcar("test" + i.format("%04d"), Almacen.ENVIADO, null); }
    }
    var total = Almacen.ids().size();
    var pend = Almacen.pendientes();
    logger.debug("en el reloj " + total.toString() + ", pendientes " + pend.size().toString() + ", primero " + pend[0]);
    var ok = total == 40 && pend.size() == 30 && (pend[0] as String).equals("test0001")
        && Almacen.leer("test0000") == null && Almacen.leer("test0001") != null;
    Application.Storage.clearValues();
    return ok;
}

(:test)
function pruebaClave(logger as Logger) as Boolean {
    Application.Properties.setValue("clave", " abcd-EFGH-jkmn-PQRS-tuvw-XYZ2 ");
    var k = Almacen.clave();
    logger.debug(k);
    Application.Properties.setValue("clave", "");
    return k.equals("ABCDEFGHJKMNPQRSTUVWXYZ2");
}

(:test)
function pruebaIdUnico(logger as Logger) as Boolean {
    var a = nuevoId();
    var b = nuevoId();
    logger.debug(a + " " + b);
    return !a.equals(b) && a.length() >= 8 && a.length() <= 64;
}

// El ms de arranque se afina con lecturas (segundos enteros, ms del temporizador).
// Arranque real en el ms 420 del segundo: tras dos lecturas se sabe exacto.
(:test)
function pruebaAfinarAncla(logger as Logger) as Boolean {
    var r = cruzarAncla(0, 999, 2, 1580);      // 1,58 s después: [420, 999]
    var r2 = cruzarAncla(r[0] as Number, r[1] as Number, 2, 2579);   // justo antes del segundo 3: [420, 420]
    var r3 = cruzarAncla(r2[0] as Number, r2[1] as Number, 1, 9000);  // lectura imposible: se queda igual
    logger.debug(r.toString() + " " + r2.toString() + " " + r3.toString());
    return r[0] == 420 && r[1] == 999 && r2[0] == 420 && r2[1] == 420 && r3[0] == 420 && r3[1] == 420;
}

// Reloj 1 s por detrás del servidor, 300 ms de ida, 300 de vuelta y 100 de proceso.
(:test)
function pruebaDesfaseNtp(logger as Logger) as Boolean {
    var r = calcularDesfase(10000l, 11300l, 11400l, 10700l);
    logger.debug(r.toString());
    return r[0] == 1000 && r[1] == 600;
}
