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

// Generate Cloudinary signature for upload or destroy
// Required alphabetical sorting: public_id, timestamp, type
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
    // 1. Verify Cloudinary configuration secrets
    const cloudName = Deno.env.get("CLOUDINARY_CLOUD_NAME");
    const apiKey = Deno.env.get("CLOUDINARY_API_KEY");
    const apiSecret = Deno.env.get("CLOUDINARY_API_SECRET");
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

    // 2. Validate Supabase JWT from Authorization Header
    const authHeader = req.headers.get("Authorization");
    if (!authHeader || !authHeader.startsWith("Bearer ")) {
      return new Response(
        JSON.stringify({ error: "Missing or invalid authorization header." }),
        { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    const jwtToken = authHeader.replace("Bearer ", "").trim();

    // Authenticated client using the caller's JWT to extract verified user
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

    // User ID derived strictly from verified Supabase JWT
    const userId = userData.user.id;

    // Admin database client for ownership checks and database mutations
    const dbClient = createClient(supabaseUrl, supabaseServiceKey);

    // Parse request body
    const body = await req.json();
    const { action } = body;

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
      const fullSignature = await signCloudinaryParams(
        {
          public_id: fullPublicId,
          timestamp: timestamp,
          type: "authenticated",
        },
        apiSecret,
      );

      // Sign parameters for thumbnail upload
      const thumbSignature = await signCloudinaryParams(
        {
          public_id: thumbPublicId,
          timestamp: timestamp,
          type: "authenticated",
        },
        apiSecret,
      );

      return new Response(
        JSON.stringify({
          cloudName,
          apiKey,
          timestamp,
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
    // ACTION 2: getDownloadUrl
    // -------------------------------------------------------------------------
    if (action === "getDownloadUrl") {
      const { photoId, target } = body; // target: 'full' | 'thumbnail'

      if (!photoId) {
        return new Response(
          JSON.stringify({ error: "Missing photoId." }),
          { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } },
        );
      }

      // Verify photo exists and belongs to auth.uid()
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

      // Generate signed delivery download URL
      // Valid for 1 hour
      const timestamp = Math.floor(Date.now() / 1000) + 3600;
      const signature = await signCloudinaryParams(
        {
          public_id: publicId,
          timestamp: timestamp,
        },
        apiSecret,
      );

      const downloadUrl = `https://api.cloudinary.com/v1_1/${cloudName}/raw/download?api_key=${apiKey}&public_id=${encodeURIComponent(publicId)}&timestamp=${timestamp}&signature=${signature}`;

      return new Response(
        JSON.stringify({ downloadUrl }),
        { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    // -------------------------------------------------------------------------
    // ACTION 3: permanentlyDelete
    // -------------------------------------------------------------------------
    if (action === "permanentlyDelete") {
      const { photoId } = body;

      if (!photoId) {
        return new Response(
          JSON.stringify({ error: "Missing photoId." }),
          { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } },
        );
      }

      // Validate ownership in database
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

      // Helper function to call Cloudinary Destroy API
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
        const result = await res.json();
        // ok or not found is acceptable for idempotent deletion
        return result.result === "ok" || result.result === "not found";
      };

      // 1. Delete full and thumbnail assets in Cloudinary
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

      return new Response(
        JSON.stringify({ success: true }),
        { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    // -------------------------------------------------------------------------
    // ACTION 4: cleanupFailedUpload
    // -------------------------------------------------------------------------
    if (action === "cleanupFailedUpload") {
      const { fullPublicId, thumbnailPublicId } = body;

      const userPrefix = `privora/${userId}/`;

      // Security check: Must strictly start with the authenticated user's prefix
      const assetsToDelete: string[] = [];
      if (typeof fullPublicId === "string" && fullPublicId.startsWith(userPrefix)) {
        assetsToDelete.push(fullPublicId);
      }
      if (typeof thumbnailPublicId === "string" && thumbnailPublicId.startsWith(userPrefix)) {
        assetsToDelete.push(thumbnailPublicId);
      }

      for (const pubId of assetsToDelete) {
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

        await fetch(`https://api.cloudinary.com/v1_1/${cloudName}/raw/destroy`, {
          method: "POST",
          body: formData,
        });
      }

      return new Response(
        JSON.stringify({ success: true, cleaned: assetsToDelete.length }),
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
      JSON.stringify({ error: "Internal server error occurred." }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }
});
