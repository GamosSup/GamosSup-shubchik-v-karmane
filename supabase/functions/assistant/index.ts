const headers = { "Cache-Control": "no-store" };
const json = (status: number, data: Record<string, unknown>) =>
  Response.json(data, { status, headers });

const projectUrl = Deno.env.get("SUPABASE_URL");
const publicKey = Deno.env.get("SUPABASE_ANON_KEY");
const serverKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

async function authenticate(authorization: string): Promise<boolean> {
  const response = await fetch(`${projectUrl}/auth/v1/user`, {
    headers: { apikey: publicKey!, Authorization: authorization },
    signal: AbortSignal.timeout(5000),
  });
  if (!response.ok) return false;
  const user = await response.json();
  return typeof user.id === "string" && user.is_anonymous !== true;
}

async function reserve(limit: number): Promise<boolean> {
  const response = await fetch(`${projectUrl}/rest/v1/rpc/reserve_assistant_request`, {
    method: "POST",
    headers: {
      apikey: serverKey!,
      Authorization: `Bearer ${serverKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ monthly_limit: limit }),
    signal: AbortSignal.timeout(5000),
  });
  if (!response.ok) throw new Error("quota_unavailable");
  return await response.json() === true;
}

async function askKimi(key: string, model: string, question: string, memory: string) {
  const messages = [
    {
      role: "system",
      content: "Ты помощник приложения «Шубчик в кармане». Отвечай по-русски. " +
        "Давай советы и черновики. Не утверждай, что изменил данные или выполнил действия.",
    },
    {
      role: "user",
      content: memory ? `Контекст, которым пользователь решил поделиться:\n${memory}\n\nВопрос:\n${question}` : question,
    },
  ];
  const response = await fetch("https://api.moonshot.ai/v1/chat/completions", {
    method: "POST",
    headers: { Authorization: `Bearer ${key}`, "Content-Type": "application/json" },
    body: JSON.stringify({ model, messages, max_tokens: 768 }),
    signal: AbortSignal.timeout(22000),
  });
  if (!response.ok) throw new Error("provider_unavailable");
  const data = await response.json();
  const answer = data.choices?.[0]?.message?.content;
  if (typeof answer !== "string" || !answer.trim()) throw new Error("empty_answer");
  return answer;
}

Deno.serve(async (request) => {
  if (request.method !== "POST") return json(405, { error: "method" });
  const authorization = request.headers.get("Authorization") ?? "";
  if (!/^Bearer [^ ]+$/.test(authorization)) return json(401, { error: "sign_in" });
  if (!projectUrl || !publicKey) return json(503, { error: "unavailable" });

  try {
    if (!await authenticate(authorization)) return json(401, { error: "sign_in" });
    const key = Deno.env.get("KIMI_API_KEY");
    const model = Deno.env.get("KIMI_MODEL");
    const limit = Number(Deno.env.get("KIMI_MONTHLY_REQUEST_LIMIT"));
    if (
      Deno.env.get("KIMI_ENABLED") !== "true" || !key || !model || !serverKey ||
      !Number.isInteger(limit) || limit < 1 || limit > 1000
    ) return json(503, { error: "not_configured" });

    const raw = await request.text();
    if (raw.length > 10000) return json(413, { error: "too_large" });
    let input;
    try {
      input = JSON.parse(raw);
    } catch {
      return json(400, { error: "invalid_input" });
    }
    const question = typeof input?.question === "string" ? input.question.trim() : "";
    const memory = typeof input?.memory === "string" ? input.memory.trim() : "";
    if (!question || question.length > 1500 || memory.length > 1000) {
      return json(400, { error: "invalid_input" });
    }
    if (!await reserve(limit)) return json(429, { error: "monthly_limit" });
    return json(200, { answer: await askKimi(key, model, question, memory) });
  } catch {
    return json(503, { error: "unavailable" });
  }
});
