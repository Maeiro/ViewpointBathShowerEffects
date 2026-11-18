import java.nio.ByteBuffer;
import java.nio.FloatBuffer;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Arrays;
import org.joml.Matrix4f;
import org.lwjgl.BufferUtils;
import org.lwjgl.glfw.GLFW;
import org.lwjgl.opengl.GL;
import static org.lwjgl.opengl.GL33C.*;

public final class CheckShader {
    private static final int SIZE = 128;
    private static final String PREFIX = "uAddon_maeiro_bath_shower_effects_";

    private static int shader(int type, String source) {
        int shader = glCreateShader(type);
        glShaderSource(shader, source);
        glCompileShader(shader);
        if (glGetShaderi(shader, GL_COMPILE_STATUS) == GL_FALSE) throw new AssertionError(glGetShaderInfoLog(shader));
        return shader;
    }

    private static void check(boolean value, String message) {
        if (!value) throw new AssertionError(message);
    }

    private static int program(String fragment, int quality, boolean water, boolean steam) {
        String defines = "#define OPTION_BATH_QUALITY " + quality + "\n#define OPTION_BATH_WATER " + (water ? 1 : 0)
            + "\n#define OPTION_BATH_STEAM " + (steam ? 1 : 0) + "\n";
        int vertex = shader(GL_VERTEX_SHADER, "#version 330\nout vec2 vUv;\nvoid main(){"
            + "vec2 p=vec2((gl_VertexID<<1)&2,gl_VertexID&2); vUv=p; gl_Position=vec4(p*2.0-1.0,0,1);}");
        int pixel = shader(GL_FRAGMENT_SHADER, fragment.replace("#version 330", "#version 330\n" + defines));
        int program = glCreateProgram();
        glAttachShader(program, vertex); glAttachShader(program, pixel); glLinkProgram(program);
        check(glGetProgrami(program, GL_LINK_STATUS) != GL_FALSE, glGetProgramInfoLog(program));
        glDeleteShader(vertex); glDeleteShader(pixel);
        return program;
    }

    private static byte[] render(int program, int count, float water, float steam, boolean wall, float originX, float clock) {
        return render(program, count, water, steam, wall, originX, clock, 0, 0, 0, 0);
    }

    private static byte[] render(int program, int count, float water, float steam, boolean wall, float originX,
            float clock, int kind, int facing, float filling, float dirty) {
        return render(program, count, water, steam, wall, originX, clock, kind, facing, filling, dirty, null);
    }

    private static byte[] render(int program, int count, float water, float steam, boolean wall, float originX,
            float clock, int kind, int facing, float filling, float dirty, float[] tint) {
        glUseProgram(program);
        glUniform1i(glGetUniformLocation(program, "uColor"), 0);
        glUniform1i(glGetUniformLocation(program, "uDepth"), 1);
        glUniform1i(glGetUniformLocation(program, PREFIX + "count"), count);
        glUniform1f(glGetUniformLocation(program, PREFIX + "clock"), clock);
        glUniform4f(glGetUniformLocation(program, PREFIX + "position0"), -originX, 0, 0, facing);
        glUniform4f(glGetUniformLocation(program, PREFIX + "effect0"), water, steam, 1, kind);
        glUniform4f(glGetUniformLocation(program, PREFIX + "tub0"), filling, dirty, 0, 0);
        glUniform4f(glGetUniformLocation(program, PREFIX + "color0"),
            tint == null ? 0 : tint[0], tint == null ? 0 : tint[1], tint == null ? 0 : tint[2], tint == null ? 0 : 1);
        glUniform3f(glGetUniformLocation(program, "uEye"), 0, 1, 3);
        glUniform3f(glGetUniformLocation(program, "uSceneOrigin"), originX, 0, 0);
        Matrix4f projection = new Matrix4f().perspective((float) Math.PI / 2, 1, 0.1f, 20);
        Matrix4f inverse = new Matrix4f(projection).lookAt(0, 1, 3, 0, 1, 0, 0, 1, 0).invert();
        FloatBuffer matrix = BufferUtils.createFloatBuffer(16);
        inverse.get(matrix);
        glUniformMatrix4fv(glGetUniformLocation(program, "uInvViewProjection"), false, matrix);
        float depth = wall ? ((20.1f / 19.9f) - (4.0f / 19.9f) / 1.0f) * 0.5f + 0.5f : 1;
        FloatBuffer pixels = BufferUtils.createFloatBuffer(SIZE * SIZE);
        for (int i = 0; i < SIZE * SIZE; i++) pixels.put(depth);
        pixels.flip();
        glActiveTexture(GL_TEXTURE1);
        glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, SIZE, SIZE, GL_RED, GL_FLOAT, pixels);
        glActiveTexture(GL_TEXTURE0);
        glDrawArrays(GL_TRIANGLES, 0, 3);
        ByteBuffer result = BufferUtils.createByteBuffer(SIZE * SIZE * 4);
        glReadPixels(0, 0, SIZE, SIZE, GL_RGBA, GL_UNSIGNED_BYTE, result);
        byte[] bytes = new byte[result.remaining()]; result.get(bytes);
        return bytes;
    }

    private static int changed(byte[] a, byte[] b) {
        int count = 0;
        for (int i = 0; i < a.length; i += 4) {
            if (a[i] != b[i] || a[i + 1] != b[i + 1] || a[i + 2] != b[i + 2]) count++;
        }
        return count;
    }

    public static void main(String[] args) throws Exception {
        GLFW.glfwSetErrorCallback((error, description) -> System.err.println("GLFW error " + error));
        check(GLFW.glfwInit(), "GLFW initialization failed");
        GLFW.glfwWindowHint(GLFW.GLFW_VISIBLE, GLFW.GLFW_FALSE);
        GLFW.glfwWindowHint(GLFW.GLFW_CONTEXT_VERSION_MAJOR, 3);
        GLFW.glfwWindowHint(GLFW.GLFW_CONTEXT_VERSION_MINOR, 3);
        long window = GLFW.glfwCreateWindow(SIZE, SIZE, "Shader validation", 0, 0);
        check(window != 0, "Hidden OpenGL context failed");
        try {
            GLFW.glfwMakeContextCurrent(window); GL.createCapabilities();
            glViewport(0, 0, SIZE, SIZE); glDisable(GL_DITHER);
            glBindVertexArray(glGenVertexArrays());
            ByteBuffer gray = BufferUtils.createByteBuffer(SIZE * SIZE * 4);
            for (int i = 0; i < SIZE * SIZE; i++) gray.put((byte) 100).put((byte) 100).put((byte) 100).put((byte) 255);
            gray.flip();
            for (int unit = 0; unit < 2; unit++) {
                glActiveTexture(GL_TEXTURE0 + unit);
                glBindTexture(GL_TEXTURE_2D, glGenTextures());
                glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
                glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
                if (unit == 0) glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, SIZE, SIZE, 0, GL_RGBA, GL_UNSIGNED_BYTE, gray);
                else glTexImage2D(GL_TEXTURE_2D, 0, GL_R32F, SIZE, SIZE, 0, GL_RED, GL_FLOAT, (FloatBuffer) null);
            }
            glActiveTexture(GL_TEXTURE0);
            String source = Files.readString(Path.of(args[0]));
            for (int quality = 0; quality <= 2; quality++) {
                for (int mode = 0; mode < 4; mode++) {
                    int program = program(source, quality, (mode & 1) != 0, (mode & 2) != 0);
                    byte[] off = render(program, 0, 1, 1, false, 0, 1);
                    byte[] on = render(program, 1, 1, 1, false, 0, 1);
                    if (mode == 0) check(Arrays.equals(off, on), "Both toggles off must preserve source");
                    else check(changed(off, on) > 0 && changed(off, on) < SIZE * SIZE / 2, "Effect must be visible and localized");
                    byte[] wall = render(program, 1, 1, 1, true, 0, 1);
                    check(Arrays.equals(off, wall), "Opaque wall must hide effects");
                    check(Arrays.equals(on, render(program, 1, 1, 1, false, 10000, 1)), "World origin shift must not move effect");
                    check(Arrays.equals(on, render(program, 1, 1, 1, false, 0, 1)), "Paused clock must reproduce frame");
                    if ((mode & 1) != 0) check(changed(on, render(program, 1, 1, 1, false, 0, 1.1f)) > 0, "Water must animate");
                    for (int facing = 0; facing < 4; facing++) {
                        byte[] bath = render(program, 1, 0.875f, 1, false, 0, 1, 1, facing, 0, 0);
                        if (mode == 0) check(Arrays.equals(off, bath), "Bathtub toggles off must preserve source");
                        else check(changed(off, bath) > 0 && changed(off, bath) < SIZE * SIZE / 2,
                            "Bathtub water and steam must be visible and localized for facing " + facing);
                        check(Arrays.equals(off, render(program, 1, 0.875f, 1, true, 0, 1, 1, facing, 0, 0)),
                            "Opaque wall must hide bathtub water and steam");
                        check(Arrays.equals(bath, render(program, 1, 0.875f, 1, false, 10000, 1, 1, facing, 0, 0)),
                            "Bathtub must remain fixed during a world-origin shift");
                        check(Arrays.equals(bath, render(program, 1, 0.875f, 1, false, 0, 1, 1, facing, 0, 0)),
                            "Bathtub must not animate while paused");
                        check(Arrays.equals(off, render(program, 1, 0, 0, false, 0, 1, 1, facing, 0, 0)),
                            "An empty cold bathtub must not draw");
                        if ((mode & 1) != 0) {
                            byte[] surface = render(program, 1, 0.875f, 0, false, 0, 1, 1, facing, 0, 0);
                            check(changed(off, surface) > 0, "Cold bath water must remain visible without steam");
                            check(changed(surface, render(program, 1, 0.125f, 0, false, 0, 1, 1, facing, 0, 0)) > 0,
                                "Fill level must change the bathtub water surface");
                            check(changed(surface, render(program, 1, 0.875f, 0, false, 0, 1, 1, facing, 0, 1)) > 0,
                                "Water stains must change surface color");
                            check(changed(surface, render(program, 1, 0.875f, 0, false, 0, 1.3f, 1, facing, 0, 0)) > 0,
                                "Water surface ripples must animate");
                            check(changed(surface, render(program, 1, 0.875f, 0, false, 0, 1, 1, facing, 1, 0)) > 0,
                                "Opening the bathtub tap must draw the filling stream");
                            float[] purple = { 0.6f, 0.3f, 0.8f }, green = { 0.1f, 0.7f, 0.2f };
                            byte[] salt = render(program, 1, 0.875f, 0, false, 0, 1, 1, facing, 0, 0, purple);
                            check(changed(surface, salt) > 0, "Bath salt tint must change the rendered water");
                            check(changed(salt, render(program, 1, 0.875f, 0, false, 0, 1, 1, facing, 0, 0, green)) > 0,
                                "Different salts must produce different rendered colors");
                            check(Arrays.equals(salt, render(program, 1, 0.875f, 0, false, 0, 1, 1, facing, 0, 1, purple)),
                                "Final TABAS tint must not receive duplicate dirt coloring");
                        }
                        if ((mode & 2) != 0) {
                            check(changed(off, render(program, 1, 0.875f, 1, false, 0, 1, 1, facing, 0, 0)) > 0,
                                "Hot bathtub steam must be visible");
                        }
                    }
                    glDeleteProgram(program);
                }
            }
            check(glGetError() == GL_NO_ERROR, "OpenGL validation error");
            System.out.println("PASS: 12 GLSL variants; shower regression and 4 bathtub facings, fill levels, tap, stains, steam, occlusion, origin shifts and pause");
        } finally {
            GLFW.glfwDestroyWindow(window); GLFW.glfwTerminate();
        }
    }
}
