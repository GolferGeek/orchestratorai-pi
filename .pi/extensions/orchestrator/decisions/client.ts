import type { Question, SystemOneRequest, SystemOneResponse } from "./types.ts";

export interface DecisionClientOptions {
  /** e.g. http://gg-macstudio:11434. Defaults to DECISION_BASE_URL. */
  baseUrl?: string;
  /** clef or clef-flash. Defaults to DECISION_MODEL, then clef. */
  model?: string;
  /** Sent as a Bearer token when set (a hosted endpoint); Ollama ignores it. Defaults to DECISION_API_KEY. */
  apiKey?: string;
  /** Injected for tests; defaults to globalThis.fetch. */
  fetch?: typeof fetch;
  /** Defaults to DECISION_TIMEOUT_MS, then 120 s: a cold Clef load takes tens of seconds. */
  timeoutMs?: number;
}

export class DecisionError extends Error {
  // Plain fields, not parameter properties: Node's type stripping (the case runner) rejects those.
  readonly status?: number;
  readonly body?: unknown;
  constructor(message: string, status?: number, body?: unknown) {
    super(message);
    this.name = "DecisionError";
    this.status = status;
    this.body = body;
  }
}

export interface DecisionModel {
  name: string;
  parameterSize?: string;
}

export const DEFAULT_DECISION_MODEL = "clef";

/** Ollama wants raw base64; callers and fixtures carry data:image/... URLs. */
export function toRawBase64(image: string): string {
  return image.startsWith("data:") ? image.slice(image.indexOf(",") + 1) : image;
}

/** Client for a /v1/systemone endpoint (Ollama today). fetch-only, no Node dependencies. */
export class DecisionClient {
  readonly baseUrl: string;
  readonly model: string;
  private readonly apiKey: string;
  private readonly fetchImpl: typeof fetch;
  private readonly timeoutMs: number;

  constructor(options: DecisionClientOptions = {}) {
    const env = (globalThis as { process?: { env?: Record<string, string | undefined> } }).process?.env ?? {};
    const baseUrl = options.baseUrl ?? env.DECISION_BASE_URL;
    if (!baseUrl) throw new DecisionError("DECISION_BASE_URL is not set: point it at Ollama on the Mac Studio, e.g. http://gg-macstudio:11434");
    this.baseUrl = baseUrl.replace(/\/$/, "");
    this.model = options.model || env.DECISION_MODEL || DEFAULT_DECISION_MODEL;
    this.apiKey = options.apiKey ?? env.DECISION_API_KEY ?? "";
    this.fetchImpl = options.fetch ?? globalThis.fetch;
    this.timeoutMs = options.timeoutMs ?? (Number(env.DECISION_TIMEOUT_MS) || 120_000);
  }

  /** Ask any mix of questions about one state in a single request. */
  async ask(state: SystemOneRequest["state"], questions: Record<string, Question>, model?: string, images?: string[]): Promise<SystemOneResponse> {
    const body: SystemOneRequest = { state, model: model || this.model, questions, ...(images?.length ? { images: images.map(toRawBase64) } : {}) };
    return (await this.request("/v1/systemone", { method: "POST", body: JSON.stringify(body) })) as SystemOneResponse;
  }

  /** The decision models the endpoint has pulled (Ollama marks them with the `decision` capability). */
  async models(): Promise<DecisionModel[]> {
    const res = (await this.request("/api/tags", { method: "GET" }, 5_000)) as {
      models?: Array<{ name: string; capabilities?: string[]; details?: { parameter_size?: string } }>;
    };
    return (res.models ?? [])
      .filter((m) => m.capabilities?.includes("decision"))
      .map((m) => ({ name: m.name.replace(/:latest$/, ""), parameterSize: m.details?.parameter_size }));
  }

  private async request(path: string, init: RequestInit, timeoutMs = this.timeoutMs): Promise<unknown> {
    const res = await this.fetchImpl(`${this.baseUrl}${path}`, {
      ...init,
      headers: { "Content-Type": "application/json", ...(this.apiKey ? { Authorization: `Bearer ${this.apiKey}` } : {}) },
      signal: AbortSignal.timeout(timeoutMs),
    });
    const text = await res.text();
    let body: unknown = text;
    try { body = JSON.parse(text); } catch { /* keep text */ }
    if (!res.ok) {
      const detail = typeof body === "object" && body && "error" in body ? String((body as { error: unknown }).error) : text;
      throw new DecisionError(`decision model ${res.status}: ${detail}`, res.status, body);
    }
    return body;
  }
}
