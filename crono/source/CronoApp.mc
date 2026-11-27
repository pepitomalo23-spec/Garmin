import Toybox.Application;
import Toybox.Attention;
import Toybox.Background;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.Time;
import Toybox.WatchUi;

// Crono pj.fire — cronómetro manual para el Fenix 6X Pro que guarda cada
// sesión en el reloj y la manda a pj.fire (GARMIN / CRONÓMETRO) a través de
// la app Garmin Connect del móvil.
(:background)
class CronoApp extends Application.AppBase {

    var crono = null;    // Cronometro (solo con la app abierta)
    var sincro = null;   // SincroPrimerPlano
    var vista = null;    // CronoVista

    function initialize() {
        AppBase.initialize();
    }

    function getInitialView() {
        Math.srand(Time.now().value() ^ System.getTimer());
        crono = new Cronometro();
        sincro = new SincroPrimerPlano();
        vista = new CronoVista();
        programarFondo();
        return [vista, new CronoDelegado()];
    }

    function getServiceDelegate() {
        return [new FondoSincro()];
    }

    // El segundo plano ha terminado un envío.
    function onBackgroundData(data) {
        if (sincro != null) {
            (sincro as SincroPrimerPlano).alTerminarFondo(data);
            programarFondo();
            WatchUi.requestUpdate();
        }
    }

    // Han cambiado los ajustes en Connect IQ (por ejemplo, la clave).
    function onSettingsChanged() {
        if (sincro != null) {
            (sincro as SincroPrimerPlano).intentar(true);
            programarFondo();
        }
        WatchUi.requestUpdate();
    }

    function onStop(state) {
        if (crono != null) {
            (crono as Cronometro).persistir();
            programarFondo();
        }
    }
}

function app() as CronoApp {
    return Application.getApp() as CronoApp;
}

// El segundo plano solo se programa si hay algo que mandar y hay clave.
function programarFondo() as Void {
    if (!(Toybox has :Background)) { return; }
    var hace = Almacen.clave().length() >= 20 && Almacen.pendientes().size() > 0;
    var cuando = Background.getTemporalEventRegisteredTime();
    if (hace && cuando == null) {
        Background.registerForTemporalEvent(new Time.Duration(5 * 60));
    } else if (!hace && cuando != null) {
        Background.deleteTemporalEvent();
    }
}

// Vibración y pitido. tipo: 1 salida, 2 parada, 3 vuelta.
function aviso(tipo as Number) as Void {
    if (Application.Properties.getValue("vibrar") != false && (Attention has :vibrate)) {
        var perfil = (tipo == 3)
            ? [new Attention.VibeProfile(60, 120)]
            : ((tipo == 2)
                ? [new Attention.VibeProfile(80, 150), new Attention.VibeProfile(0, 100), new Attention.VibeProfile(80, 150)]
                : [new Attention.VibeProfile(90, 300)]);
        Attention.vibrate(perfil);
    }
    if (Application.Properties.getValue("sonido") == true && (Attention has :playTone)) {
        Attention.playTone(tipo == 1 ? Attention.TONE_START : (tipo == 2 ? Attention.TONE_STOP : Attention.TONE_LAP));
    }
}

// Sincronización con la app abierta: al abrir, al guardar, al cambiar la
// clave, desde el menú y cada 30 s mientras haya pendientes.
class SincroPrimerPlano {

    var enviando as Boolean = false;
    var ultimoCod as Number = 0;      // 0 = aún no se ha intentado
    var pend as Number = 0;
    var mensaje as String or Null = null;   // aviso puntual (memoria llena…)
    private var _envio = null;
    private var _ultimoIntento as Number = 0;

    function initialize() {
        var s = Almacen.estadoSync();
        ultimoCod = Almacen.num(s["cod"]);
        recontar();
    }

    function recontar() as Void {
        pend = Almacen.pendientes().size();
    }

    function intentar(forzar as Boolean) as Void {
        if (enviando) { return; }
        var ahora = Time.now().value();
        if (!forzar && ahora - _ultimoIntento < 30) { return; }
        _ultimoIntento = ahora;
        _envio = new Envio(method(:alAcabar), false);
        var r = (_envio as Envio).enviar();
        if (r == 0) {
            enviando = true;
        } else {
            ultimoCod = r;
            _envio = null;
        }
        WatchUi.requestUpdate();
    }

    function alAcabar(cod as Number) as Void {
        enviando = false;
        ultimoCod = cod;
        _envio = null;
        recontar();
        if (app().crono != null) {
            var c = app().crono as Cronometro;
            var l = Almacen.ids();
            c.ultimo = (l.size() > 0) ? Almacen.leer(l[0] as String) : null;
        }
        programarFondo();
        WatchUi.requestUpdate();
    }

    function alTerminarFondo(data) as Void {
        if (data instanceof Number && data != Almacen.NADA) { ultimoCod = data as Number; }
        recontar();
    }
}
