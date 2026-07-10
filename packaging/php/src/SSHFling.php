<?php

declare(strict_types=1);

namespace GRWLX\SSHFling;

use RuntimeException;

final class SSHFling
{
    /** @return list<array{0: string, 1: list<string>}> */
    public static function pythonCandidates(): array
    {
        $candidates = [];
        $configured = trim((string) getenv('SSHFLING_PYTHON'));
        if ($configured !== '') {
            $candidates[] = [$configured, []];
        }

        if (PHP_OS_FAMILY === 'Windows') {
            $candidates[] = ['py', ['-3']];
            $candidates[] = ['python', []];
            $candidates[] = ['python3', []];
        } else {
            $candidates[] = ['python3', []];
            $candidates[] = ['python', []];
        }
        return $candidates;
    }

    public static function runtimePath(): string
    {
        return dirname(__DIR__) . DIRECTORY_SEPARATOR . 'runtime' . DIRECTORY_SEPARATOR . 'sshfling.py';
    }

    public static function templateDir(): string
    {
        return dirname(__DIR__) . DIRECTORY_SEPARATOR . 'runtime' . DIRECTORY_SEPARATOR . 'templates';
    }

    /** @param list<string> $arguments */
    public static function run(array $arguments): int
    {
        self::normalizeTemplateModes();
        $environment = getenv();
        if (!is_array($environment)) {
            $environment = [];
        }
        $environment['PYTHONUNBUFFERED'] = '1';
        $environment['SSHFLING_TEMPLATE_DIR'] = self::templateDir();

        foreach (self::pythonCandidates() as [$program, $fixedArguments]) {
            if (!self::commandExists($program)) {
                continue;
            }
            $command = array_merge([$program], $fixedArguments, [self::runtimePath()], $arguments);
            $process = proc_open(
                $command,
                [STDIN, STDOUT, STDERR],
                $pipes,
                null,
                $environment,
                ['bypass_shell' => true]
            );
            if (!is_resource($process)) {
                continue;
            }
            return proc_close($process);
        }

        throw new RuntimeException('Python 3 is required; set SSHFLING_PYTHON to its executable.');
    }

    private static function normalizeTemplateModes(): void
    {
        $runtimeRoot = dirname(self::runtimePath());
        $executables = [
            'sshfling.py',
            'templates/native/sshfling-linux-account',
            'templates/native/sshfling-unix-identity',
            'templates/production/sshfling-login-shell',
            'templates/production/sshfling-session',
            'templates/scripts/create-network.sh',
            'templates/scripts/generate-ssh-key.sh',
            'templates/scripts/install-local.sh',
            'templates/scripts/uninstall-local.sh',
            'templates/ssh-client/entrypoint.sh',
            'templates/ssh-server/entrypoint.sh',
            'templates/ssh-server/limited-session.sh',
        ];
        foreach ($executables as $relative) {
            $path = $runtimeRoot . DIRECTORY_SEPARATOR . str_replace('/', DIRECTORY_SEPARATOR, $relative);
            if (is_file($path)) {
                @chmod($path, 0755);
            }
        }
    }

    private static function commandExists(string $command): bool
    {
        if (str_contains($command, '/') || str_contains($command, '\\')) {
            return is_file($command);
        }

        $path = (string) getenv('PATH');
        if ($path === '') {
            return false;
        }
        $extensions = [''];
        if (PHP_OS_FAMILY === 'Windows') {
            $pathExtensions = (string) getenv('PATHEXT');
            $extensions = $pathExtensions !== '' ? explode(PATH_SEPARATOR, $pathExtensions) : ['.EXE', '.BAT', '.CMD'];
            array_unshift($extensions, '');
        }

        foreach (explode(PATH_SEPARATOR, $path) as $directory) {
            foreach ($extensions as $extension) {
                $candidate = rtrim($directory, DIRECTORY_SEPARATOR) . DIRECTORY_SEPARATOR . $command . $extension;
                if (is_file($candidate) && (PHP_OS_FAMILY === 'Windows' || is_executable($candidate))) {
                    return true;
                }
            }
        }
        return false;
    }
}
