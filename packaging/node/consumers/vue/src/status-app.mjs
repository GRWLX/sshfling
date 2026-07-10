import { existsSync } from "node:fs";
import sshfling from "sshfling";
import { defineComponent, h } from "vue";

export const StatusApp = defineComponent({
  name: "SshflingStatusApp",
  setup() {
    // setup() runs under the Vue server renderer in this consumer.
    const exitCode = sshfling.run(["--version"], { stdio: "pipe" });
    const ready = exitCode === 0 && existsSync(sshfling.templateDir());

    return () => h(
      "main",
      { "data-runtime": "node", "data-sshfling-ready": String(ready) },
      [
        h("h1", "SSHFling server status"),
        h("p", ready
          ? "The Node library and bundled templates are available."
          : "The server-side check failed."),
      ],
    );
  },
});
