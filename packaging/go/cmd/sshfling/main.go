package main

import (
	"context"
	"fmt"
	"os"

	sshfling "github.com/GRWLX/sshfling/packaging/go"
)

func main() {
	err := sshfling.Run(context.Background(), os.Args[1:])
	if err != nil {
		if sshfling.ExitCode(err) == 1 {
			fmt.Fprintf(os.Stderr, "sshfling: %v\n", err)
		}
		os.Exit(sshfling.ExitCode(err))
	}
}
