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
class Directo {

    private var _enCurso as Boolean = false;
    private var _otraVez as Boolean = false;
    private var _ultimo as Number = 0;
    var refinarEn as Number = 0;

    function initialize() {
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
        var opciones = {
            :method => Communications.HTTP_REQUEST_METHOD_POST,
            :headers => {
                "Content-Type" => Communications.REQUEST_CONTENT_TYPE_JSON,
                "Authorization" => "Bearer " + clave
            },
            :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
        };
        _enCurso = true;
        Communications.makeWebRequest(Almacen.servidor() + "/directo", params, opciones, method(:alResponder));
    }

    function alResponder(cod as Number, datos as Null or ByteArray or Dictionary or String or PersistedContent.Iterator) as Void {
        _enCurso = false;
        if (_otraVez) {
            _otraVez = false;
            enviar();
        }
    }
}
