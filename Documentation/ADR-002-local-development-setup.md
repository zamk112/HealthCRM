# ADR-002: Local Development Environment Setup for HealthCRM

## Context
HealthCRM is a two-part application: an ASP.NET Core Web API backend (`HealthCRM.Server`) and a Vite/React frontend (`HealthCRM.Client`). After scaffolding both projects, the local development environment needed to be put on a consistent footing before feature work began. Four concerns drove the decisions recorded here:

1. **HTTPS everywhere.** Both frontend and backend should run over TLS locally so that local behaviour matches the intended production setup (NGINX reverse proxy in front of the API, both over HTTP/2) as closely as is practical.
2. **A single launch experience.** Development happens in VS Code rather than Visual Studio, across macOS *and* Ubuntu machines. The two stacks needed to build, launch, and attach a debugger together with one action.
3. **Useful logging from the first run.** Structured logging and HTTP request logging were wanted early, to support debugging now and audit requirements later.
4. **Cross-platform TLS trust.** Ubuntu OS does not have a centralised certificate store, so the way the frontend trusts the backend's dev certificate had to work without relying on an OS trust store.

This document records the decisions made to address these concerns, the alternatives considered, and the consequences of each.

## Decision 1: Use Serilog with two-stage initialization
### Decision
Adopt Serilog (`Serilog.AspNetCore`) as the logging provider, configured via `appsettings*.json`, and initialize it in two stages: a bootstrap logger created before the host is built, then the full host-integrated logger registered through DI.

```csharp
using Serilog;

var builder = WebApplication.CreateBuilder(args);

Log.Logger = new LoggerConfiguration()
    .ReadFrom.Configuration(builder.Configuration)
    .Enrich.FromLogContext()
    .CreateBootstrapLogger();

try
{
    builder.Services.AddSerilog((services, lc) => lc
        .ReadFrom.Configuration(builder.Configuration)
        .ReadFrom.Services(services)
        .Enrich.FromLogContext());

    builder.Services.AddControllers();
    builder.Services.AddOpenApi();

    var app = builder.Build();

    // Registered on `app`, so it must come AFTER builder.Build().
    // Placed high in the pipeline so it captures the output of
    // downstream middleware as well.
    app.UseSerilogRequestLogging();
    Log.Information("Application started! Logging to both console and/or file.");

    if (app.Environment.IsDevelopment())
    {
        app.MapOpenApi();
    }

    app.UseHttpsRedirection();
    app.UseAuthorization();
    app.MapControllers();
    app.Run();
}
catch (Exception ex)
{
    Log.Fatal(ex, "Application start-up failed!");
}
finally
{
    Log.CloseAndFlush();
}
```

### Rationale
- **Bootstrap logger first.** `CreateBootstrapLogger()` gives a working logger *before* the DI container is built. This follows the two-stage initialization pattern documented by Serilog: when Serilog is initialized this early, dependency injection is not yet available, so a bootstrap logger is created to capture anything that happens during startup. Here it reads from configuration ([appsettings.json](../HealthCRM.Server/appsettings.json) or [appsettings.Development.json](../HealthCRM.Server/appsettings.Development.json)) so that startup logging uses the configured sinks (e.g. the file sink) rather than defaults. It is then replaced by the fully host-integrated logger once the host has loaded. The replacement is complete — the final logger does not inherit the bootstrap logger's configuration — so configuration is read again via `ReadFrom.Configuration` in the second stage, this time also wiring in DI-provided services via `ReadFrom.Services`. Reading the config in both stages is intentional, not redundant: it is what gives configured (file) logging during the startup window as well as after the host is built.
- **`try/catch/finally` around startup.** The `catch` logs fatal startup failures via `Log.Fatal`; the `finally` calls `Log.CloseAndFlush()` so the buffered sinks are flushed when the application stops (whether by exception or by the user stopping it). Without the flush, the tail of the log can be lost.
- **Configuration-driven.** Sinks and levels live in `appsettings*.json` rather than code, so logging behaviour can change per environment without a rebuild.

### Per-environment logging configuration
Development ([appsettings.Development.json](../HealthCRM.Server/appsettings.Development.json)): minimum level `Information`, written to **both** console and a rolling daily file.

Production ([appsettings.json](../HealthCRM.Server/appsettings.json)): minimum level `Warning`, written to **file only** (no console sink).

The reasoning: development benefits from verbose, immediately-visible console output; production wants quieter, persisted logs and no console noise. Both file sinks roll daily, retain 10 files, and cap each file at 10 MB.

### Consequences
- Positive: startup failures are now observable; log behaviour is environment-specific and editable without redeploying code.
- Negative / to watch: the two-stage pattern is slightly more ceremony than a single logger and is easy to get subtly wrong (e.g. middleware ordering — see note below).

> **Note on middleware ordering.** `app.UseSerilogRequestLogging()` is invoked on the `app` object and therefore must appear *after* `var app = builder.Build();`. It is placed high in the request pipeline deliberately, so that it logs the output of the middleware that runs after it.


## Decision 2: Add HTTP logging middleware (development only, for now)
### Decision
Enable ASP.NET Core's HTTP logging middleware (`AddHttpLogging` /`UseHttpLogging`) in the Development environment, capturing all logging fields plus a set of client-hint and fetch-metadata request headers.

```csharp
if (builder.Environment.IsDevelopment())
{
    builder.Services.AddHttpLogging(o =>
    {
        o.LoggingFields = HttpLoggingFields.All;
        o.RequestHeaders.Add("Referer");
        o.RequestHeaders.Add("sec-ch-ua-platform");
        o.RequestHeaders.Add("sec-ch-ua");
        o.RequestHeaders.Add("sec-ch-ua-mobile");
        o.RequestHeaders.Add("sec-fetch-site");
        o.RequestHeaders.Add("sec-fetch-mode");
        o.RequestHeaders.Add("sec-fetch-dest");
        o.RequestHeaders.Add("priority");
    });

    builder.Services.AddOpenApi();
}

// ...
var app = builder.Build();
app.UseSerilogRequestLogging();

if (app.Environment.IsDevelopment())
{
    app.UseHttpLogging();
    app.MapOpenApi();
}
```

### Rationale
The application will sit behind a reverse proxy, so being able to see the full request — including the extra headers the browser sends and the proxy forwards — is valuable for debugging the proxy/backend interaction. The default header allow-list omits the `sec-*` client hints and `Referer`, so those are added explicitly. OpenAPI registration (`AddOpenApi()` / `MapOpenApi()`) is likewise gated to Development.

### Consequences
- Positive: full request/response visibility while debugging the proxy setup.
- Negative / open question: this is **Development-only**, yet the longer-term intent is to use this information for **user audit purposes**. Audit logging that runs only in Development captures nothing in Production. This is intentionally left unresolved here and flagged as future work — an audit trail will need a separate, Production-appropriate mechanism (and likely field limits and PII handling, given the healthcare domain).

## Decision 3: HTTPS-only locally; drop the HTTP listener and the `.http` file
### Decision
Run the backend over HTTPS only in local development. Remove the HTTP application URL from the `https` launch profile in [launchSettings.json](../HealthCRM.Server/Properties/launchSettings.json), and delete the generated `HealthCRM.Server.http` file.

### Rationale
- **HTTPS-only** keeps local behaviour aligned with the secured production intent and avoids accidental plaintext requests. After removing the HTTP URL from the profile, the listener output shows only `https://localhost:7186`.
- **Deleting `.http`** because the REST-client `.http` file is a Visual Studio feature with no working VS Code equivalent found at the time, so it was dead weight in this VS-Code-based workflow.

### Consequences
- Positive: simpler, consistently-secure local setup.
- Negative: anything that expected a plain-HTTP endpoint locally (some tooling defaults) will need the HTTPS URL instead.

## Decision 4: Trust the dev certificate via a Node `https.Agent`, not environment variables
### Decision
Generate the .NET Core development certificate as PEM, reference it from the Vite proxy, and have the proxy trust it by constructing a Node `https.Agent` with the certificate supplied as its `ca`. Do **not** rely on `NODE_USE_SYSTEM_CA` or, as the primary mechanism, `NODE_EXTRA_CA_CERTS`.

Certificate generation (emits both a `.pem` and a matching `.key`):
```bash
mkdir -p ~/Workspaces/Certs/dotnet
dotnet dev-certs https -ep ~/Workspaces/Certs/dotnet/HealthCRM.Client.pem --format pem -np
```

> With `--format pem`, the tool writes the private key to a separate `HealthCRM.Client.key` file alongside the `.pem`. The Vite config reads both, and throws on startup if either is missing.

> The cert path uses `os.homedir()` because the certificates live in the home directory, not under the project. 
> `__dirname` is unavailable in this ESM config, and its ESM replacement `path.dirname(fileURLToPath(import.meta.url))` was tried but fails under Vite: Vite bundles the config into `node_modules/.vite-temp/`, so the path resolves there instead of the project and the `existsSync` guard throws.

Vite proxy with the agent (HTTP/1.1):

```ts
export default defineConfig({
  plugins: [react()],
  server: {
    port: 5173,
    https: {
      key: readFileSync(keyPath),
      cert: readFileSync(certPath),
    },
    proxy: {
      '^/weatherforecast': {
        target: target,        // https://localhost:7186
        secure: true,          // enforce TLS validation
        agent: new https.Agent({
          ca: readFileSync(certPath)
        }),
      },
    },
  },
});
```

### Alternatives considered
1. **`NODE_USE_SYSTEM_CA=1`.** Uses the OS trust store, where `dotnet dev-certs https --trust` has already installed the certificate. Works on Windows and macOS, and requires Node 22.15+. **Rejected** because the application is also developed on Ubuntu, which has no comparable centralised store for this to rely on, so it is not portable across both operating systems.
2. **`NODE_EXTRA_CA_CERTS=<path to pem>`.** Adds the certificate to Node's runtime trust at process start; can be set per-launch in [launch.json](../.vscode/launch.json). The mechanism is OS-agnostic (Node reads the PEM directly), but the configured `~/Workspaces/Certs/dotnet` path is a POSIX home-directory layout shared by macOS and Ubuntu; Windows uses a different file hierarchy and would need a different path. **Not chosen** because the cert path is already defined in [vite.config.ts](../HealthCRM.Client/vite.config.ts) for the agent; using this instead would mean specifying the same path a second time in [launch.json](../.vscode/launch.json).
3. **`https.Agent` with `ca` (chosen).** Keeps trust configuration *inside* [vite.config.ts](../HealthCRM.Client/vite.config.ts), version-controlled and identical on every machine, with no environment setup. This is why it is preferred for cross-platform (macOS + Ubuntu) work.

### Note on the proxy protocol and connection reuse
The proxy is deliberately kept on **HTTP/1.1**: production will use HTTP/2 end to end, but `http-proxy-3`'s HTTP/2 support is still experimental, so HTTP/1.1 is used locally for now. 

The agent is constructed with only `ca` and is **not** configured for connection pooling. A custom `new https.Agent()` defaults to `keepAlive: false`, and per the Node documentation the combination of `keepAlive: false` and the default `maxSockets: Infinity` causes the agent to send `Connection: close`. This is confirmed by the backend's HTTP logging, which records each proxied request arriving with `Connection: close` — so each request opens and tears down its own TCP connection rather than reusing a pooled one. With a single endpoint (`weatherforecast`) this is irrelevant to local development, so no pooling options are set here. Connection-pool tuning is intentionally deferred to the Docker/NGINX setup (see follow-ups).

### Consequences
- Positive: zero per-machine environment setup; trust config is committed and portable; TLS validation stays on (`secure: true`).
- Negative: each new backend endpoint must be added to the `proxy` map in [vite.config.ts](../HealthCRM.Client/vite.config.ts). The certificate path/name is currently hard-coded relative to `~/Workspaces/Certs/dotnet`, which needs to be replicated, however, these hard-coded configurations can be changed if required.


## Decision 5: One-action launch via VS Code compound configuration
### Decision
Define a build task plus two launch configurations in `.vscode/`, and a compound configuration that starts both stacks together with the debugger attached.

[tasks.json](../.vscode/tasks.json) — backend build (used as `preLaunchTask`):

```json
{
  "version": "2.0.0",
  "tasks": [
    {
      "label": "dotnet local dev build",
      "type": "dotnet",
      "task": "build ${workspaceFolder}/HealthCRM.Server/HealthCRM.Server.csproj /property:GenerateFullPaths=true /p:Configuration=Debug /p:Platform=AnyCPU /consoleloggerparameters:NoSummary",
      "file": "${workspaceFolder}/HealthCRM.Server/HealthCRM.Server.csproj",
      "group": "build",
      "problemMatcher": []
    }
  ]
}
```

[launch.json](../.vscode/launch.json) — backend, frontend, and compound:

```json
{
  "version": "0.2.0",
  "configurations": [
    {
      "name": "ASP.NET Core Launch (https)",
      "type": "coreclr",
      "request": "launch",
      "preLaunchTask": "dotnet local dev build",
      "launchSettingsProfile": "https",
      "program": "${workspaceFolder}/HealthCRM.Server/bin/Debug/net10.0/HealthCRM.Server.dll",
      "args": [],
      "cwd": "${workspaceFolder}/HealthCRM.Server",
      "stopAtEntry": false,
      "console": "internalConsole",
      "env": { "ASPNETCORE_ENVIRONMENT": "Development" }
    },
    {
      "name": "Launch React App",
      "type": "node",
      "request": "launch",
      "runtimeExecutable": "npm",
      "runtimeArgs": ["run", "dev"],
      "cwd": "${workspaceFolder}/HealthCRM.Client",
      "console": "integratedTerminal",
      "skipFiles": ["${workspaceFolder}/node_modules/**/*.js"],
      "serverReadyAction": {
        "pattern": ".+Local:.+(https?:\\/\\/.+)",
        "uriFormat": "%s",
        "webRoot": "${workspaceFolder}/HealthCRM.Client",
        "action": "debugWithChrome"
      }
    }
  ],
  "compounds": [
    {
      "name": "Launch Server and Client",
      "configurations": ["ASP.NET Core Launch (https)", "Launch React App"]
    }
  ]
}
```

### Rationale and key choices
- **Backend** reuses the project's `https` launch profile (`launchSettingsProfile: "https"`), so debugger launches behave the same as running the profile directly. `preLaunchTask` rebuilds first; `console: "internalConsole"` routes logs to the Debug Console; `stopAtEntry: false` lets the program run to a breakpoint (the default); the environment is pinned to `Development`.
- **Frontend** runs `npm run dev`. `serverReadyAction` watches the dev-server output and, when it matches the pattern `.+Local:.+(https?:\/\/.+)`, opens the matched URL in Chrome with the debugger attached. The pattern is loose on purpose: `.+` absorbs the arrow/spaces Vite prints, then it anchors on `Local`, then a capture group grabs the `http`/`https` URL — matching whatever Vite emits to the console/terminal. `skipFiles` excludes everything under `node_modules` so stepping stays in application code.
- **Compound** (`Launch Server and Client`) starts both configurations at once, giving the single-action launch the project wanted.

### Consequences
- Positive: one selection in the Run and Debug dropdown brings up the full stack, both debuggers attached, on any given machine(s).
- Negative: the `program` path hard-codes `net10.0` and `Debug`; a target framework or configuration change requires editing [launch.json](../.vscode/launch.json).

## Decision 6: Interim client-side API integration with `fetch` + `AbortController`
### Decision
Verify the end-to-end client/proxy/backend path with a throwaway React component (`<WeatherForecast />`) that calls the `weatherforecast` endpoint directly using the browser `fetch` API, inside a `useEffect`. Guard the request with an `AbortController` whose `abort()` is returned as the effect's cleanup function, so the duplicate request triggered by React Strict Mode's double-invoke of effects is cancelled rather than completing twice. A data-fetching library **will not** be introduced at this stage.
 
```tsx
useEffect(() => {
  const controller = new AbortController();
 
  const populateWeatherForecast = async () => {
    try {
      const response = await fetch('weatherforecast', { signal: controller.signal });
      if (response.ok) {
        setForecasts(await response.json());
      } else {
        throw new Error(`Request failed: ${response.status} ${response.statusText}`);
      }
    } catch (error) {
      // Cleanup aborted the in-flight request (e.g. Strict Mode double-invoke
      // or unmount) — not a real failure, so swallow it.
      if (error instanceof DOMException && error.name === 'AbortError') return;
      setErrorMsg(`Could not load weather forecasts. Please try again. Error: ${error}`);
    }
  };
 
  populateWeatherForecast();

  return () => controller.abort();
}, []);
```

### Rationale
- **Why this exists at all.** This component is a *verification harness*, not a feature. Its job is to confirm that the pieces decided above actually work together: the relative `fetch('weatherforecast')` call exercises the Vite proxy and its TLS trust (Decision 4), the HTTPS-only backend (Decision 3), and the request/HTTP logging (Decisions 1–2). It is the client end of the same path that the upcoming Docker, authentication, and authorization work will run through.
- **Why `AbortController` rather than a fetching library.** React Strict Mode intentionally mounts, unmounts, and remounts components in development, which invokes effects twice and would fire the request twice. Returning `controller.abort()` from the effect cancels the superseded request. This is the minimal, dependency-free way to handle the double-invoke for a temporary harness.

### Alternatives considered
- **Adopt a data-fetching/state library now** — a library solves the same double-request problem (and more: caching, retries, loading/error state) by deduplicating at the cache layer rather than by manual abort. **Deferred**, not rejected: pulling one in is premature for a throwaway test component, but is the intended direction once real data fetching begins (see follow-ups). The likely choice is **Redux Toolkit with RTK Query** rather than React Query, because Redux will already be used for application state — specifically the user's authentication state — so RTK Query keeps server-data fetching inside the same store rather than running a second, overlapping cache layer. A centralized fetching layer is also what makes the planned auth behaviour tractable: handling for `401 Unauthorized` responses (e.g. when a permission-gated component such as a `react-select` lazy-loads more options) can live in one place and redirect to login, rather than each component re-implementing that.
- **No abort guard** — accept the duplicate request in development. Rejected because the duplicate is noise while testing the proxy/auth path, and the abort guard is cheap.

The interim `AbortController` approach follows "Fix #3" from Jack Herrington's write-up of the React 18 / Strict Mode double-call (see References); this implementation additionally swallows the resulting abort in the `catch`, which that write-up's Fix #3 leaves unhandled.
 
### Consequences 
- Positive: confirms the full client→proxy→backend path end to end with no extra dependencies; gives a concrete surface for the Docker/auth work to build on.
- Negative / to watch: the "`AbortError` means Strict Mode" assumption only holds because this component never unmounts and has empty deps; an `AbortError` more generally signals *any* cleanup (real unmount, dependency change), so the reasoning does not transfer unchanged to a longer-lived component. This is throwaway code intended to be replaced, so the limitation is acceptable.

## Commands reference
```bash
# Add Serilog to the backend
dotnet add package Serilog.AspNetCore --project HealthCRM.Server

# Generate the dev certificate as PEM (also writes a matching .key)
dotnet dev-certs https -ep ~/Workspaces/Certs/dotnet/HealthCRM.Client.pem --format pem -np
```

## Known follow-ups
- Reconcile HTTP logging with the **audit** requirement: Development-only logging will not satisfy Production auditing, and healthcare data needs deliberate field selection and PII handling.
- Revisit the proxy's HTTP/1.1 constraint once `http-proxy-3`'s HTTP/2 support is stable, to match the intended HTTP/2 production path.
- Connection-pool tuning on the proxy agent (`keepAlive`, `keepAliveMsecs`, `maxSockets`) is left at defaults here. It will be set deliberately when the Docker/NGINX layer is configured (the next document), where NGINX and Kestrel give the values something to act on.
- The certificate folder convention (`~/Workspaces/Certs/dotnet`) is the one per-machine assumption, since the cert is generated by a manual `dotnet dev-certs` command rather than derived from the workspace. The VS Code path macros (`${workspaceFolder}`, `${userHome}`) and the `os.homedir()`-based path in [vite.config.ts](../HealthCRM.Client/vite.config.ts) are already portable across macOS, Ubuntu, and Windows, so they need no change. The `net10.0`/`Debug` segments in the launch `program` path are literals that VS Code generated; they are correct as-is and only need editing if the target framework or build configuration changes.
- Select and set up the automated test framework (MSTest for the backend, Vitest for the frontend) — deferred from this ADR.
- Replace the interim `fetch` + `AbortController` harness (Decision 6) with Redux Toolkit + RTK Query once real data fetching begins, so request deduplication, caching, loading/error state, and centralized `401` handling (redirect to login) are handled in one place rather than per component. Redux is also intended to hold the user's authentication state, which is why RTK Query is preferred over React Query.
- The real controllers should accept a `CancellationToken` (bound to `HttpContext.RequestAborted`) on cancellable read actions and thread it into EF Core / downstream calls, so a client-aborted request can abandon in-flight work rather than running to completion. Write actions must be handled deliberately — either allowed to complete or made transactional/idempotent — so a cancelled-but-partially-applied write cannot corrupt state. The throwaway `WeatherForecastController` does no cancellable work, so no token is added there; this is a concern for the future API/auth ADR.

## References
- [Configure endpoints for the ASP.NET Core Kestrel web server](https://learn.microsoft.com/en-us/aspnet/core/fundamentals/servers/kestrel/endpoints?view=aspnetcore-10.0)
- [serilog/serilog-aspnetcore](https://github.com/serilog/serilog-aspnetcore?tab=readme-ov-file)
- [serilog/serilog-settings-configuration](https://github.com/serilog/serilog-settings-configuration)
- [HTTP logging in ASP.NET Core](https://learn.microsoft.com/en-us/aspnet/core/fundamentals/http-logging/?view=aspnetcore-10.0)
- [Vite server options (HTTPS)](https://vite.dev/config/server-options#server-https)
- [sagemathinc/http-proxy-3 options](https://github.com/sagemathinc/http-proxy-3?tab=readme-ov-file#options)
- [Node.js — Enterprise Network Configuration (system CA certs)](https://nodejs.org/en/learn/http/enterprise-network-configuration#adding-ca-certificates-from-the-system-store)
- [Node.js TLS — setDefaultCACertificates](https://nodejs.org/api/tls.html#tlssetdefaultcacertificatescerts)
- [Node.js v22.15.0 release notes](https://nodejs.org/en/blog/release/v22.15.0)
- [Chrome Root Store FAQ — platform trust stores](https://chromium.googlesource.com/chromium/src/+/main/net/data/ssl/chrome_root_store/faq.md)
- [VS Code C# debugger settings](https://code.visualstudio.com/docs/csharp/debugger-settings)
- [VS Code browser debugging](https://code.visualstudio.com/docs/nodejs/browser-debugging)
- [VS Code Node.js debugging](https://code.visualstudio.com/docs/nodejs/nodejs-debugging)
- [VS Code debugging configuration](https://code.visualstudio.com/docs/debugtest/debugging-configuration)
- [Debugging ReactJS Components in ASP.NET Core (Stack Overflow)](https://stackoverflow.com/questions/66012523/debugging-reactjs-components-in-aspnet-core)
- [Node.js HTTP API](https://nodejs.org/api/http.html)
- [React 18 useEffect Double Call for APIs: Emergency Fix - DEV Community](https://dev.to/jherr/react-18-useeffect-double-call-for-apis-emergency-fix-27ee)
