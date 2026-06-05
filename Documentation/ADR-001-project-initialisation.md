# ADR-001: Frontend and Backend Framework Selection

## Context
HealthCRM is a two-part application: a backend web API and a frontend single-page application. Before any feature work could begin, a framework had to be chosen for each half of the stack, along with an approach to styling.
 
The application is an internal tool scoped to healthcare employees. It is hosted on-premise or in a containerised environment, with no public internet exposure and no SEO requirements. This shapes the decision: concerns that normally push teams toward server-side rendering or integrated full-stack frameworks — public discoverability, first-paint performance for anonymous visitors — do not apply here.

The project is also a deliberate skill-building exercise. Where two options are otherwise close, the tie is broken in favour of the one that strengthens foundational skills and reflects widely used industry tooling.
 
The initial scaffold targets ASP.NET Core 10 for the backend and Vite for the frontend toolchain. Both projects were generated and confirmed to build and run before this decision was recorded.

## Decision
Use **ReactJS (TypeScript)** for the frontend and **ASP.NET Core Web API** for the backend. Both are actively maintained, have large ecosystems, and align with the skill set I am developing through this project.
 
Styling uses **plain CSS** during infrastructure setup, moving to **Tailwind CSS** once application building begins.
 
The two projects are scaffolded as:
- `HealthCRM.Server` — created with `dotnet new webapi --use-controllers`, a controller-based ASP.NET Core Web API. The scaffold ships with the `weatherforecast` endpoint, used here only to confirm the project builds, serves over HTTPS, and exposes its OpenAPI document.
- `HealthCRM.Client` — created with `npm create vite@latest`, selecting the React + TypeScript variant.

> ASP.NET Core 10 no longer ships Swagger UI by default; the OpenAPI endpoint returns a JSON document rather than the interactive UI that earlier versions (e.g. ASP.NET Core 8) provided. API testing tooling and an HTTPS-only stance are handled separately in ADR-002.

## Alternatives Considered
 
### Backend / full-stack
- **ASP.NET Core MVC** — integrates frontend and backend into a single server, reducing hosting complexity. Ruled out because React has broader ecosystem adoption and a richer library ecosystem for building modern UIs.

### Frontend 
- **Next.js / React SSR** — would improve browser performance through server-side rendering, but SSR benefits are largely around SEO and public-facing performance. Neither applies here given the application is internal-only and not publicly accessible.

### Styling 
- **Tailwind CSS / Bootstrap** — not adopted at this stage. Current work is setting up the code infrastructure rather than building UI, so plain CSS is enough for now and I already work comfortably in it. Tailwind is the intended approach once actual application building begins: having worked through its documentation, the initial unfamiliarity is no longer a blocker, and its prevalence makes it the more valuable skill to demonstrate in a portfolio project. Bootstrap was the weaker of the two on that same portfolio-value measure.

## Consequences
- Two codebases in two languages require separate maintenance and context-switching during development.
- Not using the React Compiler, so component state optimisation requires manual memoisation where needed.
- Styling uses hand-written plain CSS during infrastructure setup; this is manageable given existing CSS experience, and will give way to Tailwind once UI work begins.
- The scaffolds run over HTTP and HTTPS as generated; both front and backend need to be standardised on HTTPS, and scaffold cleanup (e.g. removing the `weatherforecast` sample) is required. These are addressed in ADR-002.

## Known follow-ups 
- Standardise both projects on HTTPS and remove the HTTP listeners — carried into ADR-002 (local development setup).
- Remove the scaffolded `weatherforecast` sample endpoint and the default Vite template content once real features begin.
- Select a database and record that decision in a later ADR.
- Implement Tailwind CSS when application building begins, migrating any plain CSS written during infrastructure setup.

## Commands reference 
```bash
# Trust the local dev HTTPS certificate (one-time, per machine)
dotnet dev-certs https --trust
 
# Scaffold the backend (controller-based Web API)
dotnet new webapi --use-controllers -o HealthCRM.Server
 
# Run the backend over HTTPS
dotnet run -lp "https" --project HealthCRM.Server
 
# Scaffold the frontend (select React, then TypeScript)
npm create vite@latest
```

## Alternatives Considered
### Backend / full-stack
- **ASP.NET Core MVC** — integrates frontend and backend into a single server, reducing hosting complexity. Ruled out because React has broader ecosystem adoption and a richer library ecosystem for building modern UIs.

### Frontend
- **Next.js / React SSR** — would improve browser performance through server-side rendering, but SSR benefits are largely around SEO and public-facing performance. Neither applies here given the application is internal-only and not publicly accessible.

### Styling 
- **Tailwind CSS / Bootstrap** — not adopted at this stage. Current work is setting up the code infrastructure rather than building UI, so plain CSS is enough for now and I already work comfortably in it. Tailwind is the intended approach once actual application building begins: having worked through its documentation, the initial unfamiliarity is no longer a blocker, and its prevalence makes it the more valuable skill to demonstrate in a portfolio project. Bootstrap was the weaker of the two on that same portfolio-value measure.

## Consequences 
- Two codebases in two languages require separate maintenance and context-switching during development.
- Not using the React Compiler, so component state optimisation requires manual memoisation where needed.
- Styling uses hand-written plain CSS during infrastructure setup; this is manageable given existing CSS experience, and will give way to Tailwind once UI work begins.
- The scaffolds run over HTTP and HTTPS as generated; both front and backend need to be standardised on HTTPS, and scaffold cleanup (e.g. removing the `weatherforecast` sample) is required. These are addressed in ADR-002.

## Known follow-ups 
- Standardise both projects on HTTPS and remove the HTTP listeners — carried into ADR-002 (local development setup).
- Remove the scaffolded `weatherforecast` sample endpoint and the default Vite template content once real features begin.
- Select a database and record that decision in a later ADR.
- Implement Tailwind CSS when application building begins, migrating any plain CSS written during infrastructure setup.

## Commands reference
```bash
# Trust the local dev HTTPS certificate (one-time, per machine)
dotnet dev-certs https --trust
 
# Scaffold the backend (controller-based Web API)
dotnet new webapi --use-controllers -o HealthCRM.Server
 
# Run the backend over HTTPS
dotnet run -lp "https" --project HealthCRM.Server
 
# Scaffold the frontend (select React, then TypeScript)
npm create vite@latest
```
 
## References
- [Tutorial: Create a controller-based web API with ASP.NET Core | Microsoft Learn](https://learn.microsoft.com/en-us/aspnet/core/tutorials/first-web-api?view=aspnetcore-10.0&tabs=visual-studio-code)
- [Generate OpenAPI documents | Microsoft Learn](https://learn.microsoft.com/en-us/aspnet/core/fundamentals/openapi/aspnetcore-openapi?view=aspnetcore-10.0&tabs=net-cli%2Cvisual-studio-code)
- [Getting Started | Vite](https://vite.dev/guide/)
- [Node.js](https://nodejs.org/en)
 k
- [Tutorial: Create a controller-based web API with ASP.NET Core | Microsoft Learn](https://learn.microsoft.com/en-us/aspnet/core/tutorials/first-web-api?view=aspnetcore-10.0&tabs=visual-studio-code)
- [Generate OpenAPI documents | Microsoft Learn](https://learn.microsoft.com/en-us/aspnet/core/fundamentals/openapi/aspnetcore-openapi?view=aspnetcore-10.0&tabs=net-cli%2Cvisual-studio-code)
- [Getting Started | Vite](https://vite.dev/guide/)
- [Node.js](https://nodejs.org/en)
 