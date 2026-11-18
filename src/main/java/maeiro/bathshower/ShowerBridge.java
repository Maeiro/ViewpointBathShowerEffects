package maeiro.bathshower;

import viewpoint.api.AddonContext;
import viewpoint.api.lua.LuaExport;
import viewpoint.api.lua.LuaTable;
import viewpoint.api.render.ShaderValue;
import viewpoint.api.render.ValueKind;
import viewpoint.api.view.ViewState;

public final class ShowerBridge {
    private static final int LIMIT = 4;
    private static final long STALE_NANOS = 2_000_000_000L;
    private static final float[][] positions = new float[LIMIT][4];
    private static final float[][] effects = new float[LIMIT][4];
    private static final float[][] tubs = new float[LIMIT][4];
    private static final float[][] colors = new float[LIMIT][4];
    private static final ShaderValue[] positionValues = new ShaderValue[LIMIT];
    private static final ShaderValue[] effectValues = new ShaderValue[LIMIT];
    private static final ShaderValue[] tubValues = new ShaderValue[LIMIT];
    private static final ShaderValue[] colorValues = new ShaderValue[LIMIT];
    private static AddonContext context;
    private static ShaderValue clockValue;
    private static ShaderValue countValue;
    private static int count;
    private static float clock;
    private static long lastUpdate;
    private static long lastLog;
    private static boolean loggedVersions;

    private ShowerBridge() {
    }

    static void start(AddonContext nextContext) {
        context = nextContext;
        count = 0;
        clock = 0;
        lastUpdate = 0;
        lastLog = 0;
        loggedVersions = false;
        clockValue = context.shaders().values().declare("clock", ValueKind.FLOAT);
        countValue = context.shaders().values().declare("count", ValueKind.INT);
        for (int i = 0; i < LIMIT; i++) {
            positionValues[i] = context.shaders().values().declare("position" + i, ValueKind.VEC4);
            effectValues[i] = context.shaders().values().declare("effect" + i, ValueKind.VEC4);
            tubValues[i] = context.shaders().values().declare("tub" + i, ValueKind.VEC4);
            colorValues[i] = context.shaders().values().declare("color" + i, ValueKind.VEC4);
        }
    }

    static void stop() {
        if (context != null) countValue.set(0);
        context = null;
        count = 0;
        lastUpdate = 0;
    }

    @LuaExport
    public static boolean isActive() {
        return context != null;
    }

    @LuaExport
    public static boolean update(LuaTable input) {
        if (context == null || input == null) return false;
        double nextClock = number(input, "clock");
        if (!Double.isFinite(nextClock) || nextClock < 0 || nextClock > 1_000_000) return false;
        int accepted = 0;
        for (int i = 1; i <= Math.min(input.length(), LIMIT); i++) {
            Object raw = input.get(i);
            if (!(raw instanceof LuaTable entry)) continue;
            double x = number(entry, "x");
            double y = number(entry, "y");
            double z = number(entry, "z");
            double facing = number(entry, "facing");
            double water = number(entry, "water");
            double steam = number(entry, "steam");
            double light = number(entry, "light");
            double kind = optionalNumber(entry, "kind");
            double filling = optionalNumber(entry, "filling");
            double dirty = optionalNumber(entry, "dirty");
            if (!bounded(x, -10_000_000, 10_000_000) || !bounded(y, -10_000_000, 10_000_000)
                    || !bounded(z, -32, 64) || !bounded(facing, 0, 3) || facing != Math.floor(facing)
                    || !bounded(water, 0, 1) || !bounded(steam, 0, 1) || !bounded(light, 0, 1)
                    || !bounded(kind, 0, 1) || kind != Math.floor(kind)
                    || !bounded(filling, 0, 1) || !bounded(dirty, 0, 1)) continue;
            float[] position = positions[accepted];
            position[0] = (float) x;
            position[1] = (float) y;
            position[2] = (float) z;
            position[3] = (float) facing;
            float[] effect = effects[accepted];
            effect[0] = (float) water;
            effect[1] = (float) steam;
            effect[2] = (float) light;
            effect[3] = (float) kind;
            tubs[accepted][0] = (float) filling;
            tubs[accepted][1] = (float) dirty;
            float[] color = colors[accepted];
            color[0] = color[1] = color[2] = color[3] = 0;
            if (kind == 1 && entry.get("color") instanceof LuaTable tint) {
                double r = number(tint, "r"), g = number(tint, "g"), b = number(tint, "b");
                if (bounded(r, 0, 1) && bounded(g, 0, 1) && bounded(b, 0, 1)) {
                    color[0] = (float) r;
                    color[1] = (float) g;
                    color[2] = (float) b;
                    color[3] = 1;
                }
            }
            accepted++;
        }
        clock = (float) nextClock;
        count = accepted;
        lastUpdate = System.nanoTime();
        return true;
    }

    static void onFrame(ViewState state) {
        if (context == null) return;
        long now = System.nanoTime();
        int visible = state.on() && now - lastUpdate < STALE_NANOS ? count : 0;
        countValue.set(visible);
        clockValue.set(clock);
        for (int i = 0; i < visible; i++) {
            positionValues[i].set(positions[i]);
            effectValues[i].set(effects[i]);
            tubValues[i].set(tubs[i]);
            colorValues[i].set(colors[i]);
        }
        if (!loggedVersions) {
            loggedVersions = true;
            System.out.println("[BathShowerEffects] versions=" + state.versions());
        }
        if (context.settings().toggle("diagnostics") && now - lastLog >= 10_000_000_000L) {
            lastLog = now;
            int bathtubCount = 0;
            for (int i = 0; i < visible; i++) if (effects[i][3] == 1) bathtubCount++;
            System.out.println("[BathShowerEffects] selected=" + count + " rendered=" + visible
                    + " bathtubs=" + bathtubCount
                    + " snapshotAgeMs=" + (lastUpdate == 0 ? -1 : (now - lastUpdate) / 1_000_000));
        }
    }

    private static double number(LuaTable table, String key) {
        Object value = table.get(key);
        return value instanceof Double number ? number : Double.NaN;
    }

    private static double optionalNumber(LuaTable table, String key) {
        return table.get(key) == null ? 0 : number(table, key);
    }

    private static boolean bounded(double value, double min, double max) {
        return Double.isFinite(value) && value >= min && value <= max;
    }
}
