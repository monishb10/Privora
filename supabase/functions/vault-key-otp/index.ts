import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.8";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const json = (body: Record<string, unknown>, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });

function base64ToBytes(value: string): Uint8Array {
  const normalized = value.replace(/-/g, "+").replace(/_/g, "/");
  const padded = normalized.padEnd(Math.ceil(normalized.length / 4) * 4, "=");
  return Uint8Array.from(atob(padded), (character) => character.charCodeAt(0));
}

function bytesToBase64(value: Uint8Array): string {
  let binary = "";
  for (const byte of value) binary += String.fromCharCode(byte);
  return btoa(binary);
}

function decodeJwtPayload(token: string): Record<string, unknown> {
  const pieces = token.split(".");
  if (pieces.length !== 3) throw new Error("Malformed JWT");
  return JSON.parse(new TextDecoder().decode(base64ToBytes(pieces[1])));
}

async function importEncryptionKey(encodedSecret: string): Promise<CryptoKey> {
  const secretBytes = base64ToBytes(encodedSecret.trim());
  if (secretBytes.length !== 32) {
    throw new Error("VAULT_OTP_MASTER_SECRET must be exactly 32 bytes in base64");
  }
  return crypto.subtle.importKey(
    "raw",
    secretBytes,
    { name: "AES-GCM" },
    false,
    ["encrypt", "decrypt"],
  );
}

function additionalData(userId: string): Uint8Array {
  return new TextEncoder().encode(`privora-vault-otp-v1:${userId}`);
}

function hasRecentEmailOtp(payload: Record<string, unknown>): boolean {
  if (!Array.isArray(payload.amr)) return false;
  const now = Math.floor(Date.now() / 1000);
  return payload.amr.some((entry: unknown) => {
    if (!entry || typeof entry !== "object") return false;
    const method = String((entry as Record<string, unknown>).method ?? "");
    const timestamp = Number(
      (entry as Record<string, unknown>).timestamp ?? 0,
    );
    return method === "otp" && timestamp > 0 && now - timestamp <= 10 * 60;
  });
}

serve(async (request: Request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (request.method !== "POST") {
    return json({ error: "Method not allowed." }, 405);
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    const envelopeSecret = Deno.env.get("VAULT_OTP_MASTER_SECRET");
    if (!supabaseUrl || !serviceRoleKey || !envelopeSecret) {
      return json({ error: "PIN reset service is not configured." }, 500);
    }

    const authHeader = request.headers.get("Authorization");
    if (!authHeader?.startsWith("Bearer ")) {
      return json({ error: "A signed-in Privora session is required." }, 401);
    }
    const token = authHeader.slice("Bearer ".length).trim();
    const admin = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    // getUser verifies the token with Supabase Auth. JWT contents are inspected
    // only after this verification succeeds.
    const { data: userData, error: userError } = await admin.auth.getUser(token);
    if (userError || !userData.user) {
      return json({ error: "Your session expired. Sign in again." }, 401);
    }

    const user = userData.user;
    const jwt = decodeJwtPayload(token);
    if (jwt.sub !== user.id) {
      return json({ error: "Invalid account session." }, 401);
    }

    const body = await request.json().catch(() => ({}));
    const action = String(body.action ?? "");
    const encryptionKey = await importEncryptionKey(envelopeSecret);

    if (action === "hasEnvelope") {
      const { data, error } = await admin
        .from("vault_otp_envelopes")
        .select("user_id")
        .eq("user_id", user.id)
        .maybeSingle();
      if (error) return json({ error: "Could not check PIN reset status." }, 500);
      return json({ exists: data != null });
    }

    if (action === "storeEnvelope") {
      const encodedMasterKey = String(body.masterKey ?? "");
      let masterKey: Uint8Array;
      try {
        masterKey = base64ToBytes(encodedMasterKey);
      } catch (_) {
        return json({ error: "Invalid vault key encoding." }, 400);
      }
      if (masterKey.length !== 32) {
        return json({ error: "Invalid vault key length." }, 400);
      }

      const nonce = crypto.getRandomValues(new Uint8Array(12));
      const encrypted = new Uint8Array(
        await crypto.subtle.encrypt(
          { name: "AES-GCM", iv: nonce, additionalData: additionalData(user.id) },
          encryptionKey,
          masterKey,
        ),
      );
      masterKey.fill(0);

      const { error } = await admin.from("vault_otp_envelopes").upsert({
        user_id: user.id,
        encrypted_master_key: bytesToBase64(encrypted),
        nonce: bytesToBase64(nonce),
        crypto_version: 1,
        updated_at: new Date().toISOString(),
      });
      if (error) return json({ error: "Could not save the PIN reset backup." }, 500);

      // Remove the deprecated user-managed recovery-code envelope once its
      // replacement has been stored successfully. This is a one-way cleanup.
      await admin
        .from("vault_keys")
        .update({
          recovery_wrapped_key: null,
          recovery_salt: null,
          recovery_nonce: null,
          has_recovery_code: false,
          updated_at: new Date().toISOString(),
        })
        .eq("user_id", user.id);

      return json({ success: true });
    }

    if (action === "releaseEnvelope") {
      if (!user.email || !user.email_confirmed_at) {
        return json({ error: "A verified Gmail address is required." }, 403);
      }
      if (!hasRecentEmailOtp(jwt)) {
        return json(
          { error: "Verify the fresh 6-digit code sent to your Gmail first." },
          403,
        );
      }

      const tokenEmail = String(jwt.email ?? "").toLowerCase();
      if (tokenEmail !== user.email.toLowerCase()) {
        return json({ error: "OTP account does not match this vault." }, 403);
      }

      const { data: envelope, error } = await admin
        .from("vault_otp_envelopes")
        .select("encrypted_master_key, nonce")
        .eq("user_id", user.id)
        .maybeSingle();
      if (error) return json({ error: "Could not load the PIN reset backup." }, 500);
      if (!envelope) {
        return json(
          { error: "This vault has no Gmail PIN-reset backup yet." },
          404,
        );
      }

      try {
        const decrypted = new Uint8Array(
          await crypto.subtle.decrypt(
            {
              name: "AES-GCM",
              iv: base64ToBytes(envelope.nonce),
              additionalData: additionalData(user.id),
            },
            encryptionKey,
            base64ToBytes(envelope.encrypted_master_key),
          ),
        );
        if (decrypted.length !== 32) throw new Error("Invalid key length");
        const encoded = bytesToBase64(decrypted);
        decrypted.fill(0);
        return json({ masterKey: encoded });
      } catch (_) {
        return json({ error: "PIN reset backup is damaged or unavailable." }, 500);
      }
    }

    return json({ error: "Unknown action." }, 400);
  } catch (error) {
    console.error("vault-key-otp failed", String(error));
    return json({ error: "PIN reset request could not be completed." }, 500);
  }
});
