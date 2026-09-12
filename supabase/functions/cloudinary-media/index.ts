import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.8";

// Standard CORS headers
const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

// Compute SHA-1 hex digest using standard Web Crypto API
async function computeSha1(data: string): Promise<string> {
  const encoder = new TextEncoder();
  const buffer = encoder.encode(data);
  const hashBuffer = await crypto.subtle.digest("SHA-1", buffer);
  const hashArray = Array.from(new Uint8Array(hashBuffer));
  return hashArray.map((b) => b.toString(16).padStart(2, "0")).join("");
}

// Generate Cloudinary signature for upload, download, or destroy
// Alphabetical sorting of all signed parameters is strictly enforced
async function signCloudinaryParams(
  params: Record<string, string | number>,
  apiSecret: string,
): Promise<string> {
  const sortedKeys = Object.keys(params).sort();
  const toSign = sortedKeys.map((k) => `${k}=${params[k]}`).join("&") + apiSecret;
  return await computeSha1(toSign);
}

serve(async (req: Request) => {
  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    // 1. Verify Cloudinary and Supabase configuration secrets
    const cloudName = Deno.env.get("CLOUDINARY_CLOUD_NAME")?.trim();
    const apiKey = Deno.env.get("CLOUDINARY_API_KEY")?.trim();
    const apiSecret = Deno.env.get("CLOUDINARY_API_SECRET")?.trim();
    const uploadPreset = Deno.env.get("CLOUDINARY_UPLOAD_PRESET")?.trim() || "privora_signed";
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

    if (!cloudName || !apiKey || !apiSecret || !uploadPreset || !supabaseUrl || !supabaseServiceKey) {
      const missing: string[] = [];
      if (!cloudName) missing.push("CLOUDINARY_CLOUD_NAME");
      if (!apiKey) missing.push("CLOUDINARY_API_KEY");
      if (!apiSecret) missing.push("CLOUDINARY_API_SECRET");
      if (!uploadPreset) missing.push("CLOUDINARY_UPLOAD_PRESET");
      if (!supabaseUrl) missing.push("SUPABASE_URL");
      if (!supabaseServiceKey) missing.push("SUPABASE_SERVICE_ROLE_KEY");
      return new Response(
        JSON.stringify({
          error: `Cloudinary or Supabase server configuration missing: ${missing.join(", ")}`,
        }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    // Parse request body
    const body = await req.json().catch(() => ({}));
    const { action } = body;

    // Admin database client for ownership checks and database mutations
    const dbClient = createClient(supabaseUrl, supabaseServiceKey);

    // 2. Validate Supabase JWT from Authorization Header
    const authHeader = req.headers.get("Authorization");
    if (!authHeader || !authHeader.startsWith("Bearer ")) {
      return new Response(
        JSON.stringify({ error: "Missing or invalid authorization header." }),
        { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    const jwtToken = authHeader.replace("Bearer ", "").trim();
    const isServiceRole = jwtToken === supabaseServiceKey ||
      (() => {
        try {
          const parts = jwtToken.split(".");
          if (parts.length === 3) {
            let b64 = parts[1].replace(/-/g, "+").replace(/_/g, "/");
            while (b64.length % 4 !== 0) b64 += "=";
            const payload = JSON.parse(atob(b64));
            return payload && payload.role === "service_role";
          }
        } catch (_) {}
        return false;
      })();

    let userId = "";
    if (isServiceRole) {
      userId = body.userId || "";
    } else {
      const userClient = createClient(supabaseUrl, supabaseServiceKey, {
        auth: { persistSession: false },
      });
      const { data: userData, error: userError } = await userClient.auth.getUser(jwtToken);
      if (userError || !userData?.user) {
        return new Response(
          JSON.stringify({ error: "Unauthorized: Invalid or expired session." }),
          { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } },
        );
      }
      userId = userData.user.id;
    }

    // Cloudinary Admin API Basic Auth
    const basicAuthHeader = `Basic ${btoa(`${apiKey}:${apiSecret}`)}`;

    // Helper: Destroy asset on Cloudinary
    const destroyAsset = async (pubId: string | null) => {
      if (!pubId) return true;
      const timestamp = Math.floor(Date.now() / 1000);
      const signature = await signCloudinaryParams(
        {
          public_id: pubId,
          timestamp: timestamp,
          type: "authenticated",
        },
        apiSecret,
      );

      const formData = new FormData();
      formData.append("public_id", pubId);
      formData.append("timestamp", timestamp.toString());
      formData.append("type", "authenticated");
      formData.append("api_key", apiKey);
      formData.append("signature", signature);

      const res = await fetch(`https://api.cloudinary.com/v1_1/${cloudName}/raw/destroy`, {
        method: "POST",
        body: formData,
      });
      const result = await res.json().catch(() => ({}));
      return result.result === "ok" || result.result === "not found";
    };

    // Helper: Query Cloudinary Admin API for raw asset metadata
    const queryCloudinaryAsset = async (pubId: string, deliveryType = "authenticated") => {
      try {
        const url = `https://api.cloudinary.com/v1_1/${cloudName}/resources/raw/${deliveryType}/${encodeURIComponent(pubId)}`;
        const res = await fetch(url, {
          method: "GET",
          headers: { Authorization: basicAuthHeader },
        });
        if (res.status === 200) {
          return await res.json();
        }
      } catch (err) {
        console.warn(`Admin API query error for ${pubId} (${deliveryType}):`, err);
      }
      return null;
    };

    // -------------------------------------------------------------------------
    // ACTION 1: createUploadSignature
    // -------------------------------------------------------------------------
    if (action === "createUploadSignature") {
      const { categoryId, photoId: requestedPhotoId } = body;

      if (!categoryId) {
        return new Response(
          JSON.stringify({ error: "Missing required categoryId." }),
          { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } },
        );
      }

      // Verify category exists and strictly belongs to auth.uid()
      const { data: category, error: catError } = await dbClient
        .from("categories")
        .select("id")
        .eq("id", categoryId)
        .eq("user_id", userId)
        .maybeSingle();

      if (catError || !category) {
        return new Response(
          JSON.stringify({ error: "Access denied: Category not found or unowned." }),
          { status: 403, headers: { ...corsHeaders, "Content-Type": "application/json" } },
        );
      }

      const photoId = requestedPhotoId && typeof requestedPhotoId === "string" && requestedPhotoId.length === 36
        ? requestedPhotoId
        : crypto.randomUUID();

      const fullPublicId = `privora/${userId}/${categoryId}/${photoId}`;
      const thumbPublicId = `privora/${userId}/${categoryId}/${photoId}_thumb`;

      const timestamp = Math.floor(Date.now() / 1000).toString();

      const fullSignedParams: Record<string, string> = {
        public_id: fullPublicId,
        timestamp: timestamp,
        type: "authenticated",
      };
      if (uploadPreset && uploadPreset.length > 0) {
        fullSignedParams["upload_preset"] = uploadPreset;
      }
      const fullSignature = await signCloudinaryParams(fullSignedParams, apiSecret);

      const thumbSignedParams: Record<string, string> = {
        public_id: thumbPublicId,
        timestamp: timestamp,
        type: "authenticated",
      };
      if (uploadPreset && uploadPreset.length > 0) {
        thumbSignedParams["upload_preset"] = uploadPreset;
      }
      const thumbSignature = await signCloudinaryParams(thumbSignedParams, apiSecret);

      try {
        await dbClient.from("pending_uploads").upsert(
          {
            user_id: userId,
            category_id: categoryId,
            photo_id: photoId,
            full_public_id: fullPublicId,
            thumbnail_public_id: thumbPublicId,
            status: "pending",
            updated_at: new Date().toISOString(),
          },
          { onConflict: "photo_id" },
        );
      } catch (err) {
        console.warn("pending_uploads upsert skipped:", err);
      }

      return new Response(
        JSON.stringify({
          cloudName,
          apiKey,
          timestamp: parseInt(timestamp, 10),
          uploadPreset: uploadPreset || null,
          photoId,
          full: {
            publicId: fullPublicId,
            signature: fullSignature,
            signedParams: fullSignedParams,
          },
          thumbnail: {
            publicId: thumbPublicId,
            signature: thumbSignature,
            signedParams: thumbSignedParams,
          },
        }),
        { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    // -------------------------------------------------------------------------
    // ACTION 2: commitUpload
    // -------------------------------------------------------------------------
    if (action === "commitUpload") {
      const {
        photoId,
        categoryId,
        displayName,
        mimeType,
        encryptedSize,
        width,
        height,
        fullPublicId,
        thumbnailPublicId,
        fullAssetId,
        thumbnailAssetId,
        fullVersion,
        fullBytes,
      } = body;

      if (!photoId || !categoryId) {
        return new Response(
          JSON.stringify({ error: "Missing photoId or categoryId." }),
          { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } },
        );
      }

      // 1. Idempotency check: photo already committed
      const { data: existingPhoto } = await dbClient
        .from("photos")
        .select("*")
        .eq("id", photoId)
        .eq("user_id", userId)
        .maybeSingle();

      if (existingPhoto) {
        return new Response(
          JSON.stringify({ success: true, photo: existingPhoto, alreadyCommitted: true }),
          { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } },
        );
      }

      // 2. Verify pending upload record belongs to auth.uid()
      const { data: pending, error: pendError } = await dbClient
        .from("pending_uploads")
        .select("*")
        .eq("photo_id", photoId)
        .eq("user_id", userId)
        .maybeSingle();

      if (pendError || !pending) {
        return new Response(
          JSON.stringify({ error: "Access denied: Pending upload record not found or unowned." }),
          { status: 403, headers: { ...corsHeaders, "Content-Type": "application/json" } },
        );
      }

      // 3. Verify category belongs to auth.uid()
      const { data: category, error: catError } = await dbClient
        .from("categories")
        .select("id")
        .eq("id", categoryId)
        .eq("user_id", userId)
        .maybeSingle();

      if (catError || !category) {
        return new Response(
          JSON.stringify({ error: "Access denied: Category not found or unowned." }),
          { status: 403, headers: { ...corsHeaders, "Content-Type": "application/json" } },
        );
      }

      // 4. Verify returned public IDs match server-controlled expected IDs
      const expectedFullBase = pending.full_public_id;
      const expectedThumbBase = pending.thumbnail_public_id;
      const effFullPubId = fullPublicId || expectedFullBase;
      const effThumbPubId = thumbnailPublicId || expectedThumbBase;

      if (!effFullPubId.startsWith(`privora/${userId}/${categoryId}/${photoId}`) ||
          !effThumbPubId.startsWith(`privora/${userId}/${categoryId}/${photoId}_thumb`)) {
        return new Response(
          JSON.stringify({ error: "Public ID validation failed: Identity does not match server expected prefix." }),
          { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } },
        );
      }

      // 5. Verify both assets exist in Cloudinary as raw + authenticated
      const fullAssetMeta = await queryCloudinaryAsset(effFullPubId, "authenticated");
      const thumbAssetMeta = await queryCloudinaryAsset(effThumbPubId, "authenticated");

      if (!fullAssetMeta || fullAssetMeta.resource_type !== "raw" || fullAssetMeta.type !== "authenticated") {
        return new Response(
          JSON.stringify({ error: "Full photo asset verification failed: Asset not found or not raw/authenticated in Cloudinary." }),
          { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } },
        );
      }

      if (!thumbAssetMeta || thumbAssetMeta.resource_type !== "raw" || thumbAssetMeta.type !== "authenticated") {
        return new Response(
          JSON.stringify({ error: "Thumbnail asset verification failed: Asset not found or not raw/authenticated in Cloudinary." }),
          { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } },
        );
      }

      const finalFullAssetId = fullAssetMeta.asset_id || fullAssetId || null;
      const finalThumbAssetId = thumbAssetMeta.asset_id || thumbnailAssetId || null;
      const finalFullVersion = fullAssetMeta.version ? String(fullAssetMeta.version) : (fullVersion ? String(fullVersion) : null);
      const finalBytes = fullAssetMeta.bytes || fullBytes || encryptedSize || 0;

      const now = new Date().toISOString();
      const insertData: Record<string, any> = {
        id: photoId,
        user_id: userId,
        category_id: categoryId,
        storage_path: effFullPubId,
        thumbnail_path: effThumbPubId,
        display_name: displayName || "Encrypted Photo",
        mime_type: mimeType || "image/jpeg",
        encrypted_size: encryptedSize || finalBytes,
        width: width || null,
        height: height || null,
        storage_provider: "cloudinary",
        cloudinary_public_id: effFullPubId,
        cloudinary_thumbnail_public_id: effThumbPubId,
        cloudinary_asset_id: finalFullAssetId,
        cloudinary_thumbnail_asset_id: finalThumbAssetId,
        cloudinary_version: finalFullVersion,
        encrypted_bytes: finalBytes,
        original_filename: displayName || null,
        created_at: now,
        updated_at: now,
      };

      let inserted = null;
      let insertError = null;

      const { data: extData, error: extErr } = await dbClient
        .from("photos")
        .insert(insertData)
        .select()
        .single();

      if (extErr && (extErr.code === "42703" || extErr.message?.includes("column"))) {
        // Fallback without 006 columns if migration is catching up
        delete insertData.cloudinary_thumbnail_asset_id;
        const { data: retryData, error: retryErr } = await dbClient
          .from("photos")
          .insert(insertData)
          .select()
          .single();
        inserted = retryData;
        insertError = retryErr;
      } else {
        inserted = extData;
        insertError = extErr;
      }

      if (insertError) {
        return new Response(
          JSON.stringify({ error: `Database commit failed: ${insertError.message}` }),
          { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
        );
      }

      // Mark pending upload as committed
      try {
        await dbClient
          .from("pending_uploads")
          .update({ status: "committed", updated_at: now })
          .eq("photo_id", photoId)
          .eq("user_id", userId);
      } catch (_) {}

      return new Response(
        JSON.stringify({ success: true, photo: inserted }),
        { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    // -------------------------------------------------------------------------
    // ACTION 3: getDownloadUrl (Signed /asset/download + Automatic Repair)
    // -------------------------------------------------------------------------
    if (action === "getDownloadUrl") {
      const { photoId, target } = body; // target: 'full' | 'thumbnail'

      if (!photoId) {
        return new Response(
          JSON.stringify({ error: "Missing photoId." }),
          { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } },
        );
      }

      // 1. Verify photo strictly belongs to auth.uid()
      let photoQuery = dbClient
        .from("photos")
        .select("id, user_id, storage_path, thumbnail_path, storage_provider, cloudinary_public_id, cloudinary_thumbnail_public_id, cloudinary_asset_id, cloudinary_thumbnail_asset_id")
        .eq("id", photoId);

      if (!isServiceRole) {
        photoQuery = photoQuery.eq("user_id", userId);
      } else if (userId) {
        photoQuery = photoQuery.eq("user_id", userId);
      }

      const { data: photo, error: photoError } = await photoQuery.maybeSingle();

      if (photoError || !photo) {
        return new Response(
          JSON.stringify({ error: "Access denied: Photo not found or unowned." }),
          { status: 403, headers: { ...corsHeaders, "Content-Type": "application/json" } },
        );
      }

      if (isServiceRole && !userId) {
        userId = photo.user_id;
      }

      const isThumbnail = target === "thumbnail";
      let assetId = isThumbnail
        ? photo.cloudinary_thumbnail_asset_id
        : photo.cloudinary_asset_id;

      const storedPubId = isThumbnail
        ? (photo.cloudinary_thumbnail_public_id || photo.thumbnail_path)
        : (photo.cloudinary_public_id || photo.storage_path);

      const now = Math.floor(Date.now() / 1000);
      const expiresAt = now + 3600;

      // 2. PRIMARY PATH: If assetId is present, generate signed /asset/download URL
      if (assetId && typeof assetId === "string" && assetId.trim().length > 0) {
        const signParams = {
          asset_id: assetId,
          expires_at: expiresAt,
          timestamp: now,
        };
        const signature = await signCloudinaryParams(signParams, apiSecret);
        const downloadUrl = `https://api.cloudinary.com/v1_1/${cloudName}/asset/download?api_key=${apiKey}&asset_id=${encodeURIComponent(assetId)}&expires_at=${expiresAt}&timestamp=${now}&signature=${signature}`;

        return new Response(
          JSON.stringify({
            downloadUrl,
            expiresAt,
            assetId,
            deliveryType: "asset_download",
          }),
          { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } },
        );
      }

      // 3. AUTOMATIC REPAIR PATH: If asset_id is missing, query Cloudinary Admin API
      if (storedPubId && storedPubId.length > 0) {
        const candidates: string[] = [storedPubId];
        if (!storedPubId.endsWith(".enc")) {
          candidates.push(`${storedPubId}.enc`);
        } else {
          candidates.push(storedPubId.replace(/\.enc$/, ""));
        }

        let resolvedMeta: any = null;

        for (const cand of candidates) {
          // Check authenticated first
          resolvedMeta = await queryCloudinaryAsset(cand, "authenticated");
          if (resolvedMeta && resolvedMeta.asset_id) break;

          // Check upload fallback second
          resolvedMeta = await queryCloudinaryAsset(cand, "upload");
          if (resolvedMeta && resolvedMeta.asset_id) break;
        }

        if (resolvedMeta && resolvedMeta.asset_id) {
          // Security verification: Confirm returned public_id starts with privora/{userId}/
          if (resolvedMeta.public_id && !resolvedMeta.public_id.startsWith(`privora/${userId}/`)) {
            return new Response(
              JSON.stringify({ error: "Security violation: Asset does not belong to user namespace." }),
              { status: 403, headers: { ...corsHeaders, "Content-Type": "application/json" } },
            );
          }

          const repairedAssetId = resolvedMeta.asset_id;
          const repairedPubId = resolvedMeta.public_id || storedPubId;

          // Backfill into Supabase photos table
          try {
            const updatePayload: Record<string, any> = isThumbnail
              ? {
                  cloudinary_thumbnail_asset_id: repairedAssetId,
                  cloudinary_thumbnail_public_id: repairedPubId,
                  thumbnail_path: repairedPubId,
                }
              : {
                  cloudinary_asset_id: repairedAssetId,
                  cloudinary_public_id: repairedPubId,
                  storage_path: repairedPubId,
                };

            await dbClient
              .from("photos")
              .update(updatePayload)
              .eq("id", photoId)
              .eq("user_id", userId);
          } catch (updateErr) {
            console.warn("Automatic backfill update error:", updateErr);
          }

          // Generate signed /asset/download URL using the repaired asset_id
          const signParams = {
            asset_id: repairedAssetId,
            expires_at: expiresAt,
            timestamp: now,
          };
          const signature = await signCloudinaryParams(signParams, apiSecret);
          const downloadUrl = `https://api.cloudinary.com/v1_1/${cloudName}/asset/download?api_key=${apiKey}&asset_id=${encodeURIComponent(repairedAssetId)}&expires_at=${expiresAt}&timestamp=${now}&signature=${signature}`;

          return new Response(
            JSON.stringify({
              downloadUrl,
              expiresAt,
              assetId: repairedAssetId,
              deliveryType: "asset_download",
              repaired: true,
            }),
            { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } },
          );
        }
      }

      // 4. Fallback for legacy public ID if Admin API was unable to resolve asset_id
      if (storedPubId) {
        const signParams: Record<string, string | number> = {
          expires_at: expiresAt,
          public_id: storedPubId,
          timestamp: now,
          type: "authenticated",
        };
        const signature = await signCloudinaryParams(signParams, apiSecret);
        const downloadUrl = `https://api.cloudinary.com/v1_1/${cloudName}/raw/download?api_key=${apiKey}&expires_at=${expiresAt}&public_id=${encodeURIComponent(storedPubId)}&timestamp=${now}&type=authenticated&signature=${signature}`;

        return new Response(
          JSON.stringify({ downloadUrl, expiresAt, publicId: storedPubId, deliveryType: "public_id_download" }),
          { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } },
        );
      }

      return new Response(
        JSON.stringify({ error: "Cloud file could not be found." }),
        { status: 404, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    // -------------------------------------------------------------------------
    // ACTION 4: permanentlyDelete
    // -------------------------------------------------------------------------
    if (action === "permanentlyDelete") {
      const { photoId } = body;

      if (!photoId) {
        return new Response(
          JSON.stringify({ error: "Missing photoId." }),
          { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } },
        );
      }

      const { data: photo, error: photoError } = await dbClient
        .from("photos")
        .select("id, storage_path, thumbnail_path, cloudinary_public_id, cloudinary_thumbnail_public_id, deleted_at")
        .eq("id", photoId)
        .eq("user_id", userId)
        .maybeSingle();

      if (photoError || !photo) {
        return new Response(
          JSON.stringify({ error: "Access denied: Photo not found or unowned." }),
          { status: 403, headers: { ...corsHeaders, "Content-Type": "application/json" } },
        );
      }

      const fullPublicId = photo.cloudinary_public_id || photo.storage_path;
      const thumbPublicId = photo.cloudinary_thumbnail_public_id || photo.thumbnail_path;

      await destroyAsset(fullPublicId);
      await destroyAsset(thumbPublicId);
      if (fullPublicId && !fullPublicId.endsWith(".enc")) {
        await destroyAsset(`${fullPublicId}.enc`);
      }
      if (thumbPublicId && !thumbPublicId.endsWith(".enc")) {
        await destroyAsset(`${thumbPublicId}.enc`);
      }

      await dbClient
        .from("photos")
        .delete()
        .eq("id", photoId)
        .eq("user_id", userId);

      await dbClient
        .from("pending_uploads")
        .delete()
        .eq("photo_id", photoId)
        .eq("user_id", userId);

      return new Response(
        JSON.stringify({ success: true }),
        { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    // -------------------------------------------------------------------------
    // ACTION 5: cleanupFailedUpload (With Committed Photo Verification)
    // -------------------------------------------------------------------------
    if (action === "cleanupFailedUpload") {
      const { photoId, fullPublicId, thumbnailPublicId } = body;

      // 1. If photoId is provided, check if photo is already committed in photos table
      if (photoId) {
        const { data: committedPhoto } = await dbClient
          .from("photos")
          .select("id")
          .eq("id", photoId)
          .maybeSingle();

        if (committedPhoto) {
          return new Response(
            JSON.stringify({
              success: true,
              message: "Photo already committed, skipping cleanup.",
              cleaned: 0,
            }),
            { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } },
          );
        }

        // Check if pending_uploads marked as committed
        const { data: pending } = await dbClient
          .from("pending_uploads")
          .select("status")
          .eq("photo_id", photoId)
          .maybeSingle();

        if (pending && pending.status === "committed") {
          return new Response(
            JSON.stringify({
              success: true,
              message: "Pending upload marked committed, skipping cleanup.",
              cleaned: 0,
            }),
            { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } },
          );
        }
      }

      // Collect assets to destroy
      const assetsToDelete: string[] = [];
      if (fullPublicId && typeof fullPublicId === "string") {
        assetsToDelete.push(fullPublicId);
        if (!fullPublicId.endsWith(".enc")) assetsToDelete.push(`${fullPublicId}.enc`);
      }
      if (thumbnailPublicId && typeof thumbnailPublicId === "string") {
        assetsToDelete.push(thumbnailPublicId);
        if (!thumbnailPublicId.endsWith(".enc")) assetsToDelete.push(`${thumbnailPublicId}.enc`);
      }

      let cleaned = 0;
      for (const pubId of assetsToDelete) {
        // Double check no committed photo references this public ID
        const { data: refPhoto } = await dbClient
          .from("photos")
          .select("id")
          .or(`storage_path.eq.${pubId},thumbnail_path.eq.${pubId},cloudinary_public_id.eq.${pubId},cloudinary_thumbnail_public_id.eq.${pubId}`)
          .maybeSingle();

        if (!refPhoto) {
          await destroyAsset(pubId);
          cleaned++;
        }
      }

      if (photoId) {
        await dbClient
          .from("pending_uploads")
          .delete()
          .eq("photo_id", photoId)
          .eq("status", "pending");
      }

      return new Response(
        JSON.stringify({ success: true, cleaned }),
        { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    return new Response(
      JSON.stringify({ error: `Unknown action: ${action}` }),
      { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  } catch (err: any) {
    console.error("Unhandled Edge Function error:", err);
    return new Response(
      JSON.stringify({ error: `Internal Server Error: ${err.message || err}` }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }
});
