/**
 * Bridges pi-agents' internal run event bus to the OrchestratorAI - Pi RPC UI.
 *
 * The event stream is intentionally summarized before crossing the RPC
 * boundary. The native app receives the workflow tree and node lifecycle, not
 * model hidden reasoning or full intermediate payloads.
 */

type TraceEvent = {
  type: string;
  at?: number;
  runId?: string;
  path?: string;
  instance?: string;
  kind?: string;
  agent?: string;
  label?: string;
  run?: {
    id?: string;
    label?: string;
    source?: { workflow?: string; kind?: string };
  };
  status?: string;
  error?: string;
  agents?: number;
};

const CHANNEL = "pi-agents:run-event";
const MAX_LINES = 80;

function readableNode(event: TraceEvent): string {
  // Keep internal paths and dynamic map indexes out of the user-facing trace.
  return event.agent ?? event.label ?? event.kind ?? "node";
}

function formatEvent(event: TraceEvent): string {
  switch (event.type) {
    case "run_created": {
      const workflow = event.run?.source?.workflow ?? "workflow";
      const label = event.run?.label ? ` — ${event.run.label}` : "";
      return `▶ Started ${workflow}${label}`;
    }
    case "node_started":
      return `↳ Started ${readableNode(event)}`;
    case "node_completed":
      return `✓ Completed ${readableNode(event)}`;
    case "node_failed":
      return `✗ Failed ${readableNode(event)}${event.error ? ` — ${event.error}` : ""}`;
    case "node_cancelled":
      return `⊘ Cancelled ${readableNode(event)}`;
    case "node_steered":
      return `↝ Steered ${readableNode(event)}`;
    case "loop_iteration":
      return `⟳ Iteration ${event.instance ?? event.path ?? "loop"}`;
    case "run_backgrounded":
      return "… Workflow running in background";
    case "run_completed":
      return event.status === "completed"
        ? `■ Workflow completed · ${event.agents ?? 0} agent calls`
        : `! Workflow ${event.status ?? "finished"}${event.error ? ` — ${event.error}` : ""}`;
    default:
      return `• ${event.type}`;
  }
}

export default function orchestratorTrace(pi: any) {
  const lines: string[] = [];
  let activeRunId: string | undefined;
  let uiContext: any;

  pi.on("session_start", (_event: unknown, ctx: any) => {
    uiContext = ctx;
    if (ctx?.hasUI) {
      ctx.ui.setStatus("orchestratorai-trace", "Watching workflow activity");
    }
  });

  pi.events.on(CHANNEL, (envelope: { protocol?: number; event?: TraceEvent }) => {
    const event = envelope?.event;
    if (!event || typeof event.type !== "string") return;

    if (event.type === "run_created") {
      activeRunId = event.run?.id;
      lines.splice(0, lines.length);
    } else if (event.runId && activeRunId && event.runId !== activeRunId) {
      return;
    }

    const formatted = formatEvent(event);
    if (lines.includes(formatted)) return;
    lines.push(formatted);
    while (lines.length > MAX_LINES) lines.shift();

    const status = lines.at(-1) ?? "Workflow activity";
    if (uiContext?.hasUI) {
      uiContext.ui.setWidget("orchestratorai-trace", [
        "ORCH_TRACE",
        JSON.stringify({ runId: activeRunId, event, lines: [...lines], status }),
      ]);
      uiContext.ui.setStatus("orchestratorai-trace", status);
    }

    pi.events.emit("orchestratorai:trace", {
      protocol: 1,
      runId: activeRunId,
      event,
      lines: [...lines],
      status,
    });
  });

  pi.events.on("orchestratorai:trace", (message: { lines?: string[]; status?: string }) => {
    // setWidget is supported in Pi RPC mode and is harmless in the TUI.
    // The native app consumes the same request as a live activity stream.
    // This second bus hop keeps the event subscriber independent of UI policy.
    if (message?.lines) {
      pi.events.emit("orchestratorai:trace:ui", message);
    }
  });

}
