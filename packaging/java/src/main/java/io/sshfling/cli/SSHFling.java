package io.sshfling.cli;

import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;
import java.nio.file.FileVisitResult;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.SimpleFileVisitor;
import java.nio.file.StandardCopyOption;
import java.nio.file.attribute.BasicFileAttributes;
import java.nio.file.attribute.PosixFilePermission;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.EnumSet;
import java.util.List;
import java.util.Map;
import java.util.Set;

/** Java library and command-line entry point for the bundled SSHFling runtime. */
public final class SSHFling {
    private static final String RESOURCE_ROOT = "sshfling/";

    private SSHFling() {
    }

    /**
     * Runs SSHFling as a command-line process and exits with its status code.
     *
     * @param args SSHFling command-line arguments
     */
    public static void main(String[] args) {
        System.exit(run(args));
    }

    /**
     * Runs SSHFling through its public library API.
     *
     * @param args SSHFling command-line arguments
     * @return the SSHFling process exit status
     */
    public static int run(String[] args) {
        Path runtimeDir = null;
        try {
            runtimeDir = Files.createTempDirectory("sshfling-java-");
            extractRuntime(runtimeDir);

            Path scriptPath = runtimeDir.resolve("sshfling.py");
            Path templateDir = runtimeDir.resolve("templates");
            for (List<String> candidate : pythonCandidates()) {
                try {
                    return startPython(candidate, scriptPath, templateDir, args);
                } catch (IOException ignored) {
                    // Try the next conventional Python launcher name.
                }
            }

            System.err.println("sshfling-cli requires Python 3 on PATH, or set SSHFLING_PYTHON to a Python 3 executable.");
            return 127;
        } catch (IOException ex) {
            System.err.println("sshfling-cli failed to prepare bundled runtime: " + ex.getMessage());
            return 127;
        } catch (InterruptedException ex) {
            Thread.currentThread().interrupt();
            return 130;
        } finally {
            if (runtimeDir != null && !isTruthy(System.getenv("SSHFLING_JAVA_KEEP_RUNTIME"))) {
                try {
                    deleteTree(runtimeDir);
                } catch (IOException ignored) {
                    // Best-effort cleanup only.
                }
            }
        }
    }

    private static int startPython(List<String> candidate, Path scriptPath, Path templateDir, String[] args)
            throws IOException, InterruptedException {
        List<String> command = new ArrayList<>(candidate);
        command.add(scriptPath.toString());
        command.addAll(Arrays.asList(args));

        ProcessBuilder builder = new ProcessBuilder(command);
        builder.inheritIO();
        Map<String, String> environment = builder.environment();
        environment.putIfAbsent("SSHFLING_TEMPLATE_DIR", templateDir.toString());
        environment.putIfAbsent("PYTHONUNBUFFERED", "1");

        Process process = builder.start();
        process.waitFor();
        return process.exitValue();
    }

    private static List<List<String>> pythonCandidates() {
        List<List<String>> candidates = new ArrayList<>();
        String configuredPython = System.getenv("SSHFLING_PYTHON");
        if (configuredPython != null && !configuredPython.trim().isEmpty()) {
            candidates.add(Arrays.asList(configuredPython.trim()));
        }

        if (isWindows()) {
            candidates.add(Arrays.asList("py", "-3"));
            candidates.add(Arrays.asList("python"));
            candidates.add(Arrays.asList("python3"));
        } else {
            candidates.add(Arrays.asList("python3"));
            candidates.add(Arrays.asList("python"));
        }
        return candidates;
    }

    private static void extractRuntime(Path runtimeDir) throws IOException {
        try (BufferedReader reader = new BufferedReader(new InputStreamReader(
                requireResource("resource-manifest.txt"), StandardCharsets.UTF_8))) {
            String line;
            while ((line = reader.readLine()) != null) {
                line = line.trim();
                if (line.isEmpty() || line.startsWith("#")) {
                    continue;
                }

                String[] parts = line.split(" ", 2);
                if (parts.length != 2) {
                    throw new IOException("invalid resource manifest entry: " + line);
                }
                String mode = parts[0];
                String relativePath = parts[1];
                Path target = runtimeDir.resolve(relativePath).normalize();
                if (!target.startsWith(runtimeDir)) {
                    throw new IOException("resource manifest entry escapes runtime directory: " + relativePath);
                }

                Path parent = target.getParent();
                if (parent != null) {
                    Files.createDirectories(parent);
                }
                try (InputStream input = requireResource(relativePath)) {
                    Files.copy(input, target, StandardCopyOption.REPLACE_EXISTING);
                }
                setMode(target, mode);
            }
        }
    }

    private static InputStream requireResource(String relativePath) throws IOException {
        String resourceName = RESOURCE_ROOT + relativePath;
        InputStream input = SSHFling.class.getClassLoader().getResourceAsStream(resourceName);
        if (input == null) {
            throw new IOException("missing bundled resource: " + resourceName);
        }
        return input;
    }

    private static void setMode(Path path, String mode) throws IOException {
        if (isWindows()) {
            return;
        }

        Set<PosixFilePermission> permissions;
        if ("0755".equals(mode)) {
            permissions = EnumSet.of(
                    PosixFilePermission.OWNER_READ,
                    PosixFilePermission.OWNER_WRITE,
                    PosixFilePermission.OWNER_EXECUTE,
                    PosixFilePermission.GROUP_READ,
                    PosixFilePermission.GROUP_EXECUTE,
                    PosixFilePermission.OTHERS_READ,
                    PosixFilePermission.OTHERS_EXECUTE);
        } else if ("0644".equals(mode)) {
            permissions = EnumSet.of(
                    PosixFilePermission.OWNER_READ,
                    PosixFilePermission.OWNER_WRITE,
                    PosixFilePermission.GROUP_READ,
                    PosixFilePermission.OTHERS_READ);
        } else {
            throw new IOException("unsupported bundled resource mode: " + mode);
        }

        Files.setPosixFilePermissions(path, permissions);
    }

    private static void deleteTree(Path root) throws IOException {
        Files.walkFileTree(root, new SimpleFileVisitor<Path>() {
            @Override
            public FileVisitResult visitFile(Path file, BasicFileAttributes attrs) throws IOException {
                Files.deleteIfExists(file);
                return FileVisitResult.CONTINUE;
            }

            @Override
            public FileVisitResult postVisitDirectory(Path dir, IOException exc) throws IOException {
                if (exc != null) {
                    throw exc;
                }
                Files.deleteIfExists(dir);
                return FileVisitResult.CONTINUE;
            }
        });
    }

    private static boolean isWindows() {
        return System.getProperty("os.name", "").toLowerCase().contains("win");
    }

    private static boolean isTruthy(String value) {
        if (value == null) {
            return false;
        }
        String normalized = value.trim().toLowerCase();
        return "1".equals(normalized) || "true".equals(normalized) || "yes".equals(normalized) || "on".equals(normalized);
    }
}
