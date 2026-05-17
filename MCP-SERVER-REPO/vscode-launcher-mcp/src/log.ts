import * as vscode from 'vscode';

export const outputChannel = vscode.window.createOutputChannel('LAUncher MCP');

export function log(line: string): void {
  outputChannel.appendLine(line);
}
