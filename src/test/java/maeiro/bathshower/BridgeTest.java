package maeiro.bathshower;

import java.lang.reflect.Proxy;
import java.util.HashMap;
import java.util.Map;
import java.util.Optional;
import viewpoint.api.*;
import viewpoint.api.lua.LuaTable;
import viewpoint.api.render.*;
import viewpoint.api.view.*;

public final class BridgeTest {
    private static final Map<String, float[]> values = new HashMap<>();

    @SuppressWarnings("unchecked")
    private static <T> T proxy(Class<T> type, java.lang.reflect.InvocationHandler handler) {
        return (T) Proxy.newProxyInstance(type.getClassLoader(), new Class<?>[] { type }, handler);
    }

    private static ShaderValue value(String name, ValueKind kind) {
        return proxy(ShaderValue.class, (self, method, args) -> switch (method.getName()) {
            case "set" -> { values.put(name, ((float[]) args[0]).clone()); yield self; }
            case "kind" -> kind;
            case "uniform" -> name;
            default -> null;
        });
    }

    private static final class Table implements LuaTable {
        private final Map<Object, Object> data = new HashMap<>();
        @Override public Object get(String key) { return data.get(key); }
        @Override public Object get(int key) { return data.get(key); }
        @Override public void set(String key, Object value) { data.put(key, value); }
        @Override public void set(int key, Object value) { data.put(key, value); }
        @Override public int length() { int n = 0; while (data.containsKey(n + 1)) n++; return n; }
        @Override public LuaTable newTable() { return new Table(); }
    }

    private static Table entry(double x) {
        Table result = new Table();
        result.set("x", x); result.set("y", 10.0); result.set("z", 0.0);
        result.set("facing", 0.0); result.set("water", 1.0); result.set("steam", 0.5); result.set("light", 0.8);
        return result;
    }

    private static ViewState state(ViewMode mode) {
        return new ViewState(mode, new EyePose(0, 0, 0, 0, 0), 70, new Ray(0, 0, 0, 1, 0, 0),
            new Versions("42.22.2", "0.1.7", "1.0"), false, true, new Vec3(0, 0, 0),
            Optional.empty(), Optional.empty(), Terrain.NONE);
    }

    private static void check(boolean condition, String message) {
        if (!condition) throw new AssertionError(message);
    }

    public static void main(String[] args) throws Exception {
        ShaderValues shaders = proxy(ShaderValues.class, (self, method, arguments) ->
            value((String) arguments[0], (ValueKind) arguments[1]));
        AddonShaders addonShaders = proxy(AddonShaders.class, (self, method, arguments) -> shaders);
        AddonSettings settings = proxy(AddonSettings.class, (self, method, arguments) -> false);
        AddonContext context = proxy(AddonContext.class, (self, method, arguments) -> switch (method.getName()) {
            case "shaders" -> addonShaders;
            case "settings" -> settings;
            default -> null;
        });
        ShowerBridge.start(context);
        check(!ShowerBridge.update(null), "null input rejected");
        Table input = new Table(); input.set("clock", 1.0);
        input.set(1, entry(Double.NaN)); input.set(2, entry(12.0));
        check(ShowerBridge.update(input), "valid snapshot accepted");
        ShowerBridge.onFrame(state(ViewMode.FIRST_PERSON));
        check(values.get("count")[0] == 1 && values.get("position0")[0] == 12, "bad entries skipped");
        input.set("clock", Double.POSITIVE_INFINITY);
        check(!ShowerBridge.update(input), "invalid clock rejected");
        ShowerBridge.onFrame(state(ViewMode.ISOMETRIC));
        check(values.get("count")[0] == 0, "isometric clears visible effects");
        input.set("clock", 2.0);
        for (int i = 1; i <= 8; i++) input.set(i, entry(i));
        ShowerBridge.update(input);
        ShowerBridge.onFrame(state(ViewMode.THIRD_PERSON));
        check(values.get("count")[0] == 4, "four-shower limit enforced");
        Table bathtub = entry(5);
        bathtub.set("kind", 1.0); bathtub.set("water", 0.875);
        bathtub.set("filling", 1.0); bathtub.set("dirty", 0.5);
        Table bathInput = new Table(); bathInput.set("clock", 3.0); bathInput.set(1, bathtub);
        check(ShowerBridge.update(bathInput), "bathtub snapshot accepted");
        ShowerBridge.onFrame(state(ViewMode.THIRD_PERSON));
        check(values.get("count")[0] == 1 && values.get("effect0")[0] == 0.875f
            && values.get("effect0")[3] == 1 && values.get("tub0")[0] == 1 && values.get("tub0")[1] == 0.5f,
            "bathtub level, type, filling and stains reach shader uniforms");
        Table tint = new Table(); tint.set("r", 0.6); tint.set("g", 0.3); tint.set("b", 0.8);
        bathtub.set("color", tint);
        ShowerBridge.update(bathInput);
        ShowerBridge.onFrame(state(ViewMode.THIRD_PERSON));
        check(values.get("color0")[0] == 0.6f && values.get("color0")[1] == 0.3f
            && values.get("color0")[2] == 0.8f && values.get("color0")[3] == 1,
            "salt RGB and presence marker reach the shader");
        tint.set("r", Double.NaN);
        ShowerBridge.update(bathInput);
        ShowerBridge.onFrame(state(ViewMode.THIRD_PERSON));
        check(values.get("count")[0] == 1 && values.get("color0")[3] == 0,
            "malformed tint falls back without hiding the bathtub");
        tint.set("r", 0.6);
        bathtub.set("kind", 0.5);
        ShowerBridge.update(bathInput);
        ShowerBridge.onFrame(state(ViewMode.THIRD_PERSON));
        check(values.get("count")[0] == 0, "unknown effect kind rejected");
        bathtub.set("kind", 1.0); bathtub.set("dirty", Double.NaN);
        ShowerBridge.update(bathInput);
        ShowerBridge.onFrame(state(ViewMode.THIRD_PERSON));
        check(values.get("count")[0] == 0, "invalid bathtub material rejected");
        ShowerBridge.update(input);
        ShowerBridge.onFrame(state(ViewMode.THIRD_PERSON));
        check(values.get("effect0")[3] == 0 && values.get("tub0")[0] == 0 && values.get("tub0")[1] == 0
            && values.get("color0")[3] == 0,
            "reusing a bathtub slot for a shower clears bathtub fields");
        Thread.sleep(2100);
        ShowerBridge.onFrame(state(ViewMode.THIRD_PERSON));
        check(values.get("count")[0] == 0, "stale snapshots do not leave ghost effects");
        ShowerBridge.stop();
        check(!ShowerBridge.isActive() && values.get("count")[0] == 0, "disable clears shader count");
        check(!ShowerBridge.update(input), "disabled exports do not touch shaders");
        System.out.println("PASS: snapshot validation, shared four-effect limit, bathtub uniforms, cameras and disable cleanup");
    }
}
