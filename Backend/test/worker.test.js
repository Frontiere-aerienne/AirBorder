import assert from "node:assert/strict";
import test from "node:test";

import worker, { backendTesting, resetProviderStateForTesting } from "../src/index.js";

const ORIGIN = "https://airportxr-proxy.example";

function developmentEnv(overrides = {}) {
  return {
    REQUEST_AUTH_MODE: "none",
    REQUIRE_RATE_LIMITER: "false",
    ...overrides
  };
}

function request(path, init = {}) {
  return new Request(`${ORIGIN}${path}`, init);
}

function upstreamJSON(body, status = 200, extraHeaders = {}) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json", ...extraHeaders }
  });
}

async function responseBody(response) {
  return JSON.parse(await response.text());
}

async function withMockFetch(mock, operation) {
  const original = globalThis.fetch;
  globalThis.fetch = mock;
  try {
    return await operation();
  } finally {
    globalThis.fetch = original;
  }
}

function base64URL(value) {
  const bytes = typeof value === "string" ? new TextEncoder().encode(value) : value;
  return Buffer.from(bytes).toString("base64url");
}

async function accessFixture() {
  const issuer = "https://airportxr.cloudflareaccess.com";
  const audience = "airportxr-access-audience";
  const kid = "deterministic-test-key";
  const keyPair = await crypto.subtle.generateKey(
    { name: "RSASSA-PKCS1-v1_5", modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: "SHA-256" },
    true,
    ["sign", "verify"]
  );
  const jwk = await crypto.subtle.exportKey("jwk", keyPair.publicKey);
  Object.assign(jwk, { kid, alg: "RS256", use: "sig" });
  const header = base64URL(JSON.stringify({ alg: "RS256", typ: "JWT", kid }));
  const payload = base64URL(JSON.stringify({
    iss: issuer,
    aud: [audience],
    sub: "traveler-test-subject",
    iat: Math.floor(Date.now() / 1_000) - 1,
    exp: Math.floor(Date.now() / 1_000) + 3_600
  }));
  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    keyPair.privateKey,
    new TextEncoder().encode(`${header}.${payload}`)
  );
  return {
    issuer,
    audience,
    token: `${header}.${payload}.${base64URL(new Uint8Array(signature))}`,
    jwk
  };
}

test("health remains public and does not require an application secret", async () => {
  const response = await worker.fetch(request("/health"), {});
  assert.equal(response.status, 200);
  assert.equal((await responseBody(response)).status, "ok");
});

test("protected routes fail closed when authentication is not configured", async () => {
  const response = await worker.fetch(request("/v1/provider-policies"), {});
  assert.equal(response.status, 503);
  assert.deepEqual(await responseBody(response), { error: "authentication_not_configured" });
});

test("production cannot enable unauthenticated development mode", async () => {
  const response = await worker.fetch(request("/v1/provider-policies"), {
    REQUEST_AUTH_MODE: "none",
    DEPLOYMENT_ENVIRONMENT: "production"
  });
  assert.equal(response.status, 503);
  assert.deepEqual(await responseBody(response), { error: "authentication_not_configured" });
});

test("Cloudflare Access mode rejects a missing assertion", async () => {
  const response = await worker.fetch(request("/v1/provider-policies"), {
    REQUEST_AUTH_MODE: "cloudflare-access",
    CF_ACCESS_TEAM_DOMAIN: "airportxr.cloudflareaccess.com",
    CF_ACCESS_AUD: "airportxr-access-audience"
  });
  assert.equal(response.status, 401);
  assert.equal(response.headers.get("www-authenticate"), "Cloudflare-Access");
  assert.deepEqual(await responseBody(response), { error: "authentication_required" });
});

test("Cloudflare Access mode cryptographically accepts a valid RS256 assertion", async () => {
  resetProviderStateForTesting();
  const fixture = await accessFixture();
  await withMockFetch(async url => {
    assert.equal(url, `${fixture.issuer}/cdn-cgi/access/certs`);
    return upstreamJSON({ keys: [fixture.jwk] });
  }, async () => {
    const response = await worker.fetch(request("/v1/provider-policies", {
      headers: { "Cf-Access-Jwt-Assertion": fixture.token }
    }), {
      REQUEST_AUTH_MODE: "cloudflare-access",
      CF_ACCESS_TEAM_DOMAIN: "airportxr.cloudflareaccess.com",
      CF_ACCESS_AUD: fixture.audience
    });
    assert.equal(response.status, 200);
    assert.equal((await responseBody(response)).version, "provider-policy-2026-11-17-v4");
  });
});

test("Cloudflare Access mode rejects a malformed assertion without reaching JWKS", async () => {
  await withMockFetch(async () => assert.fail("JWKS must not be fetched for malformed input"), async () => {
    const response = await worker.fetch(request("/v1/provider-policies", {
      headers: { "Cf-Access-Jwt-Assertion": "not-a-jwt" }
    }), {
      REQUEST_AUTH_MODE: "cloudflare-access",
      CF_ACCESS_TEAM_DOMAIN: "airportxr.cloudflareaccess.com",
      CF_ACCESS_AUD: "airportxr-access-audience"
    });
    assert.equal(response.status, 401);
    assert.equal((await responseBody(response)).error, "authentication_required");
  });
});

test("required rate limiter fails closed when its binding is absent", async () => {
  const response = await worker.fetch(request("/v1/provider-policies"), developmentEnv({ REQUIRE_RATE_LIMITER: "true" }));
  assert.equal(response.status, 503);
  assert.equal((await responseBody(response)).error, "rate_limiter_not_configured");
});

test("rate limiter returns deterministic 429 without exposing the principal", async () => {
  let observedKey;
  const response = await worker.fetch(request("/v1/provider-policies"), developmentEnv({
    API_RATE_LIMITER: {
      async limit({ key }) {
        observedKey = key;
        return { success: false };
      }
    }
  }));
  assert.equal(response.status, 429);
  assert.equal(response.headers.get("retry-after"), "60");
  assert.equal((await responseBody(response)).error, "rate_limited");
  assert.match(observedKey, /^[a-f0-9]{64}:metadata$/);
  assert.ok(!observedKey.includes("explicitly-unauthenticated-development"));
});

test("rate limiter binding failure returns a safe 503", async () => {
  const response = await worker.fetch(request("/v1/provider-policies"), developmentEnv({
    API_RATE_LIMITER: {
      async limit() { throw new Error("binding internals must not leak"); }
    }
  }));
  assert.equal(response.status, 503);
  assert.deepEqual(await responseBody(response), { error: "rate_limiter_unavailable" });
});

test("validation rejects malformed flight and geographic queries before provider calls", async () => {
  await withMockFetch(async () => assert.fail("invalid requests must not call a provider"), async () => {
    const invalidFlight = await worker.fetch(
      request("/v1/flights/search?flightNumber=bad/value&date=2026-02-30"),
      developmentEnv({ FLIGHTAWARE_AEROAPI_KEY: "redacted" })
    );
    assert.equal(invalidFlight.status, 400);
    assert.equal((await responseBody(invalidFlight)).error, "invalid_query");

    const invalidHotel = await worker.fetch(
      request("/v1/hotels/search?latitude=95&longitude=139&radiusKm=5"),
      developmentEnv({ AMADEUS_CLIENT_ID: "id", AMADEUS_CLIENT_SECRET: "secret" })
    );
    assert.equal(invalidHotel.status, 400);
    assert.equal((await responseBody(invalidHotel)).error, "invalid_geographic_query");
  });
});

test("entry endpoint rejects sensitive document fields before provider access", async () => {
  await withMockFetch(async () => assert.fail("sensitive input must not call a provider"), async () => {
    const response = await worker.fetch(request(
      "/v1/entry-requirements?nationality=TH&destinationCountry=JP&passportNumber=ABC123"
    ), developmentEnv({ SHERPA_API_KEY: "redacted" }));
    assert.equal(response.status, 400);
    assert.deepEqual(await responseBody(response), { error: "sensitive_field_prohibited" });
  });
});

function entryRequirementPayload(overrides = {}) {
  return {
    nationalityCountryCode: "US",
    residenceCountryCode: "US",
    passportType: "ordinary",
    declaredAuthorizations: [],
    originCountryCode: "TH",
    transitCountryCode: "JP",
    onwardCountryCode: "US",
    originAirportCode: "BKK",
    transitArrivalAirportCode: "HND",
    onwardDepartureAirportCode: "NRT",
    onwardDestinationAirportCode: "LAX",
    originDeparture: "2026-07-14T01:00:00.000Z",
    arrival: "2026-07-14T07:00:00.000Z",
    departure: "2026-07-14T13:00:00.000Z",
    onwardArrival: "2026-07-14T23:00:00.000Z",
    originTimeZoneIdentifier: "Asia/Bangkok",
    transitTimeZoneIdentifier: "Asia/Tokyo",
    onwardTimeZoneIdentifier: "America/Los_Angeles",
    plannedLandsideExit: true,
    luggage: "checkedThrough",
    purpose: "transit",
    ...overrides
  };
}

function entryRequirementRequest(payload = entryRequirementPayload()) {
  return request("/v1/entry-requirements", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(payload)
  });
}

function sherpaTripPayload(overrides = {}) {
  return {
    meta: {},
    data: {
      id: "sherpa-trip-record-1",
      type: "TRIP",
      attributes: {
        informationGroups: [{ type: "VISA_REQUIREMENTS", enforcement: "NOT_REQUIRED" }]
      }
    },
    included: [{
      id: "visa-procedure-1",
      type: "PROCEDURE",
      attributes: {
        category: "NO_VISA",
        enforcement: "NOT_REQUIRED",
        title: "Visa guidance",
        description: "Provider guidance requiring official verification.",
        lastUpdatedAt: "2026-07-14T00:00:00.000Z",
        sources: [{
          type: "GOVERNMENT",
          title: "Ministry of Foreign Affairs of Japan",
          url: "https://www.mofa.go.jp/j_info/visit/visa/index.html"
        }]
      }
    }],
    ...overrides
  };
}

test("entry route uses the current Sherpa v3 trip POST and preserves structured provenance", async () => {
  await withMockFetch(async (url, init) => {
    assert.equal(url, "https://requirements-api.joinsherpa.com/v3/trips?include=restriction%2Cprocedure");
    assert.equal(init.method, "POST");
    assert.equal(init.headers["x-api-key"], "sherpa-secret");
    assert.equal(init.headers["Content-Type"], "application/vnd.api+json");
    const body = JSON.parse(init.body);
    assert.deepEqual(body.data.attributes.traveller.passports, ["USA"]);
    assert.deepEqual(body.data.attributes.travelNodes.map(node => node.airportCode), ["BKK", "HND", "NRT", "LAX"]);
    return upstreamJSON(sherpaTripPayload(), 200, { "cache-control": "public, max-age=3600" });
  }, async () => {
    const response = await worker.fetch(entryRequirementRequest(), developmentEnv({ SHERPA_API_KEY: "sherpa-secret" }));
    assert.equal(response.status, 200);
    const body = await responseBody(response);
    assert.equal(body.assessment.status, "requiresConfirmation");
    assert.equal(body.assessment.canEnter, null);
    assert.equal(body.assessment.decisionAuthority, "structuredGuidance");
    assert.equal(body.source.provider, "Sherpa Requirements API");
    assert.equal(body.source.recordID, "sherpa-trip-record-1");
    assert.equal(body.source.evidenceKind, "structuredProvider");
    assert.deepEqual(body.source.providerChain, ["Sherpa Requirements API"]);
    assert.equal(body.source.providerPolicy, "sherpa");
    assert.equal(body.source.trainingAllowed, false);
    assert.match(response.headers.get("cache-control"), /^private, max-age=3600/);
  });
});

test("malformed Sherpa data falls back to the independent Timatic contract adapter", async () => {
  const calls = [];
  await withMockFetch(async (url, init) => {
    calls.push(url);
    if (url.includes("joinsherpa.com")) return upstreamJSON({ unexpected: true });
    assert.equal(url, "https://entry-adapter.iata.org/autocheck");
    assert.equal(init.headers["x-api-key"], "timatic-secret");
    assert.equal(init.headers["x-service-token"], "timatic-service-token");
    assert.equal(JSON.parse(init.body).schemaVersion, "airportxr-entry-query-v1");
    return upstreamJSON({
      assessment: {
        recordID: "timatic-record-1",
        observedAt: new Date().toISOString(),
        expiresAt: new Date(Date.now() + 30 * 60 * 1_000).toISOString(),
        requirements: [{ id: "timatic-rule-1", category: "visa", status: "verify", summary: "Verify current requirements." }],
        officialVerificationLinks: [{ label: "Japan MOFA", url: "https://www.mofa.go.jp/j_info/visit/visa/index.html" }]
      }
    });
  }, async () => {
    const response = await worker.fetch(entryRequirementRequest(), developmentEnv({
      SHERPA_API_KEY: "sherpa-secret",
      TIMATIC_API_URL: "https://entry-adapter.iata.org/autocheck",
      TIMATIC_API_KEY: "timatic-secret",
      TIMATIC_SERVICE_TOKEN: "timatic-service-token"
    }));
    assert.equal(response.status, 200);
    const body = await responseBody(response);
    assert.equal(body.source.provider, "IATA Timatic AutoCheck adapter");
    assert.equal(body.source.recordID, "timatic-record-1");
    assert.equal(body.source.evidenceKind, "structuredProvider");
    assert.deepEqual(body.source.providerChain, ["Sherpa Requirements API", "IATA Timatic AutoCheck adapter"]);
    assert.equal(body.assessment.canEnter, null);
  });
  assert.equal(calls.length, 2);
});

test("explicitly stale structured data is rejected before fallback", async () => {
  let calls = 0;
  await withMockFetch(async url => {
    calls += 1;
    if (url.includes("joinsherpa.com")) {
      return upstreamJSON(sherpaTripPayload({ meta: { expiresAt: "2020-01-01T00:00:00.000Z" } }));
    }
    return upstreamJSON({
      assessment: {
        recordID: "fresh-backup-record",
        observedAt: new Date().toISOString(),
        expiresAt: new Date(Date.now() + 20 * 60 * 1_000).toISOString(),
        requirements: [],
        officialVerificationLinks: []
      }
    });
  }, async () => {
    const response = await worker.fetch(entryRequirementRequest(), developmentEnv({
      SHERPA_API_KEY: "sherpa-secret",
      TIMATIC_API_URL: "https://entry-adapter.iata.org/autocheck",
      TIMATIC_API_KEY: "timatic-secret"
    }));
    assert.equal(response.status, 200);
    const body = await responseBody(response);
    assert.equal(body.source.recordID, "fresh-backup-record");
    assert.equal(body.source.provider, "IATA Timatic AutoCheck adapter");
  });
  assert.equal(calls, 2);
});

test("entry provider authentication failure stops instead of masking configuration with fallback", async () => {
  let calls = 0;
  await withMockFetch(async url => {
    calls += 1;
    assert.ok(url.includes("joinsherpa.com"));
    return upstreamJSON({ error: "unauthorized" }, 401);
  }, async () => {
    const response = await worker.fetch(entryRequirementRequest(), developmentEnv({
      SHERPA_API_KEY: "invalid-sherpa-secret",
      TIMATIC_API_URL: "https://entry-adapter.iata.org/autocheck",
      TIMATIC_API_KEY: "timatic-secret"
    }));
    assert.equal(response.status, 502);
    assert.deepEqual(await responseBody(response), { error: "upstream_unavailable" });
  });
  assert.equal(calls, 1);
});

test("entry fallback uses only bundled links, even with leftover inference credentials", async () => {
  let upstreamCalls = 0;
  const env = developmentEnv({
    GEMINI_API_KEY: "unused-legacy-key",
    GEMINI_ENTRY_DISCOVERY_MODEL: "unused-legacy-model",
    ENTRY_OFFICIAL_DOMAINS_JSON: '{"JP":["unapproved.example"]}'
  });
  await withMockFetch(async () => {
    upstreamCalls += 1;
    throw new Error("Registry fallback must not reach a provider");
  }, async () => {
    for (const input of [
      entryRequirementRequest(),
      request("/v1/entry-requirements?destinationCountry=JP&plannedEntry=true")
    ]) {
      const response = await worker.fetch(input, env);
      assert.equal(response.status, 200);
      const body = await responseBody(response);
      assert.equal(body.assessment.status, "requiresConfirmation");
      assert.equal(body.assessment.canEnter, null);
      assert.equal(body.assessment.decisionAuthority, "discoveryOnly");
      assert.deepEqual(body.assessment.requirements, []);
      assert.deepEqual(body.assessment.officialVerificationLinks.map(link => link.url), [
        "https://www.mofa.go.jp/j_info/visit/visa/short/novisa.html"
      ]);
      assert.equal(body.decisionSupportOnly, true);
      assert.equal(body.source.dataMode, "publicRegistry");
      assert.equal(body.source.evidenceKind, "informationalFallback");
      assert.equal(body.source.cacheTTLSeconds, 0);
      assert.equal(body.source.expiresAt, body.source.receivedAt);
      assert.equal(response.headers.get("cache-control"), "private, max-age=0, must-revalidate");
    }
    const response = await worker.fetch(request("/v1/entry-requirements?destinationCountry=CA"), env);
    assert.equal(response.status, 200);
    const body = await responseBody(response);
    assert.deepEqual(body.assessment.officialVerificationLinks, []);
    assert.equal(body.assessment.canEnter, null);
    assert.match(body.assessment.reason, /verify manually/);
  });
  assert.equal(upstreamCalls, 0);
});

test("after a transient structured provider failure, the bundled fallback is the only next step", async () => {
  const upstreamCalls = [];
  await withMockFetch(async url => {
    upstreamCalls.push(url);
    return upstreamJSON({ error: "temporarily unavailable" }, 503);
  }, async () => {
    const response = await worker.fetch(entryRequirementRequest(), developmentEnv({
      SHERPA_API_KEY: "sherpa-secret",
      GEMINI_API_KEY: "unused-legacy-key"
    }));
    assert.equal(response.status, 200);
    const body = await responseBody(response);
    assert.equal(body.assessment.canEnter, null);
    assert.equal(body.source.evidenceKind, "informationalFallback");
    assert.deepEqual(body.source.providerChain, ["Sherpa Requirements API"]);
  });
  assert.equal(upstreamCalls.length, 1);
  assert.match(upstreamCalls[0], /joinsherpa\.com/);
});

test("upstream 429 and Retry-After propagate without provider fallback", async () => {
  resetProviderStateForTesting();
  let calls = 0;
  await withMockFetch(async () => {
    calls += 1;
    return upstreamJSON({ error: "quota", secret: "must-not-leak" }, 429, { "retry-after": "17" });
  }, async () => {
    const response = await worker.fetch(
      request("/v1/flights/search?flightNumber=AX204&date=2026-07-14"),
      developmentEnv({
        FLIGHTAWARE_AEROAPI_KEY: "flight-secret",
        AMADEUS_CLIENT_ID: "amadeus-id",
        AMADEUS_CLIENT_SECRET: "amadeus-secret"
      })
    );
    assert.equal(response.status, 429);
    assert.equal(response.headers.get("retry-after"), "17");
    assert.deepEqual(await responseBody(response), { error: "rate_limited" });
    assert.equal(calls, 1, "Fallback must not bypass a provider quota response");
  });
});

test("flight search falls back from transient FlightAware failure to Amadeus", async () => {
  resetProviderStateForTesting();
  const calls = [];
  await withMockFetch(async (url, init) => {
    calls.push({ url, init });
    if (url.startsWith("https://aeroapi.flightaware.com/")) return upstreamJSON({ error: "temporary" }, 502);
    if (url.endsWith("/v1/security/oauth2/token")) return upstreamJSON({ access_token: "test-access-token", expires_in: 900 });
    if (url.startsWith("https://test.api.amadeus.com/v2/schedule/flights")) {
      assert.equal(init.headers.Authorization, "Bearer test-access-token");
      return upstreamJSON({
        data: [{
          scheduledDepartureDate: "2026-07-14",
          flightDesignator: { carrierCode: "AX", flightNumber: 204 },
          flightPoints: [
            { iataCode: "HND", departure: { timings: [{ qualifier: "STD", value: "2026-07-14T10:00:00+09:00" }] } },
            { iataCode: "LAX", arrival: { timings: [{ qualifier: "STA", value: "2026-07-14T04:00:00-07:00" }] } }
          ],
          legs: [{ aircraftEquipment: { aircraftType: "789" } }]
        }]
      });
    }
    assert.fail(`Unexpected provider URL: ${url}`);
  }, async () => {
    const response = await worker.fetch(
      request("/v1/flights/search?flightNumber=AX204&date=2026-07-14"),
      developmentEnv({
        FLIGHT_PROVIDER: "flightaware",
        FLIGHTAWARE_AEROAPI_KEY: "flight-secret",
        AMADEUS_CLIENT_ID: "amadeus-id",
        AMADEUS_CLIENT_SECRET: "amadeus-secret"
      })
    );
    assert.equal(response.status, 200);
    const body = await responseBody(response);
    assert.equal(body.flights.length, 1);
    assert.equal(body.flights[0].routeLabel, undefined);
    assert.equal(body.flights[0].origin.iata, "HND");
    assert.equal(body.flights[0].destination.iata, "LAX");
    assert.equal(body.source.provider, "Amadeus Self-Service APIs");
    assert.equal(body.source.providerPolicy, "amadeusFlights");
    assert.equal(body.source.trainingAllowed, false);
    assert.deepEqual(body.source.trainingPurposes, []);
    assert.equal(calls.length, 3);
  });
});

test("malformed upstream JSON and malformed record shape become safe 502 errors", async () => {
  const environment = developmentEnv({ FLIGHTAWARE_AEROAPI_KEY: "flight-secret" });
  await withMockFetch(async () => new Response("not-json", { headers: { "content-type": "application/json" } }), async () => {
    const response = await worker.fetch(request("/v1/flights/search?flightNumber=AX204&date=2026-07-14"), environment);
    assert.equal(response.status, 502);
    assert.deepEqual(await responseBody(response), { error: "upstream_unavailable" });
  });
  await withMockFetch(async () => upstreamJSON({ unexpected: [] }), async () => {
    const response = await worker.fetch(request("/v1/flights/search?flightNumber=AX204&date=2026-07-14"), environment);
    assert.equal(response.status, 502);
    assert.deepEqual(await responseBody(response), { error: "upstream_unavailable" });
  });
});

test("oversized or non-JSON upstream responses are rejected", async () => {
  const environment = developmentEnv({ FLIGHTAWARE_AEROAPI_KEY: "flight-secret" });
  await withMockFetch(async () => new Response("{}", {
    headers: { "content-type": "application/json", "content-length": "1000001" }
  }), async () => {
    const response = await worker.fetch(request("/v1/flights/search?flightNumber=AX204&date=2026-07-14"), environment);
    assert.equal(response.status, 502);
    assert.equal((await responseBody(response)).error, "upstream_unavailable");
  });
  await withMockFetch(async () => new Response(JSON.stringify({
    flights: [],
    padding: "x".repeat(1_000_001)
  }), { headers: { "content-type": "application/json" } }), async () => {
    const response = await worker.fetch(request("/v1/flights/search?flightNumber=AX204&date=2026-07-14"), environment);
    assert.equal(response.status, 502);
    assert.equal((await responseBody(response)).error, "upstream_unavailable");
  });
  await withMockFetch(async () => new Response("{}", { headers: { "content-type": "text/html" } }), async () => {
    const response = await worker.fetch(request("/v1/flights/search?flightNumber=AX204&date=2026-07-14"), environment);
    assert.equal(response.status, 502);
    assert.equal((await responseBody(response)).error, "upstream_unavailable");
  });
});

test("provider timeout maps to a bounded 504 error", async () => {
  await withMockFetch(async () => {
    const error = new Error("provider included private payload");
    error.name = "TimeoutError";
    throw error;
  }, async () => {
    const response = await worker.fetch(
      request("/v1/flights/search?flightNumber=AX204&date=2026-07-14"),
      developmentEnv({ FLIGHTAWARE_AEROAPI_KEY: "flight-secret" })
    );
    assert.equal(response.status, 504);
    assert.deepEqual(await responseBody(response), { error: "upstream_timeout" });
  });
});

test("safe errors and logs never echo provider payloads or credentials", async () => {
  const originalError = console.error;
  const logs = [];
  console.error = (...values) => logs.push(values.join(" "));
  try {
    await withMockFetch(async () => new Response('{"secret":"provider-private-value"', {
      headers: { "content-type": "application/json" }
    }), async () => {
      const response = await worker.fetch(
        request("/v1/flights/search?flightNumber=AX204&date=2026-07-14"),
        developmentEnv({ FLIGHTAWARE_AEROAPI_KEY: "flight-api-private-value" })
      );
      const serialized = await response.text();
      assert.equal(response.status, 502);
      assert.ok(!serialized.includes("provider-private-value"));
      assert.ok(!serialized.includes("flight-api-private-value"));
    });
  } finally {
    console.error = originalError;
  }
  const serializedLogs = logs.join("\n");
  assert.ok(!serializedLogs.includes("provider-private-value"));
  assert.ok(!serializedLogs.includes("flight-api-private-value"));
});

test("provider-policy endpoint is versioned and denies all current commercial training", async () => {
  const response = await worker.fetch(request("/v1/provider-policies"), developmentEnv());
  assert.equal(response.status, 200);
  const body = await responseBody(response);
  assert.equal(body.version, "provider-policy-2026-11-17-v4");
  assert.ok(body.policies.flightaware);
  assert.ok(body.policies.amadeusFlights);
  assert.ok(body.policies.sherpa);
  assert.equal(body.policies.sherpa.canAuthorizeEntry, false);
  assert.equal(body.policies.timatic.canAuthorizeEntry, false);
  assert.equal(Object.hasOwn(body.policies, "geminiEntryDiscovery"), false);
  assert.equal(Object.hasOwn(body.policies, "workersAIExplanation"), false);
  for (const policy of Object.values(body.policies)) {
    assert.equal(policy.trainingAllowed, false);
    assert.deepEqual(policy.trainingPurposes, []);
  }
});

test("normalized live response carries complete provider-policy metadata", async () => {
  await withMockFetch(async () => upstreamJSON({
    flights: [{
      fa_flight_id: "FA-AX204-20260714",
      ident_iata: "AX204",
      origin: { code_iata: "HND", name: "Tokyo Haneda" },
      destination: { code_iata: "LAX", name: "Los Angeles" },
      scheduled_out: "2026-07-14T01:00:00Z",
      actual_out: "2026-07-14T01:15:00Z"
    }]
  }), async () => {
    const response = await worker.fetch(
      request("/v1/flights/search?flightNumber=AX204&date=2026-07-14"),
      developmentEnv({ FLIGHTAWARE_AEROAPI_KEY: "flight-secret" })
    );
    assert.equal(response.status, 200);
    const body = await responseBody(response);
    assert.equal(body.flights[0].providerRecordID, "FA-AX204-20260714");
    assert.equal(body.source.providerPolicy, "flightaware");
    assert.equal(body.source.providerPolicyVersion, "provider-policy-2026-11-17-v4");
    assert.equal(body.source.trainingAllowed, false);
    assert.deepEqual(body.source.trainingPurposes, []);
  });
});

test("all externally surfaced URLs and provider fetches require HTTPS", async () => {
  assert.equal(backendTesting.safeExternalURL("http://example.com/booking"), null);
  assert.equal(backendTesting.safeExternalURL("javascript:alert(1)"), null);
  assert.equal(backendTesting.safeExternalURL("https://user:pass@example.com/private"), null);
  assert.equal(backendTesting.safeExternalURL("https://example.com/booking"), "https://example.com/booking");
  await assert.rejects(() => backendTesting.providerFetch("http://example.com/provider"));
  assert.equal(backendTesting.accessIssuer("https://not-cloudflare.example"), null);
  assert.equal(
    backendTesting.accessIssuer("airportxr.cloudflareaccess.com"),
    "https://airportxr.cloudflareaccess.com"
  );
});

test("retired explanation endpoint cannot invoke a model even with an old binding", async () => {
  let inferenceCalls = 0;
  const env = developmentEnv({
    AI: { async run() { inferenceCalls += 1; throw new Error("Retired inference"); } },
    GEMINI_API_KEY: "unused-legacy-key",
    GOOGLE_VISION_API_KEY: "ocr-key"
  });
  const health = await responseBody(await worker.fetch(request("/health"), env));
  assert.equal(health.configured.cloudVision, true);
  assert.equal(Object.hasOwn(health.configured, "groundedExplanation"), false);
  assert.equal(Object.hasOwn(health.configured, "entryOfficialSourceDiscovery"), false);
  const post = await worker.fetch(request("/v1/ai/explain", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({
      task: "explainCalculationTrace",
      trace: { title: "Boarding window", steps: [{ label: "Window", formula: "end - start", result: 40 }] }
    })
  }), env);
  assert.equal(post.status, 405);
  assert.deepEqual(await responseBody(post), { error: "method_not_allowed" });
  const get = await worker.fetch(request("/v1/ai/explain"), env);
  assert.equal(get.status, 404);
  assert.equal(inferenceCalls, 0);
});

test("opt-in Google Cloud Vision text detection remains available without an LLM", async () => {
  let upstreamCalls = 0;
  const env = developmentEnv({ GOOGLE_VISION_API_KEY: "ocr-key" });
  const capture = headers => request("/v1/scene-ocr", {
    method: "POST", headers: { "content-type": "image/jpeg", ...headers }, body: new Uint8Array([255, 216, 255, 217])
  });
  await withMockFetch(async (url, init) => {
    upstreamCalls += 1;
    assert.equal(new URL(url).hostname, "vision.googleapis.com");
    assert.equal(init.method, "POST");
    assert.deepEqual(JSON.parse(init.body).requests[0].features, [{ type: "TEXT_DETECTION", maxResults: 20 }]);
    return upstreamJSON({ responses: [{ fullTextAnnotation: { text: "Gate C12" } }] });
  }, async () => {
    const refused = await worker.fetch(capture({}), env);
    assert.equal(refused.status, 403);
    assert.deepEqual(await responseBody(refused), { error: "consent_required" });
    assert.equal(upstreamCalls, 0);
    const response = await worker.fetch(capture({ "x-cloud-vision-consent": "true" }), env);
    assert.equal(response.status, 200);
    const body = await responseBody(response);
    assert.deepEqual(body.results, [{ label: "Gate C12", nodeID: "gate-c12", confidence: null }]);
    assert.equal(body.advisory, true);
    assert.equal(body.source.provider, "Google Cloud Vision");
  });
  assert.equal(upstreamCalls, 1);
});

const googleReminderScope = "00000000-0000-4000-8000-000000000001";
const googleReminderID = "00000000-0000-4000-8000-000000000002";
const staleGoogleReminderID = "00000000-0000-4000-8000-000000000003";

function googleReminderPayload(reminders = [{
  id: googleReminderID,
  title: "Return now for your onward flight",
  notes: "Derived from current return and safety inputs.",
  intendedActionAt: "2026-07-14T12:00:00.000Z",
  dueDate: "2026-07-14",
  timeZoneIdentifier: "Asia/Tokyo",
  deepLink: "airportxr://transit",
  sourceRevision: 7
}]) {
  return {
    consentRevision: "google-tasks-consent-2026-07-14-v1",
    taskListID: "@default",
    scopeID: googleReminderScope,
    reminders
  };
}

function googleReminderRequest(payload = googleReminderPayload(), headers = {}) {
  return request("/v1/reminders/google-tasks/sync", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      authorization: "Bearer short-lived-user-oauth-token",
      "x-airportxr-google-tasks-consent": "true",
      "x-airportxr-google-tasks-consent-revision": "google-tasks-consent-2026-07-14-v1",
      ...headers
    },
    body: JSON.stringify(payload)
  });
}

test("Google Tasks sync requires explicit consent and user OAuth; an API key is insufficient", async () => {
  await withMockFetch(async () => assert.fail("validation must happen before Google Tasks access"), async () => {
    const noConsent = await worker.fetch(request("/v1/reminders/google-tasks/sync", {
      method: "POST",
      headers: { "content-type": "application/json", authorization: "Bearer user-token" },
      body: JSON.stringify(googleReminderPayload())
    }), developmentEnv());
    assert.equal(noConsent.status, 403);
    assert.deepEqual(await responseBody(noConsent), { error: "consent_required" });

    const apiKeyOnly = await worker.fetch(request("/v1/reminders/google-tasks/sync", {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "x-api-key": "not-user-oauth",
        "x-airportxr-google-tasks-consent": "true",
        "x-airportxr-google-tasks-consent-revision": "google-tasks-consent-2026-07-14-v1"
      },
      body: JSON.stringify(googleReminderPayload())
    }), developmentEnv());
    assert.equal(apiKeyOnly.status, 401);
    assert.deepEqual(await responseBody(apiKeyOnly), { error: "google_oauth_required" });
  });
});

test("Google Tasks sync updates by stable marker and removes stale AirportXR tasks", async () => {
  const calls = [];
  await withMockFetch(async (url, init = {}) => {
    calls.push({ url, init });
    assert.equal(init.headers.Authorization, "Bearer short-lived-user-oauth-token");
    assert.ok(!String(init.body || "").includes("short-lived-user-oauth-token"));
    if (init.method === "PATCH") {
      const body = JSON.parse(init.body);
      assert.match(body.notes, new RegExp(`\\[AirportXR:v1 scope=${googleReminderScope} reminder=${googleReminderID}\\]`));
      assert.equal(body.due, "2026-07-14T00:00:00.000Z");
      return upstreamJSON({ id: "existing-task", webViewLink: "https://tasks.google.com/task/existing-task" });
    }
    if (init.method === "DELETE") return new Response(null, { status: 204 });
    return upstreamJSON({
      items: [
        {
          id: "existing-task",
          notes: `old notes\n[AirportXR:v1 scope=${googleReminderScope} reminder=${googleReminderID}]`
        },
        {
          id: "stale-task",
          notes: `old notes\n[AirportXR:v1 scope=${googleReminderScope} reminder=${staleGoogleReminderID}]`
        },
        {
          id: "unrelated-task",
          notes: "Personal task not managed by AirportXR"
        }
      ]
    });
  }, async () => {
    const response = await worker.fetch(googleReminderRequest(), developmentEnv());
    assert.equal(response.status, 200);
    const body = await responseBody(response);
    assert.deepEqual(body.tasks.map(task => task.reminderID), [googleReminderID]);
    assert.deepEqual(body.removedReminderIDs, [staleGoogleReminderID]);
    assert.match(body.limitations[0], /stores only the due date/i);
  });
  assert.equal(calls.filter(call => call.init.method === "PATCH").length, 1);
  assert.equal(calls.filter(call => call.init.method === "POST").length, 0);
  assert.equal(calls.filter(call => call.init.method === "DELETE").length, 1);
});

test("Google Tasks stable marker makes a retry update instead of insert a duplicate", async () => {
  let insertedTask = null;
  let insertCalls = 0;
  let patchCalls = 0;
  await withMockFetch(async (_url, init = {}) => {
    if (!init.method) return upstreamJSON({ items: insertedTask ? [insertedTask] : [] });
    if (init.method === "POST") {
      insertCalls += 1;
      const body = JSON.parse(init.body);
      insertedTask = { id: "created-on-first-sync", notes: body.notes };
      return upstreamJSON(insertedTask);
    }
    if (init.method === "PATCH") {
      patchCalls += 1;
      return upstreamJSON({ id: "created-on-first-sync", notes: JSON.parse(init.body).notes });
    }
    assert.fail(`Unexpected Google Tasks method: ${init.method}`);
  }, async () => {
    const first = await worker.fetch(googleReminderRequest(), developmentEnv());
    const replay = await worker.fetch(googleReminderRequest(), developmentEnv());
    assert.equal(first.status, 200);
    assert.equal(replay.status, 200);
  });
  assert.equal(insertCalls, 1);
  assert.equal(patchCalls, 1);
});

test("Google Tasks rejects a mismatched local due date before provider access", async () => {
  const payload = googleReminderPayload();
  payload.reminders[0].dueDate = "2026-07-15";
  await withMockFetch(async () => assert.fail("invalid local date must not reach Google Tasks"), async () => {
    const response = await worker.fetch(googleReminderRequest(payload), developmentEnv());
    assert.equal(response.status, 400);
    assert.deepEqual(await responseBody(response), { error: "invalid_reminder_sync" });
  });
});

test("Google Tasks fails before mutation when an idempotency scan exceeds its bounded page limit", async () => {
  let calls = 0;
  await withMockFetch(async (_url, init = {}) => {
    calls += 1;
    assert.equal(init.method, undefined);
    return upstreamJSON({ items: [], nextPageToken: `page-${calls}` });
  }, async () => {
    const response = await worker.fetch(googleReminderRequest(), developmentEnv());
    assert.equal(response.status, 409);
    assert.deepEqual(await responseBody(response), { error: "google_task_list_too_large_for_safe_sync" });
  });
  assert.equal(calls, 20);
});
