// Opened by a key (mod.open:jump-waiting): focus the agent that needs you, then close.
// Blocked agents come first, then done; pressing again cycles to the next waiting one.
import { View, div } from "gpui-kit";
import { agents, run, notify, props, closeOverlay, checking } from "herdr";

const URGENCY = { blocked: 2, done: 1 };

export default class JumpWaiting extends View {
  init() {
    if (checking()) return;
    closeOverlay(props().overlay);
    const waitingAgents = agents()
      .filter((agent) => URGENCY[agent.status])
      .sort((a, b) => URGENCY[b.status] - URGENCY[a.status] || b.seq - a.seq);
    if (waitingAgents.length === 0) {
      notify({ title: "No agent is waiting", level: "info", timeout: 2000 });
      return;
    }
    const focusedIndex = waitingAgents.findIndex((agent) => agent.focused);
    const nextAgent = waitingAgents[(focusedIndex + 1) % waitingAgents.length];
    run("agent.focus", { terminal: nextAgent.address });
  }

  render() {
    return div();
  }
}
