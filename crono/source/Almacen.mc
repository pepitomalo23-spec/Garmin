import Toybox.Application;
import Toybox.Lang;
import Toybox.Time;

// Memoria del reloj (Application.Storage). La usan la app y el proceso en
// segundo plano, por eso lleva (:background).
//
//   "ids"    lista de ids de los registros que hay en el reloj, el más nuevo primero
//   "r_<id>" cada registro: id, inicio, fin, dur, vueltas, parciales, tipo,
//            guardado y "est" (PENDIENTE / ENVIADO / RECHAZADO)
//   "sync"   último intento de envío: t (hora), cod (resultado), ok (último bien)
//   "crono"  el cronómetro en marcha (Cronometro.mc)
//
// Reglas para no perder nada:
//   - Un registro se escribe ANTES de apuntarlo en "ids".
//   - Solo se marca ENVIADO cuando el servidor devuelve su id en «confirmados».
//   - Al podar (máximo MAX_LOCAL) solo se borran registros ya ENVIADOS o
//     RECHAZADOS; un PENDIENTE no se borra nunca.
//   - El segundo plano solo cambia el "est" de registros que ya existen; la
//     lista "ids" solo la escribe la app (así no se pisan entre los dos).
// Límites de la plataforma: 8 KB por valor y 128 KB en total.
(:background)
module Almacen {

    const PENDIENTE = 0;
    const ENVIADO = 1;
    const RECHAZADO = 2;
    const MAX_LOCAL = 40;
    const LOTE = 5;              // registros por petición

    // Códigos propios (los de Garmin son negativos pequeños; los HTTP, 200, 401…)
    const SIN_CLAVE = -9001;
    const SIN_MOVIL = -9002;
    const RESPUESTA_RARA = -9003;
    const NADA = -9004;

    const VERSION_APP = "1.3.0";
    const MODELO = "fenix6xpro";
    const URL_POR_DEFECTO = "https://tsjaaqkvncgxqtpmlugv.supabase.co/functions/v1/garmin-api";

    function num(v) as Number {
        return (v instanceof Number) ? v as Number : 0;
    }

    function ids() as Array {
        var v = Application.Storage.getValue("ids");
        return (v instanceof Array) ? v as Array : [];
    }

    function leer(id as String) as Dictionary or Null {
        var v = Application.Storage.getValue("r_" + id);
        return (v instanceof Dictionary) ? v as Dictionary : null;
    }

    // Guarda un registro nuevo (lanza excepción si la memoria está llena).
    function guardarNuevo(reg as Dictionary) as Void {
        var id = reg["id"] as String;
        Application.Storage.setValue("r_" + id, reg);
        var l = ids();
        var nueva = [id];
        for (var i = 0; i < l.size(); i++) {
            if (!(id.equals(l[i]))) { nueva.add(l[i]); }
        }
        Application.Storage.setValue("ids", nueva);
        podar();
    }

    // Los pendientes, del más antiguo al más nuevo.
    function pendientes() as Array {
        var l = ids();
        var out = [];
        for (var i = l.size() - 1; i >= 0; i--) {
            var r = leer(l[i] as String);
            if (r != null && num(r["est"]) == PENDIENTE) { out.add(l[i]); }
        }
        return out;
    }

    function marcar(id as String, est as Number, motivo as String or Null) as Void {
        var r = leer(id);
        if (r == null) { return; }
        r["est"] = est;
        if (motivo != null) { r["motivo"] = motivo; }
        Application.Storage.setValue("r_" + id, r);
    }

    // Deja como mucho MAX_LOCAL registros: quita los enviados/rechazados más viejos.
    function podar() as Void {
        var l = ids();
        var sobran = l.size() - MAX_LOCAL;
        if (sobran <= 0) { return; }
        var fuera = {};
        for (var i = l.size() - 1; i >= 0 && sobran > 0; i--) {
            var r = leer(l[i] as String);
            if (r == null || num(r["est"]) != PENDIENTE) {
                fuera.put(l[i], true);
                sobran--;
            }
        }
        var quedan = [];
        for (var j = 0; j < l.size(); j++) {
            if (fuera.hasKey(l[j])) {
                Application.Storage.deleteValue("r_" + (l[j] as String));
            } else {
                quedan.add(l[j]);
            }
        }
        Application.Storage.setValue("ids", quedan);
    }

    function estadoSync() as Dictionary {
        var v = Application.Storage.getValue("sync");
        return (v instanceof Dictionary) ? v as Dictionary : {};
    }

    function apuntarSync(cod as Number) as Void {
        var s = estadoSync();
        var ahora = Time.now().value();
        s["t"] = ahora;
        s["cod"] = cod;
        if (cod == 200) { s["ok"] = ahora; }
        Application.Storage.setValue("sync", s);
    }

    // La clave de los ajustes, sin guiones ni espacios y en mayúsculas.
    function clave() as String {
        var v = Application.Properties.getValue("clave");
        if (!(v instanceof String)) { return ""; }
        var cs = (v as String).toCharArray();
        var out = "";
        for (var i = 0; i < cs.size(); i++) {
            var n = cs[i].toNumber();
            if (n >= 97 && n <= 122) { n = n - 32; }
            if ((n >= 65 && n <= 90) || (n >= 48 && n <= 57)) { out = out + n.toChar().toString(); }
        }
        return out;
    }

    function servidor() as String {
        var v = Application.Properties.getValue("servidor");
        if (v instanceof String && (v as String).length() > 10) { return v as String; }
        return URL_POR_DEFECTO;
    }
}
