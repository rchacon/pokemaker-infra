// Tests for the CloudFront viewer-request function (modules/frontend/viewer_request.js.tftpl).
// Run with: node --test tests/*.test.mjs
//
// The template is rendered the way Terraform's templatefile() would, then
// evaluated in a sandbox, mirroring the CloudFront Functions runtime.
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import vm from "node:vm";

const template = readFileSync(new URL("../modules/frontend/viewer_request.js.tftpl", import.meta.url), "utf8");

function load(canonicalHost) {
  const sandbox = {};
  vm.runInNewContext(template.replaceAll("${canonical_host}", canonicalHost) + "\nthis.handler = handler;", sandbox);
  return sandbox.handler;
}

const event = (host, uri, querystring = {}) => ({
  request: { uri, headers: host ? { host: { value: host } } : {}, querystring },
});

test("serves the app on its canonical hostname", () => {
  const handler = load("app.pokemaker.fun");
  assert.equal(handler(event("app.pokemaker.fun", "/p/kid1/cards/new")).uri, "/index.html");
  assert.equal(handler(event("app.pokemaker.fun", "/")).uri, "/index.html");
});

test("passes real files through untouched", () => {
  const handler = load("app.pokemaker.fun");
  assert.equal(handler(event("app.pokemaker.fun", "/assets/index-abc123.js")).uri, "/assets/index-abc123.js");
  assert.equal(handler(event("app.pokemaker.fun", "/favicon.svg")).uri, "/favicon.svg");
});

test("redirects the raw CloudFront hostname, keeping path and query", () => {
  const handler = load("app.pokemaker.fun");
  const response = handler(
    event("d111111abcdef8.cloudfront.net", "/p/kid1/print", {
      ids: { value: "a,b" },
      flag: { value: "" },
      t: { value: "1", multiValue: [{ value: "1" }, { value: "2" }] },
    }),
  );
  assert.equal(response.statusCode, 301);
  assert.equal(response.headers.location.value, "https://app.pokemaker.fun/p/kid1/print?ids=a,b&flag&t=1&t=2");
});

test("without a canonical host, only rewrites app routes", () => {
  const handler = load("");
  assert.equal(handler(event("d111111abcdef8.cloudfront.net", "/p/kid1")).uri, "/index.html");
  assert.equal(handler(event("d111111abcdef8.cloudfront.net", "/assets/app.css")).uri, "/assets/app.css");
});
