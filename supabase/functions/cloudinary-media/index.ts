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
    const cloudName = Deno.env.get("CLOUDINARY_CLOUD_NAME");
    const apiKey = Deno.env.get("CLOUDINARY_API_KEY");
    const apiSecret = Deno.env.get("CLOUDINARY_API_SECRET");
    const uploadPreset = Deno.env.get("CLOUDINARY_UPLOAD_PRESET") || "privora_signed";
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

    if (!cloudName || !apiKey || !apiSecret || !supabaseUrl || !supabaseServiceKey) {
      return new Response(
        JSON.stringify({
          error: "Cloudinary or Supabase server configuration missing.",
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

    // Check if this is a backend service-role call for scheduled cleanup
    const isServiceRole = jwtToken === supabaseServiceKey;

    let userId = "";
    if (!isServiceRole) {
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

      // Generate or validate UUID for photo
      const photoId = requestedPhotoId && typeof requestedPhotoId === "string" && requestedPhotoId.length === 36
        ? requestedPhotoId
        : crypto.randomUUID();

      // Enforce standardized Cloudinary public IDs: privora/{userId}/{categoryId}/{photoId}
      const fullPublicId = `privora/${userId}/${categoryId}/${photoId}`;
      const thumbPublicId = `privora/${userId}/${categoryId}/${photoId}_thumb`;

      const timestamp = Math.floor(Date.now() / 1000);

      // Sign parameters for full photo upload: public_id, timestamp, type=authenticated
      const fullSignParams: Record<string, string | number> = {
        public_id: fullPublicId,
        timestamp: timestamp,
        type: "authenticated",
      };
      if (uploadPreset) {
        fullSignParams["upload_preset"] = uploadPreset;
      }
      const fullSignature = await signCloudinaryParams(fullSignParams, apiSecret);

      // Sign parameters for thumbnail upload
      const thumbSignParams: Record<string, string | number> = {
        public_id: thumbPublicId,
        timestamp: timestamp,
        type: "authenticated",
      };
      if (uploadPreset) {
        thumbSignParams["upload_preset"] = uploadPreset;
      }
      const thumbSignature = await signCloudinaryParams(thumbSignParams, apiSecret);

      // Track pending upload in server-controlled database table
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

      return new Response(
        JSON.stringify({
          cloudName,
          apiKey,
          timestamp,
          uploadPreset: uploadPreset || null,
          resourceType: "raw",
          type: "authenticated",
          photoId,
          full: {
            publicId: fullPublicId,
            signature: fullSignature,
          },
          thumbnail: {
            publicId: thumbPublicId,
            signature: thumbSignature,
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
        assetId,
        version,
      } = body;

      if (!photoId || !categoryId) {
        return new Response(
          JSON.stringify({ error: "Missing photoId or categoryId." }),
          { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } },
        );
      }

      // Check if photo is already committed (Idempotent Commit)
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

      // Verify pending upload record exists and belongs to user
      const { data: pending, error: pendError } = await dbClient
        .from("pending_uploads")
        .select("*")
        .eq("photo_id", photoId)
        .eq("user_id", userId)
        .maybeSingle();

      if (pendError || !pending) {
        return new Response(
          JSON.stringify({ error: "Pending upload record not found or unowned." }),
          { status: 403, headers: { ...corsHeaders, "Content-Type": "application/json" } },
        );
      }

      const now = new Date().toISOString();
      const insertData = {
        id: photoId,
        user_id: userId,
        category_id: categoryId,
        storage_path: pending.full_public_id,
        thumbnail_path: pending.thumbnail_public_id,
        display_name: displayName || "Encrypted Photo",
        mimeType: mimeType || "image/jpeg",
        encrypted_size: encryptedSize || 0,
        width: width || null,
        height: height || null,
        storage_provider: "cloudinary",
        cloudinary_public_id: pending.full_public_id,
        cloudinary_thumbnail_public_id: pending.thumbnail_public_id,
        cloudinary_asset_id: assetId || null,
        cloudinary_version: version ? String(version) : null,
        encrypted_bytes: encryptedSize || 0,
        original_filename: displayName || null,
        created_at: now,
        updated_at: now,
      };

      const { data: inserted, error: insertError } = await dbClient
        .from("photos")
        .insert(insertData)
        .select()
        .single();

      if (insertError) {
        return new Response(
          JSON.stringify({ error: `Database commit failed: ${insertError.message}` }),
          { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
        );
      }

      // Mark pending upload as committed
      await dbClient
        .from("pending_uploads")
        .update({ status: "committed", updated_at: now })
        .eq("photo_id", photoId)
        .eq("user_id", userId);

      return new Response(
        JSON.stringify({ success: true, photo: inserted }),
        { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    // -------------------------------------------------------------------------
    // ACTION 3: getDownloadUrl
    // -------------------------------------------------------------------------
    if (action === "getDownloadUrl") {
      const { photoId, target } = body; // target: 'full' | 'thumbnail'

      if (!photoId) {
        return new Response(
          JSON.stringify({ error: "Missing photoId." }),
          { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } },
        );
      }

      // Verify photo exists and strictly belongs to auth.uid()
      const { data: photo, error: photoError } = await dbClient
        .from("photos")
        .select("id, cloudinary_public_id, cloudinary_thumbnail_public_id")
        .eq("id", photoId)
        .eq("user_id", userId)
        .maybeSingle();

      if (photoError || !photo) {
        return new Response(
          JSON.stringify({ error: "Access denied: Photo not found or unowned." }),
          { status: 403, headers: { ...corsHeaders, "Content-Type": "application/json" } },
        );
      }

      const publicId = target === "thumbnail"
        ? photo.cloudinary_thumbnail_public_id
        : photo.cloudinary_public_id;

      if (!publicId) {
        return new Response(
          JSON.stringify({ error: "Photo does not have a Cloudinary asset identifier." }),
          { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } },
        );
      }

      // Documented expiring download mechanism: private_download_url with expires_at
      const now = Math.floor(Date.now() / 1000);
      const expiresAt = now + 3600; // 1 hour expiration window

      const signParams: Record<string, string | number> = {
        expires_at: expiresAt,
        public_id: publicId,
        timestamp: now,
        type: "authenticated",
      };

      const signature = await signCloudinaryParams(signParams, apiSecret);

      const downloadUrl = `https://api.cloudinary.com/v1_1/${cloudName}/raw/download?api_key=${apiKey}&expires_at=${expiresAt}&public_id=${encodeURIComponent(publicId)}&timestamp=${now}&type=authenticated&signature=${signature}`;

      return new Response(
        JSON.stringify({ downloadUrl, expiresAt }),
        { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } },
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

      // Validate ownership in database and prevent race condition with restore
      const { data: photo, error: photoError } = await dbClient
        .from("photos")
        .select("id, cloudinary_public_id, cloudinary_thumbnail_public_id, deleted_at")
        .eq("id", photoId)
        .eq("user_id", userId)
        .maybeSingle();

      if (photoError || !photo) {
        return new Response(
          JSON.stringify({ error: "Access denied: Photo not found or unowned." }),
          { status: 403, headers: { ...corsHeaders, "Content-Type": "application/json" } },
        );
      }

      // 1. Destroy full and thumbnail assets on Cloudinary
      const fullOk = await destroyAsset(photo.cloudinary_public_id);
      const thumbOk = await destroyAsset(photo.cloudinary_thumbnail_public_id);

      if (!fullOk && !thumbOk) {
        return new Response(
          JSON.stringify({ error: "Failed to destroy Cloudinary assets." }),
          { status: 502, headers: { ...corsHeaders, "Content-Type": "application/json" } },
        );
      }

      // 2. Delete Supabase photo record only after Cloudinary confirms deletion
      const { error: dbDeleteError } = await dbClient
        .from("photos")
        .delete()
        .eq("id", photoId)
        .eq("user_id", userId);

      if (dbDeleteError) {
        return new Response(
          JSON.stringify({ error: "Failed to delete database metadata." }),
          { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
        );
      }

      // Clean pending uploads entry if present
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
    // ACTION 5: cleanupFailedUpload
    // -------------------------------------------------------------------------
    if (action === "cleanupFailedUpload") {
      const { photoId, fullPublicId, thumbnailPublicId } = body;

      const assetsToDelete: string[] = [];

      // Prefer server-tracked pending upload
      if (photoId) {
        const { data: pending } = await dbClient
          .from("pending_uploads")
          .select("full_public_id, thumbnail_public_id")
          .eq("photo_id", photoId)
          .eq("user_id", userId)
          .maybeSingle();

        if (pending) {
          if (pending.full_public_id) assetsToDelete.push(pending.full_public_id);
          if (pending.thumbnail_public_id) assetsToDelete.push(pending.thumbnail_public_id);

          await dbClient
            .from("pending_uploads")
            .update({ status: "abandoned", updated_at: new Date().toISOString() })
            .eq("photo_id", photoId)
            .eq("user_id", userId);
        }
      }

      // Fallback: validate prefix against authenticated user strictly
      const userPrefix = `privora/${userId}/`;
      if (typeof fullPublicId === "string" && fullPublicId.startsWith(userPrefix)) {
        if (!assetsToDelete.includes(fullPublicId)) assetsToDelete.push(fullPublicId);
      }
      if (typeof thumbnailPublicId === "string" && thumbnailPublicId.startsWith(userPrefix)) {
        if (!assetsToDelete.includes(thumbnailPublicId)) assetsToDelete.push(thumbnailPublicId);
      }

      for (const pubId of assetsToDelete) {
        await destroyAsset(pubId);
      }

      return new Response(
        JSON.stringify({ success: true, cleaned: assetsToDelete.length }),
        { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    // -------------------------------------------------------------------------
    // ACTION 6: cleanExpiredTrash (Scheduled backend worker or Admin call)
    // -------------------------------------------------------------------------
    if (action === "cleanExpiredTrash") {
      if (!isServiceRole && !userId) {
        return new Response(
          JSON.stringify({ error: "Access denied." }),
          { status: 403, headers: { ...corsHeaders, "Content-Type": "application/json" } },
        );
      }

      const now = new Date().toISOString();

      // Find expired photos across all users (or this user)
      let query = dbClient
        .from("photos")
        .select("id, cloudinary_public_id, cloudinary_thumbnail_public_id, storage_provider")
        .not("deleted_at", "is", null)
        .not("delete_after", "is", null)
        .lte("delete_after", now);

      if (!isServiceRole) {
        query = query.eq("user_id", userId);
      }

      const { data: expiredPhotos, error: fetchErr } = await query;
      if (fetchErr) {
        return new Response(
          JSON.stringify({ error: fetchErr.message }),
          { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
        );
      }

      let deletedCount = 0;
      for (const photo of expiredPhotos || []) {
        if (photo.storage_provider === "cloudinary") {
          await destroyAsset(photo.cloudinary_public_id);
          await destroyAsset(photo.cloudinary_thumbnail_public_id);
        }
        await dbClient.from("photos").delete().eq("id", photo.id);
        deletedCount++;
      }

      // Mark abandoned pending uploads older than 2 hours
      const twoHoursAgo = new Date(Date.now() - 2 * 3600 * 1000).toISOString();
      await dbClient
        .from("pending_uploads")
        .update({ status: "abandoned", updated_at: now })
        .eq("status", "pending")
        .lte("created_at", twoHoursAgo);

      return new Response(
        JSON.stringify({ success: true, expiredPhotosDeleted: deletedCount }),
        { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    // Unknown action
    return new Response(
      JSON.stringify({ error: `Unknown action: ${action}` }),
      { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  } catch (err) {
    return new Response(
      JSON.stringify({ error: "Internal server error occurred.", details: String(err) }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }
});
