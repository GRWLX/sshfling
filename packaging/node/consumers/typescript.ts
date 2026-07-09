import sshfling, { RunOptions, run, templateDir } from "sshfling";

const options: RunOptions = { stdio: "pipe" };
const directStatus: number = run(["--version"], options);
const defaultStatus: number = sshfling.run(["--version"], options);
const templates: string = templateDir();

void [directStatus, defaultStatus, templates];
