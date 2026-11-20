import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

class PabloFaceApp extends Application.AppBase {

    function initialize() {
        AppBase.initialize();
    }

    function getInitialView() {
        return [new PabloFaceView()];
    }
}
