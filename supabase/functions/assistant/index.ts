import { handleAssistant } from "../_shared/assistant.ts";

Deno.serve((request) => handleAssistant(request, false));
