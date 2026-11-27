import Toybox.Communications;
import Toybox.Lang;
import Toybox.PersistedContent;
import Toybox.System;
import Toybox.Time;

// El cronómetro en directo en pj.fire (POST …/garmin-api/directo).
// No manda el tiempo a cada instante: manda CUÁNDO arrancó (hora real al ms),
// lo acumulado y las vueltas, y la web cuenta sola. Se avisa en cada
// pulsación (salir, vuelta, pausa, seguir, guardar, descartar), una vez más a
// los ~3 s de arrancar (con el ancla ya afinada al ms) y con un latido cada
// minuto en marcha. Solo con la app abierta y el móvil conectado; si no, la
// web lo corrige en cuanto vuelve a haber conexión.
//
// Hora del reloj ≠ hora real (el Fenix puede ir ~1 s desfasado del móvil): en
// cada aviso se mide, como NTP, la diferencia con el servidor (t1 sale, t2
// llega al servidor, t3 responde, t4 vuelve) y se manda «cal» = servidor −
// reloj de la medida con menos retardo de las últimas 8. El servidor la suma al
// ancla, así la web cuenta con la hora real.
class Directo {

    private var _enCurso as Boolean = false;
    private var _otraVez as Boolean = false;
    private var _ultimo as Number = 0;
    var refinarEn as Number = 0;
    // Hora del reloj al ms: un segundo de Time.now() afinado con getTimer().
    private var _bE as Number = 0;
    private var _bT as Number = 0;
    private var _bLo as Number = 0;
    private var _bHi as Number = 999;
    private var _t0 as Number = 0;
    var muestras as Array = [];      // [desfase, retardo] de los últimos envíos

    function initialize() {
        _bT = System.getTimer();
        _bE = Time.now().value();
    }

    // En cada repintado (afina al ms la hora del reloj, igual que el ancla).
    function afinarBase() as Void {
        var r = cruzarAncla(_bLo, _bHi, Time.now().value() - _bE, System.getTimer() - _bT);
        _bLo = r[0] as Number;
        _bHi = r[1] as Number;
    }

    // Hora del reloj (ms desde 1970, Long) en el instante t de getTimer().
    function msReloj(t as Number) as Long {
        return _bE.toLong() * 1000l + ((_bLo + _bHi) / 2) + (t - _bT);
    }

    // La corrección con menos retardo (0 si aún no hay ninguna).
    function mejor() as Array {
        var b = null;
        for (var i = 0; i < muestras.size(); i++) {
            var m = muestras[i] as Array;
            if (b == null || (m[1] as Number) < ((b as Array)[1] as Number)) { b = m; }
        }
        return (b == null) ? [0, -1] : b as Array;
    }

    function avisar() as Void {
        if (_enCurso) { _otraVez = true; return; }
        enviar();
    }

    // Desde la pantalla, en cada repintado.
    function alTick(c as Cronometro) as Void {
        var ahora = Time.now().value();
        if (refinarEn > 0 && ahora >= refinarEn) {
            refinarEn = 0;
            avisar();
        } else if (c.estado == E_MARCHA && ahora - _ultimo >= 60) {
            avisar();
        }
    }

    function arrancado() as Void {
        refinarEn = Time.now().value() + 3;
        avisar();
    }

    private function enviar() as Void {
        _ultimo = Time.now().value();
        var clave = Almacen.clave();
        if (clave.length() < 20 || !System.getDeviceSettings().phoneConnected) { return; }
        var c = app().crono as Cronometro;
        var params = {} as Dictionary<Object, Object>;
        params.put("e", c.estado);
        params.put("ini", c.inicio);
        params.put("acum", c.acum);
        params.put("aE", c.anclaE);
        params.put("aOff", c.offsetAncla());
        params.put("par", c.parciales);
        params.put("version", Almacen.VERSION_APP);
        params.put("modelo", Almacen.MODELO);
        var m = mejor();
        if ((m[1] as Number) >= 0) {
            params.put("cal", m[0]);
            params.put("rtt", m[1]);
        }
        var opciones = {
            :method => Communications.HTTP_REQUEST_METHOD_POST,
            :headers => {
                "Content-Type" => Communications.REQUEST_CONTENT_TYPE_JSON,
                "Authorization" => "Bearer " + clave
            },
            :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
        };
        _enCurso = true;
        _t0 = System.getTimer();
        Communications.makeWebRequest(Almacen.servidor() + "/directo", params, opciones, method(:alResponder));
    }

    function alResponder(cod as Number, datos as Null or ByteArray or Dictionary or String or PersistedContent.Iterator) as Void {
        var t4 = System.getTimer();
        _enCurso = false;
        if (cod == 200 && datos instanceof Dictionary) {
            var d = datos as Dictionary;
            if (d["rs"] instanceof Number && d["rm"] instanceof Number && d["ts"] instanceof Number && d["tm"] instanceof Number) {
                var r = calcularDesfase(msReloj(_t0),
                    (d["rs"] as Number).toLong() * 1000l + (d["rm"] as Number),
                    (d["ts"] as Number).toLong() * 1000l + (d["tm"] as Number),
                    msReloj(t4));
                if ((r[1] as Number) >= 0 && (r[1] as Number) < 15000) {
                    muestras.add(r);
                    if (muestras.size() > 8) { muestras = muestras.slice(1, null); }
                }
            }
        }
        if (_otraVez) {
            _otraVez = false;
            enviar();
        }
    }
}

// Como NTP: [desfase (servidor − reloj), retardo de ida y vuelta] en ms.
//   t1 sale del reloj · t2 llega al servidor · t3 responde · t4 vuelve (Long, ms)
function calcularDesfase(t1 as Long, t2 as Long, t3 as Long, t4 as Long) as Array {
    var desfase = (((t2 - t1) + (t3 - t4)) / 2).toNumber();
    var retardo = ((t4 - t1) - (t3 - t2)).toNumber();
    return [desfase, retardo];
}
