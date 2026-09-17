/**
 * Paths as they travel on the wire.
 *
 * A job's location is a string written by whichever machine reported it, and
 * this extension shows other machines' jobs by design. So nothing here asks
 * whether a path is absolute *here* — it asks what shape the string is. Same
 * rules as `nerve_platform::path` on the Rust side, which is what encoded the
 * `openURL` these functions read back.
 */

export type PathStyle = "posix" | "windows";

const DRIVE_ROOTED = /^[A-Za-z]:[\\/]/;
const DRIVE_ONLY = /^[A-Za-z]:$/;

/**
 * The style of an *absolute* path, or `undefined` when it is not one.
 *
 * `C:work` is deliberately not absolute: it names a directory relative to the
 * current one on drive C, and a drive letter alone does not root a path.
 */
export function pathStyle(path: string): PathStyle | undefined {
  if (path.startsWith("/")) return "posix";
  if (path.startsWith("\\\\")) return "windows";
  if (DRIVE_ROOTED.test(path)) return "windows";
  return undefined;
}

export function isAbsolutePath(path: string): boolean {
  return pathStyle(path) !== undefined;
}

/**
 * Compare paths the way the OS that wrote them would.
 *
 * Windows separators are interchangeable and its filesystems are
 * case-insensitive; POSIX has neither property, and folding case there would
 * call two genuinely different directories the same one.
 */
function normalise(path: string, style: PathStyle): string {
  let out = style === "windows" ? path.replace(/\\/g, "/") : path;
  while (out.length > 1 && out.endsWith("/")) out = out.slice(0, -1);
  return style === "windows" ? out.toLowerCase() : out;
}

/** Is `candidate` the same place as `root`, or inside it? */
export function isInside(candidate: string, root: string): boolean {
  const style = pathStyle(candidate) ?? pathStyle(root) ?? "posix";
  const c = normalise(candidate, style);
  const r = normalise(root, style);
  return c === r || c.startsWith(`${r}/`);
}

/**
 * `file:///Users/me/proj` → `/Users/me/proj`,
 * `file:///C:/work` → `C:/work`.
 *
 * Tolerant of the shapes found in the wild: the `localhost` authority, a drive
 * letter with or without the RFC's leading slash, and a drive colon that
 * arrived percent-escaped (`file:///c%3A/work`), which some VS Code builds
 * produce.
 */
export function pathFromFileUri(uri: string): string | undefined {
  const trimmed = uri.trim();
  if (!trimmed.startsWith("file://")) return undefined;
  let rest = trimmed.slice("file://".length);
  for (const authority of ["//localhost", "localhost"]) {
    if (rest.startsWith(authority)) {
      rest = rest.slice(authority.length);
      break;
    }
  }
  const decoded = decode(rest);
  if (decoded.startsWith("/")) {
    const afterSlash = decoded.slice(1);
    // The slash belongs to the URL, not to the path.
    if (isDriveRooted(afterSlash)) return afterSlash;
    return decoded;
  }
  if (isDriveRooted(decoded)) return decoded;
  if (!decoded) return undefined;
  // Anything left in the authority is a UNC server.
  return `\\\\${decoded.replace(/\//g, "\\")}`;
}

function isDriveRooted(path: string): boolean {
  return DRIVE_ROOTED.test(path) || DRIVE_ONLY.test(path);
}

/** Percent-decoding that degrades instead of throwing on a bad escape. */
export function decode(value: string): string {
  try {
    return decodeURIComponent(value);
  } catch {
    return value;
  }
}
