const projectUrl = Deno.env.get("SUPABASE_URL");
const publicKey = Deno.env.get("SUPABASE_ANON_KEY");
const serverKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
const headers = { "Cache-Control": "no-store" };
const json = (status: number, data: Record<string, unknown>) =>
  Response.json(data, { status, headers });

function recentlyAuthenticated(authorization: string): boolean {
  try {
    const payload = authorization.slice(7).split(".")[1];
    const base64 = payload.replaceAll("-", "+").replaceAll("_", "/");
    const claims = JSON.parse(atob(base64.padEnd(Math.ceil(base64.length / 4) * 4, "=")));
    const now = Date.now() / 1000;
    return Array.isArray(claims.amr) && claims.amr.some(
      (entry: { method?: string; timestamp?: number }) =>
        entry?.method === "password" && typeof entry.timestamp === "number" &&
        entry.timestamp <= now + 10 && entry.timestamp > now - 300,
    );
  } catch {
    return false;
  }
}

Deno.serve(async (request) => {
  if (request.method !== "POST") return json(405, { error: "method" });
  const authorization = request.headers.get("Authorization") ?? "";
  if (!/^Bearer [^ ]+$/.test(authorization)) return json(401, { error: "sign_in" });
  if (!projectUrl || !publicKey || !serverKey) return json(503, { error: "unavailable" });
  try {
    const authenticated = await fetch(`${projectUrl}/auth/v1/user`, {
      headers: { apikey: publicKey, Authorization: authorization },
      signal: AbortSignal.timeout(5000),
    });
    if (!authenticated.ok) return json(401, { error: "sign_in" });
    const user = await authenticated.json();
    if (typeof user.id !== "string" || user.is_anonymous === true ||
      !/^[a-f0-9]{8}(-[a-f0-9]{4}){3}-[a-f0-9]{12}$/i.test(user.id)) {
      return json(401, { error: "sign_in" });
    }
    if (!recentlyAuthenticated(authorization)) return json(403, { error: "reauthenticate" });
    const deleted = await fetch(`${projectUrl}/auth/v1/admin/users/${user.id}`, {
      method: "DELETE",
      headers: {
        apikey: serverKey,
        Authorization: `Bearer ${serverKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ should_soft_delete: false }),
      signal: AbortSignal.timeout(8000),
    });
    if (!deleted.ok) return json(503, { error: "unavailable" });
    return json(200, { deleted: true });
  } catch {
    return json(503, { error: "unavailable" });
  }
});
