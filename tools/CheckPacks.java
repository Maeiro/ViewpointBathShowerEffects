package viewpoint.platform;

import java.io.File;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

public final class CheckPacks {
    private static String shader(ShaderPack pack, String name) {
        for (ShaderPack current = pack; current != null; current = current.base) {
            String source = current.shader(name);
            if (source != null) return source;
        }
        return null;
    }

    public static void main(String[] args) throws Exception {
        Map<String, ShaderPack> bases = new HashMap<>();
        for (String base : List.of("library", "default", "somber")) {
            bases.put(base, ShaderPack.parse(base, ShaderPack.jar(base), bases::get, true));
        }
        for (String base : List.of("default", "somber")) {
            String id = "maeiro.bath-shower-" + base;
            ShaderPack inherited = bases.get(base);
            ShaderPack pack = ShaderPack.parse(id, ShaderPack.folder(new File(args[0], id)), bases::get, false);
            if (pack.passes.size() != inherited.passes.size() + 1) {
                throw new AssertionError("Base passes must be preserved exactly once: " + id);
            }
            for (int i = 0; i < inherited.passes.size(); i++) {
                if (pack.passes.get(i) != inherited.passes.get(i)) {
                    throw new AssertionError("Inherited pass replaced: " + inherited.passes.get(i).id);
                }
            }
            if (!pack.targets.equals(inherited.targets)) throw new AssertionError("Base targets changed: " + id);
            PackPass bath = pack.passes.get(pack.passes.size() - 1);
            if (!bath.id.equals("bathShower") || !bath.stage.name().equals("FINAL")) {
                throw new AssertionError("Bath pass must follow the base final passes");
            }
            if (shader(pack, bath.fragment) == null) throw new AssertionError("Missing bath shader");
            for (PackPass pass : inherited.passes) {
                if (shader(pack, pass.fragment) == null) throw new AssertionError("Missing inherited shader: " + pass.fragment);
            }
            System.out.println("PASS: installed Viewpoint loader parsed " + id + "; " + pack.passes.size()
                + " passes, " + pack.targets.size() + " targets; all base shaders resolved");
        }
    }
}
