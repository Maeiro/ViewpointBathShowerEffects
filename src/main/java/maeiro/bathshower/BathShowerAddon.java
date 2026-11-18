package maeiro.bathshower;

import viewpoint.api.Addon;
import viewpoint.api.AddonContext;
import viewpoint.api.Version;

public final class BathShowerAddon implements Addon {
    @Override
    public void enable(AddonContext context) {
        ShowerBridge.start(context);
        context.view().listen(ShowerBridge::onFrame);
        System.out.println("[BathShowerEffects] " + context.id() + " active; API " + Version.API);
        System.out.println("[BathShowerEffects] Select Default + Bath & Shower Effects or Somber + Bath & Shower Effects in Graphics.");
    }

    @Override
    public void disable() {
        ShowerBridge.stop();
        System.out.println("[BathShowerEffects] inactive");
    }
}
