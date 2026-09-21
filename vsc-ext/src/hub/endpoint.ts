/** The one ingest port. It is the hub's single-instance lock. */

export const HUB_PORT = 17890;
export const HUB_HOST = "127.0.0.1";
export const HUB_ORIGIN = `http://${HUB_HOST}:${HUB_PORT}`;
export const HEALTH_PATH = "/v1/health";
export const JOBS_PATH = "/v1/jobs";
export const REFRESH_PATH = "/v1/refresh";
export const STREAM_PATH = "/v1/stream?surface=vscode";
