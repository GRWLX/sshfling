export interface RunOptions {
  cwd?: string;
  env?: Record<string, string | undefined>;
  platform?: string;
  pythonCandidates?: string[][];
  scriptPath?: string;
  stdio?: "inherit" | "pipe" | "ignore" | Array<unknown>;
  templateDir?: string;
}

export function run(args?: string[], options?: RunOptions): number;
export function pythonCandidates(env?: Record<string, string | undefined>, platform?: string): string[][];
export function normalizeTemplateModes(root?: string, platform?: string): void;
export function runtimePath(): string;
export function templateDir(): string;

declare const sshfling: {
  run: typeof run;
  pythonCandidates: typeof pythonCandidates;
  normalizeTemplateModes: typeof normalizeTemplateModes;
  runtimePath: typeof runtimePath;
  templateDir: typeof templateDir;
};

export default sshfling;
