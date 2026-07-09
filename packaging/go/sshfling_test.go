package sshfling

import (
	"context"
	"os"
	"path/filepath"
	"runtime"
	"testing"
)

func TestPythonCandidatesHonorsOverride(t *testing.T) {
	t.Setenv("SSHFLING_PYTHON", "/opt/python-custom")

	candidates := PythonCandidates()
	if len(candidates) == 0 || candidates[0].Command != "/opt/python-custom" {
		t.Fatalf("first Python candidate = %#v, want configured executable", candidates)
	}
}

func TestMaterializeRuntime(t *testing.T) {
	scriptPath, templateDir, cleanup, err := materializeRuntime()
	if err != nil {
		t.Fatal(err)
	}
	root := filepath.Dir(scriptPath)
	t.Cleanup(cleanup)

	for _, path := range []string{
		scriptPath,
		filepath.Join(templateDir, ".env.example"),
		filepath.Join(templateDir, "secrets", ".gitkeep"),
		filepath.Join(templateDir, "systemd", "sshfling-prune.timer"),
	} {
		if _, err := os.Stat(path); err != nil {
			t.Errorf("bundled path %s: %v", path, err)
		}
	}

	if runtime.GOOS != "windows" {
		info, err := os.Stat(filepath.Join(templateDir, "scripts", "install-local.sh"))
		if err != nil {
			t.Fatal(err)
		}
		if info.Mode().Perm()&0o111 == 0 {
			t.Errorf("install-local.sh mode = %o, want executable", info.Mode().Perm())
		}
	}

	cleanup()
	if _, err := os.Stat(root); !os.IsNotExist(err) {
		t.Errorf("runtime directory remains after cleanup: %v", err)
	}
}

func TestReleaseVersionWasInjected(t *testing.T) {
	if Version == "0.0.0" {
		t.Fatal("release version placeholder was not replaced")
	}
}

func TestLibraryRun(t *testing.T) {
	if err := Run(context.Background(), []string{"--version"}); err != nil {
		t.Fatal(err)
	}
}
