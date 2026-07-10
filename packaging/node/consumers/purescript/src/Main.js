import sshfling from "sshfling";

// PureScript's foreign module executes in Node, never in a browser bundle.
export const status = sshfling.run(["--version"], { stdio: "pipe" });
export const templatePath = sshfling.templateDir();
