// Package sshfling runs the bundled SSHFling command-line runtime.
package sshfling

import (
	"context"
	"embed"
	"errors"
	"fmt"
	"io/fs"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
)

// Version is replaced with the release version by packaging/build-go.sh.
const Version = "0.0.0"

//go:embed all:runtime
var bundledRuntime embed.FS

var executableRuntimeFiles = map[string]bool{
	"runtime/sshfling.py":                             true,
	"runtime/templates/native/sshfling-linux-account": true,
	"runtime/templates/native/sshfling-unix-identity": true,
	"runtime/templates/production/sshfling-session":   true,
	"runtime/templates/scripts/create-network.sh":     true,
	"runtime/templates/scripts/generate-ssh-key.sh":   true,
	"runtime/templates/scripts/install-local.sh":      true,
	"runtime/templates/scripts/uninstall-local.sh":    true,
	"runtime/templates/ssh-client/entrypoint.sh":      true,
	"runtime/templates/ssh-server/entrypoint.sh":      true,
	"runtime/templates/ssh-server/limited-session.sh": true,
}

// PythonCandidate is an executable and any fixed arguments used to start Python.
type PythonCandidate struct {
	Command string
	Args    []string
}

// PythonCandidates returns interpreter choices in platform preference order.
func PythonCandidates() []PythonCandidate {
	candidates := make([]PythonCandidate, 0, 4)
	if configured := strings.TrimSpace(os.Getenv("SSHFLING_PYTHON")); configured != "" {
		candidates = append(candidates, PythonCandidate{Command: configured})
	}
	if runtime.GOOS == "windows" {
		candidates = append(candidates,
			PythonCandidate{Command: "py", Args: []string{"-3"}},
			PythonCandidate{Command: "python"},
			PythonCandidate{Command: "python3"},
		)
	} else {
		candidates = append(candidates,
			PythonCandidate{Command: "python3"},
			PythonCandidate{Command: "python"},
		)
	}
	return candidates
}

// ExitError reports a non-zero exit status returned by the bundled CLI.
type ExitError struct {
	Code int
}

func (e *ExitError) Error() string {
	return fmt.Sprintf("sshfling exited with status %d", e.Code)
}

// ExitCode returns the bundled CLI status, or 1 for launcher errors.
func ExitCode(err error) int {
	if err == nil {
		return 0
	}
	var exitErr *ExitError
	if errors.As(err, &exitErr) && exitErr.Code > 0 {
		return exitErr.Code
	}
	return 1
}

// Run executes SSHFling with inherited standard streams.
func Run(ctx context.Context, args []string) error {
	python, err := findPython()
	if err != nil {
		return err
	}

	scriptPath, templateDir, cleanup, err := materializeRuntime()
	if err != nil {
		return err
	}
	defer cleanup()

	commandArgs := append([]string{}, python.Args...)
	commandArgs = append(commandArgs, scriptPath)
	commandArgs = append(commandArgs, args...)
	cmd := exec.CommandContext(ctx, python.Command, commandArgs...)
	cmd.Stdin = os.Stdin
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	cmd.Env = environmentWith(os.Environ(), map[string]string{
		"PYTHONUNBUFFERED":      "1",
		"SSHFLING_TEMPLATE_DIR": templateDir,
	})

	if err := cmd.Run(); err != nil {
		if ctxErr := ctx.Err(); ctxErr != nil {
			return ctxErr
		}
		var processErr *exec.ExitError
		if errors.As(err, &processErr) {
			return &ExitError{Code: processErr.ExitCode()}
		}
		return fmt.Errorf("start SSHFling with %s: %w", python.Command, err)
	}
	return nil
}

func findPython() (PythonCandidate, error) {
	for _, candidate := range PythonCandidates() {
		if _, err := exec.LookPath(candidate.Command); err == nil {
			return candidate, nil
		}
	}
	return PythonCandidate{}, errors.New("Python 3 is required; set SSHFLING_PYTHON to its executable")
}

func materializeRuntime() (string, string, func(), error) {
	root, err := os.MkdirTemp("", "sshfling-go-")
	if err != nil {
		return "", "", func() {}, fmt.Errorf("create runtime directory: %w", err)
	}
	cleanup := func() { _ = os.RemoveAll(root) }

	err = fs.WalkDir(bundledRuntime, "runtime", func(path string, entry fs.DirEntry, walkErr error) error {
		if walkErr != nil {
			return walkErr
		}
		relative := strings.TrimPrefix(path, "runtime")
		target := filepath.Join(root, filepath.FromSlash(relative))
		if entry.IsDir() {
			return os.MkdirAll(target, 0o755)
		}
		data, readErr := bundledRuntime.ReadFile(path)
		if readErr != nil {
			return readErr
		}
		mode := fs.FileMode(0o644)
		if executableRuntimeFiles[path] {
			mode = 0o755
		}
		return os.WriteFile(target, data, mode)
	})
	if err != nil {
		cleanup()
		return "", "", func() {}, fmt.Errorf("extract bundled SSHFling runtime: %w", err)
	}

	return filepath.Join(root, "sshfling.py"), filepath.Join(root, "templates"), cleanup, nil
}

func environmentWith(current []string, updates map[string]string) []string {
	result := make([]string, 0, len(current)+len(updates))
	for _, item := range current {
		key, _, found := strings.Cut(item, "=")
		if found {
			if _, replaced := updates[key]; replaced {
				continue
			}
		}
		result = append(result, item)
	}
	for key, value := range updates {
		result = append(result, key+"="+value)
	}
	return result
}
