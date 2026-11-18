import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import se.krka.kahlua.luaj.compiler.LuaCompiler;

public final class CheckLua {
    public static void main(String[] args) throws Exception {
        int count = 0;
        try (var paths = Files.walk(Path.of(args[0]))) {
            for (Path path : paths.filter(p -> p.toString().endsWith(".lua")).toList()) {
                LuaCompiler.loadstring(Files.readString(path, StandardCharsets.UTF_8), path.toString(), null);
                count++;
            }
        }
        System.out.println("PASS: compiled " + count + " Lua file(s) with the installed PZ compiler");
    }
}
