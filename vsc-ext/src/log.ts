import * as vscode from "vscode";

/** VS Code log output channel. Open via Output → Nerve. */
export type NerveLog = vscode.LogOutputChannel;

export function createNerveLog(): NerveLog {
  return vscode.window.createOutputChannel("Nerve", { log: true });
}
