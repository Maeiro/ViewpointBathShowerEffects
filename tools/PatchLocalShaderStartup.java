import java.nio.file.Files;
import java.nio.file.Path;
import java.security.MessageDigest;
import java.util.HexFormat;
import java.util.zip.ZipEntry;
import java.util.zip.ZipFile;
import java.util.zip.ZipOutputStream;
import java.lang.classfile.ClassFile;
import java.lang.classfile.ClassTransform;
import java.lang.classfile.CodeBuilder;
import java.lang.classfile.CodeElement;
import java.lang.classfile.CodeTransform;
import java.lang.constant.ClassDesc;
import java.lang.constant.MethodTypeDesc;
import static java.lang.constant.ConstantDescs.*;

public final class PatchLocalShaderStartup {
    private static final String ORIGINAL_SHA256 = "8d0d5a73227d3ba0724cab076f621435ebaed8ed2c73bfaf7d32a90b0a249e1f";
    private static final String OWNER = "viewpoint/platform/ShaderPacks";

    public static void main(String[] args) throws Exception {
        Path source = Path.of(args[0]).toRealPath();
        Path destination = Path.of(args[1]).toAbsolutePath();
        if (source.equals(destination)) throw new IllegalArgumentException("Use a separate staging path");
        String hash = HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(Files.readAllBytes(source)));
        if (!hash.equals(ORIGINAL_SHA256)) throw new IllegalArgumentException("Untested Viewpoint JAR; refusing to patch " + hash);
        try (ZipFile input = new ZipFile(source.toFile());
             ZipOutputStream output = new ZipOutputStream(Files.newOutputStream(destination))) {
            var entries = input.entries();
            int modified = 0;
            while (entries.hasMoreElements()) {
                ZipEntry entry = entries.nextElement();
                byte[] bytes;
                try (var stream = input.getInputStream(entry)) { bytes = stream.readAllBytes(); }
                if (entry.getName().equals(OWNER + ".class")) {
                    bytes = patch(bytes);
                    modified++;
                }
                ZipEntry copy = new ZipEntry(entry.getName());
                copy.setTime(entry.getTime());
                output.putNextEntry(copy);
                output.write(bytes);
                output.closeEntry();
            }
            if (modified != 1) throw new IllegalStateException("Expected exactly one ShaderPacks class");
        }
        System.out.println("Staged private shader startup patch: " + destination);
    }

    private static byte[] patch(byte[] bytes) {
        ClassFile classFile = ClassFile.of();
        var model = classFile.parse(bytes);
        long matches = model.methods().stream().filter(method -> method.methodName().equalsString("packaged")
            && method.methodType().equalsString("(Ljava/util/Map;)Ljava/util/Map;")).count();
        if (matches != 1) throw new IllegalStateException("Unexpected shader loader signature");
        ClassDesc owner = ClassDesc.of("viewpoint.platform.ShaderPacks");
        return classFile.transformClass(model, ClassTransform.transformingMethodBodies(
            method -> method.methodName().equalsString("packaged")
                && method.methodType().equalsString("(Ljava/util/Map;)Ljava/util/Map;"),
            new CodeTransform() {
                @Override
                public void atStart(CodeBuilder code) {
                    // Managed packs can start during Lua initialization, before renderer discovery.
                    code.getstatic(owner, "packs", ClassDesc.of("java.util.Map"))
                        .invokeinterface(ClassDesc.of("java.util.Map"), "isEmpty", MethodTypeDesc.of(CD_boolean))
                        .ifThen(block -> block.aconst_null()
                            .invokestatic(owner, "discover", MethodTypeDesc.of(CD_void, ClassDesc.of("java.io.File"))));
                }

                @Override
                public void accept(CodeBuilder code, CodeElement element) {
                    code.with(element);
                }
            }));
    }
}
