"""Python package surface for the SSHFling command-line tool."""

from .cli import VERSION, main

__version__ = VERSION
run = main
__all__ = ["VERSION", "__version__", "main", "run"]
