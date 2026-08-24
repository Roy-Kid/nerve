/** Split an SSE byte stream into `data:` payloads. */

export class SseParser {
  private buffer = "";

  push(chunk: string): string[] {
    this.buffer += chunk;
    const events: string[] = [];
    for (;;) {
      const boundary = this.buffer.search(/\r?\n\r?\n/);
      if (boundary < 0) break;
      const block = this.buffer.slice(0, boundary);
      this.buffer = this.buffer.slice(boundary).replace(/^\r?\n\r?\n/, "");
      const data = dataOf(block);
      if (data !== undefined) events.push(data);
    }
    return events;
  }

  reset(): void {
    this.buffer = "";
  }
}

function dataOf(block: string): string | undefined {
  const lines: string[] = [];
  for (const line of block.split(/\r?\n/)) {
    if (line.startsWith(":")) continue;
    if (line.startsWith("data:")) {
      lines.push(line.slice(5).replace(/^ /, ""));
    }
  }
  if (lines.length === 0) return undefined;
  return lines.join("\n");
}
