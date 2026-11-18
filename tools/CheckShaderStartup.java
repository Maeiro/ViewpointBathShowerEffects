package viewpoint.platform;

import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Map;

public final class CheckShaderStartup {
    public static void main(String[] args) throws Exception {
        Path root = Path.of(args[0]);
        if (args[1].equals("warm")) {
            Path playerFolder = root.resolve("player-packs");
            Path playerPack = playerFolder.resolve("startup-test");
            Files.createDirectories(playerPack);
            Files.writeString(playerPack.resolve("pack.properties"), "name=Startup test\nbase=default\n");
            ShaderPacks.discover(playerFolder.toFile());
        }
        ShaderPack previous = ShaderPacks.find("startup-test");
        for (String base : new String[]{"default", "somber"}) {
            String id = "maeiro.bath-shower-" + base;
            var files = PackagedShaderpacks.read(root.resolve(id));
            PackagedShaderpacks.install(id, files);
            require(ShaderPacks.find(id) != null, "Missing installed " + id);
            PackagedShaderpacks.install(id, files);
            require(ShaderPacks.find(id).base.id.equals(base), "Wrong base for " + id);
        }
        require(previous == ShaderPacks.find("startup-test"), "Player pack was reset");
        require(ShaderPacks.find("default") != null && ShaderPacks.find("somber") != null, "Missing built-ins");
        ShaderPack inherited = ShaderPacks.find("default");
        var errors = ShaderPacks.packaged(Map.of("invalid-test", new ShaderPack.PackFiles() {
            public String read(String name) { return name.equals("pack.properties") ? "base=missing-test\n" : null; }
            public long modified(String name) { return 0; }
        }));
        require(errors.containsKey("invalid-test"), "Invalid base must still fail");
        require(ShaderPacks.find("default") == inherited, "Built-in was unnecessarily replaced");
        PackagedShaderpacks.again();
        PackagedShaderpacks.remove("maeiro.bath-shower-default");
        require(ShaderPacks.find("maeiro.bath-shower-default") == null, "Removed pack remains registered");
        require(ShaderPacks.find("maeiro.bath-shower-somber") != null, "Removing one pack removed another");
        System.out.println("PASS: " + args[1] + " startup, native installation/reload, player packs, invalid bases and removal");
    }

    private static void require(boolean condition, String message) {
        if (!condition) throw new AssertionError(message);
    }
}
