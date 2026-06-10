FROM mcr.microsoft.com/dotnet/aspnet:10.0 AS base
WORKDIR /app
USER app

FROM --platform=$BUILDPLATFORM mcr.microsoft.com/dotnet/sdk:10.0 AS build
ARG configuration=Release
WORKDIR /src
COPY ["HealthCRM.Server.csproj", "."]
RUN dotnet restore "HealthCRM.Server.csproj"
COPY . .
RUN dotnet build "HealthCRM.Server.csproj" -c $configuration -o /app/build

FROM build AS publish
ARG configuration=Release
RUN dotnet publish "HealthCRM.Server.csproj" -c $configuration -o /app/publish /p:UseAppHost=false
COPY runtimeconfig.Staging.json /app/publish/HealthCRM.Server.runtimeconfig.json

FROM base AS final
WORKDIR /app
COPY --from=publish /app/publish .
ENTRYPOINT ["dotnet", "HealthCRM.Server.dll"]
