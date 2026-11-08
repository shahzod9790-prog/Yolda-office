// YO'LDA — "office-admin" Edge Function.
// Faqat OFIS xodimi (JWT ichida app_metadata.role = "office") chaqira oladi. Haydovchi so'rovini tasdiqlaydi/rad etadi
// va haydovchi hisobini yoqadi/o'chiradi. Maxfiy "service role" kaliti faqat shu yerda (serverda), ilovalarda EMAS.
import { createClient } from "npm:@supabase/supabase-js@2";

// Haydovchi ilovasidagi bilan AYNAN bir xil bo'lishi shart (telefon -> ichki email).
const AUTH_EMAIL_DOMAIN = "driver.yolda.app";
const phoneEmail = (phone: string) => `${phone}@${AUTH_EMAIL_DOMAIN}`;

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (status: number, body: unknown) => new Response(JSON.stringify(body), { status, headers: { ...CORS, "Content-Type": "application/json" } });
const fail = (status: number, code: string, message: string, extra: Record<string, unknown> = {}) => json(status, { ok: false, code, message, ...extra });

// O'qish oson, adashtirmaydigan belgilar (0/O, 1/l/I yo'q): 8 ta belgi
const ALPHABET = "abcdefghjkmnpqrstuvwxyz23456789";
export function genPassword(len = 8): string {
  const out: string[] = [];
  const limit = 256 - (256 % ALPHABET.length); // modul bo'yicha og'ishsiz tanlash
  while (out.length < len) {
    const buf = new Uint8Array(len * 2);
    crypto.getRandomValues(buf);
    for (const b of buf) { if (b < limit && out.length < len) out.push(ALPHABET[b % ALPHABET.length]); }
  }
  return out.join("");
}
const sameName = (a: string, b: string) => a.trim().toLowerCase() === b.trim().toLowerCase();

// deno-lint-ignore no-explicit-any
type Admin = any;

export async function handle(req: Request, admin: Admin): Promise<Response> {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return fail(405, "METHOD", "Faqat POST");

  // 1) Chaqiruvchi — ofis xodimimi?
  const token = (req.headers.get("Authorization") || "").replace(/^Bearer\s+/i, "");
  if (!token) return fail(401, "NO_AUTH", "Kirish talab qilinadi");
  const { data: u, error: ue } = await admin.auth.getUser(token);
  if (ue || !u?.user) return fail(401, "BAD_AUTH", "Sessiya yaroqsiz. Qayta kiring");
  if (u.user.app_metadata?.role !== "office") return fail(403, "NOT_OFFICE", "Bu amal faqat ofis xodimlari uchun");

  let body: Record<string, unknown>;
  try { body = await req.json(); } catch { return fail(400, "BAD_JSON", "So'rov noto'g'ri"); }
  const action = String(body.action || "");

  try {
    if (action === "approve") return await approve(admin, String(body.request_id || ""), body.force_link === true);
    if (action === "reject") return await reject(admin, String(body.request_id || ""), typeof body.message === "string" ? body.message.trim().slice(0, 300) : "");
    if (action === "set_active") return await setActive(admin, String(body.driver_id || ""), body.active === true);
    return fail(400, "BAD_ACTION", "Noma'lum amal");
  } catch (e) {
    console.error("office-admin error", action, (e as Error)?.message);
    return fail(500, "SERVER", "Server xatosi: " + ((e as Error)?.message || "noma'lum"));
  }
}

async function approve(admin: Admin, requestId: string, forceLink: boolean): Promise<Response> {
  if (!requestId) return fail(400, "BAD_ID", "So'rov ko'rsatilmagan");
  // Avval so'rovni "band qilamiz" (pending -> approved): ikki xodim bir vaqtda bosganda parol ikki marta yaratilmasin
  const { data: r, error: ce } = await admin.from("driver_requests").update({ status: "approved", decided_at: new Date().toISOString() }).eq("id", requestId).eq("status", "pending").select("*").maybeSingle();
  if (ce) throw ce;
  if (!r) return fail(409, "NOT_PENDING", "Bu so'rov topilmadi yoki allaqachon ko'rib chiqilgan");
  const revert = () => admin.from("driver_requests").update({ status: "pending", decided_at: null, temp_password: null, driver_id: null }).eq("id", requestId);

  try {
    // 2) Qaysi haydovchi? (telefon bo'yicha, so'ng ism bo'yicha) — noaniq bo'lsa ofisdan so'raymiz
    let driver: Record<string, unknown> | null = null;
    const { data: byPhone } = await admin.from("drivers").select("*").eq("phone", r.phone).maybeSingle();
    if (byPhone) {
      if (!(sameName(byPhone.first_name, r.first_name) && sameName(byPhone.last_name, r.last_name)) && !forceLink) {
        await revert();
        return fail(409, "PHONE_TAKEN", `Bu telefon raqam boshqa haydovchiga (${byPhone.first_name} ${byPhone.last_name}) biriktirilgan.`, { other: `${byPhone.first_name} ${byPhone.last_name}` });
      }
      driver = byPhone;
      if (!sameName(byPhone.first_name, r.first_name) || !sameName(byPhone.last_name, r.last_name)) {
        // forceLink: shu raqam egasi endi boshqa ism bilan — ism yangilanadi
        const { data: upd, error: ne } = await admin.from("drivers").update({ first_name: r.first_name.trim(), last_name: r.last_name.trim() }).eq("id", byPhone.id).select("*").single();
        if (ne) throw ne; driver = upd;
      }
    } else {
      const likeEsc = (x: string) => x.trim().replace(/[\\%_]/g, "\\$&"); // ism ichidagi % va _ belgilari "hammasi" ma'nosini bermasin
      const { data: sameNames } = await admin.from("drivers").select("*").ilike("first_name", likeEsc(r.first_name)).ilike("last_name", likeEsc(r.last_name));
      const free = (sameNames || []).filter((d: Record<string, unknown>) => !d.phone);
      const withPhone = (sameNames || []).filter((d: Record<string, unknown>) => !!d.phone);
      if (free.length === 1) driver = free[0]; // ofis/oldingi reyslardagi shu ismli haydovchi — raqam biriktiriladi, reyslar saqlanadi
      else if (free.length > 1) { await revert(); return fail(409, "AMBIGUOUS", "Shu ismli bir nechta haydovchi bor. Avval ularni tekshiring."); }
      else if (withPhone.length > 0 && !forceLink) {
        await revert();
        return fail(409, "NAME_HAS_OTHER_PHONE", `Shu ismli haydovchi boshqa raqam bilan bor (+${withPhone[0].phone}). Bu o'sha odammi?`, { other_phone: withPhone[0].phone });
      } else if (withPhone.length === 1 && forceLink) driver = withPhone[0];
      else if (withPhone.length > 1 && forceLink) { await revert(); return fail(409, "AMBIGUOUS", "Shu ismli bir nechta haydovchi bor. Avval ularni tekshiring."); }
    }
    if (!driver) {
      const { data: nd, error: ie } = await admin.from("drivers").insert({ first_name: r.first_name.trim(), last_name: r.last_name.trim(), phone: r.phone, active: true }).select("*").single();
      if (ie) throw ie; driver = nd;
    }

    // 3) Kirish hisobi (auth): yangi yaratiladi yoki parol yangilanadi
    const password = genPassword();
    const email = phoneEmail(r.phone);
    let authId = driver.auth_user_id as string | null;
    if (authId) {
      const { error: ae } = await admin.auth.admin.updateUserById(authId, { email, password, email_confirm: true, ban_duration: "none", app_metadata: { role: "driver", driver_id: driver.id } });
      if (ae) throw ae;
    } else {
      const { data: cu, error: ae } = await admin.auth.admin.createUser({ email, password, email_confirm: true, app_metadata: { role: "driver", driver_id: driver.id } });
      if (ae || !cu?.user) {
        await revert();
        return fail(409, "AUTH_CREATE", "Kirish hisobini yaratib bo'lmadi: " + (ae?.message || "noma'lum") + " (shu raqam bilan hisob avvaldan bo'lishi mumkin)");
      }
      authId = cu.user.id;
    }
    const { error: de } = await admin.from("drivers").update({ phone: r.phone, auth_user_id: authId, active: true }).eq("id", driver.id);
    if (de) throw de;

    // 4) Parol haydovchining "Xabarlar" bo'limiga yetkaziladi (ilova uni olgach, bazadan o'chiradi)
    const { error: fe } = await admin.from("driver_requests").update({ driver_id: driver.id, temp_password: password, message: null }).eq("id", requestId);
    if (fe) throw fe;
    return json(200, { ok: true, driver_id: driver.id, name: `${driver.first_name} ${driver.last_name}` });
  } catch (e) {
    await revert();
    throw e;
  }
}

async function reject(admin: Admin, requestId: string, message: string): Promise<Response> {
  if (!requestId) return fail(400, "BAD_ID", "So'rov ko'rsatilmagan");
  const { data: r, error } = await admin.from("driver_requests").update({ status: "rejected", message: message || null, decided_at: new Date().toISOString(), temp_password: null }).eq("id", requestId).eq("status", "pending").select("id").maybeSingle();
  if (error) throw error;
  if (!r) return fail(409, "NOT_PENDING", "Bu so'rov topilmadi yoki allaqachon ko'rib chiqilgan");
  return json(200, { ok: true });
}

async function setActive(admin: Admin, driverId: string, active: boolean): Promise<Response> {
  if (!driverId) return fail(400, "BAD_ID", "Haydovchi ko'rsatilmagan");
  const { data: d, error } = await admin.from("drivers").select("id,auth_user_id").eq("id", driverId).maybeSingle();
  if (error) throw error;
  if (!d) return fail(404, "NOT_FOUND", "Haydovchi topilmadi");
  if (d.auth_user_id) {
    // ~100 yil bloklash = o'chirish; "none" = qayta yoqish
    const { error: be } = await admin.auth.admin.updateUserById(d.auth_user_id, { ban_duration: active ? "none" : "876000h" });
    if (be) throw be;
  }
  const { error: ue } = await admin.from("drivers").update({ active }).eq("id", driverId);
  if (ue) throw ue;
  return json(200, { ok: true });
}

// Supabase ishga tushirganda (Deno) — sinovda (Node) bu qism ishlamaydi
// deno-lint-ignore no-explicit-any
const D = (globalThis as any).Deno;
if (D?.serve) {
  const admin = createClient(D.env.get("SUPABASE_URL")!, D.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false, autoRefreshToken: false } });
  D.serve((req: Request) => handle(req, admin));
}
