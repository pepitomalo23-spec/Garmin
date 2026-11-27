import Toybox.Background;
import Toybox.Communications;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;

// Un envío a la API de pj.fire (función garmin-api) a través del móvil.
// Lo usan la app abierta (SincroPrimerPlano) y el segundo plano (FondoSincro).
//   - Con pendientes: POST /registros con un lote de hasta LOTE registros.
//     Solo se marcan ENVIADO los ids que el servidor devuelve en
//     «confirmados»; los «rechazados» (datos imposibles) se marcan RECHAZADO
//     y se quedan en el reloj. Si quedan más, otra tanda.
//   - Sin pendientes (solo con la app abierta): POST /ping, para comprobar la
//     clave y que la web sepa que el reloj está conectado.
// makeWebRequest en el Fenix 6 (Connect IQ 3.4): no existe la opción :body
// (es de la 6.0.3); con Content-Type JSON y método POST, el diccionario de
// parámetros viaja como cuerpo JSON.
(:background)
class Envio {

    private var _alFinal;
    private var _fondo as Boolean;
    private var _rondas as Number = 0;
    var confirmados as Number = 0;

    function initialize(alFinal, fondo as Boolean) {
        _alFinal = alFinal;
        _fondo = fondo;
    }

    // 0 = petición en marcha (avisará con alFinal); si no, el motivo de no enviar.
    function enviar() as Number {
        var clave = Almacen.clave();
        if (clave.length() < 20) { return Almacen.SIN_CLAVE; }
        var pend = Almacen.pendientes();
        if (pend.size() == 0 && _fondo) { return Almacen.NADA; }
        if (!System.getDeviceSettings().phoneConnected) { return Almacen.SIN_MOVIL; }

        var params = {} as Dictionary<String, Object>;
        params.put("pendientes", pend.size());
        params.put("version", Almacen.VERSION_APP);
        params.put("modelo", Almacen.MODELO);
        var ruta = "/ping";
        if (pend.size() > 0) {
            var lote = [];
            for (var i = 0; i < pend.size() && lote.size() < Almacen.LOTE; i++) {
                var r = Almacen.leer(pend[i] as String);
                if (r != null) { lote.add(r); }
            }
            params.put("registros", lote);
            ruta = "/registros";
        }
        var opciones = {
            :method => Communications.HTTP_REQUEST_METHOD_POST,
            :headers => {
                "Content-Type" => Communications.REQUEST_CONTENT_TYPE_JSON,
                "Authorization" => "Bearer " + clave
            },
            :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
        };
        Communications.makeWebRequest(Almacen.servidor() + ruta, params, opciones, method(:alResponder));
        return 0;
    }

    function alResponder(cod as Number, datos) as Void {
        var nuevos = 0;
        if (cod == 200 && datos instanceof Dictionary && datos["ok"] == true) {
            var conf = datos["confirmados"];
            if (conf instanceof Array) {
                for (var i = 0; i < conf.size(); i++) {
                    if (conf[i] instanceof String) {
                        Almacen.marcar(conf[i] as String, Almacen.ENVIADO, null);
                        nuevos++;
                    }
                }
            }
            var rech = datos["rechazados"];
            if (rech instanceof Array) {
                for (var j = 0; j < rech.size(); j++) {
                    var x = rech[j];
                    if (x instanceof Dictionary && x["id"] instanceof String) {
                        var motivo = (x["motivo"] instanceof String) ? x["motivo"] as String : "rechazado";
                        Almacen.marcar(x["id"] as String, Almacen.RECHAZADO, motivo);
                        nuevos++;
                    }
                }
            }
        } else if (cod == 200) {
            cod = Almacen.RESPUESTA_RARA;
        }
        Almacen.apuntarSync(cod);
        confirmados += nuevos;
        _rondas++;
        // ¿Quedan más? Otra tanda (como mucho 8 seguidas).
        if (cod == 200 && nuevos > 0 && _rondas < 8) {
            if (enviar() == 0) { return; }
        }
        if (_alFinal != null) { _alFinal.invoke(cod); }
    }
}

// Segundo plano: cada 5 minutos (lo mínimo que deja Garmin), solo mientras
// haya registros sin enviar. Funciona aunque la app esté cerrada.
(:background)
class FondoSincro extends System.ServiceDelegate {

    private var _envio = null;

    function initialize() {
        ServiceDelegate.initialize();
    }

    function onTemporalEvent() as Void {
        _envio = new Envio(method(:alAcabar), true);
        var r = (_envio as Envio).enviar();
        if (r != 0) {
            if (r == Almacen.NADA || r == Almacen.SIN_CLAVE) {
                Background.deleteTemporalEvent();
            }
            Background.exit(r);
        }
    }

    function alAcabar(cod as Number) as Void {
        Background.exit(cod);
    }
}
