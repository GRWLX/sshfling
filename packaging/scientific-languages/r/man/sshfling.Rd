\name{sshfling}
\alias{run}
\alias{runtime_path}
\alias{template_directory}
\title{Run the Bundled SSHFling Runtime}
\description{
Locate and execute the canonical SSHFling runtime and its installed templates.
}
\usage{
run(args = character())

runtime_path()

template_directory()
}
\arguments{
  \item{args}{A character vector of SSHFling command-line arguments.}
}
\value{
\code{run} returns an integer process status. The path helpers return a
single character string.
}
