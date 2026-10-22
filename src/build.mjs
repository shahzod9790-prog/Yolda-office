import { createRequire } from "module";
import fs from "fs";
import path from "path";
import crypto from "crypto";
const require = createRequire("/opt/npm-tools/node_modules/");
const esbuild = require("esbuild");
const [,, src, out] = process.argv;
let html = fs.readFileSync(src, "utf8");
const re = /<script type="text\/babel"[^>]*>([\s\S]*?)<\/script>/;
const m = html.match(re);
if (!m) throw new Error("babel script block not found");
const r = esbuild.transformSync(m[1], { loader: "jsx", jsx: "transform", target: "es2018", minify: true, legalComments: "none" });
if (/<\/script/i.test(r.code)) throw new Error("</script found in output");
html = html.replace(re, () => "<script>" + r.code + "</script>");
html = html.replace(/<script src="[^"]*@babel\/standalone[^"]*"><\/script>\n?/, "");
// Avto-yangilanish: build raqami (kontent xeshi) index.html ichiga va yoniga version.json ga yoziladi.
// Telefon/kompyuter ochilganda shu raqamni serverdagi bilan solishtirib, yangi versiya bo'lsa o'zi yangilanadi.
const PLACEHOLDER = "__BUILD_ID__";
let build = "-";
if (html.includes(PLACEHOLDER)) {
  build = crypto.createHash("sha256").update(html).digest("hex").slice(0, 12);
  html = html.split(PLACEHOLDER).join(build);
  fs.writeFileSync(path.join(path.dirname(out), "version.json"), JSON.stringify({ build }) + "\n");
}
fs.writeFileSync(out, html);
console.log("in", fs.statSync(src).size, "out", fs.statSync(out).size, "build", build);
